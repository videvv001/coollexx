import 'dart:math' as math;
import 'dart:ui' show Rect;

import '../models/card_field_options.dart';
import '../models/card_language.dart';
import '../models/release_category.dart';

/// One recognized text block, already normalized to the cropped card image
/// (0..1 on both axes) so nothing downstream deals in camera pixels.
///
/// Deliberately free of any ML Kit types: this is what makes the layout
/// classification below testable without a device — see
/// `test/card_text_layout_test.dart`. `card_text_scan.dart` is the only
/// thing that knows how to build these from a real scan.
class OcrBlock {
  const OcrBlock({
    required this.text,
    required this.box,
    this.lineCount = 1,
    this.confidence,
  });

  final String text;
  final Rect box;
  final int lineCount;

  /// Mean per-line OCR confidence. Android-only — ML Kit returns null for
  /// it on iOS, so this is a tiebreaker, never a gate.
  final double? confidence;

  double get area => box.width * box.height;
}

/// Best-effort name/number/kind/language guess from OCR of a card photo,
/// used only to prefill the card form — never authoritative, always left
/// editable. A null field means "couldn't tell": callers leave their field
/// alone rather than filling in a guess.
class CardTextGuess {
  const CardTextGuess({this.name, this.number, this.kind, this.language});

  final String? name;
  final String? number;
  final String? kind;
  final CardLanguage? language;
}

/// A horizontal/vertical slice of the normalized card. Regions only ever
/// *narrow* the candidate set — which block is the name is then decided by
/// the relationships in `_findName`, not by the band alone. A card's lower
/// third holds the kind banner, the name, the trait line and the card ID,
/// so "it's near the bottom" can never mean "it's the name".
class _Band {
  const _Band({this.top = 0, this.bottom = 1, this.left = 0, this.right = 1});

  final double top;
  final double bottom;
  final double left;
  final double right;

  bool contains(OcrBlock b) {
    final c = b.box.center;
    return c.dy >= top && c.dy <= bottom && c.dx >= left && c.dx <= right;
  }
}

class _CardRegions {
  const _CardRegions({
    required this.name,
    required this.cardId,
    this.kind = const _Band(),
  });

  final _Band name;
  final _Band cardId;
  final _Band kind;
}

// ponytail: provisional bands, derived from a handful of inspected cards
// (a JP One Piece character card and a JP Pokémon card) — not a surveyed
// sample. They're intentionally generous because they only reduce the
// candidate set; the relational rules do the actual deciding. Tighten them
// only against real misclassifications, and keep them here rather than
// scattering thresholds through the logic.
const _regions = {
  ReleaseCategory.onePiece: _CardRegions(
    // Kind banner, name and trait all live in the bottom quarter, stacked
    // in that order; the ID is the small bottom-right stamp.
    kind: _Band(top: 0.70, bottom: 0.90),
    name: _Band(top: 0.74, bottom: 0.95, left: 0.10, right: 0.90),
    cardId: _Band(top: 0.85, bottom: 1.0, left: 0.50),
  ),
  ReleaseCategory.pokemon: _CardRegions(
    // Name is top-left, printed large; HP sits top-right on the same line.
    name: _Band(top: 0.0, bottom: 0.30, right: 0.70),
    cardId: _Band(top: 0.72, bottom: 1.0, right: 0.55),
  ),
  ReleaseCategory.others: _CardRegions(name: _Band(), cardId: _Band()),
};

final _pokemonNumberPattern = RegExp(r'\d{1,3}\s*/\s*\d{1,3}');
final _onePieceIdPattern = RegExp(r'OP\d{1,2}-\d{3}', caseSensitive: false);
final _cjkPattern = RegExp(r'[぀-ヿ一-鿿]');
// Power/counter values ("+3000", "5000") mark effect text. No card name
// carries a run of three or more digits, so this separates the effect box
// from the name even when both land in the same band.
final _bigNumberPattern = RegExp(r'\d{3,}');
// HP is printed on the same line as a Pokémon name, so OCR often returns
// them as one block; stripped rather than used to reject the block.
final _hpPattern = RegExp(r'\bHP\b\s*\d+', caseSensitive: false);

/// Longest name we'll accept. Past this it's effect/rules prose, not a
/// name — the longest real names inspected sit around a dozen characters.
const _maxNameLength = 20;

