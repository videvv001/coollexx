/// A manually typed value/price point for one card on one date.
/// At most one entry per (cardId, date) — saving on an existing date
/// overwrites it.
class ValueEntry {
  final String id;
  final String cardId;
  final DateTime date; // date only, time component ignored
  final double amount;

  const ValueEntry({
    required this.id,
    required this.cardId,
    required this.date,
    required this.amount,
  });

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  Map<String, Object?> toMap() => {
    'id': id,
    'cardId': cardId,
    'date': dateOnly(date).toIso8601String(),
    'amount': amount,
  };

  factory ValueEntry.fromMap(Map<String, Object?> map) => ValueEntry(
    id: map['id'] as String,
    cardId: map['cardId'] as String,
    date: DateTime.parse(map['date'] as String),
    amount: (map['amount'] as num).toDouble(),
  );
}
