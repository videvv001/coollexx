import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/capture_item.dart';
import '../models/capture_session.dart';
import '../models/tcg_card.dart';
import 'app_database.dart';
import 'collection_repository.dart';
import 'photo_store.dart';

/// Burst captures are written to `PhotoStore` (permanent app storage) the
/// moment each photo is taken; this repository is what makes that
/// persistence *findable* afterward — a session's items are the durable
/// record that a pending burst exists, independent of whatever Flutter
/// widget State happens to be alive. See `CaptureScreen` for where
/// sessions are created and items added, and `commit` below for how a
/// session turns into real collection entries exactly once, even if
/// retried after a crash partway through.
class CaptureSessionRepository {
  CaptureSessionRepository({Database Function()? dbOverride})
    : _dbOverride = dbOverride;

  final Database Function()? _dbOverride;
  static const _uuid = Uuid();

  Future<Database> get _db async =>
      _dbOverride != null ? _dbOverride() : AppDatabase.instance.database;

  Future<CaptureSession> createSession({String? targetReleaseId}) async {
    final db = await _db;
    final now = DateTime.now();
    final session = CaptureSession(
      id: _uuid.v4(),
      status: CaptureSessionStatus.active,
      targetReleaseId: targetReleaseId,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('capture_sessions', session.toMap());
    return session;
  }

  Future<CaptureSession?> session(String id) async {
    final db = await _db;
    final rows = await db.query(
      'capture_sessions',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return CaptureSession.fromMap(rows.first);
  }

  /// The most recently touched session, if any — there is only ever one
  /// live burst session at a time (a single camera screen), so this is
  /// what both app-start recovery and "resume without an explicit id"
  /// check. A row existing at all means it's pending: see the class doc
  /// for why committed/discarded sessions are deleted rather than flagged.
  Future<CaptureSession?> activeSession() async {
    final db = await _db;
    final rows = await db.query(
      'capture_sessions',
      orderBy: 'updatedAt DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CaptureSession.fromMap(rows.first);
  }

  Future<List<CaptureItem>> items(String sessionId) async {
    final db = await _db;
    final rows = await db.query(
      'capture_items',
      where: 'sessionId = ?',
      whereArgs: [sessionId],
      orderBy: 'sequence ASC',
    );
    return rows.map(CaptureItem.fromMap).toList();
  }

  Future<int> itemCount(String sessionId) async {
    final db = await _db;
    return Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM capture_items WHERE sessionId = ?',
            [sessionId],
          ),
        ) ??
        0;
  }

  /// Persists one captured photo into the session. Callers must not treat
  /// a shot as "safely captured" — incrementing any on-screen count — until
  /// this returns successfully; the file itself should already be written
  /// to `PhotoStore` before this is called, so a failure here only means
  /// the bookkeeping row didn't get created (in which case the caller
  /// should delete that now-unreferenced file, since nothing could ever
  /// find it again).
  Future<CaptureItem> addItem(String sessionId, String path) async {
    final db = await _db;
    // One past the highest sequence so far, rather than the item count —
    // identical for a burst, which only ever appends, but a binder scan can
    // drop a wrongly detected card mid-session (see [removeItem]), and a
    // count would then hand the next item a sequence a surviving item
    // already holds, scrambling the order `items` reads them back in.
    final next =
        (Sqflite.firstIntValue(
              await db.rawQuery(
                'SELECT MAX(sequence) FROM capture_items WHERE sessionId = ?',
                [sessionId],
              ),
            ) ??
            -1) +
        1;
    final item = CaptureItem(
      id: _uuid.v4(),
      sessionId: sessionId,
      path: path,
      sequence: next,
      capturedAt: DateTime.now(),
    );
    await db.insert('capture_items', item.toMap());
    await db.update(
      'capture_sessions',
      {'updatedAt': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    return item;
  }

  /// Re-points an item at an edited replacement file (from the in-camera
  /// review strip's crop/edit action) and removes the now-orphaned
  /// original — nothing else ever references a pending item's file.
  Future<void> updateItemPath(CaptureItem item, String newPath) async {
    final db = await _db;
    await db.update(
      'capture_items',
      {'path': newPath},
      where: 'id = ?',
      whereArgs: [item.id],
    );
    await PhotoStore.instance.delete(item.path);
  }

  /// Drops one still-pending item and its file. This is the binder scan
  /// review's "that isn't a card" and "remove this page" action, and it is
  /// only ever valid before commit — afterwards the file is a real card's
  /// photo and deleting it would blank that card.
  Future<void> removeItem(CaptureItem item) async {
    final db = await _db;
    await db.delete('capture_items', where: 'id = ?', whereArgs: [item.id]);
    await PhotoStore.instance.delete(item.path);
  }

  Future<void> _deleteSessionRows(String sessionId) async {
    final db = await _db;
    await db.delete(
      'capture_sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// Discards a session: deletes every pending item's file — nothing else
  /// references them, that's the whole point of "pending" — then the
  /// session's own rows.
  Future<void> discard(String sessionId) async {
    final pending = await items(sessionId);
    for (final item in pending) {
      await PhotoStore.instance.delete(item.path);
    }
    await _deleteSessionRows(sessionId);
  }

  /// Turns every not-yet-committed item into a real collection entry, then
  /// removes the session's bookkeeping. Idempotent and resumable: each
  /// item is marked committed immediately after its card is created (not
  /// batched at the end), so if this is interrupted — crash, killed
  /// process — calling it again on the same session only processes items
  /// that don't already have a `committedCardId`, and never creates a
  /// second card for one that does. The photo files are never copied or
  /// moved; a card's `photoPaths` simply points at the same file
  /// `PhotoStore` already saved at capture time, so "cleanup" here means
  /// deleting the now-redundant session/item rows, not the files — they're
  /// doing permanent duty as the card's own photos now.
  ///
  /// Returns the committed cards (including ones committed on an earlier,
  /// interrupted attempt), in capture order. Returns an empty list if the
  /// session no longer exists — i.e. it was already fully committed and
  /// cleaned up by a previous call.
  Future<List<TcgCard>> commit(
    CollectionRepository collection,
    String sessionId,
  ) async {
    final current = await session(sessionId);
    if (current == null) return const [];
    if (current.status != CaptureSessionStatus.committing) {
      await _setStatus(sessionId, CaptureSessionStatus.committing);
    }
    final pending = await items(sessionId);
    final cards = <TcgCard>[];
    for (final item in pending) {
      if (item.committedCardId != null) {
        final existing = await collection.card(item.committedCardId!);
        if (existing != null) cards.add(existing);
        continue;
      }
      final card = await collection.createCard(
        TcgCard(
          id: _uuid.v4(),
          photoPaths: [item.path],
          releaseId: current.targetReleaseId,
          createdAt: item.capturedAt,
        ),
      );
      await _markItemCommitted(item.id, card.id);
      cards.add(card);
    }
    await _deleteSessionRows(sessionId);
    return cards;
  }

  Future<void> _setStatus(String sessionId, CaptureSessionStatus status) async {
    final db = await _db;
    await db.update(
      'capture_sessions',
      {'status': status.label, 'updatedAt': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<void> _markItemCommitted(String itemId, String cardId) async {
    final db = await _db;
    await db.update(
      'capture_items',
      {'committedCardId': cardId},
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }
}
