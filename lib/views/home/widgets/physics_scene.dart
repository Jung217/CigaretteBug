import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:forge2d/forge2d.dart' hide Transform;

import '../../../models/smoking_record.dart';
import '../../../providers/app_providers.dart';
import '../../../services/brand_database.dart';
import '../../../utils/theme.dart';
import '../../stats/stats_screen.dart';
import '../../collection/collection_screen.dart';
import '../../settings/settings_screen.dart';
import '../../scanner/scanner_screen.dart';

// ══════════════════════════════════════════════════════════════
//  Full-screen physics scene
//  • forge2d (Box2D) rigid-body simulation
//  • True 3D box rendering: perspective projection, face sorting,
//    back-face culling, per-face lighting, depth-correct overlap
// ══════════════════════════════════════════════════════════════

const double _ppm = 50.0;
const double _tilt = 0.38; // scene X-tilt (rad) — shows box tops
const _cosT = 0.9267; // cos(0.38)
const _sinT = 0.3709; // sin(0.38)
// Light direction (upper-left, toward viewer), pre-normalized
const _lx = 0.228, _ly = -0.683, _lz = 0.693;

class PhysicsScene extends ConsumerStatefulWidget {
  const PhysicsScene({super.key});
  @override
  ConsumerState<PhysicsScene> createState() => _PhysicsSceneState();
}

