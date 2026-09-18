import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/value_entry.dart';
import 'app_database.dart';

enum ValueRange { day, week, month, year }

class ValueRepository {
  ValueRepository({Database Function()? dbOverride}) : _dbOverride = dbOverride;

  final Database Function()? _dbOverride;
  static const _uuid = Uuid();

  Future<Database> get _db async =>
      _dbOverride != null ? _dbOverride() : AppDatabase.instance.database;

  /// Saves an entry. Re-using an existing date for the same card replaces
  /// that entry rather than creating a second one.
  Future<ValueEntry> upsert(String cardId, DateTime date, double amount) async {
    final db = await _db;
    final dateOnly = ValueEntry.dateOnly(date);
    final existing = await db.query(
      'value_entries',
      where: 'cardId = ? AND date = ?',
      whereArgs: [cardId, dateOnly.toIso8601String()],
    );
    final entry = ValueEntry(
      id: existing.isNotEmpty ? existing.first['id'] as String : _uuid.v4(),
      cardId: cardId,
      date: dateOnly,
      amount: amount,
    );
    await db.insert(
      'value_entries',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return entry;
  }

  Future<void> delete(String id) async {
    final db = await _db;
    await db.delete('value_entries', where: 'id = ?', whereArgs: [id]);
  }

  /// All entries for a card, oldest first.
  Future<List<ValueEntry>> allForCard(String cardId) async {
    final db = await _db;
    final rows = await db.query(
      'value_entries',
      where: 'cardId = ?',
      whereArgs: [cardId],
      orderBy: 'date ASC',
    );
    return rows.map(ValueEntry.fromMap).toList();
  }

  Future<ValueEntry?> latestForCard(String cardId) async {
    final db = await _db;
    final rows = await db.query(
      'value_entries',
      where: 'cardId = ?',
      whereArgs: [cardId],
      orderBy: 'date DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ValueEntry.fromMap(rows.first);
  }

  /// Latest entry per card, for collection totals / movers. Cards with no
  /// entry are simply absent — never guessed at.
  Future<Map<String, ValueEntry>> latestPerCard() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT ve.* FROM value_entries ve
      INNER JOIN (
        SELECT cardId, MAX(date) AS maxDate FROM value_entries GROUP BY cardId
      ) latest ON ve.cardId = latest.cardId AND ve.date = latest.maxDate
    ''');
    final map = <String, ValueEntry>{};
    for (final row in rows) {
      final entry = ValueEntry.fromMap(row);
      map[entry.cardId] = entry;
    }
    return map;
  }

  /// Windows the sparse series to a range. Entries are returned in date
  /// order; callers connect them with straight segments and must never
  /// interpolate or extrapolate past the last real entry.
  List<ValueEntry> windowed(
    List<ValueEntry> series,
    ValueRange range, {
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    late DateTime start;
    switch (range) {
      case ValueRange.day:
        start = today.subtract(const Duration(days: 1));
        break;
      case ValueRange.week:
        start = today.subtract(const Duration(days: 7));
        break;
      case ValueRange.month:
        start = today.subtract(const Duration(days: 30));
        break;
      case ValueRange.year:
        start = today.subtract(const Duration(days: 365));
        break;
    }
    return series.where((e) => !e.date.isBefore(start)).toList();
  }

  /// Delta between the latest entry and the nearest entry on or before
  /// [daysAgo] days back. Returns null when no such earlier entry exists
  /// (callers should render "—", not 0).
  double? deltaVsDaysAgo(
    List<ValueEntry> series,
    int daysAgo, {
    DateTime? now,
  }) {
    if (series.isEmpty) return null;
    final latest = series.last;
    final cutoff = (now ?? DateTime.now()).subtract(Duration(days: daysAgo));
    ValueEntry? reference;
    for (final e in series) {
      if (!e.date.isAfter(cutoff)) {
        reference = e;
      } else {
        break;
      }
    }
    if (reference == null || reference.id == latest.id) return null;
    return latest.amount - reference.amount;
  }
}
