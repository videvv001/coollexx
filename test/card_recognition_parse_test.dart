// Recognition gating: a confident card with an uncertain printing must come
// back as verificationRequired — never identified — whichever provider
// produced it. And the printing (family, name, artwork) must survive parsing:
// the three EB04-061 printings are one card but never one printing.
//
// Recognition only PREDICTS the printing and DESCRIBES the photo (`visual`);
// what the printing really is gets settled by the resolver (see
// printing_resolution_test.dart). A tilted photo is asked for only when foil or
// texture is the doubt.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:pokedex_tcg/models/printing_variant.dart';
import 'package:pokedex_tcg/models/tcg_game.dart';
import 'package:pokedex_tcg/models/visual_observation.dart';
import 'package:pokedex_tcg/pricing/price_research_service.dart';
import 'package:pokedex_tcg/pricing/card_recognition_service.dart';
import 'package:pokedex_tcg/pricing/responses_card_recognition_service.dart';

Map<String, Object?> _f(String? value, [String status = 'READ']) => {
  'value': value,
  'status': value == null ? 'UNKNOWN' : status,
};

Map<String, Object?> redMangaVisual() => {
  'dominant_treatment_color': 'RED',
  'background_style': 'MANGA_PANEL_COLLAGE',
  'manga_panels': true,
  'speech_bubbles': true,
  'frame_treatment': 'STANDARD',
  'foil_evidence': 'UNKNOWN',
  'special_symbols': <String>[],
  'distinctive_markers': ['action lettering'],
};

String _response({
  String game = 'ONE_PIECE',
  String? name = 'Monkey.D.Luffy',
  String? number = 'OP13-118',
  String? language = 'English',
  String family = 'SUPER_PARALLEL',
  String? variantName = 'Red Manga Rare',
  String? artwork = 'Luffy in red-and-black manga panels',
  List<String> markers = const ['manga panels'],
  double card = 0.99,
  double printing = 0.95,
  List<String> reasons = const [],
  String numberStatus = 'READ',
  Map<String, Object?>? visual,
}) => jsonEncode({
  'status': 'completed',
  'output': [
    {
      'type': 'message',
      'content': [
        {
          'type': 'output_text',
          'text': jsonEncode({
            'game': game,
            'name': _f(name),
            'card_number': _f(number, numberStatus),
            'language': _f(language),
            'set_code': _f('OP13'),
            'official_rarity': _f('SEC'),
            'visual': visual ?? redMangaVisual(),
            'printing': {
              'predicted_variant_family': family,
              'predicted_variant_name': variantName,
              'artwork_description': artwork,
              'visible_markers': markers,
            },
            'printing_candidates': [
              {
                'variant_family': 'SUPER_PARALLEL',
                'variant_name': 'MANGA_RARE',
              },
            ],
            'confidence': {'logical_card': card, 'exact_printing': printing},
            'uncertainty_reasons': reasons,
            'notes': 'n',
          }),
        },
      ],
    },
  ],
});

/// The canned model answer the other test files build on.
final cannedRecognition = _response;

RecognitionResult _parse(String raw) => parseRecognitionResponse(
  raw,
  provider: 'DeepSeek',
  model: 'deepseek-flash',
  printingConfidenceThreshold: 0.85,
);

/// What a model would say for each of the three EB04-061 photos.
String _eb04(String family, String? name, String artwork, List<String> marks) =>
    _response(
      number: 'EB04-061',
      name: 'モンキー・D・ルフィ',
      language: 'Japanese',
      family: family,
      variantName: name,
      artwork: artwork,
      markers: marks,
    );

final eb04Crew = _eb04(
  'SUPER_PARALLEL',
  'Pirate Crew Super Parallel',
  'Gear 5 Luffy seated in the foreground, Straw Hat crew in black and white behind him',
  ['crew artwork'],
);
final eb04Base = _eb04(
  'BASE',
  null,
  'Gear 5 Luffy upside down, laughing, on a green and pink background',
  [],
);
final eb04Parallel = _eb04(
  'PARALLEL',
  null,
  'Gear 5 Luffy striking, rays of light behind',
  ['star by the rarity'],
);

