import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/app_providers.dart';
import '../../../utils/theme.dart';

class StatsHeader extends ConsumerWidget {
  const StatsHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(filteredRecordsProvider);
    final brandDb = ref.read(brandDatabaseProvider);

    int totalCost = 0;
    for (final r in records) {
      final brand = brandDb.findByBarcode(r.brandBarcode);
      if (brand != null) {
        totalCost += (brand.packPrice / brand.packSize).round();
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.local_fire_department, color: AppColors.amber, size: 20),
          const SizedBox(width: 4),
          Text(
            '${records.length} 根',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 16),
          const Text('｜', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(width: 16),
          Text(
            'NT\$$totalCost',
            style: const TextStyle(
              color: AppColors.amberLight,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
