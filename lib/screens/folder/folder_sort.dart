import '../../models/card_field_options.dart';
import '../../models/release_category.dart';
import '../../models/tcg_card.dart';

enum FolderSortType { favorite, recent, rarity, id }

enum SortDirection { ascending, descending }

extension FolderSortTypeLabel on FolderSortType {
  String get label => switch (this) {
    FolderSortType.favorite => 'Favorite',
    FolderSortType.recent => 'Recent',
    FolderSortType.rarity => 'Rarity',
    FolderSortType.id => 'ID',
  };
}

/// Natural (numeric-aware) comparison of card IDs, so 'OP14-2' sorts before
/// 'OP14-10' instead of after it as plain string comparison would.
int compareCardIds(String a, String b) {
  final runsA = RegExp(
    r'\d+|\D+',
  ).allMatches(a).map((m) => m.group(0)!).toList();
  final runsB = RegExp(
    r'\d+|\D+',
  ).allMatches(b).map((m) => m.group(0)!).toList();
  for (var i = 0; i < runsA.length && i < runsB.length; i++) {
    final numA = int.tryParse(runsA[i]);
    final numB = int.tryParse(runsB[i]);
    final cmp = (numA != null && numB != null)
        ? numA.compareTo(numB)
        : runsA[i].compareTo(runsB[i]);
    if (cmp != 0) return cmp;
  }
  return runsA.length.compareTo(runsB.length);
}

/// Ascending ID compare with cards missing an ID placed last, regardless of
/// the folder's chosen sort direction (an unset ID has no natural rank).
int _compareById(TcgCard a, TcgCard b) {
  if (a.number == null && b.number == null) return 0;
  if (a.number == null) return 1;
  if (b.number == null) return -1;
  return compareCardIds(a.number!, b.number!);
}

/// A card's position in its release category's rarity hierarchy
/// ([CardFieldOptions.rarity], ordered rarest-first). Unset or unrecognized
/// rarity (including the placeholder 'None') sorts after every real rarity.
int _rarityRank(TcgCard card, ReleaseCategory category) {
  final options =
      CardFieldOptions.rarity[category] ??
      CardFieldOptions.rarity[ReleaseCategory.others]!;
  final rarity = card.rarity;
  if (rarity == null || rarity == 'None') return options.length;
  final index = options.indexOf(rarity);
  return index == -1 ? options.length : index;
}

/// Sorts a folder's cards per the given [type]/[direction], never mutating
/// [cards]. Ties always fall back to ID ascending so order stays
/// deterministic across rebuilds instead of depending on database row order.
List<TcgCard> sortFolderCards(
  List<TcgCard> cards, {
  required FolderSortType type,
  required SortDirection direction,
  required ReleaseCategory category,
}) {
  final sorted = [...cards];
  switch (type) {
    case FolderSortType.favorite:
      sorted.sort((a, b) {
        if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
        return _compareById(a, b);
      });
    case FolderSortType.recent:
      sorted.sort((a, b) {
        final cmp = b.createdAt.compareTo(a.createdAt);
        return cmp != 0 ? cmp : _compareById(a, b);
      });
    case FolderSortType.rarity:
      sorted.sort((a, b) {
        final cmp = _rarityRank(
          a,
          category,
        ).compareTo(_rarityRank(b, category));
        return cmp != 0 ? cmp : _compareById(a, b);
      });
    case FolderSortType.id:
      sorted.sort((a, b) {
        // Nulls always sort last, in both directions — only negate the
        // real numeric comparison, not the null placement above it.
        if (a.number == null && b.number == null) return 0;
        if (a.number == null) return 1;
        if (b.number == null) return -1;
        final cmp = compareCardIds(a.number!, b.number!);
        return direction == SortDirection.ascending ? cmp : -cmp;
      });
  }
  return sorted;
}
