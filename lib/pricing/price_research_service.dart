import '../models/printing_variant.dart';
import '../models/tcg_card.dart';
import '../models/tcg_game.dart';

/// Researches the current market price of one exact physical printing via
/// live internet research. Implementations must never answer from model
/// memory: a result without evidence of a live search is a
/// [RetrievalFailed], not a price.
abstract interface class PriceResearchService {
  /// Human-readable provider name, stored/shown with results.
  String get provider;

  Future<PriceResearchResult> research(PriceResearchRequest request);
}

/// Where a descriptor's [PrintingDescriptor.variant] came from. Only a vision
/// model's unchecked guess is refused by [requireExactPrinting].
enum PrintingSource {
  /// A person set or confirmed it (saved cards, edits in the test screens).
  userConfirmed,

  /// `PrintingResolutionService` matched the photo to a known printing.
  resolved,

  /// The vision model's prediction, not yet resolved. Never priced.
  visionHypothesis,
}

/// The already-resolved exact physical printing. Card number alone is never
/// enough — language and [variant] are part of what is being priced, and a
/// descriptor whose variant is still unknown is refused by
/// [requireExactPrinting].
class PrintingDescriptor {
  const PrintingDescriptor({
    required this.game,
    required this.name,
    required this.cardNumber,
    required this.language,
    this.standard,
    this.setCode,
    this.rarity,
    this.variant = PrintingVariant.unknown,
    this.source = PrintingSource.userConfirmed,
    this.searchAliases = const [],
    this.excludedAliases = const [],
    this.visualMarkers = const [],
  });

  /// A saved card as a pricing target, or null when it lacks what pricing
  /// needs (name, number, language) or isn't in a game with a catalog.
  static PrintingDescriptor? fromCard(TcgCard card, TcgGame? game) {
    final name = card.name?.trim();
    final number = card.number?.trim();
    final language = card.language?.printed;
    if (game == null ||
        name == null ||
        name.isEmpty ||
        number == null ||
        number.isEmpty ||
        language == null) {
      return null;
    }
    return PrintingDescriptor(
      game: game,
      name: name,
      cardNumber: number,
      language: language,
      rarity: card.rarity,
      variant: card.variant,
    );
  }

  final TcgGame game;

  /// Catalog standard, e.g. `POKEMON_JP`, `ONE_PIECE_EN`.
  final String? standard;
  final String name;
  final String cardNumber;

  /// Printed language, e.g. `English`, `Japanese`.
  final String language;
  final String? setCode;

  /// Official printed rarity, e.g. `SEC`. Many printings share it.
  final String? rarity;

  /// Which physical printing: family, specific name and artwork.
  final PrintingVariant variant;
  final PrintingSource source;

  /// What shops call this printing (discovery + matching only), and what they
  /// call the card's OTHER printings — a listing that shows only those is a
  /// different card.
  final List<String> searchAliases;
  final List<String> excludedAliases;

  /// What the printing looks like, to check a listing's artwork against.
  final List<String> visualMarkers;
}

/// Pricing must never guess which printing a card is: an unresolved variant
/// is not "base", it is a question for the user. Every pricing service calls
/// this first and returns the result when it is non-null.
PrintingVerificationRequired? requireExactPrinting(PrintingDescriptor p) =>
    p.source == PrintingSource.visionHypothesis
    ? const PrintingVerificationRequired(
        rawResponse: '',
        reason:
            'The printing is only a vision guess so far. Resolve it against '
            'the known printings of this card before pricing.',
      )
    : p.variant.isResolved
    ? null
    : const PrintingVerificationRequired(
        rawResponse: '',
        reason:
            'Which printing is this (base, parallel, …)? Set it before '
            'looking up a price.',
      );

class PriceResearchRequest {
  const PriceResearchRequest({
    required this.printing,
    this.condition = 'Near Mint',
    this.gradingCompany,
    this.grade,
    this.currency = 'USD',
  });

  final PrintingDescriptor printing;

  /// Raw condition. Ignored when [gradingCompany] is set.
  final String condition;

  /// Set (with [grade]) only when pricing a graded copy, e.g. `PSA`, `10`.
  final String? gradingCompany;
  final String? grade;
  final String currency;

  bool get isGraded => gradingCompany != null;
}

enum SourceType {
  recentSold('RECENT_SOLD'),
  marketPrice('MARKET_PRICE'),
  currentListing('CURRENT_LISTING'),

  /// A price-comparison site's figure for what shops ask (e-Starbox). Asking
  /// prices like [currentListing], but second-hand: the site, not the shop.
  priceComparison('PRICE_COMPARISON'),

  /// What a shop pays to buy the card. Never part of a value estimate.
  buyback('BUYBACK');

  final String code;
  const SourceType(this.code);

  /// Which kind of number this is, 0 = most trustworthy. Only prices of the
  /// same tier are ever combined, so a sale, a market guide and an asking
  /// price are never averaged together. Null = not a market value at all.
  int? get estimateTier => switch (this) {
    recentSold => 0,
    marketPrice => 1,
    currentListing || priceComparison => 2,
    buyback => null,
  };

  static SourceType? fromCode(String? code) {
    for (final t in values) {
      if (t.code == code) return t;
    }
    return null;
  }
}

