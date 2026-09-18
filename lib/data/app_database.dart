import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Opens and migrates the local SQLite database. Everything the app stores
/// — releases, sub-folders, cards, value entries — lives on the device;
/// there is no server and nothing is synced.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  // Memoizes the Future itself, not just its resolved value — several
  // screens query the database concurrently on first launch (Home, Sets,
  // Trade all build on the same first frame), and without this every one
  // of them would race to independently call _open() on the same file
  // before any of them finished, causing serious lock contention.
  Future<Database>? _dbFuture;

  Future<Database> get database => _dbFuture ??= _open();

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'pokedex_tcg.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE releases (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            dateCreated TEXT NOT NULL,
            coverPhotoPath TEXT,
            orderIndex INTEGER NOT NULL,
            officialSetCode TEXT,
            totalCardsInSet INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE sub_folders (
            id TEXT PRIMARY KEY,
            releaseId TEXT NOT NULL,
            name TEXT NOT NULL,
            orderIndex INTEGER NOT NULL,
            FOREIGN KEY (releaseId) REFERENCES releases (id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE cards (
            id TEXT PRIMARY KEY,
            name TEXT,
            number TEXT,
            rarity TEXT,
            condition TEXT,
            copies INTEGER NOT NULL DEFAULT 1,
            releaseId TEXT,
            subFolderId TEXT,
            photoPaths TEXT NOT NULL DEFAULT '',
            pricePaid REAL,
            datePaid TEXT,
            forTrade INTEGER NOT NULL DEFAULT 0,
            onWishlist INTEGER NOT NULL DEFAULT 0,
            notes TEXT,
            createdAt TEXT NOT NULL,
            FOREIGN KEY (releaseId) REFERENCES releases (id) ON DELETE SET NULL,
            FOREIGN KEY (subFolderId) REFERENCES sub_folders (id) ON DELETE SET NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE value_entries (
            id TEXT PRIMARY KEY,
            cardId TEXT NOT NULL,
            date TEXT NOT NULL,
            amount REAL NOT NULL,
            FOREIGN KEY (cardId) REFERENCES cards (id) ON DELETE CASCADE
          )
        ''');
        await db.execute(
          'CREATE UNIQUE INDEX value_entries_card_date ON value_entries (cardId, date)',
        );
        await db.execute('CREATE INDEX cards_release ON cards (releaseId)');
        await db.execute(
          'CREATE INDEX cards_sub_folder ON cards (subFolderId)',
        );
      },
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }
}
