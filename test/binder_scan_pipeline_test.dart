// Phase 4 coverage: what Binder Scan hands to the rest of the app. The
// detector's own accuracy is covered in binder_page_detector_test.dart; what
// matters here is that its crops enter the *existing* capture-session and
// collection machinery unchanged — one real card per crop, pointing at a
// real file, filed and cleaned up exactly as a burst shot's photo is.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pokedex_tcg/data/binder_page_detector.dart';
import 'package:pokedex_tcg/data/capture_session_repository.dart';
import 'package:pokedex_tcg/data/collection_repository.dart';
import 'package:pokedex_tcg/screens/capture/live_framing.dart' show kCardAspect;

import 'binder_page_detector_test.dart' show syntheticPage;

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.dir);

  final Directory dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir.path;

  @override
  Future<String?> getApplicationSupportPath() async => dir.path;

  @override
  Future<String?> getTemporaryPath() async => dir.path;
}

class _Repos {
  const _Repos(this.captures, this.collection);
  final CaptureSessionRepository captures;
  final CollectionRepository collection;
}

/// Just the tables a crop's journey touches. The release-bound and
/// retry-safety cases are already covered against the full schema in
/// capture_session_test.dart; these scans file into the unsorted tray.
Future<_Repos> _openDb() async {
  final db = await databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  await db.execute('PRAGMA foreign_keys = ON');
  await db.execute('''
    CREATE TABLE cards (
      id TEXT PRIMARY KEY, name TEXT, number TEXT, rarity TEXT, variantFamily TEXT, variantName TEXT,
      artworkVariant TEXT, language TEXT,
      kind TEXT, color TEXT, type TEXT, condition TEXT,
      copies INTEGER NOT NULL DEFAULT 1, releaseId TEXT,
      photoPaths TEXT NOT NULL DEFAULT '', pricePaid REAL, datePaid TEXT,
      forTrade INTEGER NOT NULL DEFAULT 0, onWishlist INTEGER NOT NULL DEFAULT 0,
      isFavorite INTEGER NOT NULL DEFAULT 0, notes TEXT, createdAt TEXT NOT NULL
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
  );
}

void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('binder_scan_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('crops are saved as real files framed like a captured card', () async {
    final scan = detectCardsOnPage(syntheticPage());
    final paths = await saveCardCrops(scan.cardJpgs);

    expect(paths, hasLength(9));
    expect(paths.toSet(), hasLength(9), reason: 'no two crops share a file');
    for (final path in paths) {
      expect(File(path).existsSync(), isTrue);
      final crop = img.decodeJpg(File(path).readAsBytesSync())!;
      // The same framing the single-card capture flow produces, which is
      // what classifyCardText's positional field bands assume.
      expect(crop.width / crop.height, closeTo(kCardAspect, 0.02));
    }
  });

  test('a scanned page becomes one collection card per crop', () async {
    final scan = detectCardsOnPage(syntheticPage());
    final paths = await saveCardCrops(scan.cardJpgs);
    final repos = await _openDb();

    final session = await repos.captures.createSession();
    for (final path in paths) {
      await repos.captures.addItem(session.id, path);
    }
    final cards = await repos.captures.commit(repos.collection, session.id);

    expect(cards, hasLength(9));
    // Reading order survives all the way into the collection, and each card
    // points at its own crop — no copy, no second location.
    expect(cards.map((c) => c.photoPaths.single).toList(), paths);
    for (final card in cards) {
      expect(card.releaseId, isNull, reason: 'unsorted tray');
      expect(card.copies, 1);
      // Untitled on arrival: naming is batch triage's job, via the same OCR
      // autofill a burst gets. Binder Scan never names a card itself.
      expect(card.isUntitled, isTrue);
    }
    expect(await repos.captures.session(session.id), isNull);
  });

  test('two pages accumulate into one session', () async {
    final repos = await _openDb();
    final session = await repos.captures.createSession();
    for (final tilt in [0.0, 6.0]) {
      final scan = detectCardsOnPage(syntheticPage(tiltDegrees: tilt));
      for (final path in await saveCardCrops(scan.cardJpgs)) {
        await repos.captures.addItem(session.id, path);
      }
    }

    final cards = await repos.captures.commit(repos.collection, session.id);

    expect(cards, hasLength(18));
  });

  test('discarding a scan deletes the crops it made', () async {
    final scan = detectCardsOnPage(syntheticPage());
    final paths = await saveCardCrops(scan.cardJpgs);
    final repos = await _openDb();
    final session = await repos.captures.createSession();
    for (final path in paths) {
      await repos.captures.addItem(session.id, path);
    }

    await repos.captures.discard(session.id);

    // Crops that never became cards leave nothing behind on disk.
    for (final path in paths) {
      expect(File(path).existsSync(), isFalse, reason: path);
    }
    expect(await repos.collection.allCards(), isEmpty);
  });

  test('removing a wrongly detected card drops its row and file', () async {
    final scan = detectCardsOnPage(syntheticPage());
    final paths = await saveCardCrops(scan.cardJpgs);
    final repos = await _openDb();
    final session = await repos.captures.createSession();
    final items = [
      for (final path in paths) await repos.captures.addItem(session.id, path),
    ];

    await repos.captures.removeItem(items[4]);

    expect(File(items[4].path).existsSync(), isFalse);
    expect(await repos.captures.itemCount(session.id), 8);
    final cards = await repos.captures.commit(repos.collection, session.id);
    expect(cards, hasLength(8));
    expect(
      cards.map((c) => c.photoPaths.single),
      isNot(contains(items[4].path)),
    );
  });

  test('a page added after a removal keeps reading order', () async {
    // The sequence a new item gets used to be the item *count*, which after
    // a removal hands out a number a surviving item already holds — two
    // items then sort arbitrarily against each other and the cards come out
    // of the page's reading order.
    final repos = await _openDb();
    final session = await repos.captures.createSession();
    final first = [
      for (final path in await saveCardCrops(
        detectCardsOnPage(syntheticPage()).cardJpgs,
      ))
        await repos.captures.addItem(session.id, path),
    ];
    await repos.captures.removeItem(first[1]);
    await repos.captures.removeItem(first[2]);

    final second = await saveCardCrops(
      detectCardsOnPage(syntheticPage(tiltDegrees: 6)).cardJpgs,
    );
    for (final path in second) {
      await repos.captures.addItem(session.id, path);
    }

    final items = await repos.captures.items(session.id);
    expect(items.map((i) => i.sequence).toSet(), hasLength(items.length));
    // Page one's survivors, in order, then all of page two in order.
    expect(items.map((i) => i.path).toList(), [
      first[0].path,
      ...first.skip(3).map((i) => i.path),
      ...second,
    ]);
  });

  test('near-identical cards are kept separately, not deduplicated', () async {
    // A binder legitimately holds playsets — three of the same card, or the
    // same card again on a later page. Every pocket on this synthetic page
    // holds the same layout, and all nine still arrive as their own rows,
    // because nothing in this path collapses anything. That is the existing
    // collection's own behaviour and Binder Scan doesn't add a rule of its
    // own on top of it.
    final scan = detectCardsOnPage(syntheticPage());
    final paths = await saveCardCrops(scan.cardJpgs);
    final repos = await _openDb();
    final session = await repos.captures.createSession();
    for (final path in paths) {
      await repos.captures.addItem(session.id, path);
    }

    final cards = await repos.captures.commit(repos.collection, session.id);

    expect(cards, hasLength(9));
    expect(cards.map((c) => c.id).toSet(), hasLength(9));
    expect(cards.map((c) => c.photoPaths.single).toSet(), hasLength(9));
  });
}
