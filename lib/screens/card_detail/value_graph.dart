import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/value_bucket.dart';

/// Plots a fixed grid of buckets: straight segments within each run of
/// consecutive non-null buckets, never interpolated or extrapolated across
/// a null (empty) bucket — a null simply breaks the line into a visible
/// gap. Scales to the visible min/max with headroom, not to zero.
class ValueGraph extends StatelessWidget {
  const ValueGraph({super.key, required this.buckets, this.height = 160});

  final List<ValueBucket> buckets;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final amounts = buckets
        .map((b) => b.amount)
        .whereType<double>()
        .toList();

    if (amounts.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'No value recorded',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }

    final min = amounts.reduce((a, b) => a < b ? a : b);
    final max = amounts.reduce((a, b) => a > b ? a : b);
    final headroom = (max - min) * 0.2 + 1;
    final minY = min - headroom;
    final maxY = max + headroom;

    // Split into runs of consecutive non-null buckets — each run is its
    // own line segment, so a gap never gets bridged.
    final runs = <List<FlSpot>>[];
    List<FlSpot> current = [];
    for (var i = 0; i < buckets.length; i++) {
      final amount = buckets[i].amount;
      if (amount == null) {
        if (current.isNotEmpty) runs.add(current);
        current = [];
      } else {
        current = [...current, FlSpot(i.toDouble(), amount)];
      }
    }
    if (current.isNotEmpty) runs.add(current);

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: minY,
          maxY: maxY,
          minX: 0,
          maxX: (buckets.length - 1).toDouble(),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: (maxY - minY) / 2,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: scheme.outlineVariant, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                reservedSize: 22,
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  if (index < 0 || index >= buckets.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      buckets[index].label,
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: true),
          lineBarsData: [
            for (final run in runs)
              LineChartBarData(
                spots: run,
                isCurved: false,
                color: scheme.primary,
                barWidth: 2,
                dotData: FlDotData(
                  show: true,
                  checkToShowDot: (spot, barData) =>
                      spot == barData.spots.last || barData.spots.length <= 6,
                ),
                belowBarData: BarAreaData(
                  show: true,
                  color: scheme.primary.withValues(alpha: 0.08),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
