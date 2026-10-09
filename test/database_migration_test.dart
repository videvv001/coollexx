// The real AppDatabase upgrading a v6 file (before printings and price history
// existed) to the current schema: cards keep their data and read back as an
// UNKNOWN printing (never base), and the price-history and known-printings
// tables appear.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pokedex_tcg/data/app_database.dart';
import 'package:pokedex_tcg/models/printing_variant.dart';
import 'package:pokedex_tcg/models/tcg_card.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);
  final Directory dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir.path;
}

void main() {
  test('v6 database upgrades: old cards unknown, new tables present', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = Directory.systemTemp.createTempSync('pokedex_tcg_migration');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {
        // Windows may still hold the file; the temp dir is disposable.
      }
    });
    PathProviderPlatform.instance = _FakePathProvider(dir);

    // A v6 file: cards without the printing columns.
    final old = await databaseFactory.openDatabase(
      p.join(dir.path, 'pokedex_tcg.db'),
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE releases (
              id TEXT PRIMARY KEY, name TEXT NOT NULL, dateCreated TEXT NOT NULL,
              coverPhotoPath TEXT, coverPortrait INTEGER NOT NULL DEFAULT 0,
              orderIndex INTEGER NOT NULL, officialSetCode TEXT,
              totalCardsInSet INTEGER, category TEXT NOT NULL DEFAULT 'Others',
              language TEXT, landscapeCoverPath TEXT, portraitCoverPath TEXT,
              isFavorite INTEGER NOT NULL DEFAULT 0
            )''');
          await db.execute('''
            CREATE TABLE cards (
              id TEXT PRIMARY KEY, name TEXT, number TEXT, rarity TEXT,
              language TEXT, kind TEXT, color TEXT, type TEXT, condition TEXT,
              copies INTEGER NOT NULL DEFAULT 1, releaseId TEXT,
              photoPaths TEXT NOT NULL DEFAULT '', pricePaid REAL, datePaid TEXT,
              forTrade INTEGER NOT NULL DEFAULT 0,
              onWishlist INTEGER NOT NULL DEFAULT 0,
              isFavorite INTEGER NOT NULL DEFAULT 0, notes TEXT,
              createdAt TEXT NOT NULL
            )''');
          await db.insert('cards', {
            'id': 'old',
            'name': 'モンキー・D・ルフィ',
            'number': 'EB04-061',
            'rarity': 'SEC',
            'language': 'JP',
            'createdAt': '2026-01-01T00:00:00.000',
          });
        },
      ),
    );
    await old.close();

    final db = await AppDatabase.instance.database;
    expect(await db.getVersion(), 9);

    final card = TcgCard.fromMap(
      (await db.query('cards', where: 'id = ?', whereArgs: ['old'])).single,
    );
    expect(card.number, 'EB04-061');
    expect(card.variant, PrintingVariant.unknown);

    // Both new tables are usable.
    await db.insert('cards', {
      'id': 'new',
      'variantFamily': 'BASE',
      'createdAt': '2026-10-05T00:00:00.000',
    });
    expect(
      TcgCard.fromMap(
        (await db.query('cards', where: 'id = ?', whereArgs: ['new'])).single,
      ).variant.family,
      VariantFamily.base,
    );
    expect(await db.query('price_observations'), isEmpty);
    expect(await db.query('printing_candidates'), isEmpty);
    await db.close();
  });
}
