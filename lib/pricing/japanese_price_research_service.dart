import 'dart:convert';
import 'dart:math' as math;

import '../models/tcg_game.dart';
import 'japanese_price_source.dart';
import 'price_research_service.dart';
import 'pricing_config.dart';
import 'responses_price_research_service.dart';

/// Prices a Japanese card by asking several Japanese marketplaces about the
/// EXACT physical printing — not "this card number on one site".
///
///   printing → every source in parallel → each says match / no match /
///   can't tell / failed → exact matches become the evidence → price
///
/// A source failing, or finding nothing, never fails the whole research and
/// never gets another printing's price substituted: wrong-printing listings
/// are shown as not used. Which source is "more right" is not a fixed order;
/// only listings verified as the printing count, and only prices of the same
/// kind (see [SourceType.estimateTier]) are combined. When no source matches,
/// [fallback] (the live web search) gets the full printing and its search
/// terms; if that finds nothing either, the answer is
/// [InsufficientEvidence].
///
/// Everything that isn't a Japanese One Piece card goes to [fallback].
class JapanesePriceResearchService implements PriceResearchService {
  JapanesePriceResearchService({
    required this.sources,
    required this.fallback,
    this.config = const PricingConfig(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final List<JapanesePriceSource> sources;
  final PriceResearchService fallback;
  final PricingConfig config;
  final DateTime Function() _clock;

  @override
  String get provider =>
      '${sources.map((s) => s.marketplace).join(', ')} '
      '(${fallback.provider} web search as fallback)';

  static bool handles(PrintingDescriptor p) =>
      p.game == TcgGame.onePiece &&
      p.language.trim().toLowerCase() == 'japanese';

  Future<SourceResult> _ask(
    JapanesePriceSource source,
    PrintingDescriptor printing,
  ) async {
    try {
      return await source
          .research(printing)
          .timeout(config.japaneseSourceTimeout);
    } catch (e) {
      return SourceResult.failed(source.marketplace, '$e');
    }
  }

  @override
  Future<PriceResearchResult> research(PriceResearchRequest request) async {
    final printing = request.printing;
    if (!handles(printing)) return fallback.research(request);
    final unresolved = requireExactPrinting(printing);
    if (unresolved != null) return unresolved;

    final results = await Future.wait([
      for (final s in sources) _ask(s, printing),
    ]);
    final reports = [for (final r in results) r.report];
    final raw = jsonEncode({for (final r in results) r.marketplace: r.raw});
    final now = _clock();
    final all = _applyRules([for (final r in results) ...r.observations]);

    final estimate = estimateFromSources(all);
    if (estimate != null) {
      final used = all.where((s) => s.usedInEstimate).toList();
      final prices = used.map((s) => s.price);
      final warnings = <String>[];
      var confidence = estimate.confidence;
      if (used.every((s) => s.soldOut)) {
        warnings.add('Only sold-out listings; this price may be stale.');
        confidence = math.min(confidence, 0.2);
      }
      final low = prices.reduce(math.min);
      final high = prices.reduce(math.max);
      if (low > 0 && high / low >= config.spreadWarningRatio) {
        warnings.add(
          'Sources differ widely (¥${low.round()} to ¥${high.round()}).',
        );
        confidence = math.min(confidence, 0.3);
      }
      return PriceResearchSuccess(
        rawResponse: raw,
        estimatedPrice: estimate.price,
        low: estimate.low,
        high: estimate.high,
        currency: 'JPY',
        confidence: confidence,
        sources: all,
        researchedAt: now,
        searchCalls: 0,
        reports: reports,
        warnings: warnings,
      );
    }

    if (!config.japaneseWebFallback) {
      return _nothing(raw, all, reports);
    }
    final web = await fallback.research(
      PriceResearchRequest(
        printing: printing,
        condition: request.condition,
        gradingCompany: request.gradingCompany,
        grade: request.grade,
        currency: 'JPY',
      ),
    );
    switch (web) {
      case PriceResearchSuccess():
        return PriceResearchSuccess(
          rawResponse: web.rawResponse,
          estimatedPrice: web.estimatedPrice,
          low: web.low,
          high: web.high,
          currency: web.currency,
          confidence: web.confidence,
          // The adapters' not-used candidates stay visible beside the web
          // sources that carried the price.
          sources: [...web.sources, ...all],
          researchedAt: web.researchedAt,
          searchCalls: web.searchCalls,
          reports: [
            ...reports,
            const SourceReport(
              marketplace: 'Web search',
              status: SourceStatus.match,
            ),
          ],
          warnings: web.warnings,
        );
      case PrintingVerificationRequired():
        return web;
      case InsufficientEvidence():
        return _nothing(
          raw,
          [...all, ...web.sources],
          [
            ...reports,
            SourceReport(
              marketplace: 'Web search',
              status: SourceStatus.insufficientEvidence,
              reason: web.reason,
            ),
          ],
        );
      case RetrievalFailed():
        return _nothing(raw, all, [
          ...reports,
          SourceReport(
            marketplace: 'Web search',
            status: SourceStatus.retrievalFailed,
            reason: web.reason,
          ),
        ]);
    }
  }

  PriceResearchResult _nothing(
    String raw,
    List<PriceSource> sources,
    List<SourceReport> reports,
  ) {
    if (reports.every((r) => r.status == SourceStatus.retrievalFailed)) {
      return RetrievalFailed(
        rawResponse: raw,
        reason: 'No Japanese marketplace could be read.',
        reports: reports,
      );
    }
    return InsufficientEvidence(
      rawResponse: raw,
      reason:
          'No marketplace has an exact match for this printing. Nothing from '
          'a different printing was used.',
      sources: sources,
      reports: reports,
    );
  }

  /// Cross-source rules on what counts: a match below the confidence bar
  /// doesn't, and sold-out listings only when nothing is in stock anywhere.
  List<PriceSource> _applyRules(List<PriceSource> observations) {
    final confident = [
      for (final o in observations)
        o.usedInEstimate && (o.matchConfidence ?? 1) < config.minMatchConfidence
            ? o.withUse(false, 'match confidence below the bar')
            : o,
    ];
    final anyInStock = confident.any((o) => o.usedInEstimate && !o.soldOut);
    return [
      for (final o in confident)
        anyInStock && o.usedInEstimate && o.soldOut
            ? o.withUse(false, 'sold out (in-stock listings exist elsewhere)')
            : o,
    ];
  }
}
