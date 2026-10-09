// Exact-printing RESOLUTION: the vision model describes and guesses; known
// printings (found by live printing research, cached) decide; only a resolved
// printing is priced.
//
//   OP13-119 (Portgas D. Ace, JP, SEC): one logical card, a Manga print and a
//     Red Manga print. Vision calls the red one MANGA_RARE; the red treatment
//     it SAW must refine that to RED_MANGA_RARE — and never price Manga.
//   EB04-061 (Luffy, JP, SEC): base / parallel / crew-background print.
//
// Model answers and the research reply are canned (shaped like the real
// ones); the EB04 prices come from the real saved marketplace pages. Nothing
// here is keyed on a card number: the last group runs the same code on a
// made-up card.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pokedex_tcg/data/printing_candidate_repository.dart';
import 'package:pokedex_tcg/models/printing_candidate.dart';
import 'package:pokedex_tcg/models/printing_variant.dart';
import 'package:pokedex_tcg/models/visual_observation.dart';
import 'package:pokedex_tcg/pricing/card_identifier.dart';
import 'package:pokedex_tcg/pricing/card_recognition_service.dart';
import 'package:pokedex_tcg/pricing/cardrush_price_source.dart';
import 'package:pokedex_tcg/pricing/estarbox_price_source.dart';
import 'package:pokedex_tcg/pricing/japanese_price_research_service.dart';
import 'package:pokedex_tcg/pricing/price_research_service.dart';
import 'package:pokedex_tcg/pricing/printing_research_service.dart';
import 'package:pokedex_tcg/pricing/printing_resolution_service.dart';
import 'package:pokedex_tcg/pricing/responses_card_recognition_service.dart';
import 'package:pokedex_tcg/pricing/responses_price_research_service.dart';
import 'package:pokedex_tcg/pricing/yuyutei_price_service.dart';

import 'card_recognition_parse_test.dart' show cannedRecognition;
import 'support/jp_pricing_fixtures.dart';

// --- Canned printing research ------------------------------------------

Map<String, Object?> visual({
  String color = 'UNKNOWN',
  String background = 'UNKNOWN',
  bool? panels,
  bool? bubbles,
  String frame = 'STANDARD',
}) => {
  'dominant_treatment_color': color,
  'background_style': background,
  'manga_panels': panels,
  'speech_bubbles': bubbles,
  'frame_treatment': frame,
  'foil_evidence': 'UNKNOWN',
  'special_symbols': <String>[],
  'distinctive_markers': <String>[],
};

Map<String, Object?> printingJson(
  String? name,
  String family,
  Map<String, Object?> look, {
  List<String> aliases = const [],
  String rarity = 'SEC',
  List<String>? evidence,
}) => {
  'variant_family': family,
  'variant_name': name,
  'official_rarity': rarity,
  'marketplace_aliases': aliases,
  'artwork_description': name ?? family,
  'visual': look,
  'visual_markers': <String>[],
  'reference_image_url': null,
  'evidence_urls': evidence ?? ['https://shop.example/${name ?? family}'],
};

/// A Responses body: a completed live search that visited [visited], then the
/// printing list.
String researchBody(
  List<Map<String, Object?>> printings, {
  List<String>? visited,
  bool searched = true,
  String status = 'SUCCESS',
}) => jsonEncode({
  'status': 'completed',
  'output': [
    if (searched)
      {
        'type': 'web_search_call',
        'status': 'completed',
        'action': {
          'type': 'search',
          'query': 'printings',
          'sources': [
            for (final u
                in visited ??
                    [
                      for (final p in printings)
                        ...(p['evidence_urls'] as List).cast<String>(),
                    ])
              {'type': 'url', 'url': u},
          ],
        },
      },
    {
      'type': 'message',
      'content': [
        {
          'type': 'output_text',
          'text': jsonEncode({
            'status': status,
            'reason': 'r',
            'printings': printings,
          }),
          'annotations': <Object>[],
        },
      ],
    },
  ],
});

