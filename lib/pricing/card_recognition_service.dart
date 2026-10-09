import '../models/printing_variant.dart';
import '../models/visual_observation.dart';
import 'price_research_service.dart';

/// Identifies the exact physical printing shown in card photos. The rest of
/// the app depends only on this interface — the provider behind it is a
/// setting (see `AiSettings`).
abstract interface class CardRecognitionService {
  /// Human-readable provider name, stored/shown with results.
  String get provider;

  /// [imagePaths]: front first; extra angles (tilted for foil, back, close-up)
  /// may follow.
  Future<RecognitionResult> recognize(List<String> imagePaths);
}

enum RecognitionStatus {
  /// Card and exact printing both confident: safe to price.
  identified,

  /// Card known, but the exact printing (variant, language, …) isn't certain
  /// enough to price. Ask for [RecognitionResult.evidenceNeeded].
  verificationRequired,

  /// Couldn't tell which card this is.
  unrecognized,

  /// The call itself failed (network, key, provider error, bad output).
  failed,
}

enum EvidenceRequest {
  none('NONE'),
  angledPhoto('ANGLED_PHOTO'),
  backPhoto('BACK_PHOTO'),
  closeUp('CLOSE_UP'),
  userConfirmation('USER_CONFIRMATION');

  final String code;
  const EvidenceRequest(this.code);

  static EvidenceRequest fromCode(String? code) => values.firstWhere(
    (e) => e.code == code,
    orElse: () => EvidenceRequest.none,
  );
}

/// What would actually help, given why the printing is uncertain. Only
/// foil/texture doubt justifies a tilted photo; a missed detail wants a closer
/// look; naming doubt wants a person.
EvidenceRequest evidenceFor(Iterable<UncertaintyReason> reasons) {
  final r = reasons.toSet();
  if (r.contains(UncertaintyReason.foilTreatmentUncertain) ||
      r.contains(UncertaintyReason.needsAngledPhoto)) {
    return EvidenceRequest.angledPhoto;
  }
  if (r.contains(UncertaintyReason.textUnreadable) ||
      r.contains(UncertaintyReason.artworkVariantUncertain)) {
    return EvidenceRequest.closeUp;
  }
  if (r.contains(UncertaintyReason.unknownPrinting) ||
      r.contains(UncertaintyReason.marketplaceClassificationUncertain)) {
    return EvidenceRequest.userConfirmation;
  }
  return EvidenceRequest.none;
}

class RecognitionResult {
  const RecognitionResult({
    required this.status,
    required this.provider,
    required this.model,
    required this.rawResponse,
    this.printing,
    this.cardConfidence = 0,
    this.printingConfidence = 0,
    this.reason = '',
    this.evidenceNeeded = EvidenceRequest.none,
    this.printingCandidates = const [],
    this.visibleMarkers = const [],
    this.visual = VisualObservation.unknown,
    this.uncertaintyReasons = const [],
    this.cardIssues = const [],
  });

  final RecognitionStatus status;

  /// Best reading of the card; null when it wasn't recognized. Its variant is
  /// the model's PREDICTION (a hypothesis, marked
  /// [PrintingSource.visionHypothesis] so pricing refuses it): the printing is
  /// settled by `PrintingResolutionService`, not here.
  final PrintingDescriptor? printing;

  /// What the photo shows, independent of what the model called it.
  final VisualObservation visual;

  /// Why the printing is uncertain, as the model and our checks see it.
  final List<UncertaintyReason> uncertaintyReasons;

  /// Problems with the card itself (language unreadable, number only
  /// guessed), which no printing research can fix.
  final List<String> cardIssues;

  /// How sure the card itself (name + number) is right.
  final double cardConfidence;

  /// How sure the MODEL is of its printing prediction (language + variant): a
  /// hypothesis score, not the resolved printing's confidence.
  /// 99% card / 63% printing is NOT a 99% match.
  final double printingConfidence;
  final String reason;
  final EvidenceRequest evidenceNeeded;

  /// Other printings the model thought this could be.
  final List<PrintingVariant> printingCandidates;

  /// Distinguishing marks the model saw (star by the rarity, crew artwork, ...).
  /// Kept for display and debugging, not saved on the card.
  final List<String> visibleMarkers;
  final String provider;
  final String model;
  final String rawResponse;
}
