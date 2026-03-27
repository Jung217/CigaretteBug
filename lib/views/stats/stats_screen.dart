import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../providers/app_providers.dart';
import '../../utils/theme.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(recordsProvider);
    final brandDb = ref.read(brandDatabaseProvider);

    // Total stats
    int totalCost = 0;
    final Map<String, int> brandCounts = {};
    final Map<int, int> hourCounts = {};

    for (final r in records) {
      final brand = brandDb.findByBarcode(r.brandBarcode);
      if (brand != null) {
        totalCost += (brand.packPrice / brand.packSize).round();
        brandCounts[brand.nameZH] = (brandCounts[brand.nameZH] ?? 0) + 1;
      }
      hourCounts[r.createdAt.hour] = (hourCounts[r.createdAt.hour] ?? 0) + 1;
    }

    // Top brands
    final topBrands = brandCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('統計')),
      body: records.isEmpty
          ? const Center(
              child: Text(
                '還沒有記錄',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Summary cards
                Row(
                  children: [
                    _summaryCard('總計', '${records.length} 根', Icons.smoking_rooms),
                    const SizedBox(width: 12),
                    _summaryCard('花費', 'NT\$$totalCost', Icons.attach_money),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _summaryCard('品牌數', '${brandCounts.length}', Icons.collections_bookmark),
                    const SizedBox(width: 12),
                    _summaryCard(
                      '日均',
                      _dailyAvg(records),
                      Icons.trending_up,
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Brand ranking
                const Text(
                  '品牌排行',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                ...topBrands.take(5).map((e) => _brandBar(
                  e.key,
                  e.value,
                  records.length,
                )),

                const SizedBox(height: 24),

                // Hourly chart
                const Text(
                  '吸菸時段分佈',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 180,
                  child: BarChart(
                    BarChartData(
                      barGroups: List.generate(24, (hour) {
                        return BarChartGroupData(
                          x: hour,
                          barRods: [
                            BarChartRodData(
                              toY: (hourCounts[hour] ?? 0).toDouble(),
                              color: AppColors.amber,
                              width: 8,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(2),
                              ),
                            ),
                          ],
                        );
                      }),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (val, _) {
                              if (val.toInt() % 4 == 0) {
                                return Text(
                                  '${val.toInt()}',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 10,
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

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
            Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
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
              Text(name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
              Text(
                '$count 根 (${(pct * 100).round()}%)',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
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

  String _dailyAvg(List records) {
    if (records.isEmpty) return '0';
    final first = records.map((r) => r.createdAt).reduce(
      (a, b) => a.isBefore(b) ? a : b,
    );
    final days = DateTime.now().difference(first).inDays + 1;
    return (records.length / days).toStringAsFixed(1);
  }
}
