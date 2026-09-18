import 'release_category.dart';

/// Predefined dropdown values for card fields whose options are controlled
/// per `ReleaseCategory`, instead of free text. A card's category is
/// derived from its release's category (there's no separate per-card
/// category) — see `CardCategoryFields`.
class CardFieldOptions {
  CardFieldOptions._();

  static const Map<ReleaseCategory, List<String>> rarity = {
    ReleaseCategory.onePiece: [
      'None', 'P-SEC', 'SEC', 'P-SR', 'SR', 'PR', 'R', 'P-UC', 'UC', 'PC',
      'C', 'PL', 'L', 'SP', 'TR', 'PP', 'P',
    ],
    ReleaseCategory.pokemon: [
      'None', 'MUR', 'BWR', 'FUR', 'UR', 'HR', 'SAR', 'MA', 'CSR', 'SSR',
      'SR', 'AR', 'CHR', 'S', 'TR', 'A', 'H', 'ACE', 'K', 'PR', 'RRR', 'RR',
      'R', 'U', 'C', 'S-TD', 'TD', 'PROMO',
    ],
    ReleaseCategory.others: [
      'None', 'Common', 'Uncommon', 'Rare', 'Super Rare', 'Promo',
    ],
  };

  static const Map<ReleaseCategory, List<String>> kind = {
    ReleaseCategory.onePiece: [
      'None', 'Character', 'Event', 'Stage', 'DON!!Card', 'Leader',
    ],
    ReleaseCategory.pokemon: ['None', 'Pokemon', 'Energy', 'Trainers'],
  };

  static const List<String> onePieceColor = [
    'Red', 'Green', 'Blue', 'Purple', 'Black', 'Yellow',
  ];

  // ponytail: no existing Pokémon Type list in this codebase to keep, so
  // this is the standard TCG energy-type set — swap if the game adds more.
  static const List<String> pokemonType = [
    'Grass', 'Fire', 'Water', 'Lightning', 'Psychic', 'Fighting', 'Darkness',
    'Metal', 'Fairy', 'Dragon', 'Colorless',
  ];
}
