import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/printing_variant.dart';
import '../models/tcg_game.dart';
import '../pricing/price_research_service.dart';
import 'app_database.dart';

/// One marketplace observation of one exact physical printing, as researched
/// at one time. Rows are append-only history: a new research adds rows, never
/// changes or removes old ones, and the printing columns keep a price from
/// ever being read back for a different printing of the same card number.
class PriceObservation {
  const PriceObservation({
    required this.id,
    required this.game,
    required this.cardNumber,
    required this.language,
    required this.variant,
    required this.marketplace,
    required this.sourceType,
    required this.url,
    required this.price,
    required this.currency,
    required this.usedInEstimate,
    required this.researchedAt,
    this.cardId,
    this.officialRarity,
    this.sourceLabel,
    this.isGraded = false,
    this.soldOut = false,
    this.condition,
    this.matchConfidence,
    this.notUsedReason,
    this.observedAt,
    this.provider,
  });

  final String id;

  /// The saved card this research was run for, if any. No foreign key: the
  /// history outlives the card.
  final String? cardId;

  // The printing.
  final TcgGame game;
  final String cardNumber;
  final String language;
  final String? officialRarity;
  final PrintingVariant variant;

  // The observation.
  final String marketplace;
  final SourceType sourceType;

  /// The marketplace's own wording, exactly as shown.
  final String? sourceLabel;
  final String url;
  final double price;
  final String currency;
  final bool isGraded;
  final bool soldOut;
  final String? condition;
  final double? matchConfidence;
  final bool usedInEstimate;
  final String? notUsedReason;

  /// When the listing says it was seen/updated, if it said.
  final DateTime? observedAt;
  final DateTime researchedAt;
  final String? provider;

  Map<String, Object?> toMap() => {
    'id': id,
    'cardId': cardId,
    'game': game.code,
    'cardNumber': cardNumber,
    'language': language,
    'officialRarity': officialRarity,
    'variantFamily': variant.family.code,
    'variantName': variant.name,
    'artworkVariant': variant.artwork,
    'marketplace': marketplace,
    'sourceType': sourceType.code,
    'sourceLabel': sourceLabel,
    'url': url,
    'price': price,
    'currency': currency,
    'isGraded': isGraded ? 1 : 0,
    'soldOut': soldOut ? 1 : 0,
    'condition': condition,
    'matchConfidence': matchConfidence,
    'usedInEstimate': usedInEstimate ? 1 : 0,
    'notUsedReason': notUsedReason,
    'observedAt': observedAt?.toIso8601String(),
    'researchedAt': researchedAt.toIso8601String(),
    'provider': provider,
  };

  factory PriceObservation.fromMap(Map<String, Object?> m) => PriceObservation(
    id: m['id'] as String,
    cardId: m['cardId'] as String?,
    game: TcgGame.fromCode(m['game'] as String?) ?? TcgGame.onePiece,
    cardNumber: m['cardNumber'] as String,
    language: m['language'] as String,
    officialRarity: m['officialRarity'] as String?,
    variant: PrintingVariant(
      family: VariantFamily.fromCode(m['variantFamily'] as String?),
      name: m['variantName'] as String?,
      artwork: m['artworkVariant'] as String?,
    ),
    marketplace: m['marketplace'] as String,
    sourceType:
        SourceType.fromCode(m['sourceType'] as String?) ??
        SourceType.currentListing,
    sourceLabel: m['sourceLabel'] as String?,
    url: m['url'] as String,
    price: (m['price'] as num).toDouble(),
    currency: m['currency'] as String,
    isGraded: (m['isGraded'] as int? ?? 0) == 1,
    soldOut: (m['soldOut'] as int? ?? 0) == 1,
    condition: m['condition'] as String?,
    matchConfidence: (m['matchConfidence'] as num?)?.toDouble(),
    usedInEstimate: (m['usedInEstimate'] as int? ?? 0) == 1,
    notUsedReason: m['notUsedReason'] as String?,
    observedAt: m['observedAt'] == null
        ? null
        : DateTime.tryParse(m['observedAt'] as String),
    researchedAt: DateTime.parse(m['researchedAt'] as String),
    provider: m['provider'] as String?,
  );
}

/// Append-only price history. Stores every observation of a research —
/// including the ones left out of the estimate, flagged as such — so the
/// record shows what each marketplace said for which printing.
class PriceObservationRepository {
  PriceObservationRepository({Database Function()? dbOverride})
    : _dbOverride = dbOverride;

  final Database Function()? _dbOverride;
  static const _uuid = Uuid();

  Future<Database> get _db async =>
      _dbOverride != null ? _dbOverride() : AppDatabase.instance.database;

  /// Saves the observations of [result] for [printing]. A result with no
  /// sources (a refusal, a failure) saves nothing.
  Future<int> record(
    PrintingDescriptor printing,
    PriceResearchResult result, {
    String? cardId,
    String? provider,
    DateTime? now,
  }) async {
    final sources = switch (result) {
      PriceResearchSuccess() => result.sources,
      InsufficientEvidence() => result.sources,
      _ => const <PriceSource>[],
    };
    if (sources.isEmpty) return 0;
    final researchedAt = result is PriceResearchSuccess
        ? result.researchedAt
        : (now ?? DateTime.now());
    final db = await _db;
    final batch = db.batch();
    for (final s in sources) {
      batch.insert(
        'price_observations',
        PriceObservation(
          id: _uuid.v4(),
          cardId: cardId,
          game: printing.game,
          cardNumber: printing.cardNumber,
          language: printing.language,
          officialRarity: printing.rarity,
          variant: printing.variant,
          marketplace: s.marketplace ?? s.name,
          sourceType: s.type,
          sourceLabel: s.sourceLabel ?? s.title,
          url: s.url,
          price: s.price,
          currency: s.currency,
          isGraded: s.isGraded,
          soldOut: s.soldOut,
          condition: s.condition,
          matchConfidence: s.matchConfidence,
          usedInEstimate: s.usedInEstimate,
          notUsedReason: s.notUsedReason,
          observedAt: s.observedAt,
          researchedAt: researchedAt,
          provider: provider,
        ).toMap(),
      );
    }
    await batch.commit(noResult: true);
    return sources.length;
  }

  /// Every observation of exactly this printing (game, number, language,
  /// family and specific name), newest research first. Another printing of the
  /// same number is never included.
  Future<List<PriceObservation>> forPrinting(PrintingDescriptor p) async {
    final db = await _db;
    final name = p.variant.name;
    final rows = await db.query(
      'price_observations',
      where:
          'game = ? AND cardNumber = ? AND language = ? AND variantFamily = ? '
          'AND ${name == null ? 'variantName IS NULL' : 'variantName = ?'}',
      whereArgs: [
        p.game.code,
        p.cardNumber,
        p.language,
        p.variant.family.code,
        ?name,
      ],
      orderBy: 'researchedAt DESC, price DESC',
    );
    return rows.map(PriceObservation.fromMap).toList();
  }
}
