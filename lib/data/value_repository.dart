import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/value_bucket.dart';
import '../models/value_entry.dart';
import '../utils/formatting.dart';
import 'app_database.dart';

enum ValueRange { day, week, month, year }

/// Fixed period count for the card-detail value chart: the current period
/// plus the previous 11, for every range.
const valueChartPeriods = 12;

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

  /// Buckets the sparse series into [valueChartPeriods] calendar-accurate
  /// periods of `range`'s unit (day/calendar week/calendar month/calendar
  /// year), oldest first, ending with the period containing `now`. Each
  /// bucket's amount is the *latest* entry within it (this chart represents
  /// value over time, so the last known price for a period beats an
  /// average), or `null` if none fell inside it — callers must render a
  /// null bucket as a gap, never interpolated or extrapolated.
  List<ValueBucket> buckets(
    List<ValueEntry> series,
    ValueRange range, {
    DateTime? now,
  }) {
    final today = ValueEntry.dateOnly(now ?? DateTime.now());
    final result = <ValueBucket>[];
    for (var i = valueChartPeriods - 1; i >= 0; i--) {
      final start = _periodStart(range, today, i);
      final end = _periodStart(range, today, i - 1);
      ValueEntry? latest;
      for (final e in series) {
        if (!e.date.isBefore(start) &&
            e.date.isBefore(end) &&
            (latest == null || e.date.isAfter(latest.date))) {
          latest = e;
        }
      }
      result.add(
        ValueBucket(
          label: _periodLabel(range, start),
          periodStart: start,
          amount: latest?.amount,
        ),
      );
    }
    return result;
  }

  /// The start of the period `periodsAgo` periods before the one containing
  /// [today] (0 = today's own period).
  DateTime _periodStart(ValueRange range, DateTime today, int periodsAgo) {
    switch (range) {
      case ValueRange.day:
        return today.subtract(Duration(days: periodsAgo));
      case ValueRange.week:
        final weekStart = today.subtract(Duration(days: today.weekday - 1));
        return weekStart.subtract(Duration(days: 7 * periodsAgo));
      case ValueRange.month:
        return DateTime(today.year, today.month - periodsAgo, 1);
      case ValueRange.year:
        return DateTime(today.year - periodsAgo, 1, 1);
    }
  }

  String _periodLabel(ValueRange range, DateTime start) {
    switch (range) {
      case ValueRange.day:
      case ValueRange.week:
        return formatShortDate(start);
      case ValueRange.month:
        return formatMonthLabel(start);
      case ValueRange.year:
        return '${start.year}';
    }
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
