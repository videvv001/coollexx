import 'printing_variant.dart';
import 'visual_observation.dart';

/// One KNOWN physical printing of a logical card (number + language), as found
/// by printing research — never invented. Three things stay separate:
///   - [officialRarity]: what the publisher prints (shared by many printings);
///   - [variantName]: our canonical key for the printing (`RED_MANGA_RARE`);
///   - [marketplaceAliases]: what shops call it. For finding and matching
///     listings only; not an official name.
class PrintingCandidate {
  const PrintingCandidate({
    required this.family,
    required this.variantName,
    this.officialRarity,
    this.marketplaceAliases = const [],
    this.artworkDescription,
    this.visual = VisualObservation.unknown,
    this.visualMarkers = const [],
    this.referenceImageUrl,
    this.evidenceSources = const [],
  });

  final VariantFamily family;
  final String? variantName;
  final String? officialRarity;
  final List<String> marketplaceAliases;
  final String? artworkDescription;

  /// What this printing looks like, in the same vocabulary as a photo's
  /// [VisualObservation].
  final VisualObservation visual;
  final List<String> visualMarkers;

  /// A picture of this printing, when a source had one. Stored for future
  /// image matching; nothing compares pixels yet.
  final String? referenceImageUrl;

  /// Pages the research visited that show this printing.
  final List<String> evidenceSources;

  String get label => variantName ?? family.label;

  /// True when [name] (a model's guess or a listing's wording) is this
  /// printing's key or one of its aliases.
  bool matchesName(String? name) {
    final n = normalizeVariantName(name);
    if (n == null) return false;
    return n == variantName ||
        marketplaceAliases.any((a) => normalizeVariantName(a) == n);
  }

  PrintingVariant toVariant({String? artwork}) => PrintingVariant(
    family: family,
    name: variantName,
    artwork: artwork ?? artworkDescription,
  );

  factory PrintingCandidate.fromJson(Map<String, dynamic> j) {
    List<String> strings(Object? v) => [
      for (final s in (v as List?) ?? const [])
        if (s is String && s.trim().isNotEmpty) s.trim(),
    ];
    return PrintingCandidate(
      family: VariantFamily.fromCode(j['variant_family'] as String?),
      variantName: normalizeVariantName(j['variant_name'] as String?),
      officialRarity: (j['official_rarity'] as String?)?.trim(),
      marketplaceAliases: strings(j['marketplace_aliases']),
      artworkDescription: (j['artwork_description'] as String?)?.trim(),
      visual: VisualObservation.fromJson(j['visual']),
      visualMarkers: strings(j['visual_markers']),
      referenceImageUrl: (j['reference_image_url'] as String?)?.trim(),
      evidenceSources: strings(j['evidence_urls']),
    );
  }

  Map<String, Object?> toJson() => {
    'variant_family': family.code,
    'variant_name': variantName,
    'official_rarity': officialRarity,
    'marketplace_aliases': marketplaceAliases,
    'artwork_description': artworkDescription,
    'visual': visual.toJson(),
    'visual_markers': visualMarkers,
    'reference_image_url': referenceImageUrl,
    'evidence_urls': evidenceSources,
  };
}
