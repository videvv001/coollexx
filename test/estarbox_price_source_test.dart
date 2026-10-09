// e-Starbox adapter, against the real saved card pages for EB04-061. Its
// search is useless for card numbers, so each print's page is probed by id
// (OPEB04/061SEC, …SEC1, …SEC2, …SEC3 until a 404) and judged by the rarity
// line it shows. It is a price-comparison site: observations are
// PRICE_COMPARISON and buyback prices are never read.

import 'package:flutter_test/flutter_test.dart';

import 'package:pokedex_tcg/pricing/estarbox_price_source.dart';
import 'package:pokedex_tcg/pricing/japanese_price_source.dart';
import 'package:pokedex_tcg/pricing/price_research_service.dart';

import 'support/jp_pricing_fixtures.dart';

EStarboxPriceSource _source([List<Uri>? log]) => EStarboxPriceSource(
  fetch: eStarboxFetch(log),
  clock: () => DateTime(2026, 10, 5),
);

void main() {
  test('parses a card page: name, number, rarity line, shop sale prices', () {
    final c = parseEStarboxCard(fixture('estarbox_eb04_061_sec3.html'))!;
    expect(c.name, 'モンキー・Ｄ・ルフィ（背景海賊団）');
    expect(c.number, 'EB04-061');
    expect(c.rarityLine, 'シークレットレア / 海賊団パラレル');
    expect(c.rarityCode, 'SEC');
    expect(c.tags, ['海賊団パラレル']);
    expect(c.expansion, contains('OP-17'));
    expect(c.prices.single.price, 1398000);
    expect(c.prices.single.shop, 'トレコロ');
    expect(c.prices.single.updated, DateTime(2026, 10, 4));
  });

  test('the buyback table is never read as a price', () {
    final c = parseEStarboxCard(fixture('estarbox_eb04_061_sec.html'))!;
    expect(c.prices, hasLength(1));
    expect(c.prices.single.price, 1680);
  });

  test('probes the prints by id until the first 404', () async {
    final log = <Uri>[];
    await _source(log).research(printing(basePrinting));
    expect(
      [for (final u in log) u.queryParameters['no']],
      [
        'OPEB04/061SEC',
        'OPEB04/061SEC1',
        'OPEB04/061SEC2',
        'OPEB04/061SEC3',
        'OPEB04/061SEC4',
      ],
    );
    expect(log.first.toString(), contains('no=OPEB04%2F061SEC'));
  });

  test('base → the gold-frame SEC page, as a price comparison', () async {
    final r = await _source().research(printing(basePrinting));
    expect(r.status, SourceStatus.match);
    final used = r.observations.singleWhere((o) => o.usedInEstimate);
    expect(used.price, 1680);
    expect(used.type, SourceType.priceComparison);
    expect(used.marketplace, 'e-Starbox');
    expect(used.sourceLabel, 'モンキー・D・ルフィ（金枠） [シークレットレア]');
    expect(used.title, contains('via トレコロ'));
  });

  test('parallel → the パラレル page', () async {
    final r = await _source().research(printing(parallelPrinting));
    expect(r.observations.singleWhere((o) => o.usedInEstimate).price, 4780);
  });

  test(
    'crew-background print → the 海賊団パラレル page, URL and label kept',
    () async {
      final r = await _source().research(printing(crewPrinting));
      expect(r.status, SourceStatus.match);
      final used = r.observations.singleWhere((o) => o.usedInEstimate);
      expect(used.price, 1398000);
      expect(used.url, contains('OPEB04%2F061SEC3'));
      expect(used.sourceLabel, contains('海賊団パラレル'));
      expect(used.observedAt, DateTime(2026, 10, 4));
      expect(used.matchConfidence, 1.0);
    },
  );

  test(
    'the serial-numbered promo page (SEC2) is not an SEC print of any kind',
    () async {
      for (final v in [basePrinting, parallelPrinting, crewPrinting]) {
        final r = await _source().research(printing(v));
        expect(
          r.observations
              .where((o) => o.usedInEstimate)
              .any((o) => o.url.contains('SEC2')),
          isFalse,
        );
      }
      final r = await _source().research(printing(crewPrinting));
      final promo = r.observations.singleWhere((o) => o.url.contains('SEC2'));
      expect(promo.notUsedReason, 'different printing');
      expect(promo.price, 1399980);
    },
  );

  test('no rarity → insufficient, no request made', () async {
    final log = <Uri>[];
    final r = await _source(log).research(printing(basePrinting, rarity: null));
    expect(r.status, SourceStatus.insufficientEvidence);
    expect(log, isEmpty);
  });

  test('a printing with no verified e-Starbox label → insufficient', () async {
    final r = await _source().research(printing(redMangaPrinting));
    expect(r.status, SourceStatus.insufficientEvidence);
  });

  test('no page for the number → no match', () async {
    final r = await EStarboxPriceSource(
      fetch: (u) async => throw PageNotFound(u),
    ).research(printing(basePrinting));
    expect(r.status, SourceStatus.noMatch);
  });

  test('a server error is a retrieval failure, not "not found"', () async {
    final r = await EStarboxPriceSource(
      fetch: (_) async => throw Exception('HTTP 500'),
    ).research(printing(basePrinting));
    expect(r.status, SourceStatus.retrievalFailed);
  });

  test('two pages for the same print → ambiguous', () async {
    final page = fixture('estarbox_eb04_061_sec3.html');
    final r = await EStarboxPriceSource(
      fetch: (u) async {
        final no = u.queryParameters['no'];
        if (no == 'OPEB04/061SEC' || no == 'OPEB04/061SEC1') return page;
        throw PageNotFound(u);
      },
    ).research(printing(crewPrinting));
    expect(r.status, SourceStatus.insufficientEvidence);
    expect(r.observations.every((o) => !o.usedInEstimate), isTrue);
  });
}
