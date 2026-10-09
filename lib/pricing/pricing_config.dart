/// Every tunable for recognition + price research lives here — never repeat
/// these values elsewhere.
class PricingConfig {
  const PricingConfig({
    this.priceFreshness = const Duration(days: 7),
    this.insufficientRetryAfter = const Duration(days: 1),
    this.printingConfidenceThreshold = 0.85,
    this.resolutionThreshold = 0.9,
    this.printingCandidateTtl = const Duration(days: 30),
    this.resolutionBase = 0.45,
    this.resolutionPerMatch = 0.12,
    this.resolutionRivalBonus = 0.2,
    this.resolutionSoleBonus = 0.15,
    this.resolutionEvidenceBonus = 0.05,
    this.japaneseSourceTimeout = const Duration(seconds: 25),
    this.japaneseWebFallback = true,
    this.minMatchConfidence = 0.9,
    this.spreadWarningRatio = 3.0,
    this.openaiRecognitionModel = 'gpt-6-luna',
    this.deepseekRecognitionModel = 'deepseek-flash',
    this.researchModel = 'gpt-6-luna',
    this.deepseekResearchModel = 'deepseek-flash',
    this.researchReasoningEffort = 'medium',
    this.recognitionTimeout = const Duration(seconds: 90),
    this.researchTimeout = const Duration(minutes: 3),
    this.sourceRules = const {
      'english': SourceRule(
        domains: ['tcgplayer.com', 'ebay.com'],
        currency: 'USD',
      ),
    },
  });

  /// Where to look for a card printed in [language] (case-insensitive), or
  /// null to let the search roam the whole web. Restricting the search is
  /// the main lever on research time: one known site instead of many.
  SourceRule? sourceRuleFor(String language) =>
      sourceRules[language.trim().toLowerCase()];

  /// Keyed by lower-case printed language. English is limited to TCGplayer
  /// and eBay. Restricting only helps for sites the search tool has indexed:
  /// Yuyu-tei isn't (it returns only news pages), which is why Japanese One
  /// Piece is read straight from its site instead — see `YuyuteiPriceService`.
  final Map<String, SourceRule> sourceRules;

  /// A successful price younger than this is served from the database
  /// without calling price research again.
  final Duration priceFreshness;

  /// An INSUFFICIENT_EVIDENCE result is not retried (and paid for) again
  /// until it is at least this old.
  final Duration insufficientRetryAfter;

  /// Below this printing (variant) confidence, no price is researched or
  /// shown — the user is asked for another photo or to confirm.
  final double printingConfidenceThreshold;

  /// Exact-printing resolution must reach this confidence before a price is
  /// researched. Computed in code from the photo vs the known printings — the
  /// vision model's own printing confidence never decides this.
  final double resolutionThreshold;

  /// Known printings of a card are cached this long before research repeats.
  final Duration printingCandidateTtl;

  /// Resolution score = base + perMatch × (visual fields that agree, max 3)
  /// + rivalBonus (every other known printing is contradicted by the photo) or
  /// soleBonus (it is the only known printing) + evidenceBonus (the printing
  /// has a source page) + evidenceBonus (vision's own guess agrees). A rival
  /// the photo can't rule out blocks resolution outright.
  /// ponytail: uncalibrated heuristic; tune against real scans.
  final double resolutionBase;
  final double resolutionPerMatch;
  final double resolutionRivalBonus;
  final double resolutionSoleBonus;
  final double resolutionEvidenceBonus;

  /// Each Japanese marketplace gets this long; one that is slower counts as a
  /// failed retrieval and the others carry on without it.
  final Duration japaneseSourceTimeout;

  /// Run the live web search for a Japanese printing when no marketplace
  /// adapter found an exact match.
  final bool japaneseWebFallback;

  /// A listing counts toward a price only if it was matched to the printing
  /// with at least this confidence.
  final double minMatchConfidence;

  /// When the highest exact match is this many times the lowest, the price is
  /// still given but flagged and its confidence capped.
  final double spreadWarningRatio;

  final String openaiRecognitionModel;

  /// DeepSeek-V4.1-Flash. Vision only works with thinking off.
  final String deepseekRecognitionModel;

  /// OpenAI research model (needs built-in web search).
  final String researchModel;

  /// Experimental: DeepSeek's API docs say web_search is ignored.
  final String deepseekResearchModel;
  final String researchReasoningEffort;
  final Duration recognitionTimeout;

  /// Research runs several web searches inside one request; give it room.
  final Duration researchTimeout;
}

/// "Only look here, and expect prices in this currency." The currency is part
/// of the rule because a price estimate only counts sources in the requested
/// currency — a yen-only shop researched in USD would never yield an estimate.
class SourceRule {
  const SourceRule({required this.domains, required this.currency});

  /// Bare domains (no scheme), e.g. `yuyu-tei.jp`; subdomains are included.
  final List<String> domains;
  final String currency;
}
