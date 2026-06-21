import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/smoking_record.dart';
import '../../providers/app_providers.dart';
import '../../utils/theme.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(recordsProvider);
    final range = ref.watch(timeRangeProvider);
    final offset = ref.watch(dateOffsetProvider);
    final brandDb = ref.read(brandDatabaseProvider);

    // Period-aware record sets (this period + the previous one for the delta).
    final records = recordsForPeriod(all, range, offset);
    final prevRecords = recordsForPeriod(all, range, offset - 1);
    final (start, _) = periodBounds(range, offset);

    // Aggregates over the selected period.
    double costSum = 0; // accumulate, round once (honest estimate)
    final Map<String, int> brandCounts = {};
    for (final r in records) {
      final brand = brandDb.findByBarcode(r.brandBarcode);
      if (brand != null) {
        costSum += brand.packPrice / brand.packSize;
        brandCounts[brand.nameZH] = (brandCounts[brand.nameZH] ?? 0) + 1;
      }
    }
    final totalCost = costSum.round();
    final topBrands = brandCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final delta = records.length - prevRecords.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('統計')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _periodSelector(ref, range, offset, start),
          const SizedBox(height: 16),
          if (records.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 80),
              child: Center(
                child: Column(children: [
                  Icon(Icons.bar_chart_rounded,
                      color: AppColors.textSecondary.withValues(alpha: 0.4),
                      size: 40),
                  const SizedBox(height: 12),
                  const Text('這段期間還沒有記錄',
                      style: TextStyle(color: AppColors.textSecondary)),
                ]),
              ),
            )
          else ...[
            // Summary cards
            Row(children: [
              _summaryCard('總計', '${records.length} 根', Icons.smoking_rooms),
              const SizedBox(width: 12),
              _summaryCard('花費(約)', 'NT\$$totalCost', Icons.attach_money),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              _summaryCard('品牌數', '${brandCounts.length}',
                  Icons.collections_bookmark),
              const SizedBox(width: 12),
              _deltaCard(delta),
            ]),
            const SizedBox(height: 24),

            // Trend over the period
            Text(_trendTitle(range),
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            SizedBox(height: 180, child: _trendChart(records, range, start)),
            const SizedBox(height: 24),

            // Brand ranking
            const Text('品牌排行',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            ...topBrands
                .take(5)
                .map((e) => _brandBar(e.key, e.value, records.length)),
          ],
        ],
      ),
    );
  }

  // ─────────────────── period selector ───────────────────

  Widget _periodSelector(
      WidgetRef ref, TimeRange range, int offset, DateTime start) {
    Widget chip(TimeRange r, String label) {
      final on = r == range;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            ref.read(timeRangeProvider.notifier).state = r;
            ref.read(dateOffsetProvider.notifier).state = 0;
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: on ? AppColors.amber : AppColors.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: on ? Colors.white : AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      );
    }

    return Column(children: [
      Row(children: [
        chip(TimeRange.day, '日'),
        chip(TimeRange.week, '週'),
        chip(TimeRange.month, '月'),
        chip(TimeRange.year, '年'),
      ]),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, color: AppColors.textSecondary),
          onPressed: () => ref.read(dateOffsetProvider.notifier).state--,
        ),
        SizedBox(
          width: 160,
          child: Text(_periodLabel(range, start),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
        ),
        IconButton(
          icon:
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          // Don't navigate into the future past the current period.
          onPressed: offset >= 0
              ? null
              : () => ref.read(dateOffsetProvider.notifier).state++,
        ),
      ]),
    ]);
  }

  String _periodLabel(TimeRange range, DateTime start) {
    String two(int n) => n.toString().padLeft(2, '0');
    switch (range) {
      case TimeRange.day:
        return '${start.year}/${two(start.month)}/${two(start.day)}';
      case TimeRange.week:
        final end = start.add(const Duration(days: 6));
        return '${two(start.month)}/${two(start.day)} – ${two(end.month)}/${two(end.day)}';
      case TimeRange.month:
        return '${start.year}/${two(start.month)}';
      case TimeRange.year:
        return '${start.year}';
    }
  }

  String _trendTitle(TimeRange range) => switch (range) {
        TimeRange.day => '逐時趨勢',
        TimeRange.week => '逐日趨勢',
        TimeRange.month => '逐日趨勢',
        TimeRange.year => '逐月趨勢',
      };

  // ─────────────────── trend chart ───────────────────

  Widget _trendChart(
      List<SmokingRecord> records, TimeRange range, DateTime start) {
    final (values, labelFor) = _buckets(records, range, start);
    final maxY = values.fold<double>(0, (m, v) => v > m ? v : m);

    return BarChart(BarChartData(
      maxY: maxY < 1 ? 1 : maxY * 1.2,
      barGroups: List.generate(values.length, (i) {
        return BarChartGroupData(x: i, barRods: [
          BarChartRodData(
            toY: values[i],
            color: AppColors.amber,
            width: _barWidth(values.length),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
          ),
        ]);
      }),
      titlesData: FlTitlesData(
        topTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (val, _) {
              final label = labelFor(val.toInt());
              if (label.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(label,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 10)),
              );
            },
          ),
        ),
      ),
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
    ));
  }

  double _barWidth(int n) {
    if (n <= 7) return 18;
    if (n <= 12) return 12;
    if (n <= 24) return 8;
    return 5;
  }

  /// Returns per-bucket counts + a label function for the x axis.
  (List<double>, String Function(int)) _buckets(
      List<SmokingRecord> recs, TimeRange range, DateTime start) {
    switch (range) {
      case TimeRange.day:
        final v = List.filled(24, 0.0);
        for (final r in recs) {
          v[r.createdAt.hour] += 1;
        }
        return (v, (i) => i % 6 == 0 ? '$i' : '');
      case TimeRange.week:
        final v = List.filled(7, 0.0);
        for (final r in recs) {
          final d = r.createdAt.difference(start).inDays;
          if (d >= 0 && d < 7) v[d] += 1;
        }
        const wd = ['一', '二', '三', '四', '五', '六', '日'];
        return (v, (i) => (i >= 0 && i < 7) ? wd[i] : '');
      case TimeRange.month:
        final days = DateTime(start.year, start.month + 1, 0).day;
        final v = List.filled(days, 0.0);
        for (final r in recs) {
          final d = r.createdAt.day - 1;
          if (d >= 0 && d < days) v[d] += 1;
        }
        return (v, (i) => (i + 1) % 5 == 0 ? '${i + 1}' : '');
      case TimeRange.year:
        final v = List.filled(12, 0.0);
        for (final r in recs) {
          v[r.createdAt.month - 1] += 1;
        }
        return (v, (i) => '${i + 1}');
    }
  }

  // ─────────────────── small widgets ───────────────────

  Widget _summaryCard(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.amber, size: 20),
            const SizedBox(height: 8),
            Text(value,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _deltaCard(int delta) {
    final up = delta > 0;
    final flat = delta == 0;
    final color = flat
        ? AppColors.textSecondary
        : (up ? AppColors.danger : AppColors.success);
    final icon = flat
        ? Icons.remove
        : (up ? Icons.trending_up : Icons.trending_down);
    final text = flat ? '與上期持平' : '${up ? '+' : ''}$delta 根';
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text(text,
                style: TextStyle(
                    color: color, fontSize: 20, fontWeight: FontWeight.bold)),
            const Text('vs 上一期',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _brandBar(String name, int count, int total) {
    final pct = total > 0 ? count / total : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 13)),
              Text('$count 根 (${(pct * 100).round()}%)',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: AppColors.surfaceLight,
              valueColor: const AlwaysStoppedAnimation(AppColors.amber),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}
