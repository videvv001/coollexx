import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/value_entry.dart';

/// Plots a sparse, irregular value series: straight segments between real
/// entries only, never an interpolated curve and never extrapolated past
/// the last point. Scales to the window's min/max with headroom, not to
/// zero, and always marks the latest point.
class ValueGraph extends StatelessWidget {
  const ValueGraph({super.key, required this.entries, this.height = 160});

  final List<ValueEntry> entries;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (entries.isEmpty) {
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

    if (entries.length == 1) {
      final e = entries.first;
      return SizedBox(
        height: height,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 10, color: scheme.primary),
              const SizedBox(height: 8),
              Text(
                '\$${e.amount.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      );
    }

    final amounts = entries.map((e) => e.amount).toList();
    final min = amounts.reduce((a, b) => a < b ? a : b);
    final max = amounts.reduce((a, b) => a > b ? a : b);
    final headroom = (max - min) * 0.2 + 1;
    final minY = min - headroom;
    final maxY = max + headroom;
    final start = entries.first.date;

    final spots = entries
        .map(
          (e) => FlSpot(e.date.difference(start).inDays.toDouble(), e.amount),
        )
        .toList();

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: minY,
          maxY: maxY,
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: (maxY - minY) / 2,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: scheme.outlineVariant, strokeWidth: 1),
          ),
          titlesData: const FlTitlesData(
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: true),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
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
