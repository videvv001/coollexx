// Regression coverage for folder deletion: deleting a release must cascade
// to every card filed under it (its "collection entries") in the same
// transaction, so no orphaned cards (releaseId pointing at a release that no
// longer exists) are left behind — see CollectionRepository.deleteRelease.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pokedex_tcg/data/collection_repository.dart';
import 'package:pokedex_tcg/models/tcg_card.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('deleting a release deletes its cards, leaving no orphans', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    // Mirrors AppDatabase's onCreate schema.
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
        id TEXT PRIMARY KEY, name TEXT, number TEXT, rarity TEXT, language TEXT,
        kind TEXT, color TEXT, type TEXT, condition TEXT,
        copies INTEGER NOT NULL DEFAULT 1, releaseId TEXT,
        photoPaths TEXT NOT NULL DEFAULT '', pricePaid REAL, datePaid TEXT,
        forTrade INTEGER NOT NULL DEFAULT 0, onWishlist INTEGER NOT NULL DEFAULT 0,
        isFavorite INTEGER NOT NULL DEFAULT 0, notes TEXT, createdAt TEXT NOT NULL,
        FOREIGN KEY (releaseId) REFERENCES releases (id) ON DELETE SET NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE value_entries (
        id TEXT PRIMARY KEY, cardId TEXT NOT NULL, date TEXT NOT NULL, amount REAL NOT NULL,
        FOREIGN KEY (cardId) REFERENCES cards (id) ON DELETE CASCADE
      )
    ''');

    final repo = CollectionRepository(dbOverride: () => db);
    final release = await repo.createRelease('OP-14');
    final keptCard = await repo.createCard(
      TcgCard(id: 'kept', createdAt: DateTime(2026, 1, 1)),
    );
    final inReleaseCard = await repo.createCard(
      TcgCard(
        id: 'in-release',
        releaseId: release.id,
        createdAt: DateTime(2026, 1, 1),
      ),
    );
    await db.insert('value_entries', {
      'id': 've1',
      'cardId': inReleaseCard.id,
      'date': '2026-01-01',
      'amount': 5.0,
    });

    await repo.deleteRelease(release.id);

    expect(await repo.release(release.id), isNull);
    expect(await repo.card(inReleaseCard.id), isNull);
    expect(await repo.card(keptCard.id), isNotNull);
    final orphaned = await db.query(
      'value_entries',
      where: 'cardId = ?',
      whereArgs: [inReleaseCard.id],
    );
    expect(orphaned, isEmpty);
    // No card should be left pointing at a now-nonexistent release.
    final all = await repo.allCards();
    for (final card in all) {
      if (card.releaseId != null) {
        expect(card.releaseId, isNot(release.id));
      }
    }
  });
}
