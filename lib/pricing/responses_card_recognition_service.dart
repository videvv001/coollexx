import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../models/printing_variant.dart';
import '../models/tcg_game.dart';
import '../models/visual_observation.dart';
import 'card_recognition_service.dart';
import 'price_research_service.dart';
import 'pricing_config.dart';
import 'responses_http.dart';

/// Card recognition over any Responses-API-compatible vision model. OpenAI
/// and DeepSeek both speak that format, so they differ only in endpoint,
/// key, model and reasoning setting — see the two subclasses below.
class ResponsesCardRecognitionService implements CardRecognitionService {
  ResponsesCardRecognitionService({
    required this.provider,
    required Uri endpoint,
    required String apiKey,
    required this.model,
    required String reasoningEffort,
    this.config = const PricingConfig(),
    Map<String, Object?> extraBody = const {},
  }) : _endpoint = endpoint,
       _apiKey = apiKey,
       _reasoningEffort = reasoningEffort,
       _extraBody = extraBody;

  @override
  final String provider;
  final String model;
  final PricingConfig config;
  final Uri _endpoint;
  final String _apiKey;
  final String _reasoningEffort;
  final Map<String, Object?> _extraBody;

  RecognitionResult _failed(String reason, [String raw = '']) =>
      RecognitionResult(
        status: RecognitionStatus.failed,
        provider: provider,
        model: model,
        rawResponse: raw,
        reason: reason,
      );

  @override
  Future<RecognitionResult> recognize(List<String> imagePaths) async {
    if (_apiKey.isEmpty) {
      return _failed('No $provider API key configured (lib/dev_secrets.dart).');
    }
    final List<String> images;
    try {
      images = await Future.wait(imagePaths.map(_toDataUrl));
    } catch (e) {
      return _failed('Could not read the photo: $e');
    }
    final int status;
    final String raw;
    try {
      (status, raw) = await postResponses(_endpoint, _apiKey, {
        'model': model,
        'reasoning': {'effort': _reasoningEffort},
        'instructions': _instructions,
        'input': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'input_text',
                'text':
                    'Describe this card and predict its printing. '
                    'Image 1 is the front'
                    '${images.length > 1 ? '; later images are extra angles of the same card' : ''}.',
              },
              for (final url in images)
                {'type': 'input_image', 'image_url': url, 'detail': 'high'},
            ],
          },
        ],
        'text': {
          'format': {
            'type': 'json_schema',
            'name': 'card_recognition',
            'strict': true,
            'schema': _schema,
          },
        },
        ..._extraBody,
      }, timeout: config.recognitionTimeout);
    } catch (e) {
      return _failed('Request failed: $e');
    }
    if (status < 200 || status >= 300) {
      return _failed('$provider HTTP $status', raw);
    }
    return parseRecognitionResponse(
      raw,
      provider: provider,
      model: model,
      printingConfidenceThreshold: config.printingConfidenceThreshold,
    );
  }
}

/// gpt-6-luna by default (see [PricingConfig.openaiRecognitionModel]).
class OpenAICardRecognitionService extends ResponsesCardRecognitionService {
  OpenAICardRecognitionService({required super.apiKey, super.config})
    : super(
        provider: 'OpenAI',
        endpoint: Uri.parse('https://api.openai.com/v1/responses'),
        model: config.openaiRecognitionModel,
        reasoningEffort: 'low',
        extraBody: const {'store': false},
      );
}

/// DeepSeek-V4.1-Flash (`deepseek-flash`). Vision only works with thinking
/// off, hence reasoning effort `none`. No `store` field: DeepSeek doesn't
/// support it (responses are never stored).
class DeepSeekCardRecognitionService extends ResponsesCardRecognitionService {
  DeepSeekCardRecognitionService({required super.apiKey, super.config})
    : super(
        provider: 'DeepSeek',
        endpoint: Uri.parse('https://api.deepseek.com/responses'),
        model: config.deepseekRecognitionModel,
        reasoningEffort: 'none',
      );
}

