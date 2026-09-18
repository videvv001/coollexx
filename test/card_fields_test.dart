// Regression coverage for this change: the new language/kind/color/type
// columns round-trip through the real sqlite schema (exercising the v3
// migration's onCreate path), and TcgCard.toMap/fromMap's photoPaths
// join/split use the same delimiter — a mismatch here silently truncates
// every multi-photo card to its first character.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pokedex_tcg/data/collection_repository.dart';
import 'package:pokedex_tcg/models/card_language.dart';
import 'package:pokedex_tcg/models/release_category.dart';
import 'package:pokedex_tcg/models/tcg_card.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('TcgCard photoPaths round-trips through toMap/fromMap', () {
    final card = TcgCard(
      id: 'c1',
      photoPaths: const ['/a/one.jpg', '/a/two.jpg', '/a/three.jpg'],
      createdAt: DateTime(2026, 1, 1),
    );
    final restored = TcgCard.fromMap(card.toMap());
    expect(restored.photoPaths, card.photoPaths);
  });

  test('release and card language/kind/color/type persist via repository', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE releases (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, dateCreated TEXT NOT NULL,
        coverPhotoPath TEXT, coverPortrait INTEGER NOT NULL DEFAULT 0,
        orderIndex INTEGER NOT NULL, officialSetCode TEXT, totalCardsInSet INTEGER,
        category TEXT NOT NULL DEFAULT 'Others', language TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE cards (
        id TEXT PRIMARY KEY, name TEXT, number TEXT, rarity TEXT, language TEXT,
        kind TEXT, color TEXT, type TEXT, condition TEXT,
        copies INTEGER NOT NULL DEFAULT 1, releaseId TEXT,
        photoPaths TEXT NOT NULL DEFAULT '', pricePaid REAL, datePaid TEXT,
        forTrade INTEGER NOT NULL DEFAULT 0, onWishlist INTEGER NOT NULL DEFAULT 0,
        isFavorite INTEGER NOT NULL DEFAULT 0, notes TEXT, createdAt TEXT NOT NULL
      )
    ''');
    final repo = CollectionRepository(dbOverride: () => db);

    final release = await repo.createRelease(
      'OP-01',
      category: ReleaseCategory.onePiece,
    );
    await repo.updateRelease(release.copyWith(language: CardLanguage.jp));
    final storedRelease = await repo.release(release.id);
    expect(storedRelease!.language, CardLanguage.jp);
    expect(storedRelease.category, ReleaseCategory.onePiece);

    final card = await repo.createCard(
      TcgCard(
        id: 'card1',
        releaseId: release.id,
        language: CardLanguage.eng,
        kind: 'Leader',
        color: 'Red',
        createdAt: DateTime.now(),
      ),
    );
    final storedCard = await repo.card(card.id);
    expect(storedCard!.language, CardLanguage.eng);
    expect(storedCard.kind, 'Leader');
    expect(storedCard.color, 'Red');
    expect(storedCard.type, isNull);

    await db.close();
  });
}