class _PhysicsSceneState extends ConsumerState<PhysicsScene>
    with SingleTickerProviderStateMixin {
  // ── forge2d ──
  late final World _world;
  late final Body _ground;
  final List<_CigBody> _cigs = [];
  final List<Body> _walls = [];
  final List<Body> _uiBodies = [];
  MouseJoint? _mouseJoint;
  _CigBody? _dragTarget;
  final Vector2 _dragPt = Vector2.zero();

  // ── Sensors ──
  StreamSubscription? _accelSub;
  double _ax = 0, _ay = 9.8;

  // ── State ──
  late Ticker _ticker;
  Duration _prev = Duration.zero;
  Size _sz = Size.zero;
  bool _ready = false;
  int _lastN = -1;
  final _rng = Random();

  // ─────────────────── lifecycle ───────────────────

  @override
  void initState() {
    super.initState();
    _world = World(Vector2(0, 9.8));
    _ground = _world.createBody(BodyDef());
    _ticker = createTicker(_step)..start();
    _accelSub = accelerometerEventStream().listen((e) {
      _ax = e.x;
      _ay = e.y;
    });
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  // ─────────────────── world setup ───────────────────

  void _buildWalls() {
    if (_ready) return;
    _ready = true;
    final w = _sz.width / _ppm, h = _sz.height / _ppm;
    _walls.add(_edge(Vector2(-0.5, h), Vector2(w + 0.5, h)));
    _walls.add(_edge(Vector2(-0.5, -8), Vector2(-0.5, h)));
    _walls.add(_edge(Vector2(w + 0.5, -8), Vector2(w + 0.5, h)));
    _walls.add(_edge(Vector2(-0.5, -8), Vector2(w + 0.5, -8)));
  }

  Body _edge(Vector2 a, Vector2 b) {
    final body = _world.createBody(BodyDef());
    body.createFixture(FixtureDef(EdgeShape()..set(a, b), friction: 0.5, restitution: 0.15));
    return body;
  }

  void _placeUI() {
    for (final b in _uiBodies) _world.destroyBody(b);
    _uiBodies.clear();
    final sw = _sz.width, sh = _sz.height;
    _uiBodies.add(_disc(sw / 2, sh * 0.48, 38));
    _uiBodies.add(_disc(sw / 2, sh * 0.65, 30));
    _uiBodies.add(_disc(sw * 0.18, sh * 0.38, 26));
    _uiBodies.add(_disc(sw * 0.82, sh * 0.38, 26));
    _uiBodies.add(_disc(sw * 0.15, sh * 0.12, 24));
    _uiBodies.add(_disc(sw * 0.85, sh * 0.12, 24));
  }

  Body _disc(double cx, double cy, double r) {
    final body = _world.createBody(BodyDef(type: BodyType.static, position: Vector2(cx / _ppm, cy / _ppm)));
    body.createFixture(FixtureDef(CircleShape(radius: r / _ppm), friction: 0.3, restitution: 0.4));
    return body;
  }

  // ─────────────────── sync records ───────────────────

  void _sync(List<SmokingRecord> recs) {
    if (recs.length == _lastN) return;
    final db = ref.read(brandDatabaseProvider);
    final have = _cigs.map((c) => c.rec.id).toSet();
    for (final r in recs) {
      if (have.contains(r.id)) continue;
      final brand = db.findByBarcode(r.brandBarcode);
      final aging = r.agingProgress;
      final slim = brand?.packType.name == 'slim';
      double wPx = slim ? 42.0 : 52.0;
      double hPx = (slim ? 58.0 : 70.0) * (1.0 - aging * 0.35);
      double dPx = wPx * 0.45; // depth

      final sx = _sz.width * 0.15 + _rng.nextDouble() * _sz.width * 0.7;
      final sy = -hPx - _rng.nextDouble() * 100;
      final body = _world.createBody(BodyDef(
        type: BodyType.dynamic,
        position: Vector2(sx / _ppm, sy / _ppm),
        angle: (_rng.nextDouble() - 0.5) * 0.4,
        angularDamping: 2.5, linearDamping: 0.3,
      ));
      body.createFixture(FixtureDef(
        PolygonShape()..setAsBoxXY(wPx / _ppm / 2, hPx / _ppm / 2),
        density: 1.0, friction: 0.55, restitution: 0.1,
      ));
      _cigs.add(_CigBody(
        body: body, wPx: wPx, hPx: hPx, dPx: dPx,
        color: brand != null ? Color(brand.colorValue) : AppColors.ashGrey,
        label: brand?.nameZH ?? '?', aging: aging, rec: r,
      ));
    }
    final ids = recs.map((r) => r.id).toSet();
    _cigs.removeWhere((c) {
      if (!ids.contains(c.rec.id)) { _world.destroyBody(c.body); return true; }
      return false;
    });
    _lastN = recs.length;
  }

  // ─────────────────── physics step ───────────────────

  void _step(Duration now) {
    if (_sz == Size.zero) return;
    final dt = _prev == Duration.zero ? 1 / 60.0 : (now - _prev).inMicroseconds / 1e6;
    _prev = now;
    _world.gravity.setValues(_ax, _ay.clamp(2.0, 18.0));
    _world.stepDt(dt.clamp(0.001, 0.034));
    setState(() {});
  }

  // ─────────────────── drag ───────────────────

  _CigBody? _hit(Offset p) {
    final wx = p.dx / _ppm, wy = p.dy / _ppm;
    for (int i = _cigs.length - 1; i >= 0; i--) {
      final c = _cigs[i];
      final bp = c.body.position;
      final r = sqrt(pow(c.wPx / _ppm / 2, 2) + pow(c.hPx / _ppm / 2, 2));
      if (pow(wx - bp.x, 2) + pow(wy - bp.y, 2) < r * r) return c;
    }
    return null;
  }

  void _dragStart(Offset pos) {
    final t = _hit(pos);
    if (t == null) return;
    _dragTarget = t;
    _dragPt.setValues(pos.dx / _ppm, pos.dy / _ppm);
    final mjd = MouseJointDef()
      ..bodyA = _ground ..bodyB = t.body
      ..maxForce = 500.0 * t.body.mass ..frequencyHz = 12.0 ..dampingRatio = 0.7;
    mjd.target.setFrom(_dragPt);
    _mouseJoint = MouseJoint(mjd);
    _world.createJoint(_mouseJoint!);
    t.body.setAwake(true);
  }

  void _dragUpdate(Offset pos) {
    if (_mouseJoint == null) return;
    _dragPt.setValues(pos.dx / _ppm, pos.dy / _ppm);
    _mouseJoint!.setTarget(_dragPt);
  }

  void _dragEnd(DragEndDetails d) {
    if (_dragTarget != null && _mouseJoint != null) {
      final v = d.velocity.pixelsPerSecond;
      _dragTarget!.body.linearVelocity = Vector2(v.dx / _ppm * 0.5, v.dy / _ppm * 0.5);
    }
    if (_mouseJoint != null) { _world.destroyJoint(_mouseJoint!); _mouseJoint = null; }
    _dragTarget = null;
  }

  // ─────────────────── build ───────────────────

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(filteredRecordsProvider);
    final range = ref.watch(timeRangeProvider);
    const bgLight = Color(0xFFF5EDD6);
    const bgDark = Color(0xFF1A1A1A);
    final smoke = (records.length / 15).clamp(0.0, 1.0);
    final bg = Color.lerp(bgLight, bgDark, smoke)!;

    return LayoutBuilder(builder: (ctx, box) {
      final newSz = Size(box.maxWidth, box.maxHeight);
      if (newSz != _sz) { _sz = newSz; _buildWalls(); _placeUI(); }
      if (_ready) _sync(records);
      final sw = _sz.width, sh = _sz.height;

      return GestureDetector(
        onTapUp: (d) { final c = _hit(d.localPosition); if (c != null) _showDetail(c); },
        onPanStart: (d) => _dragStart(d.localPosition),
        onPanUpdate: (d) => _dragUpdate(d.localPosition),
        onPanEnd: (d) => _dragEnd(d),
        child: Stack(clipBehavior: Clip.none, children: [
          Container(color: bg),
          // ── 3D scene ──
          RepaintBoundary(
            child: CustomPaint(size: _sz, painter: _Scene3DPainter(_cigs)),
          ),
          // ── UI overlay ──
          ..._buildUI(sw, sh, range, records, smoke, context, ref),
        ]),
      );
    });
  }

  // ─────────────────── UI ───────────────────

  List<Widget> _buildUI(double sw, double sh, TimeRange range,
      List<SmokingRecord> records, double smoke, BuildContext context, WidgetRef ref) {
    final uiColor = Color.lerp(const Color(0xFF6B5B3E), AppColors.textSecondary, smoke)!;
    final bc = uiColor.withAlpha(_l(100, 60, smoke));
    final ic = uiColor.withAlpha(_l(200, 150, smoke));
    final tc = Color.lerp(const Color(0xFF3D3326), AppColors.textPrimary, smoke)!;
    final cc = uiColor.withAlpha(_l(80, 60, smoke));
    return [
      _btn(sw * 0.15 - 22, sh * 0.12 - 22, Icons.bar_chart_rounded, bc, ic,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StatsScreen()))),
      _btn(sw * 0.85 - 22, sh * 0.12 - 22, Icons.settings_rounded, bc, ic,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
      _btn(sw * 0.18 - 24, sh * 0.38 - 24, Icons.calendar_month_rounded, bc, ic,
          () => _cycleTimeRange(ref), size: 48),
      _btn(sw * 0.82 - 24, sh * 0.38 - 24, Icons.collections_bookmark_rounded, bc, ic,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CollectionScreen())), size: 48),
      Positioned(left: sw / 2 - 45, top: sh * 0.48 - 20, child: GestureDetector(
        onTap: () => _cycleTimeRange(ref),
        onHorizontalDragEnd: (d) {
          if (d.primaryVelocity != null) {
            if (d.primaryVelocity! < -100) ref.read(dateOffsetProvider.notifier).state--;
            else if (d.primaryVelocity! > 100) ref.read(dateOffsetProvider.notifier).state++;
          }
        },
        child: Container(width: 90, height: 40,
          decoration: BoxDecoration(border: Border.all(color: bc, width: 1.2), borderRadius: BorderRadius.circular(8)),
          child: Center(child: Text(_rangeLabel(range), style: TextStyle(color: tc, fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: 1)))),
      )),
      Positioned(left: sw / 2 - 28, top: sh * 0.65 - 28, child: GestureDetector(
        onTap: () => _showAddMenu(context, ref),
        child: Container(width: 56, height: 56,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: bc, width: 1.2)),
          child: Icon(Icons.add, color: ic, size: 28)),
      )),
      if (records.isNotEmpty) Positioned(top: sh * 0.04, left: 0, right: 0,
        child: Center(child: Text('${records.length}', style: TextStyle(color: cc, fontSize: 48, fontWeight: FontWeight.w200)))),
    ];
  }

  static int _l(double a, double b, double t) => (a + (b - a) * t).round();
  Widget _btn(double l, double t, IconData ic, Color bc, Color ic2, VoidCallback tap, {double size = 44}) =>
    Positioned(left: l, top: t, child: GestureDetector(onTap: tap,
      child: Container(width: size, height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: bc, width: 1)),
        child: Icon(ic, color: ic2, size: size * 0.5))));
  String _rangeLabel(TimeRange r) => switch (r) { TimeRange.day => '今日', TimeRange.week => '今週', TimeRange.month => '今月', TimeRange.year => '今年' };
  void _cycleTimeRange(WidgetRef ref) {
    final cur = ref.read(timeRangeProvider); final v = TimeRange.values;
    ref.read(timeRangeProvider.notifier).state = v[(v.indexOf(cur) + 1) % v.length];
    ref.read(dateOffsetProvider.notifier).state = 0;
  }

  // ─────────────────── bottom sheets ───────────────────

  void _showAddMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(context: context, backgroundColor: AppColors.surface, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        final brands = ref.read(brandDatabaseProvider).allBrands;
        return DraggableScrollableSheet(initialChildSize: 0.6, minChildSize: 0.3, maxChildSize: 0.85, expand: false,
          builder: (_, sc) => Column(children: [
            const SizedBox(height: 12),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(2))),
            Padding(padding: const EdgeInsets.all(16), child: Row(children: [
              const Text('選擇品牌', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              GestureDetector(
                onTap: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (_) => const ScannerScreen())); },
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(border: Border.all(color: AppColors.amber), borderRadius: BorderRadius.circular(16)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.qr_code_scanner, color: AppColors.amber, size: 16), SizedBox(width: 4),
                    Text('掃描', style: TextStyle(color: AppColors.amber, fontSize: 13))]))),
            ])),
            Expanded(child: ListView.builder(controller: sc, itemCount: brands.length, itemBuilder: (_, i) {
              final brand = brands[i];
              return ListTile(
                leading: Container(width: 36, height: 48,
                  decoration: BoxDecoration(color: Color(brand.colorValue), borderRadius: BorderRadius.circular(4)),
                  child: Center(child: Text(brand.nameZH.length > 2 ? brand.nameZH.substring(0, 2) : brand.nameZH,
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)))),
                title: Text(brand.nameZH, style: const TextStyle(color: AppColors.textPrimary)),
                subtitle: Text('${brand.name} · NT\$${brand.packPrice}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                trailing: brand.productType.name == 'heatStick' ? const Text('加熱菸', style: TextStyle(color: AppColors.amber, fontSize: 11)) : null,
                onTap: () { ref.read(recordsProvider.notifier).addRecord(SmokingRecord(brandBarcode: brand.barcode)); Navigator.pop(ctx); },
              );
            })),
          ]));
      });
  }

  void _showDetail(_CigBody c) {
    final brand = ref.read(brandDatabaseProvider).findByBarcode(c.rec.brandBarcode);
    showModalBottomSheet(context: context, backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Row(children: [
          Container(width: 48, height: 66,
            decoration: BoxDecoration(color: c.color, borderRadius: BorderRadius.circular(5),
              boxShadow: [BoxShadow(color: c.color.withAlpha(80), blurRadius: 12, offset: const Offset(0, 4))]),
            child: Center(child: Text(c.label, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold), textAlign: TextAlign.center))),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(brand?.nameZH ?? '?', style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
            Text(brand?.name ?? '', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))])),
        ]),
        const SizedBox(height: 16),
        if (brand != null) ...[
          _row('製造商', brand.manufacturer), _row('焦油', '${brand.tar} mg'),
          _row('尼古丁', '${brand.nicotine} mg'), _row('價格', 'NT\$${brand.packPrice}'),
        ],
        _row('老化', '${(c.aging * 100).round()}%'), const SizedBox(height: 12),
      ])));
  }

  Widget _row(String l, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
      Text(v, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500))]));
}

