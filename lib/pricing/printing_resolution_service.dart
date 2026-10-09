import 'dart:math' as math;

import '../data/printing_candidate_repository.dart';
import '../models/printing_candidate.dart';
import '../models/printing_variant.dart';
import '../models/visual_observation.dart';
import 'card_recognition_service.dart';
import 'price_research_service.dart';
import 'pricing_config.dart';
import 'printing_research_service.dart';

enum ResolutionStatus { resolved, verificationRequired }

class RejectedCandidate {
  const RejectedCandidate(this.candidate, this.reason);
  final PrintingCandidate candidate;
  final String reason;
}

/// Which known physical printing a photo is, and why. The vision model's guess
/// ([visionPredicted]) is kept beside the answer ([resolved]) so a refinement
/// (MANGA_RARE → RED_MANGA_RARE) is visible, never silent.
class PrintingResolution {
  const PrintingResolution({
    required this.status,
    required this.visionPredicted,
    required this.confidence,
    required this.reason,
    this.resolved,
    this.candidates = const [],
    this.rejected = const [],
    this.evidence = const [],
    this.reasons = const [],
    this.candidatesFrom = '',
    this.researchRaw = '',
  });

  final ResolutionStatus status;
  final PrintingVariant visionPredicted;
  final PrintingCandidate? resolved;
  final double confidence;
  final String reason;

  /// Every known printing considered.
  final List<PrintingCandidate> candidates;
  final List<RejectedCandidate> rejected;

  /// Lines of reasoning, in plain words.
  final List<String> evidence;
  final List<UncertaintyReason> reasons;

  /// `cache`, or the research provider that found them.
  final String candidatesFrom;
  final String researchRaw;

  bool get isResolved => status == ResolutionStatus.resolved;

  /// What would actually help when unresolved; none when resolved.
  EvidenceRequest get evidenceNeeded =>
      isResolved ? EvidenceRequest.none : evidenceFor(reasons);

  /// [logical] with the resolved printing filled in: ready to price. The
  /// other printings' aliases ride along so a listing of one of them is
  /// recognised as the wrong card.
  PrintingDescriptor? descriptorFor(PrintingDescriptor logical) {
    final w = resolved;
    if (w == null) return null;
    return PrintingDescriptor(
      game: logical.game,
      name: logical.name,
      cardNumber: logical.cardNumber,
      language: logical.language,
      standard: logical.standard,
      setCode: logical.setCode,
      rarity: logical.rarity,
      variant: w.toVariant(artwork: visionPredicted.artwork),
      source: PrintingSource.resolved,
      searchAliases: w.marketplaceAliases,
      excludedAliases: [
        for (final c in candidates)
          if (!identical(c, w)) ...c.marketplaceAliases,
      ],
      visualMarkers: w.visualMarkers,
    );
  }
}

String _rarity(String r) =>
    r.trim().toUpperCase().replaceFirst(RegExp(r'^P-'), '');