/// Classifies [blocks] into the card fields worth prefilling.
///
/// Order of trust, highest first:
/// 1. The card ID, when its format matches — an ID is self-validating in a
///    way a free-text name never is. If a card catalogue is ever bundled
///    (deliberately deferred, see `add_manual_screen.dart`), this is where
///    the ID would be looked up and the official record would replace the
///    OCR guesses below rather than sit alongside them.
/// 2. The kind banner, matched against the app's own kind list
///    (`CardFieldOptions.kind`) rather than a second list maintained here.
/// 3. The name, chosen relative to the kind banner and the other blocks.
///
/// Ambiguity resolves to null, not to a guess.
CardTextGuess classifyCardText(
  List<OcrBlock> blocks,
  ReleaseCategory category,
) {
  if (blocks.isEmpty) return const CardTextGuess();
  final deduped = _dedupe(blocks);
  final kind = _findKind(deduped, category);
  return CardTextGuess(
    name: _findName(deduped, category, kind),
    number: _findNumber(deduped, category),
    kind: kind?.value,
    language: _findLanguage(deduped),
  );
}

class _KindMatch {
  const _KindMatch(this.block, this.value);
  final OcrBlock block;
  final String value;
}

/// Whether kind is printed on the card as its own standalone banner.
///
/// One Piece prints CHARACTER/LEADER/EVENT/STAGE/DON!! in fixed English on
/// every card regardless of print language, which makes it both reliably
/// matchable and a reliable anchor for the name below it. Pokémon's kinds
/// aren't printed that way — and "Energy" appears *inside* real card names
/// ("Fire Energy") — so kind matching stays off there rather than risking
/// blanking those names.
bool _kindIsPrintedBanner(ReleaseCategory category) =>
    category == ReleaseCategory.onePiece;

/// Matches [text] against the app's existing kind options for [category]
/// (`CardFieldOptions.kind`) — the single source of truth for what kinds
/// exist, so adding a kind there teaches the scanner about it too.
String? kindValueFor(String text, ReleaseCategory category) {
  if (!_kindIsPrintedBanner(category)) return null;
  final options = CardFieldOptions.kind[category];
  if (options == null) return null;
  final upper = text.toUpperCase();
  for (final option in options) {
    if (option == 'None') continue;
    // The card prints "DON!!", the app's option is "DON!!Card".
    final printed = option.toUpperCase().replaceAll('CARD', '').trim();
    if (printed.isEmpty) continue;
    if (upper.contains(printed)) return option;
  }
  return null;
}

_KindMatch? _findKind(List<OcrBlock> blocks, ReleaseCategory category) {
  final region = _regions[category]!.kind;
  _KindMatch? loose;
  for (final b in blocks) {
    final value = kindValueFor(b.text, category);
    if (value == null) continue;
    if (region.contains(b)) return _KindMatch(b, value);
    loose ??= _KindMatch(b, value);
  }
  // A kind label found outside the expected band still identifies the
  // kind, it just isn't trusted as the name's anchor (see `_findName`).
  return loose;
}

