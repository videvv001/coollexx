// One real price-research call, run from the dev machine:
//
//   dart run tool/price_research_spike.dart            (OpenAI)
//   dart run tool/price_research_spike.dart deepseek   (DeepSeek, experimental)
//
// Reads the key from lib/dev_secrets.dart (gitignored). Prints the parsed
// result, token usage, and saves the raw response next to this file as
// price_research_spike.out.json (gitignored) for inspection.

import 'dart:convert';
import 'dart:io';

import 'package:pokedex_tcg/dev_secrets.dart';
import 'package:pokedex_tcg/models/printing_variant.dart';
import 'package:pokedex_tcg/models/tcg_game.dart';
import 'package:pokedex_tcg/pricing/responses_price_research_service.dart';
import 'package:pokedex_tcg/pricing/price_research_service.dart';

Future<void> main(List<String> args) async {
  // `jp` researches the Japanese printing, which is limited to Yuyu-tei.
  final request = PriceResearchRequest(
    printing: PrintingDescriptor(
      game: TcgGame.onePiece,
      name: 'Monkey.D.Luffy',
      cardNumber: 'OP13-118',
      language: args.contains('jp') ? 'Japanese' : 'English',
      variant: const PrintingVariant(
        family: VariantFamily.superParallel,
        name: 'RED_MANGA_RARE',
      ),
    ),
  );
  stdout.writeln('Researching:\n${describeResearchTarget(request)}\n');
  final sw = Stopwatch()..start();
  final PriceResearchService service = args.contains('deepseek')
      ? DeepSeekPriceResearchService(apiKey: deepseekApiKey)
      : OpenAIPriceResearchService(apiKey: openaiApiKey);
  stdout.writeln('Provider: ${service.provider}');
  final result = await service.research(request);
  stdout.writeln('Took ${sw.elapsed.inSeconds}s → ${result.runtimeType}');

  File(
    'tool/price_research_spike.${service.provider.toLowerCase()}.out.json',
  ).writeAsStringSync(result.rawResponse);
  switch (result) {
    case PriceResearchSuccess s:
      stdout.writeln(
        '${s.currency} ${s.estimatedPrice} (range ${s.low}–${s.high}), '
        'confidence ${s.confidence.toStringAsFixed(2)}, '
        '${s.observationCount} observations, ${s.searchCalls} search calls',
      );
      final sold = s.lastSold, listed = s.lowestListing;
      if (sold != null) {
        stdout.writeln(
          'Last sold: ${sold.price} ${sold.currency} (${sold.observedAt})',
        );
      }
      if (listed != null) {
        stdout.writeln('Lowest listing: ${listed.price} ${listed.currency}');
      }
      for (final src in s.sources) {
        stdout.writeln(
          '  [${src.usedInEstimate ? 'used' : 'kept'}] ${src.type.code} '
          '${src.currency} ${src.price} — ${src.name}\n      ${src.url}',
        );
      }
    case InsufficientEvidence s:
      stdout.writeln('Insufficient evidence: ${s.reason}');
    case PrintingVerificationRequired s:
      stdout.writeln('Printing verification required: ${s.reason}');
    case RetrievalFailed s:
      stdout.writeln('Retrieval failed: ${s.reason}');
  }
  try {
    final usage = (jsonDecode(result.rawResponse) as Map)['usage'];
    stdout.writeln('Usage: ${jsonEncode(usage)}');
  } catch (_) {}
}