/// Matches [observed] against the known printings [candidates] of one logical
/// card. Pure: no network, no card numbers, no printing names — only fields.
///
///  1. A printing is ruled out by a different official rarity, or by any
///     visual field where the photo and the printing both have a value and
///     disagree. Unknown on either side is neutral. Foil is never compared: a
///     flat photo can't show it.
///  2. More than one left → can't tell; say what kind of doubt it is.
///  3. One left → score it from agreeing fields, rivals ruled out, a source
///     page and the vision guess. At or above the threshold it is resolved.
PrintingResolution resolvePrinting({
  required PrintingDescriptor logical,
  required VisualObservation observed,
  required List<PrintingCandidate> candidates,
  PricingConfig config = const PricingConfig(),
  String candidatesFrom = '',
  String researchRaw = '',
  String note = '',
}) {
  final predicted = logical.variant;
  PrintingResolution unresolved(
    String reason,
    List<UncertaintyReason> reasons, {
    List<RejectedCandidate> rejected = const [],
    List<String> evidence = const [],
    double confidence = 0,
  }) => PrintingResolution(
    status: ResolutionStatus.verificationRequired,
    visionPredicted: predicted,
    confidence: confidence,
    reason: reason,
    candidates: candidates,
    rejected: rejected,
    evidence: evidence,
    reasons: reasons,
    candidatesFrom: candidatesFrom,
    researchRaw: researchRaw,
  );

  if (candidates.isEmpty) {
    return unresolved(
      note.isEmpty ? 'No verified printings are known for this card.' : note,
      [UncertaintyReason.unknownPrinting],
    );
  }

  final seen = observed.comparable..remove('foil');
  final wanted = logical.rarity;
  final rejected = <RejectedCandidate>[];
  final matches = <PrintingCandidate, List<String>>{};
  for (final c in candidates) {
    if (wanted != null &&
        c.officialRarity != null &&
        _rarity(wanted) != _rarity(c.officialRarity!)) {
      rejected.add(
        RejectedCandidate(
          c,
          'official rarity ${c.officialRarity} ≠ ${wanted.trim()}',
        ),
      );
      continue;
    }
    final theirs = c.visual.comparable;
    final agree = <String>[];
    final clash = <String>[];
    for (final e in seen.entries) {
      final (a, b) = (e.value, theirs[e.key]);
      if (a == null || b == null) continue;
      (a == b ? agree : clash).add(
        a == b
            ? '${e.key} ${_show(a)}'
            : '${e.key}: photo ${_show(a)} vs ${_show(b)}',
      );
    }
    if (clash.isNotEmpty) {
      rejected.add(RejectedCandidate(c, clash.join('; ')));
    } else {
      matches[c] = agree;
    }
  }

  final left = matches.keys.toList();
  if (left.isEmpty) {
    return unresolved(
      'The photo matches none of the ${candidates.length} known printings.',
      [UncertaintyReason.unknownPrinting],
      rejected: rejected,
    );
  }
  if (left.length > 1) {
    // What kind of doubt: a field the printings differ on that the photo
    // didn't show (a closer photo helps), foil only (a tilted photo helps), or
    // the research simply doesn't say (nothing a photo can fix).
    final theirs = [for (final c in left) c.visual.comparable];
    bool differs(String k) => theirs.map((m) => m[k]).toSet().length > 1;
    final photoMissed = seen.entries.any(
      (e) => e.value == null && differs(e.key),
    );
    final foilOnly = differs('foil') && !seen.keys.any(differs);
    return unresolved(
      "Can't tell ${left.map((c) => c.label).join(' from ')} apart.",
      [
        photoMissed
            ? UncertaintyReason.artworkVariantUncertain
            : foilOnly
            ? UncertaintyReason.foilTreatmentUncertain
            : UncertaintyReason.marketplaceClassificationUncertain,
      ],
      rejected: rejected,
    );
  }

  final w = left.single;
  final agree = matches[w]!;
  final predictionAgrees =
      w.matchesName(predicted.name) ||
      (predicted.name == null && predicted.family == w.family);
  final score = math.min(
    0.97,
    config.resolutionBase +
        config.resolutionPerMatch * math.min(agree.length, 3) +
        // One survivor means every other printing was ruled out.
        (candidates.length == 1
            ? config.resolutionSoleBonus
            : config.resolutionRivalBonus) +
        (w.evidenceSources.isNotEmpty ? config.resolutionEvidenceBonus : 0) +
        (predictionAgrees ? config.resolutionEvidenceBonus : 0),
  );
  final evidence = [
    for (final a in agree) 'photo and ${w.label} agree: $a',
    for (final r in rejected)
      '${r.candidate.label} ruled out — ${r.reason}',
    if (!predictionAgrees && predicted.isResolved)
      'vision predicted ${predicted.displayLabel}; the photo evidence outweighs '
          'that guess',
    if (w.evidenceSources.isNotEmpty)
      '${w.evidenceSources.length} source page(s) for ${w.label}',
  ];
  if (score < config.resolutionThreshold) {
    return unresolved(
      'Only ${w.label} fits, but at ${(score * 100).round()}% that is below '
      '${(config.resolutionThreshold * 100).round()}%.',
      [
        agree.length < 2
            ? UncertaintyReason.artworkVariantUncertain
            : UncertaintyReason.marketplaceClassificationUncertain,
      ],
      rejected: rejected,
      evidence: evidence,
      confidence: score,
    );
  }
  return PrintingResolution(
    status: ResolutionStatus.resolved,
    visionPredicted: predicted,
    resolved: w,
    confidence: score,
    reason: '',
    candidates: candidates,
    rejected: rejected,
    evidence: evidence,
    candidatesFrom: candidatesFrom,
    researchRaw: researchRaw,
  );
}

String _show(Object v) => v is Coded ? v.code : '$v';

/// Finds the known printings of a card (cached, else live research) and
/// resolves a photo against them.
class PrintingResolutionService {
  PrintingResolutionService({
    required this.research,
    this.cache,
    this.config = const PricingConfig(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final PrintingResearchService research;

  /// null = no caching (tests, one-offs).
  final PrintingCandidateRepository? cache;
  final PricingConfig config;
  final DateTime Function() _clock;

  Future<PrintingResolution> resolve({
    required PrintingDescriptor logical,
    required VisualObservation observed,
  }) async {
    var from = 'cache';
    var raw = '';
    var note = '';
    var candidates = await cache?.lookup(
      logical,
      maxAge: config.printingCandidateTtl,
      now: _clock(),
    );
    if (candidates == null || candidates.isEmpty) {
      final found = await research.discover(logical);
      from = research.provider;
      raw = found.rawResponse;
      note = found.reason;
      candidates = found.candidates;
      if (candidates.isNotEmpty) {
        await cache?.save(
          logical,
          candidates,
          provider: research.provider,
          now: _clock(),
        );
      }
    }
    return resolvePrinting(
      logical: logical,
      observed: observed,
      candidates: candidates,
      config: config,
      candidatesFrom: from,
      researchRaw: raw,
      note: note,
    );
  }
}

// --- Listings vs printings ---------------------------------------------

/// Lower-case, without spaces and separators, so `SEC-RSP`, `sec rsp` and
/// `ＳＥＣ－ＲＳＰ`-ish spellings meet.
String _squash(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[\s_\-・･　]+'), '');

int _longestHit(String title, Iterable<String> aliases) {
  final t = _squash(title);
  var best = 0;
  for (final a in aliases) {
    final q = _squash(a);
    if (q.length >= 2 && t.contains(q)) best = math.max(best, q.length);
  }
  return best;
}

enum ListingVerdict { thisPrinting, otherPrinting, ambiguous, unknown }

/// Which printing a listing's wording belongs to. One alias can contain
/// another (`コミパラ` inside `レッドコミパラ`, "Manga Rare" inside "Red Manga
/// Rare"), so the LONGEST matching alias wins and an exact tie is ambiguous.
ListingVerdict attributeListing(String title, PrintingDescriptor p) {
  if (p.excludedAliases.isEmpty) return ListingVerdict.unknown;
  final name = p.variant.name?.replaceAll('_', ' ');
  final ours = _longestHit(title, [...p.searchAliases, ?name]);
  final theirs = _longestHit(title, p.excludedAliases);
  if (ours == 0 && theirs == 0) return ListingVerdict.unknown;
  if (ours > theirs) return ListingVerdict.thisPrinting;
  return ours == theirs
      ? ListingVerdict.ambiguous
      : ListingVerdict.otherPrinting;
}
