import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../providers/app_providers.dart';
import '../../../utils/theme.dart';

class TimeRangeSelector extends ConsumerWidget {
  const TimeRangeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(timeRangeProvider);
    final offset = ref.watch(dateOffsetProvider);

    return Column(
      children: [
        // Range tabs
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: TimeRange.values.map((r) {
            final selected = r == range;
            return GestureDetector(
              onTap: () {
                ref.read(timeRangeProvider.notifier).state = r;
                ref.read(dateOffsetProvider.notifier).state = 0;
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: selected ? AppColors.amber : AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _rangeLabel(r),
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.textSecondary,
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        // Date navigation
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left, color: AppColors.textSecondary),
              onPressed: () => ref.read(dateOffsetProvider.notifier).state--,
              iconSize: 20,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            Text(
              _dateRangeLabel(range, offset),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
              onPressed: offset < 0
                  ? () => ref.read(dateOffsetProvider.notifier).state++
                  : null,
              iconSize: 20,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ],
    );
  }

  String _rangeLabel(TimeRange r) {
    switch (r) {
      case TimeRange.day: return '日';
      case TimeRange.week: return '週';
      case TimeRange.month: return '月';
      case TimeRange.year: return '年';
    }
  }

  String _dateRangeLabel(TimeRange range, int offset) {
    final now = DateTime.now();
    final df = DateFormat('MM/dd');
    final mf = DateFormat('yyyy/MM');

    switch (range) {
      case TimeRange.day:
        final day = now.add(Duration(days: offset));
        return DateFormat('yyyy/MM/dd').format(day);
      case TimeRange.week:
        final weekStart = now.add(Duration(days: offset * 7));
        final monday = weekStart.subtract(Duration(days: weekStart.weekday - 1));
        final sunday = monday.add(const Duration(days: 6));
        return '${df.format(monday)} ~ ${df.format(sunday)}';
      case TimeRange.month:
        final target = DateTime(now.year, now.month + offset, 1);
        return mf.format(target);
      case TimeRange.year:
        return '${now.year + offset}';
    }
  }
}
