// The Japanese multi-source research: every marketplace is asked about the
// exact printing, one failing never sinks the rest, a printing no marketplace
// has is "insufficient evidence" (never another printing's price), and the
// live web search runs only as the fallback. Real saved pages for EB04-061
// drive the end-to-end cases; fakes drive the orchestration rules.

import 'package:flutter_test/flutter_test.dart';

import 'package:pokedex_tcg/models/printing_variant.dart';
import 'package:pokedex_tcg/models/tcg_game.dart';
import 'package:pokedex_tcg/pricing/cardrush_price_source.dart';
import 'package:pokedex_tcg/pricing/estarbox_price_source.dart';
import 'package:pokedex_tcg/pricing/japanese_price_research_service.dart';
import 'package:pokedex_tcg/pricing/japanese_price_source.dart';
import 'package:pokedex_tcg/pricing/price_research_service.dart';
import 'package:pokedex_tcg/pricing/pricing_config.dart';
import 'package:pokedex_tcg/pricing/yuyutei_price_service.dart';

import 'support/jp_pricing_fixtures.dart';

const _noEvidence = InsufficientEvidence(rawResponse: '', reason: 'nothing');

JapanesePriceResearchService _service(
  List<JapanesePriceSource> sources, {
  PriceResearchService? web,
  PricingConfig config = const PricingConfig(),
}) => JapanesePriceResearchService(
  sources: sources,
  fallback: web ?? FakeWebResearch(_noEvidence),
  config: config,
  clock: () => DateTime(2026, 10, 5),
);

/// The three real sources over the saved EB04-061 pages.
List<JapanesePriceSource> _realSources() {
  final now = DateTime(2026, 10, 5);
  return [
    YuyuteiPriceSource(fetch: yuyuteiFetch(), clock: () => now),
    CardRushPriceSource(fetch: cardRushFetch(), clock: () => now),
    EStarboxPriceSource(fetch: eStarboxFetch(), clock: () => now),
  ];
}

Set<String> _usedMarketplaces(PriceResearchSuccess r) => {
  for (final s in r.sources)
    if (s.usedInEstimate) s.marketplace!,
};

SourceStatus _status(PriceResearchResult r, String marketplace) =>
    r.reports.singleWhere((x) => x.marketplace == marketplace).status;

/// A YuYu-tei source whose page has only the ordinary EB04-061 prints.
YuyuteiPriceSource _yuyuteiWithoutCrew() => YuyuteiPriceSource(
  fetch: (_) async => yuyuteiPage([
    ('EB04-061', 'SEC', 'モンキー・D・ルフィ', 1480, false),
    ('EB04-061', 'P-SEC', 'モンキー・D・ルフィ(パラレル)', 5980, false),
  ]),
  clock: () => DateTime(2026, 10, 5),
);