/// Downscales to ≤1600px on the long side (plenty for reading card text;
/// keeps uploads small on mobile data) and returns a JPEG data URL.
Future<String> _toDataUrl(String path) async {
  final bytes = await File(path).readAsBytes();
  final jpeg = await Isolate.run(() {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw const FormatException('Not an image');
    final longSide = math.max(decoded.width, decoded.height);
    final resized = longSide <= 1600
        ? decoded
        : img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? 1600 : null,
            height: decoded.height > decoded.width ? 1600 : null,
          );
    return img.encodeJpg(resized, quality: 90);
  });
  return 'data:image/jpeg;base64,${base64Encode(jpeg)}';
}

const _instructions = '''
You identify trading cards from photos. Supported games (use these codes):
MTG, POKEMON, ONE_PIECE, YUGIOH, LORCANA, RIFTBOUND, GUNDAM,
DBS_FUSION_WORLD, DIGIMON. Use UNKNOWN for anything else.

Your first job is to DESCRIBE WHAT YOU SEE; naming the printing comes second.
The same card number (and the same official rarity) can exist as several
printings worth very different amounts: base, parallel / alternate art, super
parallel, manga, a colour version of the manga print, SP, special illustration
rare, full art, reverse holo, Japanese vs English, and so on. You are not
expected to know what every printing is called: a later step compares your
description with the known printings of the card. So be accurate and complete
about what is on the card, and do not let a printing's name decide what you
report.

`visual` — report each field from the image alone:
- dominant_treatment_color: the colour of the special treatment (panels,
  background wash, frame), NOT the character's own colours. NONE for an
  ordinary print. If the treatment is clearly red, say RED even when you are
  unsure what the printing is called. UNKNOWN only if you cannot tell.
- background_style: STANDARD set background, MANGA_PANEL_COLLAGE,
  CHARACTER_COLLAGE, SCENE_ILLUSTRATION, SOLID_COLOR, FULL_ART, OTHER, UNKNOWN.
- manga_panels / speech_bubbles: true or false; null if you cannot tell.
- frame_treatment, and foil_evidence (PATTERN_VISIBLE only if you can actually
  see a foil or texture pattern; NONE_VISIBLE does not prove a card is
  non-foil).
- special_symbols and distinctive_markers: short phrases for anything else
  that sets this print apart (a star by the rarity, a corner stamp,
  action/sound-effect lettering, crew artwork, ...).

`printing` is your PREDICTION of the printing, a hypothesis that will be
checked:
- predicted_variant_family: BASE, PARALLEL, SUPER_PARALLEL, SPECIAL, PROMO or
  OTHER. UNKNOWN when you cannot tell. Never use OTHER as a place to put a
  guess.
- predicted_variant_name: your best UPPER_SNAKE name for it, or null when you
  don't know it or the family says it all (BASE, plain PARALLEL).
- artwork_description: ALWAYS fill in. One sentence on what the artwork shows
  (pose, composition, background, who is in it), not "alternate art".
- visible_markers: marks that helped, e.g. a star by the rarity, foil pattern,
  corner stamp, frame colour, crew/group artwork.

For every field give the value and how you know it:
- READ: printed on the card and legible in the photo
- INFERRED: deduced from visible evidence (art style, frame, layout) or from
  your knowledge of the game's card list
- UNKNOWN: not determinable from these photos — value null.

The card number is printed very small and is often NOT legible in a photo.
Do not give up when you can't read it: identify the card from everything else
you can see — the artwork, character and card name, title/type line, cost or
power, color, effect text, rarity mark, set symbol, frame — then give the card
number as INFERRED from your knowledge of that game's card list, and let
confidence.logical_card reflect how sure you are. Only use UNKNOWN for the card
number when you truly cannot narrow the card down to one. Never present an
inferred number as READ.

language is the printed language (English, Japanese, Chinese, Korean, …).
official_rarity is the rarity code printed on the card (SEC, SR, …), which
several printings share.
confidence.logical_card: 0-1, how sure you are of the card (name + card
number). confidence.exact_printing: 0-1, how sure you are of your printing
prediction. Be honest: a correct card number with a wrong printing is a wrong
answer. List other plausible printings in printing_candidates.
uncertainty_reasons: why the printing may be wrong, from the allowed codes, or
an empty list. FOIL_TREATMENT_UNCERTAIN only when the printing could differ by
foil or texture that a flat photo cannot show; ARTWORK_VARIANT_UNCERTAIN when
you cannot see enough of the artwork; TEXT_UNREADABLE for unreadable printed
text; MARKETPLACE_CLASSIFICATION_UNCERTAIN when you can see the card but are
unsure what the print is called; UNKNOWN_PRINTING when you have no idea;
NEEDS_ANGLED_PHOTO only for foil/texture. Doubt about a printing's name is NOT
a reason to ask for another photo.
notes: one or two sentences on what you saw.
''';

