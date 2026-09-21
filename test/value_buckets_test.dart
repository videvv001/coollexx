// Regression coverage for the card-detail value chart's bucketing: fixed
// 12 calendar-accurate periods, latest-value-per-period aggregation (not
// mean), and null gaps for periods with no entry.

import 'package:flutter_test/flutter_test.dart';

import 'package:pokedex_tcg/data/value_repository.dart';
import 'package:pokedex_tcg/models/value_entry.dart';

void main() {
  final repo = ValueRepository(dbOverride: () => throw UnimplementedError());
  final now = DateTime(2026, 9, 20); // Sunday

  test('always returns 12 buckets ending with the period containing now', () {
    final buckets = repo.buckets(const [], ValueRange.month, now: now);
    expect(buckets, hasLength(12));
    expect(buckets.last.periodStart, DateTime(2026, 9, 1));
    expect(buckets.first.periodStart, DateTime(2025, 10, 1));
  });

  test('month bucket uses the latest entry in that calendar month', () {
    final entries = [
      ValueEntry(id: '1', cardId: 'c', date: DateTime(2026, 1, 5), amount: 100),
      ValueEntry(id: '2', cardId: 'c', date: DateTime(2026, 1, 12), amount: 120),
      ValueEntry(id: '3', cardId: 'c', date: DateTime(2026, 1, 28), amount: 150),
    ];
    final buckets = repo.buckets(entries, ValueRange.month, now: now);
    final jan = buckets.firstWhere((b) => b.periodStart == DateTime(2026, 1, 1));
    expect(jan.amount, 150);
  });

  test('a month with no entries is a null gap, not zero', () {
    final entries = [
      ValueEntry(id: '1', cardId: 'c', date: DateTime(2026, 1, 5), amount: 100),
    ];
    final buckets = repo.buckets(entries, ValueRange.month, now: now);
    final feb = buckets.firstWhere((b) => b.periodStart == DateTime(2026, 2, 1));
    expect(feb.amount, isNull);
  });

  test('year bucket spans the whole calendar year', () {
    final entries = [
      ValueEntry(id: '1', cardId: 'c', date: DateTime(2024, 3, 1), amount: 10),
      ValueEntry(id: '2', cardId: 'c', date: DateTime(2024, 12, 31), amount: 20),
    ];
    final buckets = repo.buckets(entries, ValueRange.year, now: now);
    final y2024 = buckets.firstWhere((b) => b.periodStart == DateTime(2024, 1, 1));
    expect(y2024.amount, 20);
  });

  test('day bucket is a single calendar day', () {
    final entries = [
      ValueEntry(id: '1', cardId: 'c', date: DateTime(2026, 9, 19), amount: 5),
      ValueEntry(id: '2', cardId: 'c', date: DateTime(2026, 9, 20), amount: 7),
    ];
    final buckets = repo.buckets(entries, ValueRange.day, now: now);
    expect(buckets.last.amount, 7); // today
    expect(buckets[buckets.length - 2].amount, 5); // yesterday
  });
}