/// The name text a block would contribute, with the noise that rides along
/// with it removed. Empty means the block can't be a name.
String _nameTextOf(OcrBlock b) =>
    b.text.replaceAll(_hpPattern, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

bool _looksLikeProse(OcrBlock b, ReleaseCategory category) {
  final text = _nameTextOf(b);
  if (text.isEmpty) return true;
  if (b.lineCount > 1) return true;
  if (text.length > _maxNameLength) return true;
  if (_bigNumberPattern.hasMatch(text)) return true;
  return _isIdLike(text, category);
}

bool _isIdLike(String text, ReleaseCategory category) {
  if (_onePieceIdPattern.hasMatch(text)) return true;
  if (category == ReleaseCategory.pokemon) {
    return _pokemonNumberPattern.hasMatch(text);
  }
  return false;
}

bool _horizontallyOverlaps(Rect a, Rect b) {
  final left = math.max(a.left, b.left);
  final right = math.min(a.right, b.right);
  final overlap = right - left;
  if (overlap <= 0) return false;
  return overlap / math.min(a.width, b.width) > 0.3;
}

String? _findName(
  List<OcrBlock> blocks,
  ReleaseCategory category,
  _KindMatch? kind,
) {
  final regions = _regions[category]!;
  // Everything a name is definitively not: the kind banner itself, the
  // card ID, and effect/trait prose.
  final candidates = blocks
      .where((b) => kindValueFor(b.text, category) == null)
      .where((b) => !_looksLikeProse(b, category))
      .toList();
  if (candidates.isEmpty) return null;

  // Primary signal: the block stacked directly under the kind banner. On
  // One Piece that's the name, with the trait line below it again — which
  // is why this takes the *nearest* block below, not any of them.
  if (kind != null && regions.kind.contains(kind.block)) {
    final below =
        candidates
            .where((b) => b.box.center.dy > kind.block.box.center.dy)
            .where((b) => _horizontallyOverlaps(b.box, kind.block.box))
            .toList()
          ..sort((a, b) => a.box.top.compareTo(b.box.top));
    if (below.isNotEmpty) return _nameTextOf(below.first);
  }

  // Fallback: the most prominent candidate inside the name band. No
  // whole-card fallback beyond this — if nothing is in the band, the read
  // is ambiguous and says so by returning null.
  final inBand = candidates.where(regions.name.contains).toList();
  if (inBand.isEmpty) return null;
  inBand.sort((a, b) {
    final byArea = b.area.compareTo(a.area);
    if (byArea != 0) return byArea;
    return (b.confidence ?? 0).compareTo(a.confidence ?? 0);
  });
  return _nameTextOf(inBand.first);
}

String? _findNumber(List<OcrBlock> blocks, ReleaseCategory category) {
  final region = _regions[category]!.cardId;
  final pattern = switch (category) {
    ReleaseCategory.onePiece => _onePieceIdPattern,
    _ => _pokemonNumberPattern,
  };
  final match = _firstMatch(blocks, pattern, region) ??
      // "Others" has no known layout, so either format is fair game.
      (category == ReleaseCategory.others
          ? _firstMatch(blocks, _onePieceIdPattern, const _Band())
          : null);
  return match;
}

String? _firstMatch(List<OcrBlock> blocks, RegExp pattern, _Band region) {
  for (final b in blocks.where(region.contains)) {
    final m = pattern.firstMatch(b.text);
    if (m != null) return m.group(0);
  }
  for (final b in blocks) {
    final m = pattern.firstMatch(b.text);
    if (m != null) return m.group(0);
  }
  return null;
}

/// Only JP/EN are distinguished — those are the two scripts actually read.
/// Any kana/kanji anywhere on the card means a Japanese print.
CardLanguage? _findLanguage(List<OcrBlock> blocks) {
  if (blocks.isEmpty) return null;
  return blocks.any((b) => _cjkPattern.hasMatch(b.text))
      ? CardLanguage.jp
      : CardLanguage.eng;
}

/// Latin and Japanese recognition passes both report the same physical
/// text, so the same line arrives twice — once read properly and once as
/// mojibake. Left in, those duplicates break "the block directly below the
/// kind banner", so overlapping boxes collapse to their better reading.
List<OcrBlock> _dedupe(List<OcrBlock> blocks) {
  final kept = <OcrBlock>[];
  for (final block in blocks) {
    final existing = kept.indexWhere((k) => _overlapsHeavily(k.box, block.box));
    if (existing == -1) {
      kept.add(block);
      continue;
    }
    if (_isBetterReading(block, kept[existing])) kept[existing] = block;
  }
  return kept;
}

bool _isBetterReading(OcrBlock candidate, OcrBlock current) {
  final candidateCjk = _cjkPattern.hasMatch(candidate.text);
  final currentCjk = _cjkPattern.hasMatch(current.text);
  // A CJK reading of a CJK line beats the Latin pass's attempt at it.
  if (candidateCjk != currentCjk) return candidateCjk;
  final byConfidence =
      (candidate.confidence ?? 0).compareTo(current.confidence ?? 0);
  if (byConfidence != 0) return byConfidence > 0;
  return candidate.text.trim().length > current.text.trim().length;
}

bool _overlapsHeavily(Rect a, Rect b) {
  final inter = a.intersect(b);
  if (inter.width <= 0 || inter.height <= 0) return false;
  final smaller = math.min(a.width * a.height, b.width * b.height);
  if (smaller <= 0) return false;
  return (inter.width * inter.height) / smaller > 0.6;
}
