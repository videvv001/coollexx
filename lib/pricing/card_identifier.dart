import 'card_recognition_service.dart';
import 'price_research_service.dart';
import 'printing_resolution_service.dart';

/// A photo's full identification: what the vision model said, what the known
/// printings say, and the verdict to act on. [status] and [printing] are the
/// final answer — pricing must use them, never [recognition].printing (which is
/// only the model's hypothesis).
class IdentificationResult {
  const IdentificationResult({
    required this.recognition,
    required this.status,
    required this.reason,
    required this.evidenceNeeded,
    this.resolution,
    this.printing,
  });

  final RecognitionResult recognition;

  /// Null when the card itself wasn't recognized, so no resolution was tried.
  final PrintingResolution? resolution;

  /// `identified` only when the card is certain AND the exact printing is
  /// resolved. Anything else is not priced.
  final RecognitionStatus status;

  /// The resolved printing (priceable), the unresolved prediction (not
  /// priceable) or the user-facing card; null when unrecognized.
  final PrintingDescriptor? printing;
  final String reason;
  final EvidenceRequest evidenceNeeded;
}

/// recognize → resolve. The only place a vision prediction becomes a printing
/// that may be priced.
class CardIdentifier {
  CardIdentifier({required this.recognition, required this.resolver});

  final CardRecognitionService recognition;
  final PrintingResolutionService resolver;

  Future<IdentificationResult> identify(List<String> imagePaths) async {
    final r = await recognition.recognize(imagePaths);
    return resolveRecognition(r);
  }

  /// The second half on its own, for a recognition that's already been paid
  /// for.
  Future<IdentificationResult> resolveRecognition(RecognitionResult r) async {
    final logical = r.printing;
    if (r.status == RecognitionStatus.failed ||
        r.status == RecognitionStatus.unrecognized ||
        logical == null) {
      return IdentificationResult(
        recognition: r,
        status: r.status,
        printing: logical,
        reason: r.reason,
        evidenceNeeded: r.evidenceNeeded,
      );
    }
    final PrintingResolution resolution;
    try {
      resolution = await resolver.resolve(
        logical: logical,
        observed: r.visual,
      );
    } catch (e) {
      return IdentificationResult(
        recognition: r,
        status: RecognitionStatus.verificationRequired,
        printing: logical,
        reason: 'Printing resolution failed: $e',
        evidenceNeeded: EvidenceRequest.userConfirmation,
      );
    }
    final priceable = resolution.descriptorFor(logical);
    if (priceable != null && r.cardIssues.isEmpty) {
      return IdentificationResult(
        recognition: r,
        resolution: resolution,
        status: RecognitionStatus.identified,
        printing: priceable,
        reason: '',
        evidenceNeeded: EvidenceRequest.none,
      );
    }
    // Card-level doubt wins: no printing research fixes an unreadable number.
    final cardOnly = priceable != null;
    return IdentificationResult(
      recognition: r,
      resolution: resolution,
      status: RecognitionStatus.verificationRequired,
      printing: cardOnly ? priceable : logical,
      reason: cardOnly
          ? r.cardIssues.join('. ')
          : [resolution.reason, ...resolution.evidence].join('. '),
      evidenceNeeded: cardOnly
          ? EvidenceRequest.userConfirmation
          : resolution.evidenceNeeded,
    );
  }
}
