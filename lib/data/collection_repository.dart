import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/release.dart';
import '../models/sub_folder.dart';
import '../models/tcg_card.dart';
import 'app_database.dart';

/// CRUD + derived counts for releases, sub-folders and cards. This is the
/// spine of the app: a card belongs to at most one release and at most one
/// sub-folder, both of which are always optional.
class CollectionRepository {
  CollectionRepository({Database Function()? dbOverride})
    : _dbOverride = dbOverride;

  final Database Function()? _dbOverride;
  static const _uuid = Uuid();

  Future<Database> get _db async =>
      _dbOverride != null ? _dbOverride() : AppDatabase.instance.database;

  // ---- Releases ----------------------------------------------------

  Future<List<Release>> allReleases() async {
    final db = await _db;
    final rows = await db.query('releases', orderBy: 'orderIndex ASC');
    return rows.map(Release.fromMap).toList();
  }

  Future<Release?> release(String id) async {
    final db = await _db;
    final rows = await db.query('releases', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Release.fromMap(rows.first);
  }

  Future<Release> createRelease(String name) async {
    final db = await _db;
    final count =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM releases'),
        ) ??
        0;
    final release = Release(
      id: _uuid.v4(),
      name: name,
      dateCreated: DateTime.now(),
      orderIndex: count,
    );
    await db.insert('releases', release.toMap());
    return release;
  }

  Future<void> updateRelease(Release release) async {
    final db = await _db;
    await db.update(
      'releases',
      release.toMap(),
      where: 'id = ?',
      whereArgs: [release.id],
    );
  }

  Future<void> deleteRelease(String id) async {
    final db = await _db;
    await db.delete('releases', where: 'id = ?', whereArgs: [id]);
  }

  // ---- Sub-folders ----------------------------------------------------

  Future<List<SubFolder>> subFoldersFor(String releaseId) async {
    final db = await _db;
    final rows = await db.query(
      'sub_folders',
      where: 'releaseId = ?',
      whereArgs: [releaseId],
      orderBy: 'orderIndex ASC',
    );
    return rows.map(SubFolder.fromMap).toList();
  }

  Future<SubFolder> createSubFolder(String releaseId, String name) async {
    final db = await _db;
    final count =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM sub_folders WHERE releaseId = ?',
            [releaseId],
          ),
        ) ??
        0;
    final subFolder = SubFolder(
      id: _uuid.v4(),
      releaseId: releaseId,
      name: name,
      orderIndex: count,
    );
    await db.insert('sub_folders', subFolder.toMap());
    return subFolder;
  }

  Future<void> deleteSubFolder(String id) async {
    final db = await _db;
    // Cards in this sub-folder fall back to "in the release, no sub-folder".
    await db.update(
      'cards',
      {'subFolderId': null},
      where: 'subFolderId = ?',
      whereArgs: [id],
    );
    await db.delete('sub_folders', where: 'id = ?', whereArgs: [id]);
  }

  // ---- Cards ----------------------------------------------------

  Future<List<TcgCard>> allCards() async {
    final db = await _db;
    final rows = await db.query('cards', orderBy: 'createdAt DESC');
    return rows.map(TcgCard.fromMap).toList();
  }

  Future<List<TcgCard>> cardsInRelease(String releaseId) async {
    final db = await _db;
    final rows = await db.query(
      'cards',
      where: 'releaseId = ?',
      whereArgs: [releaseId],
      orderBy: 'createdAt DESC',
    );
    return rows.map(TcgCard.fromMap).toList();
  }

  Future<List<TcgCard>> cardsInSubFolder(String subFolderId) async {
    final db = await _db;
    final rows = await db.query(
      'cards',
      where: 'subFolderId = ?',
      whereArgs: [subFolderId],
      orderBy: 'createdAt DESC',
    );
    return rows.map(TcgCard.fromMap).toList();
  }

  /// Photos shot but not yet filed into any release — the return path
  /// surfaced by the Home unsorted-tray banner.
  Future<List<TcgCard>> unsortedCards() async {
    final db = await _db;
    final rows = await db.query(
      'cards',
      where: 'releaseId IS NULL',
      orderBy: 'createdAt DESC',
    );
    return rows.map(TcgCard.fromMap).toList();
  }

  Future<int> cardCountInRelease(String releaseId) async {
    final db = await _db;
    return Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COALESCE(SUM(copies), 0) FROM cards WHERE releaseId = ?',
            [releaseId],
          ),
        ) ??
        0;
  }

  Future<int> subFolderCountInRelease(String releaseId) async {
    final db = await _db;
    return Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM sub_folders WHERE releaseId = ?',
            [releaseId],
          ),
        ) ??
        0;
  }

  Future<TcgCard?> card(String id) async {
    final db = await _db;
    final rows = await db.query('cards', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return TcgCard.fromMap(rows.first);
  }

  Future<TcgCard> createCard(TcgCard card) async {
    final db = await _db;
    await db.insert('cards', card.toMap());
    return card;
  }

  Future<void> updateCard(TcgCard card) async {
    final db = await _db;
    await db.update(
      'cards',
      card.toMap(),
      where: 'id = ?',
      whereArgs: [card.id],
    );
  }

  Future<void> deleteCard(String id) async {
    final db = await _db;
    await db.delete('cards', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteCards(List<String> ids) async {
    final db = await _db;
    final batch = db.batch();
    for (final id in ids) {
      batch.delete('cards', where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  Future<void> moveCards(
    List<String> ids, {
    String? releaseId,
    bool clearRelease = false,
    String? subFolderId,
    bool clearSubFolder = true,
  }) async {
    final db = await _db;
    final values = <String, Object?>{};
    if (clearRelease) {
      values['releaseId'] = null;
    } else if (releaseId != null) {
      values['releaseId'] = releaseId;
    }
    values['subFolderId'] = clearSubFolder ? null : subFolderId;
    final batch = db.batch();
    for (final id in ids) {
      batch.update('cards', values, where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  Future<void> setTradeFlags(
    List<String> ids, {
    bool? forTrade,
    bool? onWishlist,
  }) async {
    final db = await _db;
    final values = <String, Object?>{};
    if (forTrade != null) values['forTrade'] = forTrade ? 1 : 0;
    if (onWishlist != null) values['onWishlist'] = onWishlist ? 1 : 0;
    if (values.isEmpty) return;
    final batch = db.batch();
    for (final id in ids) {
      batch.update('cards', values, where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  Future<List<TcgCard>> search({
    String? query,
    List<String>? rarities,
    String? releaseId,
    String? subFolderId,
    String? conditionLabel,
    bool onlyPhotographed = false,
  }) async {
    final db = await _db;
    final where = <String>[];
    final args = <Object?>[];
    if (query != null && query.trim().isNotEmpty) {
      where.add('(name LIKE ? OR number LIKE ?)');
      args.add('%${query.trim()}%');
      args.add('%${query.trim()}%');
    }
    if (rarities != null && rarities.isNotEmpty) {
      where.add('rarity IN (${rarities.map((_) => '?').join(',')})');
      args.addAll(rarities);
    }
    if (releaseId != null) {
      where.add('releaseId = ?');
      args.add(releaseId);
    }
    if (subFolderId != null) {
      where.add('subFolderId = ?');
      args.add(subFolderId);
    }
    if (conditionLabel != null) {
      where.add('condition = ?');
      args.add(conditionLabel);
    }
    if (onlyPhotographed) {
      where.add("photoPaths <> ''");
    }
    final rows = await db.query(
      'cards',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'createdAt DESC',
    );
    return rows.map(TcgCard.fromMap).toList();
  }
}
