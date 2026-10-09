import 'dart:convert';

import '../models/printing_candidate.dart';
import '../models/printing_variant.dart';
import '../models/visual_observation.dart';
import 'price_research_service.dart';
import 'pricing_config.dart';
import 'responses_http.dart';
import 'responses_price_research_service.dart';

/// Finds the KNOWN physical printings of one logical card (number + language)
/// by live research. This is printing research — it runs before price
/// research, and only to say which printings exist and what they look like.
abstract interface class PrintingResearchService {
  String get provider;

  Future<PrintingResearchResult> discover(PrintingDescriptor logical);
}

class PrintingResearchResult {
  const PrintingResearchResult({
    required this.candidates,
    required this.rawResponse,
    this.reason = '',
  });

  /// Only printings backed by a page the search really visited.
  final List<PrintingCandidate> candidates;
  final String rawResponse;

  /// Why there are none (failure, no evidence), or the model's note.
  final String reason;
}

/// Printing research over a Responses-API endpoint with forced `web_search`.
/// Nothing the model says is trusted alone: no completed live search → no
/// candidates, and a printing with no visited evidence page is dropped (the
/// model must not invent variants).
class ResponsesPrintingResearchService implements PrintingResearchService {
  ResponsesPrintingResearchService({
    required this.provider,
    required Uri endpoint,
    required String apiKey,
    required this.model,
    this.config = const PricingConfig(),
    Map<String, Object?> extraBody = const {},
  }) : _endpoint = endpoint,
       _apiKey = apiKey,
       _extraBody = extraBody;

  @override
  final String provider;
  final String model;
  final PricingConfig config;
  final Uri _endpoint;
  final String _apiKey;
  final Map<String, Object?> _extraBody;

  @override
  Future<PrintingResearchResult> discover(PrintingDescriptor logical) async {
    if (_apiKey.isEmpty) {
      return PrintingResearchResult(
        candidates: const [],
        rawResponse: '',
        reason: 'No $provider API key configured (lib/dev_secrets.dart).',
      );
    }
    final int status;
    final String raw;
    try {
      (status, raw) = await postResponses(_endpoint, _apiKey, {
        'model': model,
        'reasoning': {'effort': config.researchReasoningEffort},
        'tools': [
          {'type': 'web_search'},
        ],
        'tool_choice': 'required',
        'instructions': _instructions,
        'input': describePrintingTarget(logical),
        'text': {
          'format': {
            'type': 'json_schema',
            'name': 'printing_research',
            'strict': true,
            'schema': _schema,
          },
        },
        ..._extraBody,
      }, timeout: config.researchTimeout);
    } catch (e) {
      return PrintingResearchResult(
        candidates: const [],
        rawResponse: '',
        reason: 'Printing research request failed: $e',
      );
    }
    if (status < 200 || status >= 300) {
      return PrintingResearchResult(
        candidates: const [],
        rawResponse: raw,
        reason: '$provider HTTP $status',
      );
    }
    return parsePrintingResearch(raw);
  }
}

/// gpt-6-luna with built-in web search (see [PricingConfig.researchModel]).
class OpenAIPrintingResearchService extends ResponsesPrintingResearchService {
  OpenAIPrintingResearchService({required super.apiKey, super.config})
    : super(
        provider: 'OpenAI',
        endpoint: Uri.parse('https://api.openai.com/v1/responses'),
        model: config.researchModel,
        extraBody: openAIResearchExtraBody,
      );
}

/// The logical card, as handed to the model. Deliberately no printing: which
/// printing the photo shows is not the question here.
String describePrintingTarget(PrintingDescriptor p) => [
  'Game: ${p.game.displayName}',
  'Card: ${p.name}',
  'Card number: ${p.cardNumber}',
  'Language: ${p.language}',
  if (p.rarity != null) 'Official rarity: ${p.rarity}',
  if (p.setCode != null) 'Set: ${p.setCode}',
  if (p.language.trim().toLowerCase() == 'japanese')
    'Japanese marketplaces to check: yuyu-tei.jp, cardrush-op.jp, '
        'tcgkakaku.e-starbox.com, and others',
].join('\n');

