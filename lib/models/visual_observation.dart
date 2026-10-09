/// What a card photo (or a researched printing) LOOKS like, in a fixed
/// vocabulary shared by vision recognition and printing research so the two can
/// be compared by code instead of by a model's word. UNKNOWN never counts as
/// evidence for or against anything.
abstract interface class Coded {
  String get code;
}

T _fromCode<T extends Coded>(List<T> values, String? code, T fallback) {
  for (final v in values) {
    if (v.code == code) return v;
  }
  return fallback;
}

/// Colour of the special treatment (panels, background wash, frame) — not the
/// colour of the character's clothes.
enum TreatmentColor implements Coded {
  red('RED'),
  blue('BLUE'),
  green('GREEN'),
  yellow('YELLOW'),
  orange('ORANGE'),
  purple('PURPLE'),
  pink('PINK'),
  gold('GOLD'),
  silver('SILVER'),
  blackAndWhite('BLACK_AND_WHITE'),
  multicolor('MULTICOLOR'),

  /// An ordinary print: no special treatment colour.
  none('NONE'),
  unknown('UNKNOWN');

  @override
  final String code;
  const TreatmentColor(this.code);
  static TreatmentColor fromCode(String? c) =>
      _fromCode(values, c, TreatmentColor.unknown);
}

enum BackgroundStyle implements Coded {
  standard('STANDARD'),
  mangaPanelCollage('MANGA_PANEL_COLLAGE'),
  characterCollage('CHARACTER_COLLAGE'),
  sceneIllustration('SCENE_ILLUSTRATION'),
  solidColor('SOLID_COLOR'),
  fullArt('FULL_ART'),
  other('OTHER'),
  unknown('UNKNOWN');

  @override
  final String code;
  const BackgroundStyle(this.code);
  static BackgroundStyle fromCode(String? c) =>
      _fromCode(values, c, BackgroundStyle.unknown);
}

enum FrameTreatment implements Coded {
  standard('STANDARD'),
  borderless('BORDERLESS'),
  coloredFrame('COLORED_FRAME'),
  other('OTHER'),
  unknown('UNKNOWN');

  @override
  final String code;
  const FrameTreatment(this.code);
  static FrameTreatment fromCode(String? c) =>
      _fromCode(values, c, FrameTreatment.unknown);
}

/// Foil / texture is the one thing a flat photo often can't show.
enum FoilEvidence implements Coded {
  none('NONE_VISIBLE'),
  visible('PATTERN_VISIBLE'),
  unknown('UNKNOWN');

  @override
  final String code;
  const FoilEvidence(this.code);
  static FoilEvidence fromCode(String? c) =>
      _fromCode(values, c, FoilEvidence.unknown);
}

class VisualObservation {
  const VisualObservation({
    this.treatmentColor = TreatmentColor.unknown,
    this.backgroundStyle = BackgroundStyle.unknown,
    this.mangaPanels,
    this.speechBubbles,
    this.frame = FrameTreatment.unknown,
    this.foil = FoilEvidence.unknown,
    this.specialSymbols = const [],
    this.distinctiveMarkers = const [],
  });

  static const unknown = VisualObservation();

  final TreatmentColor treatmentColor;
  final BackgroundStyle backgroundStyle;

  /// null = not determined.
  final bool? mangaPanels;
  final bool? speechBubbles;
  final FrameTreatment frame;
  final FoilEvidence foil;
  final List<String> specialSymbols;
  final List<String> distinctiveMarkers;

  factory VisualObservation.fromJson(Object? json) {
    if (json is! Map) return unknown;
    List<String> strings(Object? v) => [
      for (final s in (v as List?) ?? const [])
        if (s is String && s.trim().isNotEmpty) s.trim(),
    ];
    return VisualObservation(
      treatmentColor: TreatmentColor.fromCode(
        json['dominant_treatment_color'] as String?,
      ),
      backgroundStyle: BackgroundStyle.fromCode(
        json['background_style'] as String?,
      ),
      mangaPanels: json['manga_panels'] as bool?,
      speechBubbles: json['speech_bubbles'] as bool?,
      frame: FrameTreatment.fromCode(json['frame_treatment'] as String?),
      foil: FoilEvidence.fromCode(json['foil_evidence'] as String?),
      specialSymbols: strings(json['special_symbols']),
      distinctiveMarkers: strings(json['distinctive_markers']),
    );
  }

