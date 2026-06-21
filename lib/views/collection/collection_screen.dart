import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/cigarette_brand.dart';
import '../../providers/app_providers.dart';
import '../../utils/theme.dart';
import '../../utils/pack_palette.dart';

class CollectionScreen extends ConsumerWidget {
  const CollectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(recordsProvider);
    final brandDb = ref.read(brandDatabaseProvider);

    final smokedBarcodes = records.map((r) => r.brandBarcode).toSet();
    final collected = <CigaretteBrand>[];
    final uncollected = <CigaretteBrand>[];
    for (final brand in brandDb.allBrands) {
      (smokedBarcodes.contains(brand.barcode) ? collected : uncollected)
          .add(brand);
    }
    final total = brandDb.allBrands.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('菸盒圖鑑')),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    '${collected.length} / $total',
                    style: const TextStyle(
                        color: AppColors.amber,
                        fontSize: 28,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text('已收集品牌',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : collected.length / total,
                      backgroundColor: AppColors.surfaceLight,
                      valueColor:
                          const AlwaysStoppedAnimation(AppColors.amber),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (collected.isNotEmpty) ...[
            _sectionHeader('已收集'),
            _brandGrid(context, collected, true, records),
          ],
          if (uncollected.isNotEmpty) ...[
            _sectionHeader('未收集'),
            _brandGrid(context, uncollected, false, records),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(title,
            style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _brandGrid(BuildContext context, List<CigaretteBrand> brands,
      bool unlocked, List records) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          childAspectRatio: 0.62,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
        ),
        delegate: SliverChildBuilderDelegate(
          (ctx, i) {
            final brand = brands[i];
            final count =
                records.where((r) => r.brandBarcode == brand.barcode).length;
            return _BrandCard(
              key: ValueKey(brand.barcode),
              brand: brand,
              unlocked: unlocked,
              count: count,
              onTap: unlocked
                  ? () => _showBrandDetail(context, brand, count)
                  : null,
            );
          },
          childCount: brands.length,
        ),
      ),
    );
  }

  void _showBrandDetail(BuildContext context, CigaretteBrand brand, int count) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Row(children: [
            SizedBox(
                width: 54,
                height: 74,
                child: CustomPaint(
                    painter: PackThumbPainter(
                        cuteify(Color(brand.colorValue)), true))),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(brand.nameZH,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                  Text(brand.name,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text('已收集 ×$count',
                      style: const TextStyle(
                          color: AppColors.amberLight,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ])),
          ]),
          const SizedBox(height: 16),
          _row('製造商', brand.manufacturer),
          _row('焦油', '${brand.tar} mg'),
          _row('尼古丁', '${brand.nicotine} mg'),
          _row('價格', 'NT\$${brand.packPrice} / ${brand.packSize} 根'),
          if (brand.productType == ProductType.heatStick)
            _row('類型', '加熱菸菸彈'),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  Widget _row(String l, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(l,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14)),
          Text(v,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
        ]),
      );
}

class _BrandCard extends StatelessWidget {
  final CigaretteBrand brand;
  final bool unlocked;
  final int count;
  final VoidCallback? onTap;

  const _BrandCard({
    super.key,
    required this.brand,
    required this.unlocked,
    required this.count,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final base =
        unlocked ? cuteify(Color(brand.colorValue)) : const Color(0xFF323236);
    final isHeat = brand.productType == ProductType.heatStick;

    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Expanded(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.85, end: 1.0),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            builder: (_, t, child) =>
                Transform.scale(scale: t, child: child),
            child: Stack(children: [
              Positioned.fill(
                child: CustomPaint(painter: PackThumbPainter(base, unlocked)),
              ),
              if (unlocked)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(brand.nameZH,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              shadows: [
                                Shadow(color: Colors.black54, blurRadius: 3)
                              ])),
                      if (count > 0)
                        Text('×$count',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 9)),
                    ]),
                  ),
                )
              else
                Center(
                  child: Icon(Icons.lock_outline,
                      color: AppColors.textSecondary.withValues(alpha: 0.4),
                      size: 18),
                ),
              if (unlocked && isHeat)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(4)),
                    child: const Text('加熱',
                        style: TextStyle(
                            color: AppColors.amberLight, fontSize: 8)),
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 3),
        Text(unlocked ? brand.nameZH : '???',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: unlocked
                    ? AppColors.textSecondary
                    : AppColors.textSecondary.withValues(alpha: 0.4),
                fontSize: 10)),
      ]),
    );
  }
}

/// Draws a single rounded "candy pack" (matches the home pile aesthetic).
class PackThumbPainter extends CustomPainter {
  final Color base;
  final bool unlocked;
  PackThumbPainter(this.base, this.unlocked);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * 0.72;
    final h = size.height * 0.88;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCenter(center: center, width: w, height: h);
    final r = Radius.circular(w * 0.22);
    final front = RRect.fromRectAndRadius(rect, r);

    // faux thickness
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.shift(const Offset(2, 4)), r),
      Paint()..color = packShade(base, -0.22),
    );
    // front gradient
    canvas.drawRRect(
      front,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [packShade(base, 0.16), base],
        ).createShader(rect),
    );
    if (unlocked) {
      // glossy rim + top highlight
      canvas.drawRRect(
        front.deflate(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white.withValues(alpha: 0.16),
      );
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(center.dx, center.dy - h * 0.28),
            width: w * 0.6,
            height: h * 0.13),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.14)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
  }

  @override
  bool shouldRepaint(covariant PackThumbPainter old) =>
      old.base != base || old.unlocked != unlocked;
}