class PriceSource {
  const PriceSource({
    required this.name,
    required this.type,
    required this.price,
    required this.currency,
    required this.isGraded,
    required this.url,
    required this.usedInEstimate,
    this.marketplace,
    this.condition,
    this.title,
    this.observedAt,
    this.originalPrice,
    this.originalCurrency,
    this.sourceLabel,
    this.matchConfidence,
    this.notUsedReason,
    this.soldOut = false,
  });

  /// The same observation with a different verdict on whether it counts.
  PriceSource withUse(bool used, [String? notUsedReason]) => PriceSource(
    name: name,
    type: type,
    price: price,
    currency: currency,
    isGraded: isGraded,
    url: url,
    usedInEstimate: used,
    marketplace: marketplace,
    condition: condition,
    title: title,
    observedAt: observedAt,
    originalPrice: originalPrice,
    originalCurrency: originalCurrency,
    sourceLabel: sourceLabel,
    matchConfidence: matchConfidence,
    notUsedReason: used ? null : (notUsedReason ?? this.notUsedReason),
    soldOut: soldOut,
  );

  final String name;
  final String? marketplace;
  final SourceType type;
  final double price;
  final String currency;
  final String? condition;
  final bool isGraded;

  /// Always a URL the research actually visited — never model-generated.
  final String url;
  final String? title;

  /// When the sale/listing happened, if the source said.
  final DateTime? observedAt;

  /// False for evidence kept for the record but excluded from the estimate
  /// (wrong currency, graded when raw was requested, …).
  final bool usedInEstimate;

  /// Set when [price] was converted from another currency (the source's own
  /// price and currency), so the UI can show what the page actually said.
  final double? originalPrice;
  final String? originalCurrency;

  /// The marketplace's own wording for the listing, exactly as shown. Never
  /// replaced by our printing names.
  final String? sourceLabel;

  /// How sure we are this listing is the exact printing asked for (1.0 =
  /// verified label + number + rarity). Null for sources that didn't match
  /// printings themselves.
  final double? matchConfidence;

  /// Why a listing was kept as evidence but left out of the estimate
  /// ("different printing", "graded", "sold out", …).
  final String? notUsedReason;

  /// Listed but not in stock.
  final bool soldOut;
}

/// What one marketplace concluded about the exact printing.
enum SourceStatus {
  /// At least one listing is verifiably this printing.
  match('MATCH'),

  /// The marketplace was read fine and has no listing of this printing.
  noMatch('NO_MATCH'),

  /// Couldn't decide: several equally good listings, or no verified way to
  /// recognise this printing on that marketplace.
  insufficientEvidence('INSUFFICIENT_EVIDENCE'),

  /// The marketplace couldn't be read (network, page shape).
  retrievalFailed('RETRIEVAL_FAILED');

  final String code;
  const SourceStatus(this.code);
}

/// One marketplace's verdict, shown to the user next to the price.
class SourceReport {
  const SourceReport({
    required this.marketplace,
    required this.status,
    this.reason = '',
  });

  final String marketplace;
  final SourceStatus status;
  final String reason;
}

sealed class PriceResearchResult {
  const PriceResearchResult({
    required this.rawResponse,
    this.reports = const [],
  });

  /// The provider's full response, kept as evidence.
  final String rawResponse;

  /// Per-marketplace verdicts, when more than one source was consulted.
  final List<SourceReport> reports;
}

class PriceResearchSuccess extends PriceResearchResult {
  const PriceResearchSuccess({
    required super.rawResponse,
    required this.estimatedPrice,
    required this.low,
    required this.high,
    required this.currency,
    required this.confidence,
    required this.sources,
    required this.researchedAt,
    required this.searchCalls,
    super.reports,
    this.warnings = const [],
  });

  /// Things worth knowing about the estimate (wide spread between sources,
  /// only sold-out listings, …).
  final List<String> warnings;

  final double estimatedPrice;
  final double low;
  final double high;
  final String currency;
  final double confidence;
  final List<PriceSource> sources;
  final DateTime researchedAt;
  final int searchCalls;

  /// "Based on N market observations".
  int get observationCount => sources.where((s) => s.usedInEstimate).length;

  /// The most recent completed sale used in the estimate. A sale whose page
  /// gave no date only wins when none have one.
  PriceSource? get lastSold {
    final sold = sources
        .where((s) => s.usedInEstimate && s.type == SourceType.recentSold)
        .toList();
    if (sold.isEmpty) return null;
    return sold.reduce((a, b) {
      final (da, db) = (a.observedAt, b.observedAt);
      if (da == null) return db == null ? a : b;
      return db != null && db.isAfter(da) ? b : a;
    });
  }

  /// The cheapest active asking price used in the estimate.
  PriceSource? get lowestListing {
    final listed = sources.where(
      (s) => s.usedInEstimate && s.type == SourceType.currentListing,
    );
    if (listed.isEmpty) return null;
    return listed.reduce((a, b) => b.price < a.price ? b : a);
  }
}

class InsufficientEvidence extends PriceResearchResult {
  const InsufficientEvidence({
    required super.rawResponse,
    required this.reason,
    this.sources = const [],
    super.reports,
  });

  final String reason;

  /// Verified evidence that was found but couldn't support an estimate.
  final List<PriceSource> sources;
}

class RetrievalFailed extends PriceResearchResult {
  const RetrievalFailed({
    required super.rawResponse,
    required this.reason,
    super.reports,
  });

  final String reason;
}

class PrintingVerificationRequired extends PriceResearchResult {
  const PrintingVerificationRequired({
    required super.rawResponse,
    required this.reason,
  });

  final String reason;
}
