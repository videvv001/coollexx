// Covers the trust checks on an OpenAI price-research response: no live
// search → never a price; unvisited URLs dropped; graded/currency mismatches
// kept but excluded; estimate computed from sources, not taken from the model.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:pokedex_tcg/models/printing_variant.dart';
import 'package:pokedex_tcg/models/tcg_game.dart';
import 'package:pokedex_tcg/pricing/responses_price_research_service.dart';
import 'package:pokedex_tcg/pricing/price_research_service.dart';
import 'package:pokedex_tcg/pricing/pricing_config.dart';

const _request = PriceResearchRequest(
  printing: PrintingDescriptor(
    game: TcgGame.onePiece,
    name: 'Monkey.D.Luffy',
    cardNumber: 'OP13-118',
    language: 'English',
    variant: PrintingVariant(
      family: VariantFamily.superParallel,
      name: 'RED_MANGA_RARE',
    ),
  ),
);

final _now = DateTime(2026, 10, 4);

Map<String, Object?> _source(
  String url,
  String type,
  num price, {
  bool graded = false,
  String currency = 'USD',
  String observedAt = '2026-10-01',
}) => {
  'name': 'src',
  'marketplace': null,
  'type': type,
  'price': price,
  'currency': currency,
  'condition': 'NM',
  'is_graded': graded,
  'url': url,
  'title': null,
  'observed_at': observedAt,
};

String _response({
  String status = 'completed',
  bool searched = true,
  List<String> visited = const [],
  String answerStatus = 'SUCCESS',
  List<Map<String, Object?>> sources = const [],
}) => jsonEncode({
  'status': status,
  'output': [
    if (searched)
      {
        'type': 'web_search_call',
        'status': 'completed',
        'action': {
          'type': 'search',
          'query': 'OP13-118 red manga',
          'sources': [
            for (final u in visited) {'type': 'url', 'url': u},
          ],
        },
      },
    {
      'type': 'message',
      'content': [
        {
          'type': 'output_text',
          'text': jsonEncode({
            'status': answerStatus,
            'reason': 'r',
            'sources': sources,
          }),
          'annotations': <Object>[],
        },
      ],
    },
  ],
});