void main() {
  group('EB04-061 end to end over the three real saved sources', () {
    test('crew-background print: all three find it, price is the median of '
        'the in-stock ones, the sold-out YuYu-tei listing is shown but not '
        'used', () async {
      final r = await _service(_realSources()).research(request(crewPrinting));
      r as PriceResearchSuccess;
      expect(r.currency, 'JPY');
      expect(r.estimatedPrice, 1489000); // median of 1,580,000 and 1,398,000
      expect(r.low, 1398000);
      expect(r.high, 1580000);
      expect(_usedMarketplaces(r), {'CardRush', 'e-Starbox'});

      final yuyutei = r.sources.singleWhere(
        (s) => s.marketplace == 'Yuyu-tei' && s.price == 1280000,
      );
      expect(yuyutei.usedInEstimate, isFalse);
      expect(yuyutei.soldOut, isTrue);
      expect(yuyutei.notUsedReason, contains('sold out'));

      for (final m in ['Yuyu-tei', 'CardRush', 'e-Starbox']) {
        expect(_status(r, m), SourceStatus.match, reason: m);
      }
      expect(r.warnings, isEmpty);
    });

    test('URLs and source types survive onto the observations', () async {
      final r = await _service(_realSources()).research(request(crewPrinting));
      r as PriceResearchSuccess;
      final cardRush = r.sources.singleWhere(
        (s) => s.marketplace == 'CardRush' && s.usedInEstimate,
      );
      expect(cardRush.url, 'https://www.cardrush-op.jp/product/14531');
      expect(cardRush.type, SourceType.currentListing);
      expect(cardRush.sourceLabel, contains('海賊団背景'));
      final eStarbox = r.sources.singleWhere(
        (s) => s.marketplace == 'e-Starbox' && s.usedInEstimate,
      );
      expect(eStarbox.url, contains('OPEB04%2F061SEC3'));
      expect(eStarbox.type, SourceType.priceComparison);
      expect(eStarbox.sourceLabel, contains('海賊団パラレル'));
      final yuyutei = r.sources.singleWhere(
        (s) => s.marketplace == 'Yuyu-tei' && s.price == 1280000,
      );
      expect(yuyutei.url, startsWith('https://yuyu-tei.jp/sell/opc/card/'));
      expect(yuyutei.sourceLabel, contains('海賊団スーパーパラレル'));
      // Every counted observation was matched to the printing.
      expect(
        r.sources
            .where((s) => s.usedInEstimate)
            .every((s) => s.matchConfidence == 1.0),
        isTrue,
      );
    });

    test(
      'base and parallel get their own prices, never the crew print\'s',
      () async {
        final base =
            await _service(_realSources()).research(request(basePrinting))
                as PriceResearchSuccess;
        final parallel =
            await _service(_realSources()).research(request(parallelPrinting))
                as PriceResearchSuccess;
        expect(base.estimatedPrice, lessThan(2000));
        expect(parallel.estimatedPrice, inInclusiveRange(4000, 6000));
        expect(
          base.sources
              .where((s) => s.usedInEstimate)
              .every((s) => s.price < 2000),
          isTrue,
        );
      },
    );

    test(
      'the three printings of one number are three different prices',
      () async {
        final prices = <double>[];
        for (final v in [basePrinting, parallelPrinting, crewPrinting]) {
          final r = await _service(_realSources()).research(request(v));
          prices.add((r as PriceResearchSuccess).estimatedPrice);
        }
        expect(prices.toSet(), hasLength(3));
        expect(prices[0] < prices[1] && prices[1] < prices[2], isTrue);
      },
    );
  });

  group('one source misses, others find it', () {
    test('YuYu-tei misses, CardRush finds the exact printing', () async {
      final r = await _service([
        _yuyuteiWithoutCrew(),
        CardRushPriceSource(fetch: cardRushFetch()),
        FakeSource('e-Starbox', (_) async => noMatch('e-Starbox')),
      ]).research(request(crewPrinting));
      r as PriceResearchSuccess;
      expect(r.estimatedPrice, 1580000);
      expect(_usedMarketplaces(r), {'CardRush'});
      expect(_status(r, 'Yuyu-tei'), SourceStatus.noMatch);
      // The ordinary prints YuYu-tei did list are shown, not used.
      expect(
        r.sources
            .where((s) => s.marketplace == 'Yuyu-tei')
            .every((s) => !s.usedInEstimate),
        isTrue,
      );
    });

    test('YuYu-tei misses, e-Starbox finds the exact printing', () async {
      final r = await _service([
        _yuyuteiWithoutCrew(),
        FakeSource('CardRush', (_) async => noMatch('CardRush')),
        EStarboxPriceSource(fetch: eStarboxFetch()),
      ]).research(request(crewPrinting));
      r as PriceResearchSuccess;
      expect(r.estimatedPrice, 1398000);
      expect(_usedMarketplaces(r), {'e-Starbox'});
      expect(_status(r, 'e-Starbox'), SourceStatus.match);
    });

    test(
      'YuYu-tei misses, both others find it → two supporting sources',
      () async {
        final r = await _service([
          _yuyuteiWithoutCrew(),
          CardRushPriceSource(fetch: cardRushFetch()),
          EStarboxPriceSource(fetch: eStarboxFetch()),
        ]).research(request(crewPrinting));
        r as PriceResearchSuccess;
        expect(_usedMarketplaces(r), {'CardRush', 'e-Starbox'});
        expect(r.estimatedPrice, 1489000);
        expect(_status(r, 'Yuyu-tei'), SourceStatus.noMatch);
      },
    );

    test('one source failing does not discard the others', () async {
      final r = await _service([
        FakeSource(
          'Yuyu-tei',
          (_) async => SourceResult.failed('Yuyu-tei', 'offline'),
        ),
        CardRushPriceSource(fetch: cardRushFetch()),
        FakeSource('e-Starbox', (_) async => throw Exception('boom')),
      ]).research(request(crewPrinting));
      r as PriceResearchSuccess;
      expect(r.estimatedPrice, 1580000);
      expect(_status(r, 'Yuyu-tei'), SourceStatus.retrievalFailed);
      expect(_status(r, 'e-Starbox'), SourceStatus.retrievalFailed);
      expect(_status(r, 'CardRush'), SourceStatus.match);
    });

    test('a source slower than the timeout counts as failed', () async {
      final r = await _service(
        [
          FakeSource(
            'Slow',
            (_) => Future.delayed(
              const Duration(seconds: 2),
              () => matched('Slow', [observation('Slow', 100)]),
            ),
          ),
          FakeSource(
            'Fast',
            (_) async => matched('Fast', [observation('Fast', 200)]),
          ),
        ],
        config: const PricingConfig(
          japaneseSourceTimeout: Duration(milliseconds: 50),
        ),
      ).research(request(basePrinting));
      r as PriceResearchSuccess;
      expect(r.estimatedPrice, 200);
      expect(_status(r, 'Slow'), SourceStatus.retrievalFailed);
    });
  });

  group('never another printing\'s price', () {
    test('the crew print is not listed anywhere → insufficient evidence, '
        'neither the plain nor the parallel price used', () async {
      final r = await _service([
        _yuyuteiWithoutCrew(),
        FakeSource('CardRush', (_) async => noMatch('CardRush')),
        FakeSource('e-Starbox', (_) async => noMatch('e-Starbox')),
      ]).research(request(crewPrinting));
      r as InsufficientEvidence;
      expect(r.sources.where((s) => s.usedInEstimate), isEmpty);
      expect(r.sources.map((s) => s.price), containsAll([1480.0, 5980.0]));
      expect(
        r.reports.map((x) => x.status),
        everyElement(
          isIn([SourceStatus.noMatch, SourceStatus.insufficientEvidence]),
        ),
      );
    });

    test(
      'OP13-118 Red Manga: no verified labels → insufficient evidence',
      () async {
        final page = yuyuteiPage([
          ('OP13-118', 'SEC', 'モンキー・D・ルフィ', 780, false),
          ('OP13-118', 'P-SEC', 'モンキー・D・ルフィ(パラレル)', 12800, false),
          ('OP13-118', 'P-SEC', 'モンキー・D・ルフィ(パラレル)(スーパーパラレル)', 178000, true),
        ]);
        final r =
            await _service([
              YuyuteiPriceSource(fetch: (_) async => page),
              CardRushPriceSource(fetch: cardRushFetch()),
              EStarboxPriceSource(fetch: eStarboxFetch()),
            ]).research(
              PriceResearchRequest(
                printing: printing(redMangaPrinting, number: 'OP13-118'),
              ),
            );
        r as InsufficientEvidence;
        expect(r.sources.where((s) => s.usedInEstimate), isEmpty);
        expect(r.sources, hasLength(3));
      },
    );

    test('several equally good listings are ambiguous, not averaged', () async {
      final html = [
        cardRushCell(1, 'モンキー・D・ルフィ(海賊団背景)【SEC】{EB04-061[OP17]}', 1580000),
        cardRushCell(2, 'モンキー・D・ルフィ(海賊団背景)【SEC】{EB04-061[OP17]}', 1480000),
      ].join();
      final r = await _service([
        CardRushPriceSource(fetch: (_) async => html),
      ]).research(request(crewPrinting));
      r as InsufficientEvidence;
      expect(_status(r, 'CardRush'), SourceStatus.insufficientEvidence);
      expect(r.sources.where((s) => s.usedInEstimate), isEmpty);
    });

    test(
      'every source failing → retrieval failed, not "no evidence"',
      () async {
        final r = await _service(
          [
            FakeSource('A', (_) async => SourceResult.failed('A', 'x')),
            FakeSource('B', (_) async => SourceResult.failed('B', 'y')),
          ],
          web: FakeWebResearch(
            const RetrievalFailed(rawResponse: '', reason: 'no net'),
          ),
        ).research(request(basePrinting));
        expect(r, isA<RetrievalFailed>());
        expect(r.reports, hasLength(3));
      },
    );

    test('a match below the confidence bar is not used', () async {
      final low = observation('A', 500).withUse(true);
      final r = await _service([
        FakeSource(
          'A',
          (_) async => matched('A', [
            PriceSource(
              name: 'A',
              marketplace: 'A',
              type: SourceType.currentListing,
              price: low.price,
              currency: 'JPY',
              isGraded: false,
              url: low.url,
              usedInEstimate: true,
              matchConfidence: 0.6,
            ),
          ]),
        ),
      ]).research(request(basePrinting));
      expect(r, isA<InsufficientEvidence>());
    });
  });

  group('how prices combine', () {
    test('sold-out listings are used only when nothing is in stock', () async {
      final onlySoldOut = await _service([
        FakeSource(
          'A',
          (_) async => matched('A', [observation('A', 900, soldOut: true)]),
        ),
        FakeSource(
          'B',
          (_) async => matched('B', [observation('B', 1100, soldOut: true)]),
        ),
      ]).research(request(basePrinting));
      onlySoldOut as PriceResearchSuccess;
      expect(onlySoldOut.estimatedPrice, 1000);
      expect(onlySoldOut.warnings.single, contains('sold-out'));
      expect(onlySoldOut.confidence, lessThanOrEqualTo(0.2));

      final mixed = await _service([
        FakeSource(
          'A',
          (_) async => matched('A', [observation('A', 900, soldOut: true)]),
        ),
        FakeSource('B', (_) async => matched('B', [observation('B', 1100)])),
      ]).research(request(basePrinting));
      mixed as PriceResearchSuccess;
      expect(mixed.estimatedPrice, 1100);
      expect(
        mixed.sources.singleWhere((s) => s.price == 900).notUsedReason,
        contains('sold out'),
      );
    });

    test('a wide spread between exact matches is flagged and capped', () async {
      final r = await _service([
        FakeSource('A', (_) async => matched('A', [observation('A', 1000)])),
        FakeSource('B', (_) async => matched('B', [observation('B', 5000)])),
      ]).research(request(basePrinting));
      r as PriceResearchSuccess;
      expect(r.warnings.single, contains('differ widely'));
      expect(r.confidence, lessThanOrEqualTo(0.3));
    });

    test('buyback prices are never part of the estimate', () async {
      final r = await _service([
        FakeSource(
          'A',
          (_) async => matched('A', [
            observation('A', 100, type: SourceType.buyback),
            observation('A', 900),
          ]),
        ),
      ]).research(request(basePrinting));
      r as PriceResearchSuccess;
      expect(r.estimatedPrice, 900);
    });

    test(
      'only same-kind prices are combined: a sale beats asking prices',
      () async {
        final r = await _service([
          FakeSource(
            'A',
            (_) async => matched('A', [
              observation('A', 700, type: SourceType.recentSold),
              observation('A', 5000),
            ]),
          ),
        ]).research(request(basePrinting));
        r as PriceResearchSuccess;
        expect(r.estimatedPrice, 700);
      },
    );
  });

  group('the web search fallback', () {
    test(
      'runs only when no source matched, with the full printing and JPY',
      () async {
        final web = FakeWebResearch(
          PriceResearchSuccess(
            rawResponse: 'raw',
            estimatedPrice: 1400000,
            low: 1390000,
            high: 1410000,
            currency: 'JPY',
            confidence: 0.4,
            sources: [observation('Somewhere', 1400000)],
            researchedAt: DateTime(2026, 10, 5),
            searchCalls: 2,
          ),
        );
        final r = await _service([
          FakeSource('A', (_) async => noMatch('A')),
        ], web: web).research(request(crewPrinting));
        r as PriceResearchSuccess;
        expect(web.calls, 1);
        expect(web.got!.printing.variant, crewPrinting);
        expect(web.got!.printing.cardNumber, 'EB04-061');
        expect(web.got!.currency, 'JPY');
        expect(r.estimatedPrice, 1400000);
        expect(r.reports.map((x) => x.marketplace), ['A', 'Web search']);
      },
    );

    test(
      'does not run when a marketplace already has the exact printing',
      () async {
        final web = FakeWebResearch(_noEvidence);
        await _service([
          FakeSource('A', (_) async => matched('A', [observation('A', 1000)])),
        ], web: web).research(request(basePrinting));
        expect(web.calls, 0);
      },
    );

    test(
      'finding nothing either → insufficient evidence, still no substitute',
      () async {
        final web = FakeWebResearch(_noEvidence);
        final r = await _service([
          _yuyuteiWithoutCrew(),
        ], web: web).research(request(crewPrinting));
        expect(web.calls, 1);
        r as InsufficientEvidence;
        expect(r.sources.where((s) => s.usedInEstimate), isEmpty);
        expect(r.reports.last.marketplace, 'Web search');
      },
    );

    test('can be switched off', () async {
      final web = FakeWebResearch(_noEvidence);
      await _service(
        [FakeSource('A', (_) async => noMatch('A'))],
        web: web,
        config: const PricingConfig(japaneseWebFallback: false),
      ).research(request(basePrinting));
      expect(web.calls, 0);
    });
  });

  group('what it handles', () {
    test(
      'an unknown printing is refused before any marketplace is asked',
      () async {
        final source = FakeSource('A', (_) async => noMatch('A'));
        final r = await _service([
          source,
        ]).research(request(PrintingVariant.unknown));
        expect(r, isA<PrintingVerificationRequired>());
        expect(source.calls, 0);
      },
    );

    test('other languages and games go to the fallback untouched', () async {
      final web = FakeWebResearch(_noEvidence);
      final source = FakeSource('A', (_) async => noMatch('A'));
      final service = _service([source], web: web);
      final english = PriceResearchRequest(
        printing: printing(basePrinting, language: 'English'),
      );
      await service.research(english);
      expect(web.got, same(english));
      final pokemon = PriceResearchRequest(
        printing: printing(basePrinting, game: TcgGame.pokemon),
      );
      await service.research(pokemon);
      expect(web.got, same(pokemon));
      expect(source.calls, 0);
    });
  });
}
