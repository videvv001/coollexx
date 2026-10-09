// One live Japanese price lookup against YuYu-tei, CardRush and e-Starbox (no
// AI, no key needed), run from the dev machine:
//
//   dart run tool/japanese_price_spike.dart [base|parallel|crew] [EB04-061]
//
// Prints each marketplace's verdict and every observation, so the saved test
// fixtures can be checked against what the sites say today.

import 'dart:io';

import 'package:pokedex_tcg/models/printing_variant.dart';
import 'package:pokedex_tcg/models/tcg_game.dart';
import 'package:pokedex_tcg/pricing/cardrush_price_source.dart';
import 'package:pokedex_tcg/pricing/estarbox_price_source.dart';
import 'package:pokedex_tcg/pricing/japanese_price_research_service.dart';
import 'package:pokedex_tcg/pricing/price_research_service.dart';
import 'package:pokedex_tcg/pricing/pricing_config.dart';
import 'package:pokedex_tcg/pricing/yuyutei_price_service.dart';

class _NoWeb implements PriceResearchService {
  @override
  String get provider => 'none';
  @override
  Future<PriceResearchResult> research(PriceResearchRequest request) async =>
      const InsufficientEvidence(rawResponse: '', reason: 'web search off');
}

Future<void> main(List<String> args) async {
  final which = args.isEmpty ? 'crew' : args.first;
  final number = args.length > 1 ? args[1] : 'EB04-061';
  final variant = switch (which) {
    'base' => const PrintingVariant(family: VariantFamily.base),
    'parallel' => const PrintingVariant(family: VariantFamily.parallel),
    _ => const PrintingVariant(
      family: VariantFamily.superParallel,
      name: 'PIRATE_CREW_SUPER_PARALLEL',
    ),
  };
  final service = JapanesePriceResearchService(
    sources: [
      YuyuteiPriceSource(),
      CardRushPriceSource(),
      EStarboxPriceSource(),
    ],
    fallback: _NoWeb(),
    config: const PricingConfig(japaneseWebFallback: false),
  );
  final result = await service.research(
    PriceResearchRequest(
      printing: PrintingDescriptor(
        game: TcgGame.onePiece,
        name: 'Monkey.D.Luffy',
        cardNumber: number,
        language: 'Japanese',
        rarity: 'SEC',
        variant: variant,
      ),
    ),
  );
  stdout.writeln('$number · ${variant.displayLabel}');
  for (final r in result.reports) {
    stdout.writeln('  ${r.marketplace}: ${r.status.code} ${r.reason}');
  }
  final sources = switch (result) {
    PriceResearchSuccess() => result.sources,
    InsufficientEvidence() => result.sources,
    _ => const <PriceSource>[],
  };
  for (final s in sources) {
    stdout.writeln(
      '  ${s.usedInEstimate ? 'USED    ' : 'not used'} ¥${s.price.round()} '
      '${s.marketplace} ${s.type.code} ${s.sourceLabel ?? ''} '
      '${s.notUsedReason ?? ''}',
    );
  }
  switch (result) {
    case PriceResearchSuccess():
      stdout.writeln(
        '=> ¥${result.estimatedPrice.round()} '
        '(¥${result.low.round()}–¥${result.high.round()}) '
        'confidence ${result.confidence.toStringAsFixed(2)} '
        '${result.warnings}',
      );
    default:
      stdout.writeln('=> ${result.runtimeType}');
  }
}
