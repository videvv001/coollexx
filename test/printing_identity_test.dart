// The whole path for exact physical printing identity, with canned model
// answers instead of a live AI call and the real saved marketplace pages
// instead of the live sites:
//
//   recognition answer → printing descriptor → saved card → reload (and copy)
//   → pricing request → YuYu-tei + CardRush + e-Starbox matching → price
//   → price history for that exact printing.
//
// The three EB04-061 prints are one logical card, three physical printings:
// base, parallel and the crew-background super parallel. They must stay
// distinct all the way through, each priced from its own listings.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pokedex_tcg/data/collection_repository.dart';
import 'package:pokedex_tcg/data/price_observation_repository.dart';
import 'package:pokedex_tcg/models/card_language.dart';
import 'package:pokedex_tcg/models/printing_variant.dart';
import 'package:pokedex_tcg/models/release_category.dart';
import 'package:pokedex_tcg/models/tcg_card.dart';
import 'package:pokedex_tcg/models/tcg_game.dart';
import 'package:pokedex_tcg/pricing/card_recognition_service.dart';
import 'package:pokedex_tcg/pricing/cardrush_price_source.dart';
import 'package:pokedex_tcg/pricing/estarbox_price_source.dart';
import 'package:pokedex_tcg/pricing/japanese_price_research_service.dart';
import 'package:pokedex_tcg/pricing/price_research_service.dart';
import 'package:pokedex_tcg/pricing/responses_card_recognition_service.dart';
import 'package:pokedex_tcg/pricing/yuyutei_price_service.dart';

