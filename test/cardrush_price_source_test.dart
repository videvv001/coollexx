// CardRush adapter, against the real saved search page for EB04-061 (14
// products: every condition grade, graded copies, a serial-numbered promo and
// the crew-background print). A listing is the printing only by number +
// rarity + verified label; condition and graded copies are evidence, never a
// price.

import 'package:flutter_test/flutter_test.dart';

import 'package:pokedex_tcg/pricing/cardrush_price_source.dart';
import 'package:pokedex_tcg/pricing/japanese_price_source.dart';
import 'package:pokedex_tcg/pricing/price_research_service.dart';

import 'support/jp_pricing_fixtures.dart';

CardRushPriceSource _source([List<Uri>? log]) => CardRushPriceSource(
  fetch: cardRushFetch(log),
  clock: () => DateTime(2026, 10, 5),
);

PriceSource _used(SourceResult r) =>
    r.observations.singleWhere((o) => o.usedInEstimate);

void main() {
  test('parses title parts, rarity, set tag, prices and stock', () {
    final entries = parseCardRushList(fixture('cardrush_eb04_061.html'));
    expect(entries.where((e) => e.number == 'EB04-061'), hasLength(14));

    final crew = entries.firstWhere((e) => e.url.endsWith('/14531'));
    expect(crew.title, 'モンキー・D・ルフィ(海賊団背景)【SEC】{EB04-061[OP17]}');
    expect(crew.groups, ['海賊団背景']);
    expect(crew.rarity, 'SEC');
    expect(crew.setTag, 'OP17');
    expect(crew.price, 1580000);
    expect(crew.inStock, isTrue);
    expect(crew.prefixes, isEmpty);

    final parallel = entries.firstWhere((e) => e.url.endsWith('/11722'));
    expect(parallel.groups, ['パラレル/illust:Minato Sashima']);
    expect(parallel.rarity, 'SEC/P');
    expect(parallel.baseRarity, 'SEC');

    final graded = entries.firstWhere((e) => e.url.endsWith('/12949'));
    expect(graded.isGraded, isTrue);
    expect(graded.inStock, isFalse);

    final grade = entries.firstWhere((e) => e.url.endsWith('/11838'));
    expect(grade.prefixes, ['状態B']);
    expect(grade.isGraded, isFalse);
  });

  test('searches by card number', () async {
    final log = <Uri>[];
    await _source(log).research(printing(basePrinting));
    expect(log.single.host, 'www.cardrush-op.jp');
    expect(log.single.path, '/product-list');
    expect(log.single.queryParameters['keyword'], 'EB04-061');
  });

  test('base → the new plain SEC, not the condition-grade copies', () async {
    final r = await _source().research(printing(basePrinting));
    expect(r.status, SourceStatus.match);
    final used = _used(r);
    expect(used.price, 1780);
    expect(used.sourceLabel, 'モンキー・D・ルフィ【SEC】{EB04-061}');
    expect(
      r.observations.singleWhere((o) => o.url.endsWith('/11838')).notUsedReason,
      contains('not a new copy'),
    );
  });

  test('parallel → the new (パラレル) SEC/P, not graded or graded-down', () async {
    final r = await _source().research(printing(parallelPrinting));
    expect(_used(r).price, 4780);
    final graded = r.observations.where((o) => o.isGraded).toList();
    expect(graded, isNotEmpty);
    expect(graded.every((o) => !o.usedInEstimate), isTrue);
    expect(
      graded.singleWhere((o) => o.url.endsWith('/12949')).notUsedReason,
      contains('graded copy'),
    );
  });

  test('crew-background print → its own listing, label and URL kept', () async {
    final r = await _source().research(printing(crewPrinting));
    expect(r.status, SourceStatus.match);
    final used = _used(r);
    expect(used.price, 1580000);
    expect(used.type, SourceType.currentListing);
    expect(used.marketplace, 'CardRush');
    expect(used.url, 'https://www.cardrush-op.jp/product/14531');
    expect(used.sourceLabel, contains('海賊団背景'));
    expect(used.matchConfidence, 1.0);
    // The lower-condition crew copies are evidence only.
    expect(
      r.observations
          .where((o) => o.sourceLabel!.contains('海賊団背景') && !o.usedInEstimate)
          .length,
      greaterThanOrEqualTo(3),
    );
  });

  test(
    'the serial-numbered manga promo is never taken for any of them',
    () async {
      for (final v in [basePrinting, parallelPrinting, crewPrinting]) {
        final r = await _source().research(printing(v));
        expect(
          r.observations
              .where((o) => o.usedInEstimate)
              .any((o) => o.sourceLabel!.contains('シリアル')),
          isFalse,
        );
      }
    },
  );

  test('a printing CardRush has no verified label for → insufficient, '
      'no request made', () async {
    final log = <Uri>[];
    final r = await _source(log).research(printing(redMangaPrinting));
    expect(r.status, SourceStatus.insufficientEvidence);
    expect(log, isEmpty);
  });

  test('crew print absent (only ordinary prints listed) → no match, never '
      'the parallel price', () async {
    final html = [
      cardRushCell(1, 'モンキー・D・ルフィ【SEC】{ EB04-061 }', 1780),
      cardRushCell(
        2,
        'モンキー・D・ルフィ(パラレル/illust:Minato Sashima)【SEC/P】{ EB04-061 }',
        4780,
      ),
    ].join();
    final r = await CardRushPriceSource(
      fetch: (_) async => html,
    ).research(printing(crewPrinting));
    expect(r.status, SourceStatus.noMatch);
    expect(r.observations.every((o) => !o.usedInEstimate), isTrue);
  });

  test('two in-stock new listings of the same printing → ambiguous', () async {
    final html = [
      cardRushCell(1, 'モンキー・D・ルフィ(海賊団背景)【SEC】{ EB04-061 [OP17]}', 1580000),
      cardRushCell(2, 'モンキー・D・ルフィ(海賊団背景)【SEC】{ EB04-061 [OP17]}', 1480000),
    ].join();
    final r = await CardRushPriceSource(
      fetch: (_) async => html,
    ).research(printing(crewPrinting));
    expect(r.status, SourceStatus.insufficientEvidence);
    expect(r.observations.every((o) => !o.usedInEstimate), isTrue);
  });

  test(
    'an in-stock listing beats a sold-out one of the same printing',
    () async {
      final html = [
        cardRushCell(
          1,
          'モンキー・D・ルフィ(海賊団背景)【SEC】{ EB04-061 [OP17]}',
          1580000,
          inStock: false,
        ),
        cardRushCell(2, 'モンキー・D・ルフィ(海賊団背景)【SEC】{ EB04-061 [OP17]}', 1480000),
      ].join();
      final r = await CardRushPriceSource(
        fetch: (_) async => html,
      ).research(printing(crewPrinting));
      expect(_used(r).price, 1480000);
    },
  );

  test('network failure → retrieval failed, not an exception', () async {
    final r = await CardRushPriceSource(
      fetch: (_) async => throw Exception('offline'),
    ).research(printing(basePrinting));
    expect(r.status, SourceStatus.retrievalFailed);
  });
}