// ══════════════════════════════════════════════════════════════
//  3D Scene Painter
//  — Renders all cigarette boxes as true 3D rectangular prisms
//  — Per-face lighting, back-face culling, depth-sorted overlap
// ══════════════════════════════════════════════════════════════

class _Scene3DPainter extends CustomPainter {
  final List<_CigBody> cigs;
  _Scene3DPainter(this.cigs);

  // Face definitions: [v0,v1,v2,v3], normal (nx,ny,nz)
  // Vertex layout per box:
  //   Front (z+): 0=TL 1=TR 2=BR 3=BL
  //   Back  (z-): 4=TL 5=TR 6=BR 7=BL
  static const _faces = [
    [0, 1, 2, 3, 0.0, 0.0, 1.0],   // front
    [5, 4, 7, 6, 0.0, 0.0, -1.0],  // back
    [4, 5, 1, 0, 0.0, -1.0, 0.0],  // top
    [3, 2, 6, 7, 0.0, 1.0, 0.0],   // bottom
    [1, 5, 6, 2, 1.0, 0.0, 0.0],   // right
    [4, 0, 3, 7, -1.0, 0.0, 0.0],  // left
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final allFaces = <_RF>[];
    final shadowPaint = Paint()
      ..color = Colors.black.withAlpha(40)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    for (final c in cigs) {
      final pos = c.body.position;
      final ang = c.body.angle;
      final px = pos.x * _ppm, py = pos.y * _ppm;
      final hw = c.wPx / 2, hh = c.hPx / 2, hd = c.dPx / 2;
      final cosA = cos(ang), sinA = sin(ang);

      // 8 local vertices → transform → screen
      final sv = List<_V3>.generate(8, (_) => _V3(0, 0, 0));
      final lx = [-hw, hw, hw, -hw, -hw, hw, hw, -hw];
      final ly = [-hh, -hh, hh, hh, -hh, -hh, hh, hh];
      final lz = [hd, hd, hd, hd, -hd, -hd, -hd, -hd];

      for (int i = 0; i < 8; i++) {
        // Z-rotate (physics angle)
        final x1 = lx[i] * cosA - ly[i] * sinA;
        final y1 = lx[i] * sinA + ly[i] * cosA;
        final z1 = lz[i];
        // X-tilt (scene camera)
        sv[i] = _V3(
          x1 + px,
          y1 * _cosT + z1 * _sinT + py,
          -y1 * _sinT + z1 * _cosT,
        );
      }

      // Shadow (projected center on "floor")
      canvas.drawOval(
        Rect.fromCenter(center: Offset(px + 3, py + 5), width: c.wPx * 0.9, height: c.hPx * 0.35),
        shadowPaint,
      );

      // Build visible faces
      for (final f in _faces) {
        final i0 = f[0] as int, i1 = f[1] as int, i2 = f[2] as int, i3 = f[3] as int;
        final nx0 = f[4] as double, ny0 = f[5] as double, nz0 = f[6] as double;

        // Transform normal
        final nx1 = nx0 * cosA - ny0 * sinA;
        final ny1 = nx0 * sinA + ny0 * cosA;
        final nz1 = nz0;
        final ny2 = ny1 * _cosT + nz1 * _sinT;
        final nz2 = -ny1 * _sinT + nz1 * _cosT;

        if (nz2 <= 0.01) continue; // back-face cull

        // Lighting
        final dot = nx1 * _lx + ny2 * _ly + nz2 * _lz;
        final bright = (dot * 0.45 + 0.55).clamp(0.25, 1.0);

        // Face color (front gets brand color, top lighter, sides darker)
        Color fc;
        if (nz0 > 0.5) {
          fc = c.color; // front
        } else if (ny0 < -0.5) {
          fc = _lighten(c.color, 0.18); // top
        } else {
          fc = _darken(c.color, 0.12); // sides
        }
        fc = Color.lerp(Colors.black, fc, bright)!;
        if (c.aging > 0.15) fc = Color.lerp(fc, const Color(0xFF3D2B15), c.aging * 0.3)!;

        // Depth (average Z of 4 verts)
        final depth = (sv[i0].z + sv[i1].z + sv[i2].z + sv[i3].z) / 4;

        allFaces.add(_RF(
          Offset(sv[i0].x, sv[i0].y), Offset(sv[i1].x, sv[i1].y),
          Offset(sv[i2].x, sv[i2].y), Offset(sv[i3].x, sv[i3].y),
          fc, depth,
          isFront: nz0 > 0.5,
          label: nz0 > 0.5 ? c.label : null,
          aging: c.aging,
          faceW: c.wPx,
        ));
      }
    }

    // Sort back-to-front (ascending Z = farthest first)
    allFaces.sort((a, b) => a.depth.compareTo(b.depth));

    // Paint all faces
    final borderPaint = Paint()..style = PaintingStyle.stroke ..strokeWidth = 0.7;
    for (final f in allFaces) {
      final path = Path()
        ..moveTo(f.p0.dx, f.p0.dy)
        ..lineTo(f.p1.dx, f.p1.dy)
        ..lineTo(f.p2.dx, f.p2.dy)
        ..lineTo(f.p3.dx, f.p3.dy)
        ..close();

      // Fill
      canvas.drawPath(path, Paint()..color = f.color);

      // Subtle edge
      borderPaint.color = Colors.white.withAlpha(f.aging > 0.5 ? 6 : 18);
      canvas.drawPath(path, borderPaint);

      // Front face: brand label + aging details
      if (f.isFront && f.label != null) {
        _drawLabel(canvas, f);
        if (f.aging > 0.35) _drawCrumple(canvas, f);
      }
    }
  }

