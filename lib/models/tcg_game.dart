import 'release_category.dart';

/// The card games in scope. [code] is the stable internal identifier (store
/// and compare this); [displayName] is for prompts and UI only.
///
/// Japanese Pokémon is not a separate game — it's [pokemon] printed under a
/// Japanese catalog standard (see `PrintingDescriptor.standard`).
enum TcgGame {
  mtg('MTG', 'Magic: The Gathering'),
  pokemon('POKEMON', 'Pokémon Trading Card Game'),
  onePiece('ONE_PIECE', 'One Piece Card Game'),
  yugioh('YUGIOH', 'Yu-Gi-Oh! Trading Card Game'),
  lorcana('LORCANA', 'Disney Lorcana'),
  riftbound('RIFTBOUND', 'Riftbound: League of Legends Trading Card Game'),
  gundam('GUNDAM', 'Gundam Card Game'),
  dbsFusionWorld(
    'DBS_FUSION_WORLD',
    'Dragon Ball Super Card Game: Fusion World',
  ),
  digimon('DIGIMON', 'Digimon Card Game');

  final String code;
  final String displayName;
  const TcgGame(this.code, this.displayName);

  /// The game a folder category holds, or null for `others` (no catalog to
  /// price against).
  static TcgGame? fromCategory(ReleaseCategory category) => switch (category) {
    ReleaseCategory.pokemon => pokemon,
    ReleaseCategory.onePiece => onePiece,
    ReleaseCategory.others => null,
  };

  static TcgGame? fromCode(String? code) {
    for (final g in values) {
      if (g.code == code) return g;
    }
    return null;
  }
}
