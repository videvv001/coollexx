import 'dart:convert';
import 'dart:math' as math;

import 'exchange_rates.dart';
import 'price_research_service.dart';
import 'printing_aliases.dart';
import 'printing_resolution_service.dart';
import 'pricing_config.dart';
import 'responses_http.dart';

/// Price research over a Responses-API-compatible endpoint with the
/// built-in `web_search` tool, forced on with `tool_choice: required`. One
/// request per research — the provider may run several searches inside it.
///
/// Nothing the model says is trusted on its own: see [parseResearchResponse]
/// for the checks that turn a response into a [PriceResearchResult]. Above
/// all, no proof of a completed live search → no price, whichever provider.
class ResponsesPriceResearchService implements PriceResearchService {
  ResponsesPriceResearchService({
    required this.provider,
    required Uri endpoint,
    required String apiKey,
    required this.model,
    this.config = const PricingConfig(),
    Map<String, Object?> extraBody = const {},
    DateTime Function()? clock,
    Future<Map<String, double>> Function(String base)? rates,
  }) : _endpoint = endpoint,
       _apiKey = apiKey,
       _extraBody = extraBody,
       _clock = clock ?? DateTime.now,
       _rates = rates ?? fetchRates;

  @override
  final String provider;
  final String model;
  final PricingConfig config;
  final Uri _endpoint;
  final String _apiKey;
  final Map<String, Object?> _extraBody;
  final DateTime Function() _clock;
  final Future<Map<String, double>> Function(String base) _rates;

  @override
  Future<PriceResearchResult> research(PriceResearchRequest request) async {
    final unresolved = requireExactPrinting(request.printing);
    if (unresolved != null) return unresolved;
    if (_apiKey.isEmpty) {
      return RetrievalFailed(
        rawResponse: '',
        reason: 'No $provider API key configured (lib/dev_secrets.dart).',
      );
    }
    // A restricted site prices in its own currency; asking for any other
    // would throw away every source it finds.
    final rule = config.sourceRuleFor(request.printing.language);
    if (rule != null) {
      request = PriceResearchRequest(
        printing: request.printing,
        condition: request.condition,
        gradingCompany: request.gradingCompany,
        grade: request.grade,
        currency: rule.currency,
      );
    }
    final int status;
    final String raw;
    final Map<String, double> rates;
    try {
      // Rates are fetched alongside the search, so converting costs no time.
      final ratesFuture = _rates(request.currency.toUpperCase());
      (status, raw) = await postResponses(_endpoint, _apiKey, {
        ...buildResearchRequestBody(
          request,
          model: model,
          reasoningEffort: config.researchReasoningEffort,
          onlyDomains: rule?.domains,
        ),
        ..._extraBody,
      }, timeout: config.researchTimeout);
      rates = await ratesFuture;
    } catch (e) {
      return RetrievalFailed(rawResponse: '', reason: 'Request failed: $e');
    }
    if (status < 200 || status >= 300) {
      return RetrievalFailed(
        rawResponse: raw,
        reason: '$provider HTTP $status',
      );
    }
    return parseResearchResponse(raw, request, now: _clock(), rates: rates);
  }
}

/// OpenAI-only request fields: the full list of pages each search visited
/// (what [parseResearchResponse] checks source URLs against), and don't
/// keep the response on OpenAI's side.
const openAIResearchExtraBody = {
  'include': ['web_search_call.action.sources'],
  'store': false,
};

/// gpt-6-luna with built-in web search (see [PricingConfig.researchModel]).
class OpenAIPriceResearchService extends ResponsesPriceResearchService {
  OpenAIPriceResearchService({required super.apiKey, super.config, super.clock})
    : super(
        provider: 'OpenAI',
        endpoint: Uri.parse('https://api.openai.com/v1/responses'),
        model: config.researchModel,
        extraBody: openAIResearchExtraBody,
      );
}

