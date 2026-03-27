import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:async';
import '../../../models/smoking_record.dart';
import '../../../providers/app_providers.dart';
import '../../../services/brand_database.dart';
import '../../../utils/theme.dart';
import '../../stats/stats_screen.dart';
import '../../collection/collection_screen.dart';
import '../../settings/settings_screen.dart';
import '../../scanner/scanner_screen.dart';

// ══════════════════════════════════════════════════════════════
//  Full-screen physics scene (YoiLog style)
//  - Entire screen is the physics world
//  - UI buttons are static collision bodies
//  - Cigarette boxes pile up with gravity
// ══════════════════════════════════════════════════════════════

class PhysicsScene extends ConsumerStatefulWidget {
  const PhysicsScene({super.key});

  @override
  ConsumerState<PhysicsScene> createState() => _PhysicsSceneState();
}

class _PhysicsSceneState extends ConsumerState<PhysicsScene>
    with SingleTickerProviderStateMixin {
  // Physics
  final List<_Box> _boxes = [];
  final List<_StaticCircle> _uiColliders = [];
  late Ticker _ticker;
  double _tiltX = 0;
  double _tiltY = 0;
  StreamSubscription? _accelSub;
  Size _screenSize = Size.zero;
  int _lastRecordCount = -1;
  final _rng = Random();

  // Drag state
  _Box? _dragTarget;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _accelSub = accelerometerEventStream().listen((event) {
      _tiltX = -event.x;
      _tiltY = event.y;
    });
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  // ── Sync boxes with records ──────────────────────────────────

  void _syncBoxes(List<SmokingRecord> records) {
    if (records.length == _lastRecordCount) return;
    final brandDb = ref.read(brandDatabaseProvider);
    final existingIds = _boxes.map((b) => b.record.id).toSet();

    for (final record in records) {
      if (existingIds.contains(record.id)) continue;
      final brand = brandDb.findByBarcode(record.brandBarcode);
      final aging = record.agingProgress;
      final isSlim = brand?.packType.name == 'slim';

      double w = isSlim ? 42 : 52;
      double h = isSlim ? 58 : 70;

      // Aged boxes are shorter (crushed)
      h *= (1.0 - aging * 0.4);

      _boxes.add(_Box(
        x: _screenSize.width / 2 + (_rng.nextDouble() - 0.5) * _screenSize.width * 0.5,
        y: -h - _rng.nextDouble() * 200, // start above screen
        vx: (_rng.nextDouble() - 0.5) * 2,
        vy: 0,
        w: w,
        h: h,
        rotation: (_rng.nextDouble() - 0.5) * 0.4,
        rotVel: (_rng.nextDouble() - 0.5) * 0.03,
        color: brand != null ? Color(brand.colorValue) : AppColors.ashGrey,
        label: brand?.nameZH ?? '?',
        aging: aging,
        record: record,
      ));
    }

    final recordIds = records.map((r) => r.id).toSet();
    _boxes.removeWhere((b) => !recordIds.contains(b.record.id));
    _lastRecordCount = records.length;
  }

  // ── Physics tick ─────────────────────────────────────────────

  void _onTick(Duration elapsed) {
    if (_screenSize == Size.zero) return;

    const gravity = 600.0; // px/s²
    const dt = 1.0 / 60.0;
    const friction = 0.985;
    const bounce = 0.3;
    final floorY = _screenSize.height;
    final wallR = _screenSize.width;

    for (final box in _boxes) {
      if (box == _dragTarget) continue; // skip dragged box

      // Gravity + tilt
      box.vy += gravity * dt;
      box.vx += _tiltX * 80 * dt;
      box.vy += (_tiltY - 9.8) * 30 * dt;

      // Velocity damping
      box.vx *= friction;
      box.vy *= friction;

      // Move
      box.x += box.vx * dt;
      box.y += box.vy * dt;
      box.rotation += box.rotVel;
      box.rotVel *= 0.97;

      // Floor
      if (box.y + box.h > floorY) {
        box.y = floorY - box.h;
        if (box.vy > 30) {
          box.vy = -box.vy * bounce;
          box.rotVel += (_rng.nextDouble() - 0.5) * 0.05;
        } else {
          box.vy = 0;
        }
      }

      // Walls
      if (box.x < 0) { box.x = 0; box.vx = box.vx.abs() * bounce; }
      if (box.x + box.w > wallR) { box.x = wallR - box.w; box.vx = -box.vx.abs() * bounce; }

      // Ceiling (let them come from above)
      if (box.y < -300) { box.y = -300; box.vy = 0; }

      // ── Collide with UI button colliders ──
      final bcx = box.x + box.w / 2;
      final bcy = box.y + box.h / 2;
      for (final circle in _uiColliders) {
        final dx = bcx - circle.cx;
        final dy = bcy - circle.cy;
        final dist = sqrt(dx * dx + dy * dy);
        final minDist = circle.r + max(box.w, box.h) / 2;
        if (dist < minDist && dist > 0.01) {
          final nx = dx / dist;
          final ny = dy / dist;
          final overlap = minDist - dist;
          box.x += nx * overlap;
          box.y += ny * overlap;
          // Reflect velocity
          final dot = box.vx * nx + box.vy * ny;
          if (dot < 0) {
            box.vx -= 2 * dot * nx * 0.5;
            box.vy -= 2 * dot * ny * 0.5;
            box.rotVel += nx * 0.02;
          }
        }
      }
    }

    // ── Box-box collisions ──
    for (int i = 0; i < _boxes.length; i++) {
      for (int j = i + 1; j < _boxes.length; j++) {
        final a = _boxes[i], b = _boxes[j];
        // Simple AABB overlap + push
        final overlapX = (a.w + b.w) / 2 - (a.x + a.w / 2 - b.x - b.w / 2).abs();
        final overlapY = (a.h + b.h) / 2 - (a.y + a.h / 2 - b.y - b.h / 2).abs();
        if (overlapX > 0 && overlapY > 0) {
          if (overlapX < overlapY) {
            final sign = (a.x + a.w / 2 > b.x + b.w / 2) ? 1.0 : -1.0;
            a.x += sign * overlapX / 2;
            b.x -= sign * overlapX / 2;
            final vSwap = (a.vx - b.vx) * 0.3;
            a.vx -= vSwap;
            b.vx += vSwap;
          } else {
            final sign = (a.y + a.h / 2 > b.y + b.h / 2) ? 1.0 : -1.0;
            a.y += sign * overlapY / 2;
            b.y -= sign * overlapY / 2;
            final vSwap = (a.vy - b.vy) * 0.3;
            a.vy -= vSwap;
            b.vy += vSwap;
          }
          a.rotVel += (_rng.nextDouble() - 0.5) * 0.01;
          b.rotVel += (_rng.nextDouble() - 0.5) * 0.01;
        }
      }
    }

    setState(() {});
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(filteredRecordsProvider);
    final range = ref.watch(timeRangeProvider);

    // Background: light beige → dark gray-black based on cigarette count
    const bgLight = Color(0xFFF5EDD6); // 淡米黃
    const bgDark = Color(0xFF1A1A1A);  // 深灰黑
    final smokiness = (records.length / 15).clamp(0.0, 1.0);
    final bgColor = Color.lerp(bgLight, bgDark, smokiness)!;

    return LayoutBuilder(builder: (context, constraints) {
      _screenSize = Size(constraints.maxWidth, constraints.maxHeight);
      _syncBoxes(records);

      // Register UI collider positions (called every frame but cheap)
      _uiColliders.clear();
      final sw = _screenSize.width;
      final sh = _screenSize.height;
      // "今週" label area - center of screen
      _uiColliders.add(_StaticCircle(sw / 2, sh * 0.48, 36));
      // + button
      _uiColliders.add(_StaticCircle(sw / 2, sh * 0.65, 28));
      // Left button (calendar)
      _uiColliders.add(_StaticCircle(sw * 0.18, sh * 0.38, 24));
      // Right button (collection)
      _uiColliders.add(_StaticCircle(sw * 0.82, sh * 0.38, 24));
      // Top-left (stats)
      _uiColliders.add(_StaticCircle(sw * 0.15, sh * 0.12, 22));
      // Top-right (settings)
      _uiColliders.add(_StaticCircle(sw * 0.85, sh * 0.12, 22));

      return GestureDetector(
        onPanStart: (d) {
          _dragTarget = _findBoxAt(d.localPosition);
        },
        onPanUpdate: (d) {
          if (_dragTarget != null) {
            _dragTarget!.x += d.delta.dx;
            _dragTarget!.y += d.delta.dy;
            _dragTarget!.vx = d.delta.dx * 8;
            _dragTarget!.vy = d.delta.dy * 8;
            _dragTarget!.rotVel = d.delta.dx * 0.003;
          }
        },
        onPanEnd: (_) {
          _dragTarget = null;
        },
        child: Stack(
          children: [
            // Background — gets darker as you smoke more
            Container(color: bgColor),

            // Render all boxes
            ..._boxes.map((box) => Positioned(
              left: box.x,
              top: box.y,
              child: Transform.rotate(
                angle: box.rotation,
                child: GestureDetector(
                  onTap: () => _showBoxDetail(box),
                  child: _CigBoxWidget(box: box),
                ),
              ),
            )),

            // ── Floating UI buttons (these are also collision bodies) ──
            // Adaptive colors: dark on light bg, light on dark bg
            ..._buildUI(sw, sh, range, records, smokiness, context, ref),
          ],
        ),
      );
    });
  }

  List<Widget> _buildUI(double sw, double sh, TimeRange range,
      List<SmokingRecord> records, double smokiness,
      BuildContext context, WidgetRef ref) {
    // Interpolate UI colors: brown-ish on light bg → light gray on dark bg
    final uiColor = Color.lerp(
      const Color(0xFF6B5B3E), // warm brown for light bg
      AppColors.textSecondary,  // light gray for dark bg
      smokiness,
    )!;
    final borderColor = uiColor.withAlpha(lerpDouble(100, 60, smokiness).round());
    final iconColor = uiColor.withAlpha(lerpDouble(200, 150, smokiness).round());
    final textColor = Color.lerp(const Color(0xFF3D3326), AppColors.textPrimary, smokiness)!;
    final countColor = uiColor.withAlpha(lerpDouble(80, 60, smokiness).round());

    return [
      // Stats (top-left)
      _buildFloatingButton(
        left: sw * 0.15 - 22, top: sh * 0.12 - 22,
        icon: Icons.bar_chart_rounded,
        borderColor: borderColor, iconColor: iconColor,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StatsScreen())),
      ),
      // Settings (top-right)
      _buildFloatingButton(
        left: sw * 0.85 - 22, top: sh * 0.12 - 22,
        icon: Icons.settings_rounded,
        borderColor: borderColor, iconColor: iconColor,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
      ),
      // Calendar (left)
      _buildFloatingButton(
        left: sw * 0.18 - 24, top: sh * 0.38 - 24,
        icon: Icons.calendar_month_rounded, size: 48,
        borderColor: borderColor, iconColor: iconColor,
        onTap: () => _cycleTimeRange(ref),
      ),
      // Collection (right)
      _buildFloatingButton(
        left: sw * 0.82 - 24, top: sh * 0.38 - 24,
        icon: Icons.collections_bookmark_rounded, size: 48,
        borderColor: borderColor, iconColor: iconColor,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CollectionScreen())),
      ),
      // Time range label
      Positioned(
        left: sw / 2 - 45, top: sh * 0.48 - 20,
        child: GestureDetector(
          onTap: () => _cycleTimeRange(ref),
          onHorizontalDragEnd: (d) {
            if (d.primaryVelocity != null) {
              if (d.primaryVelocity! < -100) {
                ref.read(dateOffsetProvider.notifier).state--;
              } else if (d.primaryVelocity! > 100) {
                ref.read(dateOffsetProvider.notifier).state++;
              }
            }
          },
          child: Container(
            width: 90, height: 40,
            decoration: BoxDecoration(
              border: Border.all(color: borderColor, width: 1.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                _timeRangeLabel(range),
                style: TextStyle(
                  color: textColor,
                  fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: 1,
                ),
              ),
            ),
          ),
        ),
      ),
      // Add (+) button
      Positioned(
        left: sw / 2 - 28, top: sh * 0.65 - 28,
        child: GestureDetector(
          onTap: () => _showAddMenu(context, ref),
          child: Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: borderColor, width: 1.2),
            ),
            child: Icon(Icons.add, color: iconColor, size: 28),
          ),
        ),
      ),
      // Count badge
      if (records.isNotEmpty)
        Positioned(
          top: sh * 0.04, left: 0, right: 0,
          child: Center(
            child: Text(
              '${records.length}',
              style: TextStyle(
                color: countColor,
                fontSize: 48, fontWeight: FontWeight.w200,
              ),
            ),
          ),
        ),
    ];
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;

  Widget _buildFloatingButton({
    required double left,
    required double top,
    required IconData icon,
    required VoidCallback onTap,
    required Color borderColor,
    required Color iconColor,
    double size = 44,
  }) {
    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Icon(icon, color: iconColor, size: size * 0.5),
        ),
      ),
    );
  }

  String _timeRangeLabel(TimeRange range) {
    switch (range) {
      case TimeRange.day: return '今日';
      case TimeRange.week: return '今週';
      case TimeRange.month: return '今月';
      case TimeRange.year: return '今年';
    }
  }

  void _cycleTimeRange(WidgetRef ref) {
    final current = ref.read(timeRangeProvider);
    final values = TimeRange.values;
    final next = values[(values.indexOf(current) + 1) % values.length];
    ref.read(timeRangeProvider.notifier).state = next;
    ref.read(dateOffsetProvider.notifier).state = 0;
  }

  _Box? _findBoxAt(Offset pos) {
    // Find topmost box at touch position
    for (int i = _boxes.length - 1; i >= 0; i--) {
      final b = _boxes[i];
      if (pos.dx >= b.x && pos.dx <= b.x + b.w &&
          pos.dy >= b.y && pos.dy <= b.y + b.h) {
        return b;
      }
    }
    return null;
  }

  void _showAddMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final brandDb = ref.read(brandDatabaseProvider);
        final brands = brandDb.allBrands;

        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (_, sc) => Column(
            children: [
              const SizedBox(height: 12),
              Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Text('選擇品牌', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const ScannerScreen()));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.amber),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.qr_code_scanner, color: AppColors.amber, size: 16),
                            SizedBox(width: 4),
                            Text('掃描', style: TextStyle(color: AppColors.amber, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: sc,
                  itemCount: brands.length,
                  itemBuilder: (_, i) {
                    final brand = brands[i];
                    return ListTile(
                      leading: Container(
                        width: 36, height: 48,
                        decoration: BoxDecoration(
                          color: Color(brand.colorValue),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Center(child: Text(brand.nameZH.length > 2 ? brand.nameZH.substring(0, 2) : brand.nameZH, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold))),
                      ),
                      title: Text(brand.nameZH, style: const TextStyle(color: AppColors.textPrimary)),
                      subtitle: Text('${brand.name} · NT\$${brand.packPrice}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      trailing: brand.productType.name == 'heatStick'
                          ? const Text('加熱菸', style: TextStyle(color: AppColors.amber, fontSize: 11))
                          : null,
                      onTap: () {
                        ref.read(recordsProvider.notifier).addRecord(SmokingRecord(brandBarcode: brand.barcode));
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showBoxDetail(_Box box) {
    final brandDb = ref.read(brandDatabaseProvider);
    final brand = brandDb.findByBarcode(box.record.brandBarcode);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Row(children: [
              Container(
                width: 48, height: 66,
                decoration: BoxDecoration(color: box.color, borderRadius: BorderRadius.circular(5),
                  boxShadow: [BoxShadow(color: box.color.withAlpha(80), blurRadius: 12, offset: const Offset(0, 4))]),
                child: Center(child: Text(box.label, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(brand?.nameZH ?? '?', style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                Text(brand?.name ?? '', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ])),
            ]),
            const SizedBox(height: 16),
            if (brand != null) ...[
              _row('製造商', brand.manufacturer),
              _row('焦油', '${brand.tar} mg'),
              _row('尼古丁', '${brand.nicotine} mg'),
              _row('價格', 'NT\$${brand.packPrice}'),
            ],
            _row('老化', '${(box.aging * 100).round()}%'),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _row(String l, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
      Text(v, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
    ]),
  );
}

// ══════════════════════════════════════════════════════════════
//  Cigarette box widget (3D-ish rendering)
// ══════════════════════════════════════════════════════════════

class _CigBoxWidget extends StatelessWidget {
  final _Box box;
  const _CigBoxWidget({required this.box});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: box.w + 6, // extra space for 3D side
      height: box.h + 6,
      child: CustomPaint(
        painter: _BoxPainter(box),
      ),
    );
  }
}

class _BoxPainter extends CustomPainter {
  final _Box box;
  _BoxPainter(this.box);

  @override
  void paint(Canvas canvas, Size size) {
    final aging = box.aging;
    final w = box.w;
    final h = box.h;
    final sideW = 6.0; // 3D side width
    final topH = 4.0;  // 3D top height

    // ── Shadow ──
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(3, 5, w, h).inflate(2),
        const Radius.circular(4),
      ),
      Paint()
        ..color = Colors.black.withAlpha(50)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // ── Right side (3D depth) ──
    final sidePath = Path()
      ..moveTo(w, topH)
      ..lineTo(w + sideW, 0)
      ..lineTo(w + sideW, h - 2)
      ..lineTo(w, h + topH)
      ..close();
    canvas.drawPath(sidePath, Paint()..color = _darken(box.color, 0.3).withAlpha(aging > 0.7 ? 120 : 220));

    // ── Top face (3D depth) ──
    final topPath = Path()
      ..moveTo(0, topH)
      ..lineTo(sideW, 0)
      ..lineTo(w + sideW, 0)
      ..lineTo(w, topH)
      ..close();
    canvas.drawPath(topPath, Paint()..color = _lighten(box.color, 0.2).withAlpha(aging > 0.7 ? 120 : 220));

    // ── Front face ──
    final frontRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, topH, w, h),
      const Radius.circular(3),
    );

    // Gradient for front face
    canvas.drawRRect(frontRect, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          _lighten(box.color, 0.1),
          box.color,
          _darken(box.color, 0.1),
        ],
      ).createShader(Rect.fromLTWH(0, topH, w, h)));

    // ── Highlight strip (top of front face) ──
    if (aging < 0.5) {
      canvas.drawRect(
        Rect.fromLTWH(2, topH + 1, w - 4, 3),
        Paint()..color = Colors.white.withAlpha((30 * (1 - aging * 2)).round()),
      );
    }

    // ── Brand label ──
    final tp = TextPainter(
      text: TextSpan(
        text: box.label,
        style: TextStyle(
          color: Colors.white.withAlpha((240 * (1.0 - aging * 0.3)).round()),
          fontSize: w > 48 ? 12 : 10,
          fontWeight: FontWeight.bold,
          height: 1.2,
          shadows: [Shadow(color: Colors.black.withAlpha(120), blurRadius: 2)],
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 2,
    );
    tp.layout(maxWidth: w - 8);
    tp.paint(canvas, Offset((w - tp.width) / 2, topH + (h - tp.height) / 2));

    // ── Aging dirt overlay ──
    if (aging > 0.15) {
      canvas.drawRRect(frontRect, Paint()..color = const Color(0xFF3D2B15).withAlpha((aging * 70).round()));

      // Crumple lines
      if (aging > 0.35) {
        final lp = Paint()
          ..color = Colors.black.withAlpha((aging * 30).round())
          ..strokeWidth = 0.7;
        for (int i = 0; i < (aging * 4).round(); i++) {
          final ly = topH + h * (0.2 + i * 0.18);
          canvas.drawLine(Offset(3, ly), Offset(w - 3, ly + 1.5), lp);
        }
      }
    }

    // ── Front face border ──
    canvas.drawRRect(
      frontRect,
      Paint()
        ..color = Colors.white.withAlpha(aging > 0.5 ? 8 : 20)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  Color _lighten(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 0.95)).toColor();
  }

  Color _darken(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness - amount).clamp(0.05, 1.0)).toColor();
  }

  @override
  bool shouldRepaint(covariant _BoxPainter old) => true;
}

// ══════════════════════════════════════════════════════════════
//  Data classes
// ══════════════════════════════════════════════════════════════

class _Box {
  double x, y, vx, vy;
  double w, h;
  double rotation, rotVel;
  final Color color;
  final String label;
  final double aging;
  final SmokingRecord record;

  _Box({
    required this.x, required this.y,
    required this.vx, required this.vy,
    required this.w, required this.h,
    required this.rotation, required this.rotVel,
    required this.color, required this.label,
    required this.aging, required this.record,
  });
}

class _StaticCircle {
  final double cx, cy, r;
  _StaticCircle(this.cx, this.cy, this.r);
}
