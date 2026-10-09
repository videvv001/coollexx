// Regression coverage for the new folder-favorite persistence and the
// collection Move/Copy repository operations: Move must reassign the
// existing entry (same id) to the new folder, Copy must produce a distinct
// entry with its own id while leaving the original untouched, and Favorite
// must round-trip through the real sqlite schema.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pokedex_tcg/data/collection_repository.dart';
import 'package:pokedex_tcg/models/tcg_card.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<CollectionRepository> openRepo() async {
    // singleInstance: false — otherwise sqflite hands back the same cached
    // ":memory:" connection (and its already-created tables) to every test
    // in this file instead of a fresh database each time.
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
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
    return CollectionRepository(dbOverride: () => db);
  }

  test(
    'a new release defaults to not favorite, and favorite persists via updateRelease',
    () async {
      final repo = await openRepo();
      final release = await repo.createRelease('OP-14');
      expect(release.isFavorite, isFalse);

      await repo.updateRelease(release.copyWith(isFavorite: true));
      final reloaded = await repo.release(release.id);
      expect(reloaded!.isFavorite, isTrue);

      // Unrelated edits (rename) must not reset favorite state.
      await repo.updateRelease(reloaded.copyWith(name: 'OP-14 Renamed'));
      final afterRename = await repo.release(release.id);
      expect(afterRename!.isFavorite, isTrue);
      expect(afterRename.name, 'OP-14 Renamed');
    },
  );

  test(
    'moveCards reassigns the existing entry to the destination folder',
    () async {
      final repo = await openRepo();
      final source = await repo.createRelease('OP-14');
      final destination = await repo.createRelease('OP-15');
      final card = await repo.createCard(
        TcgCard(
          id: 'c1',
          name: 'Luffy',
          releaseId: source.id,
          notes: 'foil',
          createdAt: DateTime(2026, 1, 1),
        ),
      );

      await repo.moveCards([card.id], releaseId: destination.id);

      final moved = await repo.card(card.id);
      expect(moved!.releaseId, destination.id);
      expect(moved.notes, 'foil'); // user metadata preserved
      expect(await repo.cardsInRelease(source.id), isEmpty);
      expect(await repo.cardsInRelease(destination.id), hasLength(1));
    },
  );

  test(
    'copyCards creates an independent entry with its own id, leaving the original in place',
    () async {
      final repo = await openRepo();
      final source = await repo.createRelease('OP-14');
      final destination = await repo.createRelease('OP-15');
      final card = await repo.createCard(
        TcgCard(
          id: 'c1',
          name: 'Luffy',
          releaseId: source.id,
          copies: 2,
          notes: 'foil',
          createdAt: DateTime(2026, 1, 1),
        ),
      );

      final copies = await repo.copyCards([card.id], releaseId: destination.id);

      expect(copies, hasLength(1));
      final copy = copies.first;
      expect(copy.id, isNot(card.id));
      expect(copy.releaseId, destination.id);
      expect(copy.name, 'Luffy');
      expect(copy.copies, 2);
      expect(copy.notes, 'foil');

      // Original untouched.
      final original = await repo.card(card.id);
      expect(original!.releaseId, source.id);
      expect(await repo.cardsInRelease(source.id), hasLength(1));
      expect(await repo.cardsInRelease(destination.id), hasLength(1));

      // Deleting the copy must not affect the original.
      await repo.deleteCard(copy.id);
      expect(await repo.card(card.id), isNotNull);
    },
  );
}