/// EXPERIMENTAL. DeepSeek's Responses API docs list web_search as
/// "Ignored", so this is expected to come back as [RetrievalFailed] ("no
/// live web search") with DeepSeek's memory-based answer visible only in the
/// raw response. Kept so that claim can be tested, not assumed. `include`
/// and `store` are omitted: DeepSeek lists both as unsupported.
class DeepSeekPriceResearchService extends ResponsesPriceResearchService {
  DeepSeekPriceResearchService({
    required super.apiKey,
    super.config,
    super.clock,
  }) : super(
         provider: 'DeepSeek',
         endpoint: Uri.parse('https://api.deepseek.com/responses'),
         model: config.deepseekResearchModel,
       );
}

/// The provider-neutral Responses request body for one research task.
Map<String, Object?> buildResearchRequestBody(
  PriceResearchRequest request, {
  required String model,
  required String reasoningEffort,
  List<String>? onlyDomains,
}) => {
  'model': model,
  'reasoning': {'effort': reasoningEffort},
  'tools': [
    {
      'type': 'web_search',
      if (onlyDomains != null) 'filters': {'allowed_domains': onlyDomains},
    },
  ],
  // Forces a tool call; web_search is the only tool, so the model must
  // search. parseResearchResponse still verifies that it actually did.
  'tool_choice': 'required',
  'instructions': onlyDomains == null
      ? _instructions
      : '$_instructions\n$_restrictedSearchNote',
  'input': describeResearchTarget(request),
  'text': {
    'format': {
      'type': 'json_schema',
      'name': 'price_research',
      'strict': true,
      'schema': _schema,
    },
  },
};

/// The exact printing + condition, as handed to the model.
String describeResearchTarget(PriceResearchRequest r) {
  final p = r.printing;
  return [
    'Game: ${p.game.displayName}',
    'Card: ${p.name}',
    'Card number: ${p.cardNumber}',
    'Language: ${p.language}',
    if (p.standard != null) 'Catalog standard: ${p.standard}',
    if (p.setCode != null) 'Set: ${p.setCode}',
    if (p.rarity != null) 'Official rarity: ${p.rarity}',
    'Printing: ${p.variant.family.label}'
        '${p.variant.name == null ? '' : ' (${p.variant.name})'}',
    if (p.variant.artwork != null) 'Artwork: ${p.variant.artwork}',
    if (_searchTerms(p).isNotEmpty)
      'Search terms (to find listings only; a listing counts only if its '
          'label or artwork shows it is this printing): '
          '${_searchTerms(p).join(', ')}',
    if (p.visualMarkers.isNotEmpty)
      'What this printing looks like: ${p.visualMarkers.join('; ')}',
    if (p.excludedAliases.isNotEmpty)
      'NOT this printing (shops use these words for the other printings '
          'of this card; a listing that shows only these is a different '
          'card, whatever its price): ${p.excludedAliases.join(', ')}',
    if (p.language.trim().toLowerCase() == 'japanese')
      'Japanese marketplaces to check: yuyu-tei.jp, cardrush-op.jp, '
          'tcgkakaku.e-starbox.com (price comparison), and others',
    r.isGraded
        ? 'Condition: Graded ${r.gradingCompany} ${r.grade}'
        : 'Condition: Raw (ungraded) / ${r.condition}',
    'Currency: ${r.currency}',
  ].join('\n');
}

List<String> _searchTerms(PrintingDescriptor p) => {
  ...discoveryTermsFor(p.variant),
  ...p.searchAliases,
}.toList();