// OP13-119, the way printing research would describe it. The look of each
// print is canned here; a real run decides it from sources.
final op13Printings = [
  printingJson(
    null,
    'BASE',
    visual(color: 'NONE', background: 'STANDARD', panels: false, bubbles: false),
  ),
  printingJson(
    'MANGA_RARE',
    'SUPER_PARALLEL',
    visual(
      color: 'BLACK_AND_WHITE',
      background: 'MANGA_PANEL_COLLAGE',
      panels: true,
      bubbles: true,
    ),
    aliases: ['Manga Rare', 'Comic Parallel', 'コミパラ', 'SEC-SP'],
  ),
  printingJson(
    'RED_MANGA_RARE',
    'SUPER_PARALLEL',
    visual(
      color: 'RED',
      background: 'MANGA_PANEL_COLLAGE',
      panels: true,
      bubbles: true,
    ),
    aliases: [
      'Red Manga Rare',
      'Red Comic Parallel',
      'レッドコミパラ',
      'SEC-RSP',
      'Red Super Parallel',
    ],
  ),
];

final eb04Printings = [
  printingJson(
    null,
    'BASE',
    visual(
      color: 'NONE',
      background: 'SOLID_COLOR',
      panels: false,
      bubbles: false,
    ),
  ),
  printingJson(
    null,
    'PARALLEL',
    visual(
      color: 'NONE',
      background: 'SCENE_ILLUSTRATION',
      panels: false,
      bubbles: false,
    ),
    aliases: ['パラレル'],
  ),
  printingJson(
    'PIRATE_CREW_SUPER_PARALLEL',
    'SUPER_PARALLEL',
    visual(
      color: 'BLACK_AND_WHITE',
      background: 'CHARACTER_COLLAGE',
      panels: false,
      bubbles: false,
    ),
    aliases: ['海賊団スーパーパラレル', 'TEAM_SP'],
  ),
];

List<PrintingCandidate> known(List<Map<String, Object?>> printings) =>
    parsePrintingResearch(researchBody(printings)).candidates;

class FakePrintingResearch implements PrintingResearchService {
  FakePrintingResearch(this.candidates, {this.reason = ''});

  List<PrintingCandidate> candidates;
  final String reason;
  int calls = 0;

  @override
  String get provider => 'FakeResearch';

  @override
  Future<PrintingResearchResult> discover(PrintingDescriptor logical) async {
    calls++;
    return PrintingResearchResult(
      candidates: candidates,
      rawResponse: '{}',
      reason: reason,
    );
  }
}

class FakeRecognition implements CardRecognitionService {
  FakeRecognition(this.raw);
  final String raw;

  @override
  String get provider => 'Fake';

  @override
  Future<RecognitionResult> recognize(List<String> imagePaths) async =>
      parseRecognitionResponse(
        raw,
        provider: 'Fake',
        model: 'canned',
        printingConfidenceThreshold: 0.85,
      );
}

// --- Canned vision answers ---------------------------------------------

Map<String, Object?> redPanels() => visual(
  color: 'RED',
  background: 'MANGA_PANEL_COLLAGE',
  panels: true,
  bubbles: true,
);

/// Vision's answer for the red Ace photo: it SAW red manga panels but only
/// predicted MANGA_RARE, at 70%.
String aceRaw({
  Map<String, Object?>? look,
  String? predicted = 'MANGA_RARE',
  double printing = 0.7,
}) => cannedRecognition(
  name: 'Portgas D. Ace',
  number: 'OP13-119',
  language: 'Japanese',
  family: 'SUPER_PARALLEL',
  variantName: predicted,
  artwork: 'Ace centred over red manga panels with speech bubbles',
  printing: printing,
  visual: look ?? redPanels(),
);

RecognitionResult read(String raw) => parseRecognitionResponse(
  raw,
  provider: 'Fake',
  model: 'canned',
  printingConfidenceThreshold: 0.85,
);