void main() {
  test('confident card and printing → identified', () {
    final r = _parse(_response());
    expect(r.status, RecognitionStatus.identified);
    expect(r.printing!.game, TcgGame.onePiece);
    expect(r.printing!.rarity, 'SEC');
    expect(r.printing!.variant.family, VariantFamily.superParallel);
    expect(r.printing!.variant.name, 'RED_MANGA_RARE');
    expect(r.evidenceNeeded, EvidenceRequest.none);
  });

  test('artwork, markers and candidates are kept, not thrown away', () {
    final r = _parse(_response());
    expect(r.printing!.variant.artwork, 'Luffy in red-and-black manga panels');
    expect(r.visibleMarkers, ['manga panels']);
    expect(r.printingCandidates.single.name, 'MANGA_RARE');
  });

  test('99% card / 63% printing → verification required, not a match', () {
    final r = _parse(
      _response(printing: 0.63, reasons: ['FOIL_TREATMENT_UNCERTAIN']),
    );
    expect(r.status, RecognitionStatus.verificationRequired);
    expect(r.evidenceNeeded, EvidenceRequest.angledPhoto);
    expect(r.cardConfidence, 0.99);
    expect(r.printingConfidence, 0.63);
    expect(r.reason, contains('63%'));
  });

  test('low printing confidence alone does not ask for a tilted photo', () {
    // The doubt is what the print is called, not how its surface looks.
    final r = _parse(_response(printing: 0.7));
    expect(r.status, RecognitionStatus.verificationRequired);
    expect(r.evidenceNeeded, isNot(EvidenceRequest.angledPhoto));
    expect(r.uncertaintyReasons, [UncertaintyReason.artworkVariantUncertain]);
    expect(
      _parse(
        _response(printing: 0.7, reasons: ['MARKETPLACE_CLASSIFICATION_UNCERTAIN']),
      ).evidenceNeeded,
      EvidenceRequest.userConfirmation,
    );
  });

  test('the photo description survives, whatever the model called the print', () {
    // A model that says MANGA_RARE for a red print still reports the red.
    final r = _parse(_response(variantName: 'MANGA_RARE', printing: 0.7));
    expect(r.printing!.variant.name, 'MANGA_RARE');
    expect(r.visual.treatmentColor, TreatmentColor.red);
    expect(r.visual.backgroundStyle, BackgroundStyle.mangaPanelCollage);
    expect(r.visual.mangaPanels, isTrue);
    expect(r.visual.speechBubbles, isTrue);
    expect(r.visual.distinctiveMarkers, ['action lettering']);
  });

  test('a recognition result is a hypothesis, never priceable as is', () {
    final p = _parse(_response()).printing!;
    expect(p.source, PrintingSource.visionHypothesis);
    expect(requireExactPrinting(p), isA<PrintingVerificationRequired>());
  });

  test('unknown printing → verification required even at high confidence', () {
    final r = _parse(_response(family: 'UNKNOWN', variantName: null));
    expect(r.status, RecognitionStatus.verificationRequired);
    expect(r.printing!.variant.isResolved, isFalse);
    expect(r.reason, contains('printing not identified'));
    expect(r.evidenceNeeded, EvidenceRequest.userConfirmation);
  });

  test('unknown language → verification required', () {
    expect(
      _parse(_response(language: null)).status,
      RecognitionStatus.verificationRequired,
    );
  });

  test('unsupported game or missing number → unrecognized', () {
    expect(
      _parse(_response(game: 'UNKNOWN')).status,
      RecognitionStatus.unrecognized,
    );
    expect(
      _parse(_response(number: null)).status,
      RecognitionStatus.unrecognized,
    );
  });

  test('number inferred from the image: confident → identified', () {
    final r = _parse(_response(numberStatus: 'INFERRED', card: 0.92));
    expect(r.status, RecognitionStatus.identified);
    expect(r.printing!.cardNumber, 'OP13-118');
  });

  test('number inferred at low confidence → verification required', () {
    final r = _parse(_response(numberStatus: 'INFERRED', card: 0.6));
    expect(r.status, RecognitionStatus.verificationRequired);
    expect(r.reason, contains('inferred from the image at 60%'));
    expect(r.evidenceNeeded, EvidenceRequest.userConfirmation);
  });

  test('provider error / bad output → failed', () {
    expect(
      _parse(
        jsonEncode({
          'error': {'message': 'bad key'},
        }),
      ).status,
      RecognitionStatus.failed,
    );
    expect(_parse('not json').status, RecognitionStatus.failed);
  });

  test('empty key fails fast without a network call', () async {
    final r = await DeepSeekCardRecognitionService(
      apiKey: '',
    ).recognize(['x.jpg']);
    expect(r.status, RecognitionStatus.failed);
    expect(r.reason, contains('DeepSeek'));
  });

  test('EB04-061: same logical card, three different printings', () {
    final crew = _parse(eb04Crew).printing!;
    final base = _parse(eb04Base).printing!;
    final parallel = _parse(eb04Parallel).printing!;
    for (final p in [crew, base, parallel]) {
      expect(p.game, TcgGame.onePiece);
      expect(p.cardNumber, 'EB04-061');
      expect(p.name, 'モンキー・D・ルフィ');
      expect(p.language, 'Japanese');
      expect(p.rarity, 'SEC');
    }
    expect(crew.variant.family, VariantFamily.superParallel);
    expect(crew.variant.name, 'PIRATE_CREW_SUPER_PARALLEL');
    expect(base.variant.family, VariantFamily.base);
    expect(parallel.variant.family, VariantFamily.parallel);
    expect({crew.variant, base.variant, parallel.variant}, hasLength(3));
  });

  test('normalizeVariantName', () {
    expect(
      normalizeVariantName(' Pirate Crew Super-Parallel '),
      'PIRATE_CREW_SUPER_PARALLEL',
    );
    expect(normalizeVariantName('RED_MANGA_RARE'), 'RED_MANGA_RARE');
    expect(normalizeVariantName('  '), isNull);
    expect(normalizeVariantName(null), isNull);
  });

  test('unrecognised stored family reads back as unknown, not base', () {
    expect(VariantFamily.fromCode('SOMETHING_NEW'), VariantFamily.unknown);
    expect(VariantFamily.fromCode(null), VariantFamily.unknown);
  });
}