const _instructions = '''
You are a trading-card price researcher. Research the CURRENT market value of
the EXACT physical card printing described in the input.

You MUST search the live internet. Do not answer from training knowledge, and
do not estimate a price yourself. Report only evidence you found.

Only accept evidence for this exact printing. Reject evidence for:
- other languages or regional printings (e.g. Japanese, Chinese, Korean
  copies when the input is English, and vice versa)
- the base version, a regular parallel, alternate art, or any other variant
  or treatment than the one in the input (e.g. another Manga variant). The
  card number and rarity are shared by every printing: the Printing and
  Artwork lines are what identify this one, so a listing whose artwork or
  treatment differs from them is a different card
- reprints that are physically different
- graded copies (PSA, BGS, CGC, SGC, or any other) when the input is raw, and
  raw copies or other grades when the input is graded
- lots, bundles, proxies, customs, and listings that don't clearly identify
  this exact card

Classify each source:
- RECENT_SOLD: a completed sale / sold listing
- MARKET_PRICE: a marketplace or price-guide market value
- CURRENT_LISTING: an active asking price (not a sale)
Prefer recent completed sales. Use several independent sources when
practical. Report prices in the currency the source shows; do not convert
(the app converts using live exchange rates).
Also look for the most recent completed sale (with its date) and the lowest
current active listing, and report both as sources when you can find them.

For every source give the URL of the page you actually visited — never
construct, guess, or shorten a URL. Never invent prices, transactions,
sources, or dates; use null for anything the page doesn't state.

status:
- SUCCESS: you found at least one reliable source for this exact printing.
- INSUFFICIENT_EVIDENCE: you could not find reliable evidence for this exact
  printing. Do not guess.
- PRINTING_VERIFICATION_REQUIRED: the described printing seems not to exist
  or is ambiguous (e.g. that variant does not exist for this card number).
Explain your decision briefly in reason.
''';

const _restrictedSearchNote = '''
Search access is limited to a fixed list of sites, so the "several independent
sources" advice above does not apply: use what those sites show, and do not
spend searches trying to reach others. Look the card up by its card number
first. If the exact printing is not listed there, answer
INSUFFICIENT_EVIDENCE rather than substituting a different printing.
Prefer listings priced in the requested currency (e.g. US sellers on
ebay.com for USD) over ones priced in another.
''';

const _nullableString = {
  'type': ['string', 'null'],
};

const _schema = {
  'type': 'object',
  'additionalProperties': false,
  'required': ['status', 'reason', 'sources'],
  'properties': {
    'status': {
      'type': 'string',
      'enum': [
        'SUCCESS',
        'INSUFFICIENT_EVIDENCE',
        'PRINTING_VERIFICATION_REQUIRED',
      ],
    },
    'reason': {'type': 'string'},
    'sources': {
      'type': 'array',
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'required': [
          'name',
          'marketplace',
          'type',
          'price',
          'currency',
          'condition',
          'is_graded',
          'url',
          'title',
          'observed_at',
        ],
        'properties': {
          'name': {'type': 'string'},
          'marketplace': _nullableString,
          'type': {
            'type': 'string',
            'enum': ['RECENT_SOLD', 'MARKET_PRICE', 'CURRENT_LISTING'],
          },
          'price': {'type': 'number'},
          'currency': {
            'type': 'string',
            'description': 'ISO 4217 code as shown by the source, e.g. USD',
          },
          'condition': _nullableString,
          'is_graded': {'type': 'boolean'},
          'url': {'type': 'string'},
          'title': _nullableString,
          'observed_at': {
            'type': ['string', 'null'],
            'description':
                'ISO 8601 date of the sale/listing if the page states it',
          },
        },
      },
    },
  },
};

