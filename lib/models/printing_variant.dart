/// Broad bucket for how a printing differs from the card's regular print.
/// Stored as [code]; an unrecognised stored code reads back as [unknown], so
/// families can be added later without breaking older rows.
enum VariantFamily {
  base('BASE', 'Base'),
  parallel('PARALLEL', 'Parallel'),
  superParallel('SUPER_PARALLEL', 'Super parallel'),
  special('SPECIAL', 'Special'),
  promo('PROMO', 'Promo'),
  other('OTHER', 'Other'),

  /// Not determined. Never the same as [base]: old cards and uncertain scans
  /// are unknown, and an unknown printing is not priced.
  unknown('UNKNOWN', 'Unknown');

  final String code;
  final String label;
  const VariantFamily(this.code, this.label);

  static VariantFamily fromCode(String? code) {
    for (final f in values) {
      if (f.code == code) return f;
    }
    return unknown;
  }
}

/// Which physical printing of a card this is — the part card number and
/// official rarity can't tell apart (EB04-061 has a base, a parallel and a
/// crew-art print, all `SEC`). Game-neutral: marketplace wording belongs in
/// each marketplace adapter, never here.
class PrintingVariant {
  const PrintingVariant({required this.family, this.name, this.artwork});

  static const unknown = PrintingVariant(family: VariantFamily.unknown);

  final VariantFamily family;

  /// The specific printing as an UPPER_SNAKE key, e.g. `RED_MANGA_RARE`. Free
  /// text so a new printing needs no code change; see [normalizeVariantName].
  final String? name;

  /// What the artwork shows. Visual evidence kept from recognition; later it
  /// can hold an artwork ID or fingerprint.
  final String? artwork;

  bool get isResolved => family != VariantFamily.unknown;

  /// Human label for the UI: the specific name when there is one.
  String get displayLabel {
    final n = name;
    if (n == null) return family.label;
    final words = n
        .split('_')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0] + w.substring(1).toLowerCase());
    return words.join(' ');
  }

  PrintingVariant copyWith({
    VariantFamily? family,
    String? name,
    bool clearName = false,
    String? artwork,
    bool clearArtwork = false,
  }) => PrintingVariant(
    family: family ?? this.family,
    name: clearName ? null : (name ?? this.name),
    artwork: clearArtwork ? null : (artwork ?? this.artwork),
  );

  @override
  bool operator ==(Object other) =>
      other is PrintingVariant &&
      other.family == family &&
      other.name == name &&
      other.artwork == artwork;

  @override
  int get hashCode => Object.hash(family, name, artwork);

  @override
  String toString() => 'PrintingVariant(${family.code}, $name, $artwork)';
}

/// "Pirate Crew Super Parallel" → `PIRATE_CREW_SUPER_PARALLEL`. Null for
/// anything with no letters or digits.
String? normalizeVariantName(String? raw) {
  final n = raw
      ?.trim()
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return (n == null || n.isEmpty) ? null : n;
}
