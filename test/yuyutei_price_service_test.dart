// YuYu-tei adapter: reads the shop's own search (not a set page derived from
// the card number), and prices a printing only through a verified label match.
// EB04-061's crew-background print lives on OP17's page, so the old
// prefix → set-page lookup could never see it; the search finds it. Nothing
// here may fall back to "the" alternate when the printing isn't listed.

import 'package:flutter_test/flutter_test.dart';

import 'package:pokedex_tcg/pricing/price_research_service.dart';
import 'package:pokedex_tcg/pricing/yuyutei_price_service.dart';

import 'support/jp_pricing_fixtures.dart';

final _op13 = yuyuteiPage([
  ('OP13-118', 'SEC', 'モンキー・D・ルフィ', 780, false),
  ('OP13-118', 'P-SEC', 'モンキー・D・ルフィ(パラレル)', 12800, false),
  ('OP13-118', 'P-SEC', 'モンキー・D・ルフィ(パラレル)(スーパーパラレル)', 178000, true),
  ('OP13-001', 'L', 'ポートガス・D・エース', 300, false),
  ('OP13-002', 'P-L', 'ポートガス・D・エース(パラレル)', 900, false),
]);

YuyuteiPriceSource _source(String page, [List<Uri>? log]) => YuyuteiPriceSource(
  fetch: (u) async {
    log?.add(u);
    return page;
  },
  clock: () => DateTime(2026, 10, 5),
);

void main() {
  test('parses number, rarity, name, every suffix, yen price, stock, link', () {
    final e = parseYuyuteiListing(_op13);
    expect(e, hasLength(5));
    expect(e[1].number, 'OP13-118');
    expect(e[1].rarity, 'P-SEC');
    expect(e[1].name, 'モンキー・D・ルフィ(パラレル)');
    expect(e[1].price, 12800);
    expect(e[1].soldOut, isFalse);
    expect(e[2].soldOut, isTrue);
    expect(e[1].suffixes, ['パラレル']);
    expect(e[2].suffixes, ['パラレル', 'スーパーパラレル']);
    expect(e[0].suffixes, isEmpty);
    expect(e[0].isRegular, isTrue);
  });

  test('searches by card number, across sets', () async {
    final log = <Uri>[];
    await _source(
      _op13,
      log,
    ).research(printing(basePrinting, number: 'op13-118'));
    expect(
      log.single.toString(),
      'https://yuyu-tei.jp/sell/opc/s/search?search_word=OP13-118',
    );
  });

  test(
    'regular printing → the plain listing, others kept as evidence',
    () async {
      final r = await _source(
        _op13,
      ).research(printing(basePrinting, number: 'OP13-118'));
      expect(r.status, SourceStatus.match);
      final used = r.observations.where((o) => o.usedInEstimate).single;
      expect(used.price, 780);
      expect(used.currency, 'JPY');
      expect(used.type, SourceType.currentListing);
      expect(used.matchConfidence, 1.0);
      expect(r.observations, hasLength(3));
      expect(
        r.observations
            .where((o) => !o.usedInEstimate)
            .every((o) => o.notUsedReason == 'different printing'),
        isTrue,
      );
    },
  );

  test('parallel → the (パラレル) listing, rarity P-L matches L', () async {
    final r = await _source(
      _op13,
    ).research(printing(parallelPrinting, number: 'OP13-002', rarity: 'L'));
    expect(r.observations.singleWhere((o) => o.usedInEstimate).price, 900);
  });

  test('a parallel never matches the stacked super parallel listing', () async {
    final r = await _source(
      _op13,
    ).research(printing(parallelPrinting, number: 'OP13-118'));
    expect(r.observations.singleWhere((o) => o.usedInEstimate).price, 12800);
  });

  test('printing with no verified label → insufficient, nothing used '
      '(OP13-118 Red Manga)', () async {
    final r = await _source(
      _op13,
    ).research(printing(redMangaPrinting, number: 'OP13-118'));
    expect(r.status, SourceStatus.insufficientEvidence);
    expect(r.observations, hasLength(3));
    expect(r.observations.every((o) => !o.usedInEstimate), isTrue);
  });

  test('official rarity must agree with the listing', () async {
    final r = await _source(
      _op13,
    ).research(printing(parallelPrinting, number: 'OP13-002', rarity: 'SR'));
    expect(r.status, SourceStatus.noMatch);
  });

  test('two equally good listings → ambiguous, not priced', () async {
    final page = yuyuteiPage([
      ('OP13-050', 'P-R', 'ナミ(パラレル)', 500, false),
      ('OP13-050', 'P-R', 'ナミ(パラレル)', 700, false),
    ]);
    final r = await _source(
      page,
    ).research(printing(parallelPrinting, number: 'OP13-050', rarity: 'R'));
    expect(r.status, SourceStatus.insufficientEvidence);
    expect(r.observations.every((o) => !o.usedInEstimate), isTrue);
  });

  test('number not listed → no match, not a guess', () async {
    final r = await _source(
      _op13,
    ).research(printing(basePrinting, number: 'OP13-999'));
    expect(r.status, SourceStatus.noMatch);
    expect(r.observations, isEmpty);
  });

  test('network failure → retrieval failed', () async {
    final r = await YuyuteiPriceSource(
      fetch: (_) async => throw Exception('offline'),
    ).research(printing(basePrinting, number: 'OP13-118'));
    expect(r.status, SourceStatus.retrievalFailed);
  });

  group('EB04-061 (real saved search page): one number, three prints', () {
    late YuyuteiPriceSource source;
    setUp(() => source = _source(fixture('yuyutei_search_eb04_061.html')));

    test('the page has the three real listings, in the real labels', () {
      final e = parseYuyuteiListing(fixture('yuyutei_search_eb04_061.html'));
      expect(
        e
            .where((x) => x.number == 'EB04-061')
            .map((x) => '${x.rarity}|${x.suffixes.join(',')}|${x.price}'),
        ['P-SEC|パラレル,海賊団スーパーパラレル|1280000', 'P-SEC|パラレル|5980', 'SEC||1480'],
      );
    });

    test('base → the plain SEC', () async {
      final r = await source.research(printing(basePrinting));
      expect(r.observations.singleWhere((o) => o.usedInEstimate).price, 1480);
    });

    test('parallel → the (パラレル) P-SEC', () async {
      final r = await source.research(printing(parallelPrinting));
      expect(r.observations.singleWhere((o) => o.usedInEstimate).price, 5980);
    });

    test(
      'crew-background print → its own listing, sold out and flagged',
      () async {
        final r = await source.research(printing(crewPrinting));
        expect(r.status, SourceStatus.match);
        final used = r.observations.singleWhere((o) => o.usedInEstimate);
        expect(used.price, 1280000);
        expect(used.soldOut, isTrue);
        expect(used.sourceLabel, contains('海賊団スーパーパラレル'));
        expect(used.url, startsWith('https://yuyu-tei.jp/'));
      },
    );

    test('crew print is never priced as the plain parallel when only the '
        'ordinary prints are listed', () async {
      final page = yuyuteiPage([
        ('EB04-061', 'SEC', 'モンキー・D・ルフィ', 1480, false),
        ('EB04-061', 'P-SEC', 'モンキー・D・ルフィ(パラレル)', 5980, false),
      ]);
      final r = await _source(page).research(printing(crewPrinting));
      expect(r.status, SourceStatus.noMatch);
      expect(r.observations.every((o) => !o.usedInEstimate), isTrue);
      expect(r.observations, hasLength(2), reason: 'candidates still shown');
    });
  });
}