PrintingResolutionService resolverOver(
  List<PrintingCandidate> candidates, {
  PrintingCandidateRepository? cache,
}) => PrintingResolutionService(
  research: FakePrintingResearch(candidates),
  cache: cache,
);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('printing research is verified, not trusted', () {
    test('printings keep only evidence pages the search really visited', () {
      final r = parsePrintingResearch(
        researchBody(
          [
            ...op13Printings,
            printingJson(
              'INVENTED_GOLD',
              'SPECIAL',
              visual(color: 'GOLD'),
              evidence: ['https://never-visited.example/page'],
            ),
          ],
          visited: [
            for (final p in op13Printings)
              ...(p['evidence_urls'] as List).cast<String>(),
          ],
        ),
      );
      expect(r.candidates.map((c) => c.variantName), [
        null,
        'MANGA_RARE',
        'RED_MANGA_RARE',
      ]);
      expect(r.candidates.last.evidenceSources, isNotEmpty);
      expect(r.candidates.last.visual.treatmentColor, TreatmentColor.red);
      expect(r.candidates.last.marketplaceAliases, contains('レッドコミパラ'));
    });

    test('no live search → no printings, whatever the model answered', () {
      final r = parsePrintingResearch(
        researchBody(op13Printings, searched: false),
      );
      expect(r.candidates, isEmpty);
      expect(r.reason, contains('No live web search'));
    });

    test('a failed or empty research is not a catalog', () {
      expect(parsePrintingResearch('not json').candidates, isEmpty);
      expect(
        parsePrintingResearch(
          researchBody(const [], status: 'INSUFFICIENT_EVIDENCE'),
        ).candidates,
        isEmpty,
      );
    });
  });

  group('OP13-119: Manga vs Red Manga', () {
    test('vision keeps what it saw even while it names the wrong print', () {
      final r = read(aceRaw());
      expect(r.printing!.variant.name, 'MANGA_RARE');
      expect(r.printingConfidence, 0.7);
      expect(r.visual.treatmentColor, TreatmentColor.red);
      expect(r.visual.backgroundStyle, BackgroundStyle.mangaPanelCollage);
      expect(r.evidenceNeeded, isNot(EvidenceRequest.angledPhoto));
      expect(r.printing!.source, PrintingSource.visionHypothesis);
    });

    test('the red treatment refines the MANGA_RARE guess to RED_MANGA_RARE', () async {
      final r = read(aceRaw());
      final res = await resolverOver(known(op13Printings)).resolve(
        logical: r.printing!,
        observed: r.visual,
      );
      expect(res.isResolved, isTrue);
      expect(res.resolved!.variantName, 'RED_MANGA_RARE');
      expect(res.visionPredicted.name, 'MANGA_RARE');
      expect(res.confidence, greaterThanOrEqualTo(0.9));
      expect(res.evidence.join('\n'), contains('treatment colour RED'));
      expect(res.evidence.join('\n'), contains('vision predicted Manga Rare'));
      final out = {for (final x in res.rejected) x.candidate.label: x.reason};
      expect(out['MANGA_RARE'], contains('treatment colour'));
      expect(out['MANGA_RARE'], contains('BLACK_AND_WHITE'));
      expect(out['Base'], contains('background'));
    });

    test('identified end to end, as a priceable RED_MANGA_RARE', () async {
      final ident = await CardIdentifier(
        recognition: FakeRecognition(aceRaw()),
        resolver: resolverOver(known(op13Printings)),
      ).identify(['ace.jpg']);
      expect(ident.status, RecognitionStatus.identified);
      expect(ident.evidenceNeeded, EvidenceRequest.none);
      final p = ident.printing!;
      expect(p.source, PrintingSource.resolved);
      expect(p.variant.name, 'RED_MANGA_RARE');
      expect(p.cardNumber, 'OP13-119');
      expect(p.language, 'Japanese');
      expect(p.rarity, 'SEC');
      expect(requireExactPrinting(p), isNull);
      // The model's own guess is still on record.
      expect(ident.recognition.printing!.variant.name, 'MANGA_RARE');
    });

    test('an ordinary (not red) manga photo stays MANGA_RARE', () async {
      final plain = visual(
        color: 'BLACK_AND_WHITE',
        background: 'MANGA_PANEL_COLLAGE',
        panels: true,
        bubbles: true,
      );
      final r = read(aceRaw(look: plain, predicted: 'MANGA_RARE', printing: 0.9));
      final res = await resolverOver(known(op13Printings)).resolve(
        logical: r.printing!,
        observed: r.visual,
      );
      expect(res.resolved!.variantName, 'MANGA_RARE');
      expect(res.rejected.map((x) => x.candidate.variantName), contains('RED_MANGA_RARE'));
    });

    test('colour not visible → cannot tell, nothing priced, no angled photo', () async {
      final unclear = visual(
        background: 'MANGA_PANEL_COLLAGE',
        panels: true,
        bubbles: true,
      );
      final ident = await CardIdentifier(
        recognition: FakeRecognition(aceRaw(look: unclear)),
        resolver: resolverOver(known(op13Printings)),
      ).identify(['ace.jpg']);
      expect(ident.status, RecognitionStatus.verificationRequired);
      expect(ident.resolution!.isResolved, isFalse);
      expect(ident.resolution!.reason, contains('MANGA_RARE'));
      expect(ident.resolution!.reason, contains('RED_MANGA_RARE'));
      // The photo didn't show the one thing that separates them: look closer,
      // not tilt.
      expect(ident.evidenceNeeded, EvidenceRequest.closeUp);
      expect(
        ident.printing!.source,
        PrintingSource.visionHypothesis,
        reason: 'neither print may be priced',
      );
      expect(requireExactPrinting(ident.printing!), isNotNull);
    });

    test('research that does not record the Manga colour cannot settle it', () async {
      // Red photo, but the Manga print's look is unknown on record: red could
      // still be Manga as far as the evidence goes, so neither is priced.
      final vague = [
        op13Printings[0],
        printingJson(
          'MANGA_RARE',
          'SUPER_PARALLEL',
          visual(background: 'MANGA_PANEL_COLLAGE', panels: true, bubbles: true),
          aliases: ['コミパラ', 'SEC-SP'],
        ),
        op13Printings[2],
      ];
      final ident = await CardIdentifier(
        recognition: FakeRecognition(aceRaw()),
        resolver: resolverOver(known(vague)),
      ).identify(['ace.jpg']);
      expect(ident.status, RecognitionStatus.verificationRequired);
      expect(ident.resolution!.reasons, [
        UncertaintyReason.marketplaceClassificationUncertain,
      ]);
      expect(ident.evidenceNeeded, EvidenceRequest.userConfirmation);
    });

    test('no known printings → unknown printing, nothing priced', () async {
      final ident = await CardIdentifier(
        recognition: FakeRecognition(aceRaw()),
        resolver: PrintingResolutionService(
          research: FakePrintingResearch(const [], reason: 'No live web search'),
        ),
      ).identify(['ace.jpg']);
      expect(ident.status, RecognitionStatus.verificationRequired);
      expect(ident.resolution!.reasons, [UncertaintyReason.unknownPrinting]);
      expect(ident.reason, contains('No live web search'));
      expect(requireExactPrinting(ident.printing!), isNotNull);
    });

    test('the price query names the red aliases and excludes Manga’s', () async {
      final ident = await CardIdentifier(
        recognition: FakeRecognition(aceRaw()),
        resolver: resolverOver(known(op13Printings)),
      ).identify(['ace.jpg']);
      final target = describeResearchTarget(
        PriceResearchRequest(printing: ident.printing!, currency: 'JPY'),
      );
      final at = target.indexOf('NOT this printing');
      expect(at, greaterThan(0));
      final wanted = target.substring(0, at);
      final notWanted = target.substring(at);
      for (final a in ['RED_MANGA_RARE', 'Red Comic Parallel', 'レッドコミパラ', 'SEC-RSP']) {
        expect(wanted, contains(a));
      }
      expect(wanted, isNot(contains('SEC-SP')));
      expect(notWanted, contains('SEC-SP'));
      expect(notWanted, contains('コミパラ'));
    });

    test('a Manga listing never counts toward the Red Manga price', () async {
      final ident = await CardIdentifier(
        recognition: FakeRecognition(aceRaw()),
        resolver: resolverOver(known(op13Printings)),
      ).identify(['ace.jpg']);
      final request = PriceResearchRequest(
        printing: ident.printing!,
        currency: 'JPY',
      );
      Map<String, Object?> src(String url, String title, num price) => {
        'name': title,
        'marketplace': null,
        'type': 'CURRENT_LISTING',
        'price': price,
        'currency': 'JPY',
        'condition': null,
        'is_graded': false,
        'url': url,
        'title': title,
        'observed_at': '2026-10-05',
      };
      const manga = 'https://shop.example/manga';
      const red = 'https://shop.example/red';
      final body = jsonEncode({
        'status': 'completed',
        'output': [
          {
            'type': 'web_search_call',
            'status': 'completed',
            'action': {
              'sources': [
                {'url': manga},
                {'url': red},
              ],
            },
          },
          {
            'type': 'message',
            'content': [
              {
                'type': 'output_text',
                'text': jsonEncode({
                  'status': 'SUCCESS',
                  'reason': 'r',
                  'sources': [
                    src(manga, 'ポートガス・D・エース(コミパラ) SEC-SP OP13-119', 6000),
                    src(red, 'ポートガス・D・エース(レッドコミパラ) SEC-RSP OP13-119', 90000),
                  ],
                }),
                'annotations': <Object>[],
              },
            ],
          },
        ],
      });
      final result = parseResearchResponse(body, request, now: DateTime(2026, 10, 5))
          as PriceResearchSuccess;
      final byUrl = {for (final s in result.sources) s.url: s};
      expect(byUrl[manga]!.usedInEstimate, isFalse);
      expect(byUrl[manga]!.notUsedReason, 'different printing');
      expect(byUrl[red]!.usedInEstimate, isTrue);
      expect(result.estimatedPrice, 90000);
    });

    test('an alias inside a longer alias belongs to the longer one', () async {
      final ident = await CardIdentifier(
        recognition: FakeRecognition(aceRaw()),
        resolver: resolverOver(known(op13Printings)),
      ).identify(['ace.jpg']);
      final red = ident.printing!;
      ListingVerdict v(String t) => attributeListing(t, red);
      // コミパラ is inside レッドコミパラ; "Manga Rare" inside "Red Manga Rare".
      expect(v('エース レッドコミパラ'), ListingVerdict.thisPrinting);
      expect(v('エース コミパラ'), ListingVerdict.otherPrinting);
      expect(v('Ace Red Manga Rare OP13-119'), ListingVerdict.thisPrinting);
      expect(v('Ace Manga Rare OP13-119'), ListingVerdict.otherPrinting);
      expect(v('OP13-119 SEC-SP'), ListingVerdict.otherPrinting);
      expect(v('OP13-119 SEC-RSP'), ListingVerdict.thisPrinting);
      expect(v('OP13-119 ace'), ListingVerdict.unknown);
    });

    test('a vision guess is refused by the Japanese price service', () async {
      final web = FakeWebResearch(
        const InsufficientEvidence(rawResponse: '', reason: 'x'),
      );
      final service = JapanesePriceResearchService(
        sources: [
          YuyuteiPriceSource(fetch: yuyuteiFetch()),
          CardRushPriceSource(fetch: cardRushFetch()),
          EStarboxPriceSource(fetch: eStarboxFetch()),
        ],
        fallback: web,
      );
      final guess = read(aceRaw()).printing!;
      final result = await service.research(PriceResearchRequest(printing: guess));
      expect(result, isA<PrintingVerificationRequired>());
      expect(web.calls, 0);
    });
  });

  group('EB04-061: base / parallel / crew print', () {
    String lookRaw(String? predicted, String family, Map<String, Object?> look) =>
        cannedRecognition(
          name: 'モンキー・D・ルフィ',
          number: 'EB04-061',
          language: 'Japanese',
          family: family,
          variantName: predicted,
          artwork: 'Gear 5 Luffy',
          printing: 0.9,
          visual: look,
        );

    final baseLook = visual(
      color: 'NONE',
      background: 'SOLID_COLOR',
      panels: false,
      bubbles: false,
    );
    final parallelLook = visual(
      color: 'NONE',
      background: 'SCENE_ILLUSTRATION',
      panels: false,
      bubbles: false,
    );
    final crewLook = visual(
      color: 'BLACK_AND_WHITE',
      background: 'CHARACTER_COLLAGE',
      panels: false,
      bubbles: false,
    );

    Future<IdentificationResult> identify(String raw) => CardIdentifier(
      recognition: FakeRecognition(raw),
      resolver: resolverOver(known(eb04Printings)),
    ).identify(['luffy.jpg']);

    test('each photo resolves to its own physical printing', () async {
      final crew = await identify(
        lookRaw('PIRATE_CREW_SUPER_PARALLEL', 'SUPER_PARALLEL', crewLook),
      );
      final base = await identify(lookRaw(null, 'BASE', baseLook));
      final parallel = await identify(lookRaw(null, 'PARALLEL', parallelLook));
      for (final i in [crew, base, parallel]) {
        expect(i.status, RecognitionStatus.identified);
        expect(i.printing!.cardNumber, 'EB04-061');
      }
      expect(crew.printing!.variant.name, 'PIRATE_CREW_SUPER_PARALLEL');
      expect(base.printing!.variant.family, VariantFamily.base);
      expect(parallel.printing!.variant.family, VariantFamily.parallel);
      expect(
        {crew.printing!.variant, base.printing!.variant, parallel.printing!.variant},
        hasLength(3),
      );
    });

    test('a wrong PARALLEL guess for the crew print is corrected', () async {
      final i = await identify(lookRaw(null, 'PARALLEL', crewLook));
      expect(i.status, RecognitionStatus.identified);
      expect(i.printing!.variant.name, 'PIRATE_CREW_SUPER_PARALLEL');
      expect(i.resolution!.visionPredicted.family, VariantFamily.parallel);
    });

    test('a resolved crew print is priced from the crew listings only', () async {
      final i = await identify(
        lookRaw('PARALLEL', 'PARALLEL', crewLook),
      );
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
      final result = await service.research(
        PriceResearchRequest(printing: i.printing!),
      );
      expect((result as PriceResearchSuccess).estimatedPrice, greaterThan(1000000));
      expect(web.calls, 0);
    });
  });

  group('caching', () {
    late dynamic db;
    late PrintingCandidateRepository cache;

    setUp(() async {
      db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await db.execute('''
        CREATE TABLE printing_candidates (
          id TEXT PRIMARY KEY, game TEXT NOT NULL, cardNumber TEXT NOT NULL,
          language TEXT NOT NULL, candidates TEXT NOT NULL,
          researchedAt TEXT NOT NULL, provider TEXT
        )
      ''');
      cache = PrintingCandidateRepository(dbOverride: () => db);
    });

    tearDown(() => db.close());

    test('a card is researched once; the next scan reuses the printings', () async {
      final research = FakePrintingResearch(known(op13Printings));
      final service = PrintingResolutionService(
        research: research,
        cache: cache,
        clock: () => DateTime(2026, 10, 5),
      );
      final r = read(aceRaw());
      final first = await service.resolve(logical: r.printing!, observed: r.visual);
      final second = await service.resolve(logical: r.printing!, observed: r.visual);
      expect(research.calls, 1);
      expect(first.candidatesFrom, 'FakeResearch');
      expect(second.candidatesFrom, 'cache');
      expect(second.resolved!.variantName, 'RED_MANGA_RARE');
      expect(second.resolved!.evidenceSources, isNotEmpty);
    });

    test('stale printings are researched again; failures are never cached', () async {
      final r = read(aceRaw());
      final research = FakePrintingResearch(known(op13Printings));
      var now = DateTime(2026, 10, 5);
      final service = PrintingResolutionService(
        research: research,
        cache: cache,
        clock: () => now,
      );
      await service.resolve(logical: r.printing!, observed: r.visual);
      now = now.add(const Duration(days: 31));
      await service.resolve(logical: r.printing!, observed: r.visual);
      expect(research.calls, 2);

      final failing = FakePrintingResearch(const [], reason: 'down');
      final other = PrintingResolutionService(research: failing, cache: cache);
      final z = read(
        cannedRecognition(number: 'ZZ99-001', language: 'English'),
      );
      await other.resolve(logical: z.printing!, observed: z.visual);
      await other.resolve(logical: z.printing!, observed: z.visual);
      expect(failing.calls, 2);
    });
  });

  group('not keyed on any card', () {
    test('the same rules settle a made-up card', () async {
      final printings = [
        printingJson(
          'GLITTER_BLUE',
          'PARALLEL',
          visual(color: 'BLUE', background: 'SOLID_COLOR', panels: false),
        ),
        printingJson(
          'GLITTER_GREEN',
          'PARALLEL',
          visual(color: 'GREEN', background: 'SOLID_COLOR', panels: false),
        ),
        // Same look as the green one, but a different official rarity: not
        // this card's printing at all.
        printingJson(
          'GLITTER_GREEN_SR',
          'PARALLEL',
          visual(color: 'GREEN', background: 'SOLID_COLOR', panels: false),
          rarity: 'SR',
        ),
      ];
      String raw(String color) => cannedRecognition(
        name: 'Nonexistent Sprite',
        number: 'ZZ99-001',
        language: 'English',
        family: 'PARALLEL',
        variantName: 'GLITTER_BLUE',
        printing: 0.6,
        visual: visual(color: color, background: 'SOLID_COLOR', panels: false),
      );
      final resolver = resolverOver(known(printings));
      final green = await CardIdentifier(
        recognition: FakeRecognition(raw('GREEN')),
        resolver: resolver,
      ).identify(['x.jpg']);
      final blue = await CardIdentifier(
        recognition: FakeRecognition(raw('BLUE')),
        resolver: resolver,
      ).identify(['x.jpg']);
      expect(green.printing!.variant.name, 'GLITTER_GREEN');
      expect(
        green.resolution!.rejected.map((x) => x.reason),
        contains('official rarity SR ≠ SEC'),
      );
      expect(blue.printing!.variant.name, 'GLITTER_BLUE');
    });

    test('no card number or printing name appears as a rule in lib/', () {
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final text = f.readAsStringSync();
        expect(text, isNot(contains('OP13-119')), reason: f.path);
        expect(
          RegExp('''['"]RED_MANGA''').hasMatch(text),
          isFalse,
          reason: f.path,
        );
      }
    });
  });
}
