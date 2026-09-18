import 'package:flutter/foundation.dart';

import '../data/collection_repository.dart';
import '../data/value_repository.dart';
import '../models/release.dart';
import '../models/tcg_card.dart';

/// Cross-cutting app state: the release list, the unsorted-tray count, and
/// a change counter screens can key their FutureBuilders on so they refetch
/// after a write elsewhere. Per-screen data (a release's cards, a
/// sub-folder's cards, search results) is queried directly from the
/// repositories and paginated by the screen that needs it — collections run
/// to thousands of cards, so nothing here loads a full card list into
/// memory.
class AppState extends ChangeNotifier {
  AppState({CollectionRepository? collection, ValueRepository? value})
    : collection = collection ?? CollectionRepository(),
      value = value ?? ValueRepository();

  final CollectionRepository collection;
  final ValueRepository value;

  List<Release> releases = [];
  int unsortedCount = 0;
  int totalCards = 0;
  double totalValue = 0;
  bool _loaded = false;
  bool get loaded => _loaded;

  Future<void> load() async {
    await refresh();
    _loaded = true;
    notifyListeners();
  }

  Future<void> refresh() async {
    releases = await collection.allReleases();
    final unsorted = await collection.unsortedCards();
    unsortedCount = unsorted.length;
    final all = await collection.allCards();
    totalCards = all.fold<int>(0, (sum, c) => sum + c.copies);
    final latest = await value.latestPerCard();
    totalValue = 0;
    for (final card in all) {
      final entry = latest[card.id];
      if (entry != null) totalValue += entry.amount * card.copies;
    }
    notifyListeners();
  }

  Future<TcgCard> addCard(TcgCard card) async {
    final saved = await collection.createCard(card);
    await refresh();
    return saved;
  }

  Future<void> updateCard(TcgCard card) async {
    await collection.updateCard(card);
    await refresh();
  }

  Future<void> deleteCard(String id) async {
    await collection.deleteCard(id);
    await refresh();
  }

  Future<void> deleteCards(List<String> ids) async {
    await collection.deleteCards(ids);
    await refresh();
  }

  Future<void> moveCards(
    List<String> ids, {
    String? releaseId,
    bool clearRelease = false,
    String? subFolderId,
    bool clearSubFolder = true,
  }) async {
    await collection.moveCards(
      ids,
      releaseId: releaseId,
      clearRelease: clearRelease,
      subFolderId: subFolderId,
      clearSubFolder: clearSubFolder,
    );
    await refresh();
  }

  Future<Release> createRelease(String name) async {
    final release = await collection.createRelease(name);
    await refresh();
    return release;
  }

  Future<void> createSubFolder(String releaseId, String name) async {
    await collection.createSubFolder(releaseId, name);
    notifyListeners();
  }
}
