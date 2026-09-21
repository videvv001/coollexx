import 'package:flutter/foundation.dart';

import '../data/capture_session_repository.dart';
import '../data/collection_repository.dart';
import '../data/value_repository.dart';
import '../models/release.dart';
import '../models/release_category.dart';
import '../models/tcg_card.dart';

/// The live burst session's id and how many photos it currently holds —
/// kept on `AppState` (not just the camera screen's own State) so anything
/// that can navigate away from the camera — the bottom nav bar, in
/// particular — can tell there's unsaved work without reaching into that
/// screen directly. The photos themselves are already durably persisted
/// via `CaptureSessionRepository` the moment they're shot; this is purely a
/// cheap, in-memory mirror of "is there currently something pending" for
/// gating navigation, not the source of truth (that's the database).
class PendingCapture {
  const PendingCapture({required this.sessionId, required this.count});
  final String sessionId;
  final int count;
}

/// Cross-cutting app state: the release list, the unsorted-tray count, and
/// a change counter screens can key their FutureBuilders on so they refetch
/// after a write elsewhere. Per-screen data (a release's cards, search
/// results) is queried directly from the repositories and paginated by the
/// screen that needs it — collections run to thousands of cards, so nothing
/// here loads a full card list into memory.
class AppState extends ChangeNotifier {
  AppState({
    CollectionRepository? collection,
    ValueRepository? value,
    CaptureSessionRepository? captureSessions,
  }) : collection = collection ?? CollectionRepository(),
       value = value ?? ValueRepository(),
       captureSessions = captureSessions ?? CaptureSessionRepository();

  final CollectionRepository collection;
  final ValueRepository value;
  final CaptureSessionRepository captureSessions;

  List<Release> releases = [];
  int unsortedCount = 0;
  int totalCards = 0;
  double totalValue = 0;
  bool _loaded = false;
  bool get loaded => _loaded;

  PendingCapture? pendingCapture;

  void setPendingCapture(PendingCapture? pending) {
    pendingCapture = pending;
    notifyListeners();
  }

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
  }) async {
    await collection.moveCards(
      ids,
      releaseId: releaseId,
      clearRelease: clearRelease,
    );
    await refresh();
  }

  Future<void> copyCards(List<String> ids, {required String releaseId}) async {
    await collection.copyCards(ids, releaseId: releaseId);
    await refresh();
  }

  Future<void> deleteRelease(String id) async {
    await collection.deleteRelease(id);
    await refresh();
  }

  Future<Release> createRelease(
    String name, {
    ReleaseCategory category = ReleaseCategory.others,
  }) async {
    final release = await collection.createRelease(name, category: category);
    await refresh();
    return release;
  }
}