  Map<String, Object?> toJson() => {
    'dominant_treatment_color': treatmentColor.code,
    'background_style': backgroundStyle.code,
    'manga_panels': mangaPanels,
    'speech_bubbles': speechBubbles,
    'frame_treatment': frame.code,
    'foil_evidence': foil.code,
    'special_symbols': specialSymbols,
    'distinctive_markers': distinctiveMarkers,
  };

  /// The comparable fields as (name, value-or-null-when-unknown). Lists are
  /// descriptive only and never compared.
  Map<String, Object?> get comparable => {
    'treatment colour': treatmentColor == TreatmentColor.unknown
        ? null
        : treatmentColor,
    'background': backgroundStyle == BackgroundStyle.unknown
        ? null
        : backgroundStyle,
    'manga panels': mangaPanels,
    'speech bubbles': speechBubbles,
    'frame': frame == FrameTreatment.unknown ? null : frame,
    'foil': foil == FoilEvidence.unknown ? null : foil,
  };

  /// Short human summary for the debug UI.
  String get summary => [
    for (final e in comparable.entries)
      if (e.value != null)
        '${e.key}: ${e.value is Coded ? (e.value as Coded).code : e.value}',
    ...specialSymbols.map((s) => 'symbol: $s'),
    ...distinctiveMarkers,
  ].join(' · ');
}

/// Why the printing can't be settled yet. Each reason asks for a different
/// remedy (see `evidenceFor`); only foil/texture doubt justifies a tilted
/// photo.
enum UncertaintyReason implements Coded {
  artworkVariantUncertain('ARTWORK_VARIANT_UNCERTAIN'),
  foilTreatmentUncertain('FOIL_TREATMENT_UNCERTAIN'),
  textUnreadable('TEXT_UNREADABLE'),
  marketplaceClassificationUncertain('MARKETPLACE_CLASSIFICATION_UNCERTAIN'),
  unknownPrinting('UNKNOWN_PRINTING'),
  needsAngledPhoto('NEEDS_ANGLED_PHOTO');

  @override
  final String code;
  const UncertaintyReason(this.code);

  static UncertaintyReason? fromCode(String? c) {
    for (final v in values) {
      if (v.code == c) return v;
    }
    return null;
  }
}

List<String> _codes(List<Coded> values) => [for (final v in values) v.code];

/// The JSON schema (OpenAI strict mode: every property required) for a
/// [VisualObservation]. Used by vision recognition and printing research, so
/// both speak the same vocabulary.
final visualObservationSchema = {
  'type': 'object',
  'additionalProperties': false,
  'required': [
    'dominant_treatment_color',
    'background_style',
    'manga_panels',
    'speech_bubbles',
    'frame_treatment',
    'foil_evidence',
    'special_symbols',
    'distinctive_markers',
  ],
  'properties': {
    'dominant_treatment_color': {
      'type': 'string',
      'enum': _codes(TreatmentColor.values),
    },
    'background_style': {
      'type': 'string',
      'enum': _codes(BackgroundStyle.values),
    },
    'manga_panels': {
      'type': ['boolean', 'null'],
    },
    'speech_bubbles': {
      'type': ['boolean', 'null'],
    },
    'frame_treatment': {
      'type': 'string',
      'enum': _codes(FrameTreatment.values),
    },
    'foil_evidence': {'type': 'string', 'enum': _codes(FoilEvidence.values)},
    'special_symbols': {
      'type': 'array',
      'items': {'type': 'string'},
    },
    'distinctive_markers': {
      'type': 'array',
      'items': {'type': 'string'},
    },
  },
};