const _field = {
  'type': 'object',
  'additionalProperties': false,
  'required': ['value', 'status'],
  'properties': {
    'value': {
      'type': ['string', 'null'],
    },
    'status': {
      'type': 'string',
      'enum': ['READ', 'INFERRED', 'UNKNOWN'],
    },
  },
};

final _variantFamilies = [for (final f in VariantFamily.values) f.code];

final _schema = {
  'type': 'object',
  'additionalProperties': false,
  'required': [
    'game',
    'name',
    'card_number',
    'language',
    'set_code',
    'official_rarity',
    'visual',
    'printing',
    'printing_candidates',
    'confidence',
    'uncertainty_reasons',
    'notes',
  ],
  'properties': {
    'game': {
      'type': 'string',
      'enum': [for (final g in TcgGame.values) g.code, 'UNKNOWN'],
    },
    'name': _field,
    'card_number': _field,
    'language': _field,
    'set_code': _field,
    'official_rarity': _field,
    'visual': visualObservationSchema,
    'printing': {
      'type': 'object',
      'additionalProperties': false,
      'required': [
        'predicted_variant_family',
        'predicted_variant_name',
        'artwork_description',
        'visible_markers',
      ],
      'properties': {
        'predicted_variant_family': {
          'type': 'string',
          'enum': _variantFamilies,
        },
        'predicted_variant_name': {
          'type': ['string', 'null'],
        },
        'artwork_description': {
          'type': ['string', 'null'],
        },
        'visible_markers': {
          'type': 'array',
          'items': {'type': 'string'},
        },
      },
    },
    'printing_candidates': {
      'type': 'array',
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'required': ['variant_family', 'variant_name'],
        'properties': {
          'variant_family': {'type': 'string', 'enum': _variantFamilies},
          'variant_name': {
            'type': ['string', 'null'],
          },
        },
      },
    },
    'confidence': {
      'type': 'object',
      'additionalProperties': false,
      'required': ['logical_card', 'exact_printing'],
      'properties': {
        'logical_card': {'type': 'number'},
        'exact_printing': {'type': 'number'},
      },
    },
    'uncertainty_reasons': {
      'type': 'array',
      'items': {
        'type': 'string',
        'enum': [for (final r in UncertaintyReason.values) r.code],
      },
    },
    'notes': {'type': 'string'},
  },
};