  void _drawLabel(Canvas canvas, _RF f) {
    // Face center and approximate width
    final cx = (f.p0.dx + f.p1.dx + f.p2.dx + f.p3.dx) / 4;
    final cy = (f.p0.dy + f.p1.dy + f.p2.dy + f.p3.dy) / 4;
    final faceW = (f.p1 - f.p0).distance;
    final fontSize = (faceW > 40 ? 11.0 : 9.0).clamp(7.0, 13.0);

    final tp = TextPainter(
      text: TextSpan(text: f.label!, style: TextStyle(
        color: Colors.white.withAlpha((230 * (1.0 - f.aging * 0.3)).round()),
        fontSize: fontSize, fontWeight: FontWeight.bold, height: 1.2,
        shadows: [Shadow(color: Colors.black.withAlpha(150), blurRadius: 3)],
      )),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 2,
    );
    tp.layout(maxWidth: faceW - 6);
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  void _drawCrumple(Canvas canvas, _RF f) {
    final lp = Paint()
      ..color = Colors.black.withAlpha((f.aging * 35).round())
      ..strokeWidth = 0.6;
    final dy = (f.p3.dy - f.p0.dy);
    for (int i = 0; i < (f.aging * 4).round(); i++) {
      final y = f.p0.dy + dy * (0.2 + i * 0.18);
      canvas.drawLine(Offset(f.p0.dx + 3, y), Offset(f.p1.dx - 3, y + 1.2), lp);
    }
  }

  static Color _lighten(Color c, double a) {
    final h = HSLColor.fromColor(c);
    return h.withLightness((h.lightness + a).clamp(0.0, 0.95)).toColor();
  }

  static Color _darken(Color c, double a) {
    final h = HSLColor.fromColor(c);
    return h.withLightness((h.lightness - a).clamp(0.05, 1.0)).toColor();
  }

  @override
  bool shouldRepaint(covariant _Scene3DPainter old) => true;
}

// ══════════════════════════════════════════════════════════════
//  Data
// ══════════════════════════════════════════════════════════════

class _V3 {
  final double x, y, z;
  const _V3(this.x, this.y, this.z);
}

/// Renderable face (4 screen-space corners + metadata)
class _RF {
  final Offset p0, p1, p2, p3;
  final Color color;
  final double depth;
  final bool isFront;
  final String? label;
  final double aging;
  final double faceW;
  const _RF(this.p0, this.p1, this.p2, this.p3, this.color, this.depth,
      {this.isFront = false, this.label, this.aging = 0, this.faceW = 50});
}

class _CigBody {
  final Body body;
  final double wPx, hPx, dPx;
  final Color color;
  final String label;
  final double aging;
  final SmokingRecord rec;
  _CigBody({required this.body, required this.wPx, required this.hPx,
    required this.dPx, required this.color, required this.label,
    required this.aging, required this.rec});
}
