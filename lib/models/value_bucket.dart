/// One point on the value chart's fixed bucket grid: a labeled period with
/// the average of whatever value entries fell inside it, or `amount: null`
/// when none did. A null bucket is a gap — the chart must never interpolate
/// or extrapolate across it, same invariant as the raw entry series.
class ValueBucket {
  const ValueBucket({
    required this.label,
    required this.periodStart,
    required this.amount,
  });

  final String label;
  final DateTime periodStart;
  final double? amount;
}