/// Turns a raw Responses body into a [RecognitionResult]. The model's word
/// isn't final: an UNKNOWN language/printing or a printing confidence below
/// [printingConfidenceThreshold] always means verification is required.
RecognitionResult parseRecognitionResponse(
  String raw, {
  required String provider,
  required String model,
  required double printingConfidenceThreshold,
}) {
  RecognitionResult failed(String reason) => RecognitionResult(
    status: RecognitionStatus.failed,
    provider: provider,
    model: model,
    rawResponse: raw,
    reason: reason,
  );

  final Map<String, dynamic> json;
  try {
    json = jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return failed('Response was not JSON');
  }
  final error = json['error'];
  if (error is Map) return failed('$provider error: ${error['message']}');
  if (json['status'] != 'completed') {
    return failed('Response ${json['status']}: ${json['incomplete_details']}');
  }
  final Map<String, dynamic> a;
  try {
    a = jsonDecode(responsesOutputText(json)) as Map<String, dynamic>;
  } catch (_) {
    return failed('Recognition answer was not valid JSON');
  }

  String? value(String key) {
    final f = a[key];
    if (f is! Map || f['status'] == 'UNKNOWN') return null;
    final v = (f['value'] as String?)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  final confidence = a['confidence'];
  double conf(String key) {
    final v = confidence is Map ? confidence[key] : null;
    return (v is num ? v.toDouble() : 0.0).clamp(0.0, 1.0);
  }

  String? text(Object? v) {
    final t = v is String ? v.trim() : null;
    return (t == null || t.isEmpty) ? null : t;
  }

  PrintingVariant variantOf(Object? json, {bool withArtwork = false}) {
    if (json is! Map) return PrintingVariant.unknown;
    return PrintingVariant(
      family: VariantFamily.fromCode(
        (json['predicted_variant_family'] ?? json['variant_family']) as String?,
      ),
      name: normalizeVariantName(
        (json['predicted_variant_name'] ?? json['variant_name']) as String?,
      ),
      artwork: withArtwork ? text(json['artwork_description']) : null,
    );
  }

  final game = TcgGame.fromCode(a['game'] as String?);
  final name = value('name');
  final number = value('card_number');
  final notes = (a['notes'] as String?) ?? '';
  final candidates = [
    for (final c in (a['printing_candidates'] as List?) ?? const [])
      variantOf(c),
  ];
  final markers = [
    for (final m
        in ((a['printing'] as Map?)?['visible_markers'] as List?) ?? const [])
      if (text(m) != null) text(m)!,
  ];
  final reasons = <UncertaintyReason>{
    for (final r in (a['uncertainty_reasons'] as List?) ?? const [])
      ?UncertaintyReason.fromCode(r as String?),
  };
  final visual = VisualObservation.fromJson(a['visual']);

  if (game == null || name == null || number == null) {
    return RecognitionResult(
      status: RecognitionStatus.unrecognized,
      provider: provider,
      model: model,
      rawResponse: raw,
      cardConfidence: conf('logical_card'),
      reason: notes,
      evidenceNeeded: evidenceFor(reasons),
      visual: visual,
      uncertaintyReasons: reasons.toList(),
    );
  }

  final language = value('language');
  final variant = variantOf(a['printing'], withArtwork: true);
  final printingConfidence = conf('exact_printing');
  // A number the model worked out rather than read is the likeliest way to
  // price the wrong card, so it has to clear the same bar as the printing.
  final numberField = a['card_number'];
  final numberInferred =
      numberField is Map && numberField['status'] == 'INFERRED';
  final cardConfidence = conf('logical_card');
  // Problems no printing research can fix.
  final cardIssues = [
    if (numberInferred && cardConfidence < printingConfidenceThreshold)
      'card number not readable; inferred from the image at '
          '${(cardConfidence * 100).round()}% confidence',
    if (language == null) 'language not readable',
  ];
  // The model's own verdict on its printing prediction. Not final: resolution
  // may still settle it from the known printings.
  final printingIssues = [
    if (!variant.isResolved) 'printing not identified',
    if (printingConfidence < printingConfidenceThreshold)
      'printing confidence ${(printingConfidence * 100).round()}% is below '
          '${(printingConfidenceThreshold * 100).round()}%',
  ];
  if (!variant.isResolved) reasons.add(UncertaintyReason.unknownPrinting);
  if (printingConfidence < printingConfidenceThreshold && reasons.isEmpty) {
    reasons.add(UncertaintyReason.artworkVariantUncertain);
  }
  final issues = [...cardIssues, ...printingIssues];
  var evidence = evidenceFor(reasons);
  if (cardIssues.isNotEmpty && evidence == EvidenceRequest.none) {
    evidence = EvidenceRequest.userConfirmation;
  }
  return RecognitionResult(
    status: issues.isEmpty
        ? RecognitionStatus.identified
        : RecognitionStatus.verificationRequired,
    provider: provider,
    model: model,
    rawResponse: raw,
    printing: PrintingDescriptor(
      game: game,
      name: name,
      cardNumber: number,
      language: language ?? 'Unknown',
      setCode: value('set_code'),
      rarity: value('official_rarity'),
      variant: variant,
      source: PrintingSource.visionHypothesis,
    ),
    cardConfidence: cardConfidence,
    printingConfidence: printingConfidence,
    reason: [...issues, if (notes.isNotEmpty) notes].join('. '),
    evidenceNeeded: issues.isEmpty ? EvidenceRequest.none : evidence,
    printingCandidates: candidates,
    visibleMarkers: markers,
    visual: visual,
    uncertaintyReasons: reasons.toList(),
    cardIssues: cardIssues,
  );
}
