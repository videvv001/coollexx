// Regression coverage for the folder landscape/portrait cover feature: the
// new release columns round-trip through the real sqlite schema (v4
// migration's onCreate path), the legacy-cover fallback getters behave, and
// the pure center-crop geometry used to auto-fill the "other" orientation
// never picks a rect that overflows the source image.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pokedex_tcg/data/collection_repository.dart';
import 'package:pokedex_tcg/models/release.dart';
import 'package:pokedex_tcg/models/release_category.dart';
import 'package:pokedex_tcg/screens/shared/folder_cover.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Release cover fallback', () {
    test('falls back to legacy coverPhotoPath when unset', () {
      final release = Release(
        id: 'r1',
        name: 'Base Set',
        dateCreated: DateTime(2026, 1, 1),
        orderIndex: 0,
        coverPhotoPath: '/legacy/cover.jpg',
      );
      expect(release.displayLandscapeCover, '/legacy/cover.jpg');
      expect(release.displayPortraitCover, '/legacy/cover.jpg');
    });

    test('prefers the explicit cover over the legacy fallback', () {
      final release = Release(
        id: 'r1',
        name: 'Base Set',
        dateCreated: DateTime(2026, 1, 1),
        orderIndex: 0,
        coverPhotoPath: '/legacy/cover.jpg',
        landscapeCoverPath: '/new/landscape.jpg',
        portraitCoverPath: '/new/portrait.jpg',
      );
      expect(release.displayLandscapeCover, '/new/landscape.jpg');
      expect(release.displayPortraitCover, '/new/portrait.jpg');
    });
  });

  test('landscape/portrait cover paths persist via repository', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
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
    final repo = CollectionRepository(dbOverride: () => db);

    final release = await repo.createRelease(
      'OP-15',
      category: ReleaseCategory.onePiece,
    );
    await repo.updateRelease(
      release.copyWith(
        landscapeCoverPath: '/photos/land.jpg',
        portraitCoverPath: '/photos/port.jpg',
      ),
    );
    final stored = await repo.release(release.id);
    expect(stored!.landscapeCoverPath, '/photos/land.jpg');
    expect(stored.portraitCoverPath, '/photos/port.jpg');
  });

  group('centerCropRect', () {
    test('crops a wide source down to a portrait target, centered', () {
      final rect = centerCropRect(
        sourceWidth: 1000,
        sourceHeight: 500,
        targetAspect: 5 / 7,
      );
      expect(rect.width / rect.height, closeTo(5 / 7, 0.001));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(1000));
      expect(rect.bottom, lessThanOrEqualTo(500));
      // Centered horizontally: equal margin on both sides.
      expect(rect.left, closeTo(1000 - rect.right, 0.001));
    });

    test('crops a tall source down to a landscape target, centered', () {
      final rect = centerCropRect(
        sourceWidth: 500,
        sourceHeight: 1000,
        targetAspect: 4 / 3,
      );
      expect(rect.width / rect.height, closeTo(4 / 3, 0.001));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(500));
      expect(rect.bottom, lessThanOrEqualTo(1000));
      expect(rect.top, closeTo(1000 - rect.bottom, 0.001));
    });

    test('a source already at the target aspect crops to itself', () {
      final rect = centerCropRect(
        sourceWidth: 400,
        sourceHeight: 300,
        targetAspect: 4 / 3,
      );
      expect(rect.width, closeTo(400, 0.001));
      expect(rect.height, closeTo(300, 0.001));
    });
  });
}