void main() {
  test('request forces web search; OpenAI also asks for visited sources', () {
    final body = buildResearchRequestBody(
      _request,
      model: const PricingConfig().researchModel,
      reasoningEffort: 'medium',
    );
    expect(body['tool_choice'], 'required');
    expect(body['tools'], [
      {'type': 'web_search'},
    ]);
    expect(body.containsKey('include'), isFalse); // DeepSeek rejects it
    expect(
      openAIResearchExtraBody['include'],
      contains('web_search_call.action.sources'),
    );
    expect(
      body['input'],
      contains('Printing: Super parallel (RED_MANGA_RARE)'),
    );
    expect(body['input'], contains('Raw (ungraded)'));
  });

  test('a source rule limits the search to its sites', () {
    const config = PricingConfig(
      sourceRules: {
        'japanese': SourceRule(domains: ['example.jp'], currency: 'JPY'),
      },
    );
    final rule = config.sourceRuleFor(' Japanese ')!;
    expect(rule.currency, 'JPY');
    expect(config.sourceRuleFor('English'), isNull);
    final body = buildResearchRequestBody(
      _request,
      model: config.researchModel,
      reasoningEffort: 'medium',
      onlyDomains: rule.domains,
    );
    expect(body['tools'], [
      {
        'type': 'web_search',
        'filters': {
          'allowed_domains': ['example.jp'],
        },
      },
    ]);
    expect(body['instructions'], contains('limited to a fixed list of sites'));
  });

  test('English research defaults to TCGplayer and eBay, in USD', () {
    final rule = const PricingConfig().sourceRuleFor('English')!;
    expect(rule.domains, ['tcgplayer.com', 'ebay.com']);
    expect(rule.currency, 'USD');
  });

  test('no web search performed → RetrievalFailed, never a price', () {
    final r = parseResearchResponse(
      _response(
        searched: false,
        sources: [_source('https://ebay.com/itm/1', 'RECENT_SOLD', 3100)],
      ),
      _request,
      now: _now,
    );
    expect(r, isA<RetrievalFailed>());
  });

  test('incomplete response → RetrievalFailed', () {
    final r = parseResearchResponse(
      _response(status: 'incomplete'),
      _request,
      now: _now,
    );
    expect(r, isA<RetrievalFailed>());
  });

  test('unvisited URL is dropped; estimate is median of sold sources', () {
    final r = parseResearchResponse(
      _response(
        visited: [
          'https://www.ebay.com/itm/1?hash=x',
          'https://ebay.com/itm/2',
          'https://ebay.com/itm/3/',
          'https://tcgplayer.com/product/9',
        ],
        sources: [
          _source('https://ebay.com/itm/1', 'RECENT_SOLD', 3100),
          _source('https://ebay.com/itm/2', 'RECENT_SOLD', 3250),
          _source('https://ebay.com/itm/3', 'RECENT_SOLD', 3400),
          _source('https://tcgplayer.com/product/9', 'MARKET_PRICE', 9999),
          _source('https://made-up.example/x', 'RECENT_SOLD', 1),
        ],
      ),
      _request,
      now: _now,
    );
    expect(r, isA<PriceResearchSuccess>());
    final s = r as PriceResearchSuccess;
    expect(
      s.sources.map((x) => x.url),
      isNot(contains('https://made-up.example/x')),
    );
    expect(s.estimatedPrice, 3250);
    expect(s.low, 3100);
    expect(s.high, 3400);
    expect(s.observationCount, 4);
    expect(s.searchCalls, 1);
  });

  test(
    'other-currency source is converted at the live rate, original kept',
    () {
      final r =
          parseResearchResponse(
                _response(
                  visited: ['https://ebay.com/itm/1', 'https://ebay.com/itm/2'],
                  sources: [
                    _source(
                      'https://ebay.com/itm/1',
                      'RECENT_SOLD',
                      89,
                      currency: 'EUR',
                    ),
                    _source(
                      'https://ebay.com/itm/2',
                      'RECENT_SOLD',
                      400000,
                      currency: 'JPY',
                    ),
                  ],
                ),
                _request,
                now: _now,
                rates: {'EUR': 0.89}, // 1 USD = 0.89 EUR; no JPY rate
              )
              as PriceResearchSuccess;
      final eur = r.sources.first;
      expect(eur.price, 100.0);
      expect(eur.currency, 'USD');
      expect(eur.originalPrice, 89);
      expect(eur.originalCurrency, 'EUR');
      expect(eur.usedInEstimate, isTrue);
      // No rate for JPY → not converted, not used.
      expect(r.sources.last.usedInEstimate, isFalse);
      expect(r.sources.last.originalPrice, isNull);
      expect(r.estimatedPrice, 100.0);
    },
  );

  test(
    'lastSold is the most recent dated sale; lowestListing the cheapest',
    () {
      final r =
          parseResearchResponse(
                _response(
                  visited: [
                    for (var i = 1; i <= 5; i++) 'https://ebay.com/itm/$i',
                  ],
                  sources: [
                    _source(
                      'https://ebay.com/itm/1',
                      'RECENT_SOLD',
                      3100,
                      observedAt: '2026-09-20',
                    ),
                    _source(
                      'https://ebay.com/itm/2',
                      'RECENT_SOLD',
                      3300,
                      observedAt: '2026-09-30',
                    ),
                    _source(
                      'https://ebay.com/itm/3',
                      'RECENT_SOLD',
                      3200,
                      observedAt: 'not a date',
                    ),
                    _source('https://ebay.com/itm/4', 'CURRENT_LISTING', 3900),
                    _source('https://ebay.com/itm/5', 'CURRENT_LISTING', 3600),
                  ],
                ),
                _request,
                now: _now,
              )
              as PriceResearchSuccess;
      expect(r.lastSold!.price, 3300);
      expect(r.lowestListing!.price, 3600);
    },
  );

  test('graded and wrong-currency sources are kept but not used', () {
    final r =
        parseResearchResponse(
              _response(
                visited: [
                  'https://ebay.com/itm/1',
                  'https://ebay.com/itm/2',
                  'https://ebay.com/itm/3',
                ],
                sources: [
                  _source(
                    'https://ebay.com/itm/1',
                    'RECENT_SOLD',
                    9000,
                    graded: true,
                  ),
                  _source(
                    'https://ebay.com/itm/2',
                    'RECENT_SOLD',
                    400000,
                    currency: 'JPY',
                  ),
                  _source('https://ebay.com/itm/3', 'CURRENT_LISTING', 3500),
                ],
              ),
              _request,
              now: _now,
            )
            as PriceResearchSuccess;
    expect(r.sources, hasLength(3));
    expect(r.observationCount, 1);
    expect(r.estimatedPrice, 3500);
    expect(r.confidence, lessThanOrEqualTo(0.4)); // asking price only
  });

  test('SUCCESS with no verifiable source → InsufficientEvidence', () {
    final r = parseResearchResponse(
      _response(
        visited: ['https://ebay.com/itm/1'],
        sources: [_source('https://elsewhere.example/a', 'RECENT_SOLD', 3000)],
      ),
      _request,
      now: _now,
    );
    expect(r, isA<InsufficientEvidence>());
  });

  test('model statuses pass through', () {
    expect(
      parseResearchResponse(
        _response(answerStatus: 'INSUFFICIENT_EVIDENCE'),
        _request,
        now: _now,
      ),
      isA<InsufficientEvidence>(),
    );
    expect(
      parseResearchResponse(
        _response(answerStatus: 'PRINTING_VERIFICATION_REQUIRED'),
        _request,
        now: _now,
      ),
      isA<PrintingVerificationRequired>(),
    );
  });

  test('API error body → RetrievalFailed', () {
    final r = parseResearchResponse(
      jsonEncode({
        'error': {'message': 'Invalid API key'},
      }),
      _request,
      now: _now,
    );
    expect(r, isA<RetrievalFailed>());
    expect((r as RetrievalFailed).reason, contains('Invalid API key'));
  });

  test('empty key fails fast without a network call', () async {
    final r = await OpenAIPriceResearchService(apiKey: '').research(_request);
    expect(r, isA<RetrievalFailed>());
    final d = await DeepSeekPriceResearchService(apiKey: '').research(_request);
    expect((d as RetrievalFailed).reason, contains('DeepSeek'));
  });

  test('a plausible answer with no search proof is still rejected', () {
    // What an ignored web_search tool looks like: a confident memory-based
    // SUCCESS and no web_search_call output item.
    final r = parseResearchResponse(
      _response(
        searched: false,
        sources: [
          _source('https://ebay.com/itm/1', 'RECENT_SOLD', 3100),
          _source('https://tcgplayer.com/p/2', 'MARKET_PRICE', 3200),
        ],
      ),
      _request,
      now: _now,
    );
    expect((r as RetrievalFailed).reason, 'No live web search was performed');
  });

  test('the printing and its artwork are what the model is told to match', () {
    const request = PriceResearchRequest(
      printing: PrintingDescriptor(
        game: TcgGame.onePiece,
        name: 'x',
        cardNumber: 'EB04-061',
        language: 'Japanese',
        variant: PrintingVariant(
          family: VariantFamily.superParallel,
          name: 'PIRATE_CREW_SUPER_PARALLEL',
          artwork: 'Straw Hat crew behind Luffy',
        ),
      ),
    );
    final target = describeResearchTarget(request);
    expect(target, contains('PIRATE_CREW_SUPER_PARALLEL'));
    expect(target, contains('Artwork: Straw Hat crew behind Luffy'));
  });

  test(
    'unknown printing is refused before any request (not priced as base)',
    () async {
      const request = PriceResearchRequest(
        printing: PrintingDescriptor(
          game: TcgGame.onePiece,
          name: 'x',
          cardNumber: 'EB04-061',
          language: 'English',
        ),
      );
      final r = await OpenAIPriceResearchService(apiKey: 'k').research(request);
      expect(r, isA<PrintingVerificationRequired>());
    },
  );

  test(
    'the web-search request carries the printing and its discovery terms',
    () {
      const request = PriceResearchRequest(
        printing: PrintingDescriptor(
          game: TcgGame.onePiece,
          name: 'モンキー・D・ルフィ',
          cardNumber: 'EB04-061',
          language: 'Japanese',
          rarity: 'SEC',
          variant: PrintingVariant(
            family: VariantFamily.superParallel,
            name: 'PIRATE_CREW_SUPER_PARALLEL',
            artwork: 'Straw Hat crew behind Luffy',
          ),
        ),
        currency: 'JPY',
      );
      final target = describeResearchTarget(request);
      expect(target, contains('EB04-061'));
      expect(target, contains('Official rarity: SEC'));
      expect(target, contains('PIRATE_CREW_SUPER_PARALLEL'));
      expect(target, contains('Artwork: Straw Hat crew behind Luffy'));
      expect(target, contains('海賊団スーパーパラレル'));
      expect(target, contains('TEAM_SP'));
      expect(target, contains('to find listings only'));
      expect(target, contains('cardrush-op.jp'));
      expect(target, contains('Currency: JPY'));
    },
  );

  test('a cited page is credited to the marketplace its host belongs to', () {
    expect(
      marketplaceForUrl('https://www.cardrush-op.jp/product/14531'),
      'CardRush',
    );
    expect(
      marketplaceForUrl('https://yuyu-tei.jp/sell/opc/card/op17/10001'),
      'Yuyu-tei',
    );
    expect(
      marketplaceForUrl('https://tcgkakaku.e-starbox.com/opc/card?no=x'),
      'e-Starbox',
    );
    expect(marketplaceForUrl('https://example.com/x'), isNull);
    // A look-alike host is not the marketplace.
    expect(marketplaceForUrl('https://notyuyu-tei.jp/x'), isNull);
  });
}
