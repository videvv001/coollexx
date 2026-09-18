import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/release.dart';
import '../models/release_category.dart';
import '../models/tcg_card.dart';
import 'app_database.dart';

/// CRUD + derived counts for releases and cards. A card belongs to at most
/// one release, which is always optional (null = unsorted).
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

  Future<Release> createRelease(
    String name, {
    ReleaseCategory category = ReleaseCategory.others,
  }) async {
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
      category: category,
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
  }) async {
    final db = await _db;
    final values = <String, Object?>{};
    if (clearRelease) {
      values['releaseId'] = null;
    } else if (releaseId != null) {
      values['releaseId'] = releaseId;
    }
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
    String? conditionLabel,
    bool onlyPhotographed = false,
    ReleaseCategory? category,
  }) async {
    final db = await _db;
    final where = <String>[];
    final args = <Object?>[];
    if (query != null && query.trim().isNotEmpty) {
      where.add('(cards.name LIKE ? OR cards.number LIKE ?)');
      args.add('%${query.trim()}%');
      args.add('%${query.trim()}%');
    }
    if (rarities != null && rarities.isNotEmpty) {
      where.add('cards.rarity IN (${rarities.map((_) => '?').join(',')})');
      args.addAll(rarities);
    }
    if (releaseId != null) {
      where.add('cards.releaseId = ?');
      args.add(releaseId);
    }
    if (conditionLabel != null) {
      where.add('cards.condition = ?');
      args.add(conditionLabel);
    }
    if (onlyPhotographed) {
      where.add("cards.photoPaths <> ''");
    }
    if (category != null) {
      where.add('releases.category = ?');
      args.add(category.label);
    }
    // Only joins to releases when actually filtering by category — the join
    // is otherwise unnecessary cost for every other search.
    final join = category != null
        ? 'INNER JOIN releases ON cards.releaseId = releases.id'
        : '';
    final rows = await db.rawQuery(
      'SELECT cards.* FROM cards $join'
      '${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'}'
      ' ORDER BY cards.createdAt DESC',
      args,
    );
    return rows.map(TcgCard.fromMap).toList();
  }
}
