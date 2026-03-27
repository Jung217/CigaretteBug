import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/cigarette_brand.dart';
import '../../providers/app_providers.dart';
import '../../utils/theme.dart';

class CollectionScreen extends ConsumerWidget {
  const CollectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(recordsProvider);
    final brandDb = ref.read(brandDatabaseProvider);

    // Collect unique barcodes that user has smoked
    final smokedBarcodes = records.map((r) => r.brandBarcode).toSet();

    // Group: collected vs uncollected
    final collected = <CigaretteBrand>[];
    final uncollected = <CigaretteBrand>[];
    for (final brand in brandDb.allBrands) {
      if (smokedBarcodes.contains(brand.barcode)) {
        collected.add(brand);
      } else {
        uncollected.add(brand);
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('菸盒圖鑑')),
      body: CustomScrollView(
        slivers: [
          // Progress
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    '${collected.length} / ${brandDb.allBrands.length}',
                    style: const TextStyle(
                      color: AppColors.amber,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '已收集品牌',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: brandDb.allBrands.isEmpty
                          ? 0
                          : collected.length / brandDb.allBrands.length,
                      backgroundColor: AppColors.surfaceLight,
                      valueColor: const AlwaysStoppedAnimation(AppColors.amber),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Section: Collected
          if (collected.isNotEmpty) ...[
            _sectionHeader('已收集'),
            _brandGrid(collected, true, records),
          ],
          // Section: Uncollected
          if (uncollected.isNotEmpty) ...[
            _sectionHeader('未收集'),
            _brandGrid(uncollected, false, records),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          title,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _brandGrid(List<CigaretteBrand> brands, bool unlocked, List records) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          childAspectRatio: 0.65,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        delegate: SliverChildBuilderDelegate(
          (ctx, i) {
            final brand = brands[i];
            final count = records
                .where((r) => r.brandBarcode == brand.barcode)
                .length;
            return _BrandCard(brand: brand, unlocked: unlocked, count: count);
          },
          childCount: brands.length,
        ),
      ),
    );
  }
}

class _BrandCard extends StatelessWidget {
  final CigaretteBrand brand;
  final bool unlocked;
  final int count;

  const _BrandCard({
    required this.brand,
    required this.unlocked,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: unlocked
                  ? Color(brand.colorValue)
                  : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(6),
              border: unlocked
                  ? Border.all(color: AppColors.amber.withOpacity(0.5), width: 1)
                  : null,
            ),
            child: Center(
              child: unlocked
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          brand.nameZH,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                        ),
                        if (count > 0)
                          Text(
                            '×$count',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 9,
                            ),
                          ),
                      ],
                    )
                  : Icon(
                      Icons.lock_outline,
                      color: AppColors.textSecondary.withOpacity(0.3),
                      size: 20,
                    ),
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          unlocked ? brand.nameZH : '???',
          style: TextStyle(
            color: unlocked ? AppColors.textSecondary : AppColors.textSecondary.withOpacity(0.4),
            fontSize: 10,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
