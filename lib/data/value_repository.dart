import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/value_bucket.dart';
import '../models/value_entry.dart';
import '../utils/formatting.dart';
import 'app_database.dart';

enum ValueRange { day, week, month, year }

/// Rolling-window width backing each range, in days — day/week match their
/// literal names; month/year reuse the same 30/365-day approximation the
/// range picker has always used rather than introducing calendar-boundary
/// math (leap years, variable month lengths) nothing else in the app has.
const valueRangeUnitDays = {
  ValueRange.day: 1,
  ValueRange.week: 7,
  ValueRange.month: 30,
  ValueRange.year: 365,
};

const valueRangeCountOptions = {
  ValueRange.day: [7, 15, 30],
  ValueRange.week: [4, 8, 12],
  ValueRange.month: [4, 8, 12],
  ValueRange.year: [4, 8, 12],
};

const valueRangeDefaultCount = {
  ValueRange.day: 7,
  ValueRange.week: 4,
  ValueRange.month: 4,
  ValueRange.year: 4,
};

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

  /// Buckets the sparse series into `count` fixed-width windows of
  /// `range`'s unit size, oldest first, ending today. Each bucket's amount
  /// is the mean of whatever entries fall inside it, or `null` if none —
  /// callers must render a null bucket as a gap, never interpolated or
  /// extrapolated, same invariant the old single-window `windowed()` had.
  List<ValueBucket> buckets(
    List<ValueEntry> series,
    ValueRange range,
    int count, {
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final unitDays = valueRangeUnitDays[range]!;
    final result = <ValueBucket>[];
    for (var i = count - 1; i >= 0; i--) {
      final end = today.subtract(Duration(days: unitDays * i));
      final start = end.subtract(Duration(days: unitDays));
      final inBucket = series.where(
        (e) => e.date.isAfter(start) && !e.date.isAfter(end),
      );
      final amount = inBucket.isEmpty
          ? null
          : inBucket.fold<double>(0, (sum, e) => sum + e.amount) /
                inBucket.length;
      result.add(
        ValueBucket(
          label: range == ValueRange.year
              ? '${start.year}'
              : formatShortDate(start),
          periodStart: start,
          amount: amount,
        ),
      );
    }
    return result;
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
