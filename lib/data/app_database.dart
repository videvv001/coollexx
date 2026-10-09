import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Opens and migrates the local SQLite database. Everything the app stores
/// — releases, cards, value entries — lives on the device; there is no
/// server and nothing is synced.
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
      version: 9,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE releases (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            dateCreated TEXT NOT NULL,
            coverPhotoPath TEXT,
            coverPortrait INTEGER NOT NULL DEFAULT 0,
            orderIndex INTEGER NOT NULL,
            officialSetCode TEXT,
            totalCardsInSet INTEGER,
            category TEXT NOT NULL DEFAULT 'Others',
            language TEXT,
            landscapeCoverPath TEXT,
            portraitCoverPath TEXT,
            isFavorite INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE cards (
            id TEXT PRIMARY KEY,
            name TEXT,
            number TEXT,
            rarity TEXT,
            variantFamily TEXT,
            variantName TEXT,
            artworkVariant TEXT,
            language TEXT,
            kind TEXT,
            color TEXT,
            type TEXT,
            condition TEXT,
            copies INTEGER NOT NULL DEFAULT 1,
            releaseId TEXT,
            photoPaths TEXT NOT NULL DEFAULT '',
            pricePaid REAL,
            datePaid TEXT,
            forTrade INTEGER NOT NULL DEFAULT 0,
            onWishlist INTEGER NOT NULL DEFAULT 0,
            isFavorite INTEGER NOT NULL DEFAULT 0,
            notes TEXT,
            createdAt TEXT NOT NULL,
            FOREIGN KEY (releaseId) REFERENCES releases (id) ON DELETE SET NULL
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
        await db.execute('''
          CREATE TABLE capture_sessions (
            id TEXT PRIMARY KEY,
            status TEXT NOT NULL,
            targetReleaseId TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE capture_items (
            id TEXT PRIMARY KEY,
            sessionId TEXT NOT NULL,
            path TEXT NOT NULL,
            sequence INTEGER NOT NULL,
            capturedAt TEXT NOT NULL,
            committedCardId TEXT,
            FOREIGN KEY (sessionId) REFERENCES capture_sessions (id) ON DELETE CASCADE
          )
        ''');
        await db.execute(
          'CREATE INDEX capture_items_session ON capture_items (sessionId)',
        );
        await db.execute('''
          CREATE TABLE price_observations (
            id TEXT PRIMARY KEY,
            cardId TEXT,
            game TEXT NOT NULL,
            cardNumber TEXT NOT NULL,
            language TEXT NOT NULL,
            officialRarity TEXT,
            variantFamily TEXT NOT NULL,
            variantName TEXT,
            artworkVariant TEXT,
            marketplace TEXT NOT NULL,
            sourceType TEXT NOT NULL,
            sourceLabel TEXT,
            url TEXT NOT NULL,
            price REAL NOT NULL,
            currency TEXT NOT NULL,
            isGraded INTEGER NOT NULL DEFAULT 0,
            soldOut INTEGER NOT NULL DEFAULT 0,
            condition TEXT,
            matchConfidence REAL,
            usedInEstimate INTEGER NOT NULL DEFAULT 0,
            notUsedReason TEXT,
            observedAt TEXT,
            researchedAt TEXT NOT NULL,
            provider TEXT
          )
        ''');
        await db.execute(
          'CREATE INDEX price_observations_printing ON price_observations (game, cardNumber, language, variantFamily, variantName)',
        );
        await db.execute('''
          CREATE TABLE printing_candidates (
            id TEXT PRIMARY KEY,
            game TEXT NOT NULL,
            cardNumber TEXT NOT NULL,
            language TEXT NOT NULL,
            candidates TEXT NOT NULL,
            researchedAt TEXT NOT NULL,
            provider TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Sub-folders were removed in this version. Their old table and
          // cards.subFolderId column are left in place rather than dropped:
          // ALTER TABLE ... DROP COLUMN needs SQLite >=3.35, which isn't
          // guaranteed on every Android version this app supports. Inert
          // dead schema on an upgrading install is zero-risk; a migration
          // that can fail on some devices is not.
          await db.execute(
            "ALTER TABLE releases ADD COLUMN coverPortrait INTEGER NOT NULL DEFAULT 0",
          );
          await db.execute(
            "ALTER TABLE releases ADD COLUMN category TEXT NOT NULL DEFAULT 'Others'",
          );
          await db.execute(
            'ALTER TABLE cards ADD COLUMN isFavorite INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE releases ADD COLUMN language TEXT');
          await db.execute('ALTER TABLE cards ADD COLUMN language TEXT');
          await db.execute('ALTER TABLE cards ADD COLUMN kind TEXT');
          await db.execute('ALTER TABLE cards ADD COLUMN color TEXT');
          await db.execute('ALTER TABLE cards ADD COLUMN type TEXT');
        }
        if (oldVersion < 4) {
          await db.execute(
            'ALTER TABLE releases ADD COLUMN landscapeCoverPath TEXT',
          );
          await db.execute(
            'ALTER TABLE releases ADD COLUMN portraitCoverPath TEXT',
          );
        }
        if (oldVersion < 5) {
          await db.execute(
            'ALTER TABLE releases ADD COLUMN isFavorite INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 6) {
          await db.execute('''
            CREATE TABLE capture_sessions (
              id TEXT PRIMARY KEY,
              status TEXT NOT NULL,
              targetReleaseId TEXT,
              createdAt TEXT NOT NULL,
              updatedAt TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE capture_items (
              id TEXT PRIMARY KEY,
              sessionId TEXT NOT NULL,
              path TEXT NOT NULL,
              sequence INTEGER NOT NULL,
              capturedAt TEXT NOT NULL,
              committedCardId TEXT,
              FOREIGN KEY (sessionId) REFERENCES capture_sessions (id) ON DELETE CASCADE
            )
          ''');
          await db.execute(
            'CREATE INDEX capture_items_session ON capture_items (sessionId)',
          );
        }
        if (oldVersion < 7) {
          // Physical-printing identity. NULL = unknown: existing cards are
          // deliberately not backfilled as base.
          await db.execute('ALTER TABLE cards ADD COLUMN variantFamily TEXT');
          await db.execute('ALTER TABLE cards ADD COLUMN variantName TEXT');
          await db.execute('ALTER TABLE cards ADD COLUMN artworkVariant TEXT');
        }
        if (oldVersion < 8) {
          // Append-only price history, one row per marketplace observation of
          // an exact printing. See PriceObservationRepository.
          await db.execute('''
          CREATE TABLE price_observations (
            id TEXT PRIMARY KEY,
            cardId TEXT,
            game TEXT NOT NULL,
            cardNumber TEXT NOT NULL,
            language TEXT NOT NULL,
            officialRarity TEXT,
            variantFamily TEXT NOT NULL,
            variantName TEXT,
            artworkVariant TEXT,
            marketplace TEXT NOT NULL,
            sourceType TEXT NOT NULL,
            sourceLabel TEXT,
            url TEXT NOT NULL,
            price REAL NOT NULL,
            currency TEXT NOT NULL,
            isGraded INTEGER NOT NULL DEFAULT 0,
            soldOut INTEGER NOT NULL DEFAULT 0,
            condition TEXT,
            matchConfidence REAL,
            usedInEstimate INTEGER NOT NULL DEFAULT 0,
            notUsedReason TEXT,
            observedAt TEXT,
            researchedAt TEXT NOT NULL,
            provider TEXT
          )
          ''');
          await db.execute(
            'CREATE INDEX price_observations_printing ON price_observations (game, cardNumber, language, variantFamily, variantName)',
          );
        }
        if (oldVersion < 9) {
          // Known printings of a logical card, from printing research.
          await db.execute('''
          CREATE TABLE printing_candidates (
            id TEXT PRIMARY KEY,
            game TEXT NOT NULL,
            cardNumber TEXT NOT NULL,
            language TEXT NOT NULL,
            candidates TEXT NOT NULL,
            researchedAt TEXT NOT NULL,
            provider TEXT
          )
          ''');
        }
      },
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }
}