import 'card_recognition_parse_test.dart' show eb04Base, eb04Crew, eb04Parallel;
import 'support/jp_pricing_fixtures.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late CollectionRepository repo;
  late PriceObservationRepository history;
  late dynamic db;
  late String releaseId;

  final web = FakeWebResearch(
    const InsufficientEvidence(rawResponse: '', reason: 'nothing'),
  );
  final service = JapanesePriceResearchService(
    sources: [
      YuyuteiPriceSource(fetch: yuyuteiFetch()),
      CardRushPriceSource(fetch: cardRushFetch()),
      EStarboxPriceSource(fetch: eStarboxFetch()),
    ],
    fallback: web,
    clock: () => DateTime(2026, 10, 5),
  );

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.execute('''
      CREATE TABLE releases (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, dateCreated TEXT NOT NULL,
        coverPhotoPath TEXT, coverPortrait INTEGER NOT NULL DEFAULT 0,
        orderIndex INTEGER NOT NULL, officialSetCode TEXT, totalCardsInSet INTEGER,
        category TEXT NOT NULL DEFAULT 'Others', language TEXT,
        landscapeCoverPath TEXT, portraitCoverPath TEXT,
        isFavorite INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE cards (
        id TEXT PRIMARY KEY, name TEXT, number TEXT, rarity TEXT,
        variantFamily TEXT, variantName TEXT, artworkVariant TEXT,
        language TEXT, kind TEXT, color TEXT, type TEXT, condition TEXT,
        copies INTEGER NOT NULL DEFAULT 1, releaseId TEXT,
        photoPaths TEXT NOT NULL DEFAULT '', pricePaid REAL, datePaid TEXT,
        forTrade INTEGER NOT NULL DEFAULT 0, onWishlist INTEGER NOT NULL DEFAULT 0,
        isFavorite INTEGER NOT NULL DEFAULT 0, notes TEXT, createdAt TEXT NOT NULL,
        FOREIGN KEY (releaseId) REFERENCES releases (id) ON DELETE SET NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE price_observations (
        id TEXT PRIMARY KEY, cardId TEXT, game TEXT NOT NULL,
        cardNumber TEXT NOT NULL, language TEXT NOT NULL, officialRarity TEXT,
        variantFamily TEXT NOT NULL, variantName TEXT, artworkVariant TEXT,
        marketplace TEXT NOT NULL, sourceType TEXT NOT NULL, sourceLabel TEXT,
        url TEXT NOT NULL, price REAL NOT NULL, currency TEXT NOT NULL,
        isGraded INTEGER NOT NULL DEFAULT 0, soldOut INTEGER NOT NULL DEFAULT 0,
        condition TEXT, matchConfidence REAL,
        usedInEstimate INTEGER NOT NULL DEFAULT 0, notUsedReason TEXT,
        observedAt TEXT, researchedAt TEXT NOT NULL, provider TEXT
      )
    ''');
    repo = CollectionRepository(dbOverride: () => db);
    history = PriceObservationRepository(dbOverride: () => db);
    releaseId = (await repo.createRelease(
      'EB04',
      category: ReleaseCategory.onePiece,
    )).id;
  });

  tearDown(() => db.close());

  /// Recognise → save as a card → read it back from the database.
  Future<TcgCard> scanAndSave(String modelAnswer, String id) async {
    final r = parseRecognitionResponse(
      modelAnswer,
      provider: 'test',
      model: 'canned',
      printingConfidenceThreshold: 0.85,
    );
    expect(r.status, RecognitionStatus.identified);
    final p = r.printing!;
    await repo.createCard(
      TcgCard(
        id: id,
        name: p.name,
        number: p.cardNumber,
        rarity: p.rarity,
        variant: p.variant,
        language: CardLanguage.fromPrinted(p.language),
        releaseId: releaseId,
        createdAt: DateTime(2026, 10, 5),
      ),
    );
    return (await repo.card(id))!;
  }

  Future<(PrintingDescriptor, PriceResearchResult)> price(TcgCard card) async {
    final release = (await repo.release(card.releaseId!))!;
    final printing = PrintingDescriptor.fromCard(
      card,
      TcgGame.fromCategory(release.category),
    )!;
    return (
      printing,
      await service.research(PriceResearchRequest(printing: printing)),
    );
  }

  test(
    'three scans: one logical card, three printings, three prices',
    () async {
      final crew = await scanAndSave(eb04Crew, 'crew');
      final base = await scanAndSave(eb04Base, 'base');
      final parallel = await scanAndSave(eb04Parallel, 'parallel');

      // Same logical card …
      for (final c in [crew, base, parallel]) {
        expect(c.number, 'EB04-061');
        expect(c.rarity, 'SEC');
        expect(c.language, CardLanguage.jp);
      }
      // … different physical printings, artwork kept.
      expect({crew.variant, base.variant, parallel.variant}, hasLength(3));
      expect(crew.variant.name, 'PIRATE_CREW_SUPER_PARALLEL');
      expect(crew.variant.artwork, contains('Straw Hat crew'));

      final (_, crewResult) = await price(crew);
      final (_, baseResult) = await price(base);
      final (_, parallelResult) = await price(parallel);
      final crewPrice = (crewResult as PriceResearchSuccess).estimatedPrice;
      final basePrice = (baseResult as PriceResearchSuccess).estimatedPrice;
      final parallelPrice =
          (parallelResult as PriceResearchSuccess).estimatedPrice;

      expect(basePrice, lessThan(2000));
      expect(parallelPrice, inInclusiveRange(4000, 6000));
      expect(crewPrice, greaterThan(1000000));
      expect({basePrice, parallelPrice, crewPrice}, hasLength(3));
      expect(web.calls, 0, reason: 'exact matches found; no web search');
    },
  );

  test('price history is per exact printing and append-only', () async {
    final crew = await scanAndSave(eb04Crew, 'crew');
    final base = await scanAndSave(eb04Base, 'base');
    final (crewPrinting, crewResult) = await price(crew);
    final (basePrinting_, baseResult) = await price(base);

    final saved = await history.record(
      crewPrinting,
      crewResult,
      cardId: 'crew',
      provider: 'test',
    );
    await history.record(basePrinting_, baseResult, cardId: 'base');
    expect(saved, greaterThan(3));

    final crewRows = await history.forPrinting(crewPrinting);
    expect(crewRows.length, saved);
    expect(
      crewRows.every((r) => r.variant.name == 'PIRATE_CREW_SUPER_PARALLEL'),
      isTrue,
    );
    // Nothing from the base printing leaks into the crew print's history.
    expect(
      crewRows.where((r) => r.price < 100000 && r.usedInEstimate),
      isEmpty,
    );
    final used = crewRows.where((r) => r.usedInEstimate).toList();
    expect(used.map((r) => r.marketplace).toSet(), {'CardRush', 'e-Starbox'});
    expect(used.every((r) => r.matchConfidence == 1.0), isTrue);
    final yuyutei = crewRows.singleWhere(
      (r) => r.marketplace == 'Yuyu-tei' && r.price == 1280000,
    );
    expect(yuyutei.usedInEstimate, isFalse);
    expect(yuyutei.notUsedReason, contains('sold out'));
    expect(yuyutei.soldOut, isTrue);
    expect(yuyutei.sourceLabel, contains('海賊団スーパーパラレル'));
    expect(yuyutei.url, startsWith('https://yuyu-tei.jp/'));
    expect(
      crewRows.firstWhere((r) => r.marketplace == 'e-Starbox').sourceType,
      SourceType.priceComparison,
    );

    // Researching again adds rows; the old ones stay.
    await history.record(crewPrinting, crewResult, cardId: 'crew');
    expect((await history.forPrinting(crewPrinting)).length, saved * 2);

    final baseRows = await history.forPrinting(basePrinting_);
    expect(
      baseRows.every((r) => r.variant.family == VariantFamily.base),
      isTrue,
    );
    expect(
      baseRows
          .map((r) => r.id)
          .toSet()
          .intersection(crewRows.map((r) => r.id).toSet()),
      isEmpty,
    );
  });

  test('a refusal or failure saves no history', () async {
    final unknown = printing(PrintingVariant.unknown);
    final refused = await service.research(
      PriceResearchRequest(printing: unknown),
    );
    expect(await history.record(unknown, refused), 0);
  });

  test('copy and edit keep the printing', () async {
    final crew = await scanAndSave(eb04Crew, 'crew');
    final other = (await repo.createRelease('Binder')).id;

    final copy = (await repo.copyCards(['crew'], releaseId: other)).single;
    expect((await repo.card(copy.id))!.variant, crew.variant);

    await repo.updateCard(crew.copyWith(rarity: 'SEC', copies: 2));
    expect((await repo.card('crew'))!.variant, crew.variant);
  });

  test(
    'a card saved before printings existed is unknown, never base',
    () async {
      await db.insert('cards', {
        'id': 'old',
        'name': 'モンキー・D・ルフィ',
        'number': 'EB04-061',
        'rarity': 'SEC',
        'language': 'JP',
        'releaseId': releaseId,
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      });
      final old = (await repo.card('old'))!;
      expect(old.variant, PrintingVariant.unknown);
      expect(old.variant.isResolved, isFalse);
      expect((await price(old)).$2, isA<PrintingVerificationRequired>());
    },
  );
}