/// What a Responses web-search run did: how many searches ran and completed,
/// every page they visited or cited (as [urlKey]s), and the answer text.
/// Shared by price research and printing research so both apply the same test
/// to anything a model claims to have found.
({int searches, int completedSearches, Set<String> visited, String text})
readWebSearchRun(Map<String, dynamic> json) {
  final output = (json['output'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  final searches = output.where((o) => o['type'] == 'web_search_call').toList();
  final completed = searches.where((o) => o['status'] == 'completed').toList();
  final visited = <String>{};
  for (final s in completed) {
    final action = s['action'];
    if (action is! Map) continue;
    final url = action['url'];
    if (url is String) visited.add(urlKey(url) ?? '');
    for (final src in (action['sources'] as List?) ?? const []) {
      final u = src is Map ? src['url'] : null;
      if (u is String) visited.add(urlKey(u) ?? '');
    }
  }
  final text = StringBuffer();
  for (final o in output.where((o) => o['type'] == 'message')) {
    for (final c in (o['content'] as List?) ?? const []) {
      if (c is! Map || c['type'] != 'output_text') continue;
      text.write(c['text']);
      for (final a in (c['annotations'] as List?) ?? const []) {
        if (a is Map && a['type'] == 'url_citation' && a['url'] is String) {
          visited.add(urlKey(a['url'] as String) ?? '');
        }
      }
    }
  }
  visited.remove('');
  return (
    searches: searches.length,
    completedSearches: completed.length,
    visited: visited,
    text: text.toString(),
  );
}

/// Turns a raw Responses API body into a result, enforcing:
/// - the response completed and at least one live web search completed —
///   otherwise it's [RetrievalFailed], never a price from model memory;
/// - every source URL was actually visited/cited by that search — others
///   are dropped as possibly fabricated;
/// - graded-vs-raw and currency mismatches are kept as evidence but
///   excluded from the estimate;
/// - the estimate/range are computed here from the kept sources, not taken
///   from the model.
PriceResearchResult parseResearchResponse(
  String raw,
  PriceResearchRequest request, {
  required DateTime now,
  Map<String, double> rates = const {},
}) {
  final Map<String, dynamic> json;
  try {
    json = jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return RetrievalFailed(rawResponse: raw, reason: 'Response was not JSON');
  }
  final error = json['error'];
  if (error is Map) {
    return RetrievalFailed(
      rawResponse: raw,
      reason: 'API error: ${error['message']}',
    );
  }
  if (json['status'] != 'completed') {
    return RetrievalFailed(
      rawResponse: raw,
      reason: 'Response ${json['status']}: ${json['incomplete_details']}',
    );
  }

  final run = readWebSearchRun(json);
  if (run.completedSearches == 0) {
    return RetrievalFailed(
      rawResponse: raw,
      reason: 'No live web search was performed',
    );
  }
  final visited = run.visited;
  final text = run.text;

  final Map<String, dynamic> answer;
  try {
    answer = jsonDecode(text) as Map<String, dynamic>;
  } catch (_) {
    return RetrievalFailed(
      rawResponse: raw,
      reason: 'Research answer was not valid JSON',
    );
  }
  final reason = (answer['reason'] as String?) ?? '';

  switch (answer['status']) {
    case 'PRINTING_VERIFICATION_REQUIRED':
      return PrintingVerificationRequired(rawResponse: raw, reason: reason);
    case 'INSUFFICIENT_EVIDENCE':
      return InsufficientEvidence(rawResponse: raw, reason: reason);
    case 'SUCCESS':
      break;
    default:
      return RetrievalFailed(
        rawResponse: raw,
        reason: 'Unknown research status ${answer['status']}',
      );
  }

  final sources = <PriceSource>[];
  for (final s in (answer['sources'] as List?) ?? const []) {
    if (s is! Map) continue;
    final url = s['url'];
    final type = SourceType.fromCode(s['type'] as String?);
    final price = s['price'];
    // Unvisited URL → possibly fabricated: dropped, never stored.
    if (url is! String || !visited.contains(urlKey(url))) continue;
    if (type == null || price is! num || price <= 0) continue;
    var currency = ((s['currency'] as String?) ?? '').toUpperCase();
    var amount = price.toDouble();
    // Another currency is converted at the live rate, never a model-supplied
    // one; the page's own price is kept alongside. No rate → left as is, and
    // so excluded from the estimate below.
    final target = request.currency.toUpperCase();
    final rate = currency == target ? null : rates[currency];
    double? originalPrice;
    String? originalCurrency;
    if (rate != null) {
      (originalPrice, originalCurrency) = (amount, currency);
      amount = double.parse((amount / rate).toStringAsFixed(2));
      currency = target;
    }
    final isGraded = s['is_graded'] == true;
    // A listing worded like one of the card's OTHER printings is that card,
    // however plausible its price looks.
    final verdict = attributeListing(
      '${s['title'] ?? ''} ${s['name'] ?? ''}',
      request.printing,
    );
    final wrongPrinting =
        verdict == ListingVerdict.otherPrinting ||
        verdict == ListingVerdict.ambiguous;
    sources.add(
      PriceSource(
        name: (s['name'] as String?) ?? url,
        // The page's host decides which marketplace this is; the model's
        // word only fills in for sites we don't know.
        marketplace: marketplaceForUrl(url) ?? s['marketplace'] as String?,
        type: type,
        price: amount,
        currency: currency,
        originalPrice: originalPrice,
        originalCurrency: originalCurrency,
        condition: s['condition'] as String?,
        isGraded: isGraded,
        url: url,
        title: s['title'] as String?,
        sourceLabel: s['title'] as String?,
        observedAt: DateTime.tryParse((s['observed_at'] as String?) ?? ''),
        usedInEstimate:
            type.estimateTier != null &&
            isGraded == request.isGraded &&
            currency == target &&
            !wrongPrinting,
        notUsedReason: wrongPrinting
            ? (verdict == ListingVerdict.otherPrinting
                  ? 'different printing'
                  : 'ambiguous: wording fits two printings')
            : null,
      ),
    );
  }

  final estimate = estimateFromSources(sources);
  if (estimate == null) {
    return InsufficientEvidence(
      rawResponse: raw,
      reason: sources.isEmpty
          ? 'No source survived verification. Model said: $reason'
          : 'No source matched the requested currency/grading. Model said: $reason',
      sources: sources,
    );
  }
  return PriceResearchSuccess(
    rawResponse: raw,
    estimatedPrice: estimate.price,
    low: estimate.low,
    high: estimate.high,
    currency: request.currency.toUpperCase(),
    confidence: estimate.confidence,
    sources: sources,
    researchedAt: now,
    searchCalls: run.searches,
  );
}

/// Median/min/max of the best evidence tier present among sources used in
/// the estimate: recent sales, else market prices, else asking prices.
({double price, double low, double high, double confidence})?
estimateFromSources(List<PriceSource> sources) {
  final used = sources.where((s) => s.usedInEstimate).toList();
  for (var tier = 0; tier <= 2; tier++) {
    final prices =
        used
            .where((s) => s.type.estimateTier == tier)
            .map((s) => s.price)
            .toList()
          ..sort();
    if (prices.isEmpty) continue;
    final mid = prices.length ~/ 2;
    final median = prices.length.isOdd
        ? prices[mid]
        : (prices[mid - 1] + prices[mid]) / 2;
    int count(SourceType t) => used.where((s) => s.type == t).length;
    // ponytail: evidence-count heuristic, uncalibrated. Replace with a
    // calibrated score once we have researched prices to check against.
    var confidence =
        0.2 +
        0.15 * math.min(count(SourceType.recentSold), 4) +
        0.1 * math.min(count(SourceType.marketPrice), 2) +
        0.05 *
            math.min(
              count(SourceType.currentListing) +
                  count(SourceType.priceComparison),
              2,
            );
    if (tier == 2) confidence = math.min(confidence, 0.4);
    return (
      price: median,
      low: prices.first,
      high: prices.last,
      confidence: math.min(confidence, 0.95),
    );
  }
  return null;
}

/// The marketplace a URL belongs to, for the Japanese shops we know — so a
/// CardRush page is never reported as YuYu-tei or the other way round.
String? marketplaceForUrl(String url) {
  final host = Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';
  for (final (domain, name) in const [
    ('yuyu-tei.jp', 'Yuyu-tei'),
    ('cardrush-op.jp', 'CardRush'),
    ('e-starbox.com', 'e-Starbox'),
  ]) {
    if (host == domain || host.endsWith('.$domain')) return name;
  }
  return null;
}

/// Host (minus `www.`) + path without trailing slash, so a cited URL still
/// matches the visited one when only query/fragment/case differs.
String? urlKey(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) return null;
  var host = uri.host.toLowerCase();
  if (host.startsWith('www.')) host = host.substring(4);
  var path = uri.path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return '$host$path';
}
