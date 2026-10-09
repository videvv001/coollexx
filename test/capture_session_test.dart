// Regression coverage for burst-capture reliability: a session's items must
// be independently persisted (not just held in a widget's State), commit
// must be safe to retry without duplicating collection entries, and discard
// must remove a pending session's files without ever touching a file a real
// card already owns. See CaptureSessionRepository and CaptureScreen.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pokedex_tcg/data/capture_session_repository.dart';
import 'package:pokedex_tcg/data/collection_repository.dart';
import 'package:pokedex_tcg/models/capture_session.dart';
import 'package:pokedex_tcg/models/tcg_card.dart';

Future<Directory> _tempPhotos() =>
    Directory.systemTemp.createTemp('capture_session_test_');

Future<File> _fakePhoto(Directory dir, String name) async {
  final file = File(p.join(dir.path, name));
  await file.writeAsBytes([0]);
  return file;
}

class _Repos {
  const _Repos(this.captures, this.collection, this.db);
  final CaptureSessionRepository captures;
  final CollectionRepository collection;
  final Database db;
}

Future<_Repos> _openDb() async {
  // Each test opens its own isolated in-memory database — `singleInstance:
  // false` is needed because sqflite otherwise caches connections by path,
  // and every call here uses the same `inMemoryDatabasePath`.
  final db = await databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  await db.execute('PRAGMA foreign_keys = ON');
  await db.execute('''
    CREATE TABLE releases (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, dateCreated TEXT NOT NULL,
      coverPhotoPath TEXT, coverPortrait INTEGER NOT NULL DEFAULT 0,
      orderIndex INTEGER NOT NULL, officialSetCode TEXT, totalCardsInSet INTEGER,
      category TEXT NOT NULL DEFAULT 'Others', language TEXT,
      landscapeCoverPath TEXT, portraitCoverPath TEXT,
      isFavorite INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE cards (
      id TEXT PRIMARY KEY, name TEXT, number TEXT, rarity TEXT, variantFamily TEXT, variantName TEXT,
      artworkVariant TEXT, language TEXT,
      kind TEXT, color TEXT, type TEXT, condition TEXT,
      copies INTEGER NOT NULL DEFAULT 1, releaseId TEXT,
      photoPaths TEXT NOT NULL DEFAULT '', pricePaid REAL, datePaid TEXT,
      forTrade INTEGER NOT NULL DEFAULT 0, onWishlist INTEGER NOT NULL DEFAULT 0,
      isFavorite INTEGER NOT NULL DEFAULT 0, notes TEXT, createdAt TEXT NOT NULL,
      FOREIGN KEY (releaseId) REFERENCES releases (id) ON DELETE SET NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE capture_sessions (
      id TEXT PRIMARY KEY, status TEXT NOT NULL, targetReleaseId TEXT,
      createdAt TEXT NOT NULL, updatedAt TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE capture_items (
      id TEXT PRIMARY KEY, sessionId TEXT NOT NULL, path TEXT NOT NULL,
      sequence INTEGER NOT NULL, capturedAt TEXT NOT NULL, committedCardId TEXT,
      FOREIGN KEY (sessionId) REFERENCES capture_sessions (id) ON DELETE CASCADE
    )
  ''');
  return _Repos(
    CaptureSessionRepository(dbOverride: () => db),
    CollectionRepository(dbOverride: () => db),
    db,
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('items persist independently of any in-memory list', () async {
    final repos = await _openDb();
    final release = await repos.collection.createRelease('OP-14');
    final session = await repos.captures.createSession(
      targetReleaseId: release.id,
    );
    await repos.captures.addItem(session.id, '/tmp/a.jpg');
    await repos.captures.addItem(session.id, '/tmp/b.jpg');

    final items = await repos.captures.items(session.id);
    expect(items.map((i) => i.path), ['/tmp/a.jpg', '/tmp/b.jpg']);
    expect(await repos.captures.itemCount(session.id), 2);
    expect((await repos.captures.activeSession())?.id, session.id);
  });

  test('commit creates one card per item and clears the session', () async {
    final repos = await _openDb();
    final release = await repos.collection.createRelease('OP-14');
    final session = await repos.captures.createSession(
      targetReleaseId: release.id,
    );
    await repos.captures.addItem(session.id, '/tmp/a.jpg');
    await repos.captures.addItem(session.id, '/tmp/b.jpg');
    await repos.captures.addItem(session.id, '/tmp/c.jpg');

    final cards = await repos.captures.commit(repos.collection, session.id);

    expect(cards.map((c) => c.photoPaths.single), [
      '/tmp/a.jpg',
      '/tmp/b.jpg',
      '/tmp/c.jpg',
    ]);
    for (final card in cards) {
      expect(card.releaseId, release.id);
    }
    expect(await repos.captures.session(session.id), isNull);
    expect(await repos.captures.activeSession(), isNull);
  });

  test('committing an already-committed session is a safe no-op', () async {
    final repos = await _openDb();
    final session = await repos.captures.createSession();
    await repos.captures.addItem(session.id, '/tmp/a.jpg');
    await repos.captures.commit(repos.collection, session.id);

    // The session row (and its items) are gone now — a second commit call
    // against the same id, as an app-start recovery retry might do, must
    // not throw and must not create anything.
    final second = await repos.captures.commit(repos.collection, session.id);
    expect(second, isEmpty);
    expect(await repos.collection.allCards(), hasLength(1));
  });

  test(
    'retrying commit after a partial success never duplicates a card',
    () async {
      final repos = await _openDb();
      final session = await repos.captures.createSession();
      final first = await repos.captures.addItem(session.id, '/tmp/a.jpg');
      await repos.captures.addItem(session.id, '/tmp/b.jpg');

      final firstCommit = await repos.captures.commit(
        repos.collection,
        session.id,
      );
      expect(firstCommit, hasLength(2));
      expect(await repos.collection.allCards(), hasLength(2));

      // Recreate the exact "interrupted mid-commit" state by hand: the
      // session and one item row still exist — as they would if the
      // process died right after the commit loop but before the final
      // row cleanup — with that item already marked against a real card.
      await repos.db.insert('capture_sessions', {
        'id': session.id,
        'status': CaptureSessionStatus.committing.label,
        'targetReleaseId': null,
        'createdAt': session.createdAt.toIso8601String(),
        'updatedAt': session.updatedAt.toIso8601String(),
      });
      await repos.db.insert('capture_items', {
        'id': first.id,
        'sessionId': session.id,
        'path': first.path,
        'sequence': 0,
        'capturedAt': first.capturedAt.toIso8601String(),
        'committedCardId': firstCommit.first.id,
      });

      final retried = await repos.captures.commit(repos.collection, session.id);

      // The already-committed item's existing card is returned, not
      // recreated — total card count is unchanged from the first commit.
      expect(retried.map((c) => c.id), contains(firstCommit.first.id));
      expect(await repos.collection.allCards(), hasLength(2));
    },
  );

  test(
    "discard deletes pending files but never a committed card's file",
    () async {
      final repos = await _openDb();
      final dir = await _tempPhotos();
      addTearDown(() => dir.delete(recursive: true));

      final keptPhoto = await _fakePhoto(dir, 'keep.jpg');
      final discardedPhoto = await _fakePhoto(dir, 'discard.jpg');

      // One photo already belongs to a real, committed card...
      await repos.collection.createCard(
        TcgCard(
          id: 'kept-card',
          photoPaths: [keptPhoto.path],
          createdAt: DateTime(2026, 1, 1),
        ),
      );
      // ...and a separate, still-pending session holds the other.
      final session = await repos.captures.createSession();
      await repos.captures.addItem(session.id, discardedPhoto.path);

      await repos.captures.discard(session.id);

      expect(await discardedPhoto.exists(), isFalse);
      expect(await keptPhoto.exists(), isTrue);
      expect(await repos.captures.session(session.id), isNull);
    },
  );
}