const _instructions = '''
You are a trading-card catalog researcher. List the KNOWN PHYSICAL PRINTINGS
of the one card in the input: the same card number and language can exist as a
regular print, a parallel / alternate art, a manga or comic parallel, a colour
variant of that, a special promo print, and so on. Decide from sources whether
two names are one physical printing or two.

You MUST search the live internet. Do not answer from training knowledge. Do
not invent printings: list only printings you found evidence for, and give the
URL of each page you actually visited for it — never construct, guess or
shorten a URL. If you find no printing evidence, answer INSUFFICIENT_EVIDENCE.

For each printing:
- variant_family: BASE, PARALLEL, SUPER_PARALLEL, SPECIAL, PROMO or OTHER.
- variant_name: a short UPPER_SNAKE key for the printing, or null for a plain
  BASE / PARALLEL. Name printings consistently with how the sources tell them
  apart.
- official_rarity: the rarity code printed on the card (the same for several
  printings), or null.
- marketplace_aliases: every name, rarity suffix or label that shops and
  price sites use for THIS printing, in every language you saw it in, exactly
  as written (e.g. a shop's own abbreviation or its Japanese name). These are
  marketplace wording, not official names. Put an alias on only one printing.
- artwork_description: one sentence on what its artwork shows.
- visual: what it looks like, using the allowed values; UNKNOWN / null when the
  sources don't show it. dominant_treatment_color is the colour of the special
  treatment (panels, background wash, frame), NONE for an ordinary print. Be
  careful and complete: this is what a photo is later compared against, so give
  the colour whenever a source's text or image shows it.
- visual_markers: short phrases for distinctive things (e.g. a frame colour, a
  panel style).
- reference_image_url: a URL of a picture of exactly this printing that you
  visited, or null.
- evidence_urls: the pages you visited that show this printing.
''';

const _nullableString = {
  'type': ['string', 'null'],
};

const _stringList = {
  'type': 'array',
  'items': {'type': 'string'},
};

final _schema = {
  'type': 'object',
  'additionalProperties': false,
  'required': ['status', 'reason', 'printings'],
  'properties': {
    'status': {
      'type': 'string',
      'enum': ['SUCCESS', 'INSUFFICIENT_EVIDENCE'],
    },
    'reason': {'type': 'string'},
    'printings': {
      'type': 'array',
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'required': [
          'variant_family',
          'variant_name',
          'official_rarity',
          'marketplace_aliases',
          'artwork_description',
          'visual',
          'visual_markers',
          'reference_image_url',
          'evidence_urls',
        ],
        'properties': {
          'variant_family': {
            'type': 'string',
            'enum': [for (final f in VariantFamily.values) f.code],
          },
          'variant_name': _nullableString,
          'official_rarity': _nullableString,
          'marketplace_aliases': _stringList,
          'artwork_description': _nullableString,
          'visual': visualObservationSchema,
          'visual_markers': _stringList,
          'reference_image_url': _nullableString,
          'evidence_urls': _stringList,
        },
      },
    },
  },
};

/// Turns a raw Responses body into the verified candidates: a completed live
/// search is required, and each printing keeps only the evidence URLs the
/// search really visited and is dropped when none remain.
PrintingResearchResult parsePrintingResearch(String raw) {
  PrintingResearchResult none(String reason) => PrintingResearchResult(
    candidates: const [],
    rawResponse: raw,
    reason: reason,
  );

  final Map<String, dynamic> json;
  try {
    json = jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return none('Response was not JSON');
  }
  final error = json['error'];
  if (error is Map) return none('API error: ${error['message']}');
  if (json['status'] != 'completed') {
    return none('Response ${json['status']}: ${json['incomplete_details']}');
  }
  final run = readWebSearchRun(json);
  if (run.completedSearches == 0) return none('No live web search was performed');

  final Map<String, dynamic> answer;
  try {
    answer = jsonDecode(run.text) as Map<String, dynamic>;
  } catch (_) {
    return none('Printing research answer was not valid JSON');
  }
  final reason = (answer['reason'] as String?) ?? '';
  if (answer['status'] != 'SUCCESS') return none(reason);

  final candidates = <PrintingCandidate>[];
  for (final p in (answer['printings'] as List?) ?? const []) {
    if (p is! Map<String, dynamic>) continue;
    final c = PrintingCandidate.fromJson(p);
    final seen = [
      for (final u in c.evidenceSources)
        if (run.visited.contains(urlKey(u))) u,
    ];
    if (seen.isEmpty) continue;
    final image = c.referenceImageUrl;
    candidates.add(
      PrintingCandidate(
        family: c.family,
        variantName: c.variantName,
        officialRarity: c.officialRarity,
        marketplaceAliases: c.marketplaceAliases,
        artworkDescription: c.artworkDescription,
        visual: c.visual,
        visualMarkers: c.visualMarkers,
        referenceImageUrl: image != null && run.visited.contains(urlKey(image))
            ? image
            : null,
        evidenceSources: seen,
      ),
    );
  }
  return PrintingResearchResult(
    candidates: candidates,
    rawResponse: raw,
    reason: candidates.isEmpty
        ? 'No printing survived verification. Model said: $reason'
        : reason,
  );
}
