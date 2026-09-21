// Regression coverage for the per-folder sort options added in FolderScreen
// (see lib/screens/folder/folder_sort.dart): natural (numeric-aware) ID
// ordering, rarity-hierarchy ordering, and deterministic tie-breaks so card
// order never depends on database row order or recomposition timing.

import 'package:flutter_test/flutter_test.dart';

import 'package:pokedex_tcg/models/release_category.dart';
import 'package:pokedex_tcg/models/tcg_card.dart';
import 'package:pokedex_tcg/screens/folder/folder_sort.dart';

TcgCard _card({
  required String id,
  String? number,
  String? rarity,
  bool isFavorite = false,
  DateTime? createdAt,
}) => TcgCard(
  id: id,
  number: number,
  rarity: rarity,
  isFavorite: isFavorite,
  createdAt: createdAt ?? DateTime(2026, 1, 1),
);

void main() {
  test('compareCardIds sorts numeric runs numerically, not lexically', () {
    final ids = ['OP14-100', 'OP14-2', 'OP14-10', 'OP14-1'];
    ids.sort(compareCardIds);
    expect(ids, ['OP14-1', 'OP14-2', 'OP14-10', 'OP14-100']);
  });

  test('ID sort supports ascending and descending, nulls always last', () {
    final cards = [
      _card(id: 'a', number: 'OP14-10'),
      _card(id: 'b', number: null),
      _card(id: 'c', number: 'OP14-2'),
    ];

    final asc = sortFolderCards(
      cards,
      type: FolderSortType.id,
      direction: SortDirection.ascending,
      category: ReleaseCategory.onePiece,
    );
    expect(asc.map((c) => c.id), ['c', 'a', 'b']);

    final desc = sortFolderCards(
      cards,
      type: FolderSortType.id,
      direction: SortDirection.descending,
      category: ReleaseCategory.onePiece,
    );
    expect(desc.map((c) => c.id), ['a', 'c', 'b']);
  });

  test(
    'Favorite sort puts favorites first, ID ascending within each group',
    () {
      final cards = [
        _card(id: 'a', number: 'OP14-2'),
        _card(id: 'b', number: 'OP14-1', isFavorite: true),
        _card(id: 'c', number: 'OP14-10'),
        _card(id: 'd', number: 'OP14-5', isFavorite: true),
      ];

      final sorted = sortFolderCards(
        cards,
        type: FolderSortType.favorite,
        direction: SortDirection.ascending,
        category: ReleaseCategory.onePiece,
      );
      expect(sorted.map((c) => c.id), ['b', 'd', 'a', 'c']);
    },
  );

  test('Recent sort shows newest additions first', () {
    final cards = [
      _card(id: 'old', createdAt: DateTime(2025, 1, 1)),
      _card(id: 'new', createdAt: DateTime(2026, 3, 1)),
      _card(id: 'mid', createdAt: DateTime(2025, 6, 1)),
    ];

    final sorted = sortFolderCards(
      cards,
      type: FolderSortType.recent,
      direction: SortDirection.ascending,
      category: ReleaseCategory.onePiece,
    );
    expect(sorted.map((c) => c.id), ['new', 'mid', 'old']);
  });

  test('Rarity sort follows the category rarity hierarchy, unknown last', () {
    final cards = [
      _card(id: 'common', rarity: 'C'),
      _card(id: 'secret', rarity: 'SEC'),
      _card(id: 'unknown', rarity: null),
      _card(id: 'none', rarity: 'None'),
      _card(id: 'rare', rarity: 'R'),
    ];

    final sorted = sortFolderCards(
      cards,
      type: FolderSortType.rarity,
      direction: SortDirection.ascending,
      category: ReleaseCategory.onePiece,
    );
    // SEC is rarer than R which is rarer than C in CardFieldOptions.rarity
    // for One Piece; null/'None' are placeholders, not real rarities.
    expect(sorted.map((c) => c.id).take(3), ['secret', 'rare', 'common']);
    expect(sorted.map((c) => c.id).skip(3), containsAll(['unknown', 'none']));
  });
}
