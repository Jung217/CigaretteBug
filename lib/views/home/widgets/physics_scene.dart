import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:oimo_physics/oimo_physics.dart' as oimo;
import 'package:vector_math/vector_math.dart' as vm;

import '../../../models/smoking_record.dart';
import '../../../providers/app_providers.dart';
import '../../../services/brand_database.dart';
import '../../../utils/theme.dart';
import '../../../utils/pack_palette.dart';
import '../../scanner/scanner_screen.dart';

// ══════════════════════════════════════════════════════════════
//  Home scene — REAL 3D physics (oimo) on a dark stage
//
//  Each logged item is a genuine 3D rigid body in an oimo world:
//   • PACK  → a 3D box (cuboid) that tumbles end-over-end,
//   • STICK → a 3D cylinder that actually rolls.
//  Bodies live in a floor "tray"; tilt the phone → gravity shifts →
//  they roll/tumble around. Rendered by a software pinhole camera
//  (perspective + per-face lighting from each body's quaternion).
//
//  Tuning knobs are grouped here at the top.
// ══════════════════════════════════════════════════════════════

// ── world / tray (world units) ──
const double _trayW = 4.2; // half-width  (x)
const double _trayD = 5.6; // half-depth  (z)
const double _gDown = 17.0; // base downward gravity onto the floor
const double _tiltMul = 2.6; // accelerometer → lateral gravity

// ── camera ──
const double _camH = 8.6; // camera height above floor
const double _camZ = 10.6; // camera distance in front (+z)
const double _fitFrac = 0.92; // how much of screen width the tray fills

// ── light (world space: x=right, y=up, z=toward viewer), ~unit ──
const double _lx = 0.40, _ly = 0.82, _lz = 0.40;

// ── perf ──
const int _maxLiveRecords = 26; // most-recent records that get live bodies

// ── look (crayon hand-drawn color blocks) ──
const double _crayonAmp = 0.25; // edge wobble amplitude (px) — small = regular lines
const double _crayonFeather = 0.7; // soft edge feather (px)

const _stageTop = Color(0xFF26262B);
const _stageBottom = Color(0xFF111113);
const _cigBody = Color(0xFFF1EFE8);
const _cigFilter = Color(0xFFC68A3C);

class PhysicsScene extends ConsumerStatefulWidget {
  const PhysicsScene({super.key});
  @override
  ConsumerState<PhysicsScene> createState() => _PhysicsSceneState();
}

class _PhysicsSceneState extends ConsumerState<PhysicsScene>
    with SingleTickerProviderStateMixin {
  oimo.World? _world;
  final List<_Solid> _solids = [];
  bool _trayBuilt = false;

  StreamSubscription? _accelSub;
  double _ax = 0, _ay = 0;

  late Ticker _ticker;
  Duration _prev = Duration.zero;
  double _acc = 0; // fixed-step accumulator
  double _elapsed = 0;
  double _lastHaptic = 0;
  Size _sz = Size.zero;
  final _rng = Random();
  final List<_Particle> _particles = [];

  // drag
  _Solid? _drag;
  Offset _dragPos = Offset.zero;

  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _world = oimo.World(oimo.WorldConfigure(
      isStat: true,
      scale: 1.0,
      iterations: 12, // more solver iterations → less inter-penetration
      gravity: vm.Vector3(0, -_gDown, 0),
    ));
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
    _repaint.dispose();
    super.dispose();
  }

  // ─────────────────── tray ───────────────────

  void _buildTray() {
    if (_trayBuilt) return;
    _trayBuilt = true;
    final w = _world!;
    final cfg = oimo.ShapeConfig(geometry: oimo.Shapes.box, friction: 0.5);
    // floor (top at y = 0)
    w.add(oimo.ObjectConfigure(
      shapes: [oimo.Box(cfg, _trayW * 2 + 4, 1.0, _trayD * 2 + 4)],
      position: vm.Vector3(0, -0.5, 0),
    ));
    // 4 walls
    void wall(double x, double z, double sx, double sz) {
      w.add(oimo.ObjectConfigure(
        shapes: [oimo.Box(cfg, sx, 6.0, sz)],
        position: vm.Vector3(x, 2.0, z),
      ));
    }

    wall(-_trayW - 0.5, 0, 1.0, _trayD * 2 + 4);
    wall(_trayW + 0.5, 0, 1.0, _trayD * 2 + 4);
    wall(0, -_trayD - 0.5, _trayW * 2 + 4, 1.0);
    wall(0, _trayD + 0.5, _trayW * 2 + 4, 1.0);
  }

  // ─────────────────── sync records ───────────────────

  void _sync(List<SmokingRecord> recs) {
    // Only the most-recent N records get live bodies (perf cap).
    final sorted = [...recs]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final live = sorted.take(_maxLiveRecords).map((r) => r.id).toSet();
    final db = ref.read(brandDatabaseProvider);

    _solids.removeWhere((s) {
      if (!live.contains(s.rec.id)) {
        _world!.removeRigidBody(s.body);
        return true;
      }
      return false;
    });

    final have = _solids.map((s) => s.rec.id).toSet();
    for (final r in sorted.take(_maxLiveRecords)) {
      if (have.contains(r.id)) continue;
      _spawnPack(r, db);
      _spawnCig(r);
    }
  }

  double _rx() => (_rng.nextDouble() * 2 - 1) * (_trayW - 1.2);
  double _rz() => (_rng.nextDouble() * 2 - 1) * (_trayD - 1.2);

  void _spawnPack(SmokingRecord r, BrandDatabase db) {
    final brand = db.findByBarcode(r.brandBarcode);
    final slim = brand?.packType.name == 'slim';
    final bw = slim ? 0.9 : 1.1, bh = 0.45, bd = slim ? 1.7 : 1.6;
    final body = _world!.add(oimo.ObjectConfigure(
      shapes: [
        oimo.Box(oimo.ShapeConfig(geometry: oimo.Shapes.box, friction: 0.5,
            restitution: 0.03, density: 1.0), bw, bh, bd)
      ],
      position: vm.Vector3(_rx(), 5 + _rng.nextDouble() * 4, _rz()),
      move: true,
      name: 'pack',
    )) as oimo.RigidBody;
    body.angularVelocity.setValues(_rng.nextDouble() * 2 - 1,
        _rng.nextDouble() * 2 - 1, _rng.nextDouble() * 2 - 1);
    final nz = brand?.nameZH ?? '';
    final nm = (brand?.name ?? '').toLowerCase();
    final bk = (nz.contains('七星') || nm.contains('mevius'))
        ? _Brand.mevius
        : (nz.contains('萬寶路') || nm.contains('marlboro'))
            ? _Brand.marlboro
            : (nz.contains('長壽') ||
                    nm.contains('long life') ||
                    nm.contains('longlife'))
                ? _Brand.longlife
                : _Brand.generic;
    // variant accent colour
    Color cv = const Color(0xFF1564B0);
    if (bk == _Brand.mevius) {
      cv = nz.contains('天藍')
          ? const Color(0xFF57AEEA)
          : nz.contains('風藍')
              ? const Color(0xFF2B3F8F)
              : const Color(0xFF1564B0); // 原味
    } else if (bk == _Brand.marlboro) {
      cv = nz.contains('金')
          ? const Color(0xFFD2A53C)
          : nz.contains('薄荷')
              ? const Color(0xFF2E9E5B)
              : const Color(0xFFCE1126); // 紅
    } else if (bk == _Brand.longlife) {
      cv = nz.contains('薄荷')
          ? const Color(0xFF2FA36B)
          : const Color(0xFF1F7A3D);
    }
    _solids.add(_Solid(
      body: body,
      kind: _Kind.pack,
      dimX: bw,
      dimY: bh,
      dimZ: bd,
      color: brand != null ? cuteify(Color(brand.colorValue)) : AppColors.ashGrey,
      label: brand?.nameZH ?? '?',
      brand: bk,
      brandColor: cv,
      rec: r,
    ));
  }

  void _spawnCig(SmokingRecord r) {
    const radius = 0.17, length = 1.7; // thicker → above oimo's 0.1 stable min
    final body = _world!.add(oimo.ObjectConfigure(
      shapes: [
        oimo.Cylinder(oimo.ShapeConfig(geometry: oimo.Shapes.cylinder,
            friction: 0.45, restitution: 0.05, density: 0.7), radius, length)
      ],
      position: vm.Vector3(_rx(), 6 + _rng.nextDouble() * 4, _rz()),
      move: true,
      name: 'cig',
    )) as oimo.RigidBody;
    body.angularVelocity.setValues(_rng.nextDouble() * 3 - 1.5,
        _rng.nextDouble() * 3 - 1.5, _rng.nextDouble() * 3 - 1.5);
    _solids.add(_Solid(
      body: body,
      kind: _Kind.cig,
      dimX: radius * 2,
      dimY: length,
      dimZ: radius * 2,
      color: _cigBody,
      label: '',
      rec: r,
    ));
  }

  // ─────────────────── step ───────────────────

  void _step(Duration now) {
    final world = _world;
    if (world == null || _sz == Size.zero || !_trayBuilt) return;
    final dt =
        _prev == Duration.zero ? 1 / 60.0 : (now - _prev).inMicroseconds / 1e6;
    _prev = now;
    _elapsed += dt;

    // tilt → in-floor gravity (keeps a downward pull so they stay in the tray)
    world.gravity.setValues(_ax * _tiltMul, -_gDown, _ay * _tiltMul);

    // fixed 1/60 steps (handles 120Hz ProMotion without running 2× fast)
    _acc += dt.clamp(0.0, 0.05);
    int steps = 0;
    while (_acc >= 1 / 60 && steps < 4) {
      world.step();
      _acc -= 1 / 60;
      steps++;
    }

    // drag: pull the grabbed body toward the finger's floor point
    if (_drag != null) {
      final hit = _unproject(_dragPos);
      if (hit != null) {
        final b = _drag!.body;
        b.linearVelocity.setValues(
          (hit[0] - b.position.x) * 10,
          (1.5 - b.position.y).clamp(-3.0, 6.0) * 4,
          (hit[1] - b.position.z) * 10,
        );
      }
    }

    // animations + impact approximation
    for (final s in _solids) {
      if (s.pop < 1.0) s.pop = (s.pop + dt * 3.0).clamp(0.0, 1.0);
      final sp = s.body.linearVelocity.length;
      if (s.prevSpeed - sp > 5.0 && _elapsed - s.lastImpactAt > 0.18) {
        s.lastImpactAt = _elapsed;
        _burst(s, ((s.prevSpeed - sp) / 14).clamp(0.0, 1.0));
      }
      s.prevSpeed = sp;
    }
    for (final p in _particles) {
      p.life -= dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vy += 600 * dt;
    }
    _particles.removeWhere((p) => p.life <= 0);

    _repaint.value = (_repaint.value + 1) & 0xFFFF;
  }

  void _burst(_Solid s, double mag) {
    if (mag < 0.12) return;
    if (_elapsed - _lastHaptic > 0.09 && mag > 0.4) {
      _lastHaptic = _elapsed;
      HapticFeedback.lightImpact();
    }
    final p = _project(s.body.position.x, s.body.position.y, s.body.position.z);
    if (p == null) return;
    final n = (2 + mag * 6).round();
    for (int i = 0; i < n; i++) {
      final a = (_rng.nextDouble() - 0.5) * pi * 0.8;
      final sp = 30 + _rng.nextDouble() * 90 * mag;
      _particles.add(_Particle(
        x: p.x + (_rng.nextDouble() - 0.5) * 24,
        y: p.y + 6,
        vx: sin(a) * sp,
        vy: -cos(a).abs() * sp * 0.5,
        life: 0.28 + _rng.nextDouble() * 0.22,
        maxLife: 0.5,
        size: 1.4 + _rng.nextDouble() * 2.0,
      ));
    }
  }

  // ─────────────────── camera (state-side copies for hit/unproject) ───────────────────

  // basis recomputed each frame in build; cached here for input mapping
  List<double> _camFwd = const [0, 0, -1],
      _camRight = const [1, 0, 0],
      _camUp = const [0, 1, 0];
  double _focal = 800;

  void _updateCamera() {
    final c = [0.0, _camH, _camZ];
    var fwd = [-c[0], -c[1], -c[2]];
    fwd = _norm(fwd);
    final right = _norm(_cross(fwd, [0.0, 1.0, 0.0]));
    final up = _norm(_cross(right, fwd));
    _camFwd = fwd;
    _camRight = right;
    _camUp = up;
    // fit: tray half-width _trayW at distance ~|C| fills _fitFrac of half screen
    final dist = sqrt(_camH * _camH + _camZ * _camZ);
    _focal = (_sz.width * _fitFrac / 2) * dist / _trayW;
  }

  _P2? _project(double x, double y, double z) {
    final dx = x, dy = y - _camH, dz = z - _camZ;
    final cz = dx * _camFwd[0] + dy * _camFwd[1] + dz * _camFwd[2];
    if (cz <= 0.1) return null;
    final cx = dx * _camRight[0] + dy * _camRight[1] + dz * _camRight[2];
    final cy = dx * _camUp[0] + dy * _camUp[1] + dz * _camUp[2];
    return _P2(_sz.width / 2 + _focal * cx / cz, _sz.height / 2 - _focal * cy / cz,
        cz);
  }

  // screen → floor (y=0) world point [x,z]
  List<double>? _unproject(Offset p) {
    final ux = (p.dx - _sz.width / 2) / _focal;
    final uy = -(p.dy - _sz.height / 2) / _focal;
    final dir = _norm([
      _camFwd[0] + _camRight[0] * ux + _camUp[0] * uy,
      _camFwd[1] + _camRight[1] * ux + _camUp[1] * uy,
      _camFwd[2] + _camRight[2] * ux + _camUp[2] * uy,
    ]);
    if (dir[1].abs() < 1e-4) return null;
    final t = (0 - _camH) / dir[1];
    if (t <= 0) return null;
    return [0 + dir[0] * t, _camZ + dir[2] * t];
  }

  _Solid? _hit(Offset p) {
    _Solid? best;
    double bestD = 44 * 44;
    for (final s in _solids) {
      final sp = _project(s.body.position.x, s.body.position.y, s.body.position.z);
      if (sp == null) continue;
      final d = (sp.x - p.dx) * (sp.x - p.dx) + (sp.y - p.dy) * (sp.y - p.dy);
      if (d < bestD) {
        bestD = d;
        best = s;
      }
    }
    return best;
  }

  // ─────────────────── build ───────────────────

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(filteredRecordsProvider);
    final range = ref.watch(timeRangeProvider);

    return LayoutBuilder(builder: (ctx, box) {
      final newSz = Size(box.maxWidth, box.maxHeight);
      if (newSz != _sz) {
        _sz = newSz;
        _buildTray();
      }
      _updateCamera();
      if (_trayBuilt) _sync(records);

      return GestureDetector(
        onTapUp: (d) {
          final s = _hit(d.localPosition);
          if (s != null && s.kind == _Kind.pack) _showDetail(s);
        },
        onPanStart: (d) {
          _drag = _hit(d.localPosition);
          _dragPos = d.localPosition;
          if (_drag != null) HapticFeedback.selectionClick();
        },
        onPanUpdate: (d) => _dragPos = d.localPosition,
        onPanEnd: (_) => _drag = null,
        child: Stack(clipBehavior: Clip.none, children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_stageTop, _stageBottom],
              ),
            ),
            child: SizedBox.expand(),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.3),
                  radius: 0.95,
                  colors: [
                    AppColors.amber.withValues(alpha: 0.10),
                    Colors.transparent
                  ],
                ),
              ),
            ),
          ),
          RepaintBoundary(
            child: CustomPaint(
              size: _sz,
              painter: _Scene3D(this, repaint: _repaint),
            ),
          ),
          ..._buildUI(_sz.width, _sz.height, range, records, context, ref),
        ]),
      );
    });
  }

  // ─────────────────── UI overlay ───────────────────

  List<Widget> _buildUI(double sw, double sh, TimeRange range,
      List<SmokingRecord> records, BuildContext context, WidgetRef ref) {
    final empty = records.isEmpty;
    final mq = MediaQuery.of(context);
    final topInset = mq.padding.top;
    final bottomInset = mq.padding.bottom;
    return [
      Positioned(
        top: topInset + 6, // clear the Dynamic Island / status bar
        left: 0,
        right: 0,
        child: Center(
          child: GestureDetector(
            onTap: () => _cycleTimeRange(ref),
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v < -100) ref.read(dateOffsetProvider.notifier).state--;
              if (v > 100) ref.read(dateOffsetProvider.notifier).state++;
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.amber.withValues(alpha: 0.35)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_rangeLabel(range),
                    style: const TextStyle(
                        color: AppColors.amberLight,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1)),
                const SizedBox(width: 8),
                Text('${records.length}',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                const Text(' 根',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ]),
            ),
          ),
        ),
      ),
      if (empty)
        Positioned(
          top: sh * 0.34,
          left: 32,
          right: 32,
          child: IgnorePointer(
            child: Column(children: [
              Icon(Icons.touch_app_rounded,
                  color: AppColors.amber.withValues(alpha: 0.6), size: 40),
              const SizedBox(height: 14),
              const Text('點 + 記錄第一根菸',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              const Text('3D 菸盒與香菸會掉進來、隨手機傾斜翻滾',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ]),
          ),
        ),
      Positioned(
        bottom: bottomInset + 18,
        left: 0,
        right: 0,
        child: Center(
          child: GestureDetector(
            onTap: () => _showAddMenu(context, ref),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.amber,
                boxShadow: [
                  BoxShadow(
                      color: AppColors.amber.withValues(alpha: 0.45),
                      blurRadius: 18,
                      offset: const Offset(0, 6)),
                ],
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 34),
            ),
          ),
        ),
      ),
    ];
  }

  String _rangeLabel(TimeRange r) => switch (r) {
        TimeRange.day => '今日',
        TimeRange.week => '今週',
        TimeRange.month => '今月',
        TimeRange.year => '今年',
      };

  void _cycleTimeRange(WidgetRef ref) {
    final cur = ref.read(timeRangeProvider);
    final v = TimeRange.values;
    ref.read(timeRangeProvider.notifier).state =
        v[(v.indexOf(cur) + 1) % v.length];
    ref.read(dateOffsetProvider.notifier).state = 0;
  }

  void _showAddMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        final brands = ref.read(brandDatabaseProvider).allBrands;
        return DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.3,
            maxChildSize: 0.85,
            expand: false,
            builder: (_, sc) => Column(children: [
                  const SizedBox(height: 12),
                  Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(2))),
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        const Text('選擇品牌',
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                        const Spacer(),
                        GestureDetector(
                            onTap: () {
                              Navigator.pop(ctx);
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const ScannerScreen()));
                            },
                            child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                    border: Border.all(color: AppColors.amber),
                                    borderRadius: BorderRadius.circular(16)),
                                child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.qr_code_scanner,
                                          color: AppColors.amber, size: 16),
                                      SizedBox(width: 4),
                                      Text('掃描',
                                          style: TextStyle(
                                              color: AppColors.amber,
                                              fontSize: 13))
                                    ]))),
                      ])),
                  Expanded(
                      child: ListView.builder(
                          controller: sc,
                          itemCount: brands.length,
                          itemBuilder: (_, i) {
                            final brand = brands[i];
                            return ListTile(
                              leading: Container(
                                  width: 36,
                                  height: 48,
                                  decoration: BoxDecoration(
                                      color: Color(brand.colorValue),
                                      borderRadius: BorderRadius.circular(6)),
                                  child: Center(
                                      child: Text(
                                          brand.nameZH.length > 2
                                              ? brand.nameZH.substring(0, 2)
                                              : brand.nameZH,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold)))),
                              title: Text(brand.nameZH,
                                  style: const TextStyle(
                                      color: AppColors.textPrimary)),
                              subtitle: Text(
                                  '${brand.name} · NT\$${brand.packPrice}',
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12)),
                              trailing: brand.productType.name == 'heatStick'
                                  ? const Text('加熱菸',
                                      style: TextStyle(
                                          color: AppColors.amber, fontSize: 11))
                                  : null,
                              onTap: () {
                                ref.read(recordsProvider.notifier).addRecord(
                                    SmokingRecord(brandBarcode: brand.barcode));
                                HapticFeedback.mediumImpact();
                                Navigator.pop(ctx);
                              },
                            );
                          })),
                ]));
      },
    );
  }

  void _showDetail(_Solid s) {
    final brand = ref.read(brandDatabaseProvider).findByBarcode(s.rec.brandBarcode);
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
                Container(
                    width: 48,
                    height: 66,
                    decoration: BoxDecoration(
                        color: s.color,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                              color: s.color.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4))
                        ]),
                    child: Center(
                        child: Text(s.label,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center))),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(brand?.nameZH ?? '?',
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                      Text(brand?.name ?? '',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 13))
                    ])),
              ]),
              const SizedBox(height: 16),
              if (brand != null) ...[
                _row('製造商', brand.manufacturer),
                _row('焦油', '${brand.tar} mg'),
                _row('尼古丁', '${brand.nicotine} mg'),
                _row('價格', 'NT\$${brand.packPrice}'),
              ],
              _row('老化', '${(s.aging * 100).round()}%'),
              const SizedBox(height: 12),
            ])));
  }

  Widget _row(String l, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(l,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
        Text(v,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500))
      ]));

  // ─────────────────── small vector helpers ───────────────────

  static List<double> _cross(List<double> a, List<double> b) => [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
      ];

  static List<double> _norm(List<double> v) {
    final m = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    if (m < 1e-9) return [0, 0, 1];
    return [v[0] / m, v[1] / m, v[2] / m];
  }
}

// ══════════════════════════════════════════════════════════════
//  Software 3D painter — reads each rigid body's quaternion + pos
// ══════════════════════════════════════════════════════════════

class _P2 {
  final double x, y, depth;
  const _P2(this.x, this.y, this.depth);
}

class _Scene3D extends CustomPainter {
  final _PhysicsSceneState st;
  _Scene3D(this.st, {required Listenable repaint}) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final solids = st._solids;
    // sort by camera depth (far first)
    final order = [...solids];
    for (final s in order) {
      final p = st._project(s.body.position.x, s.body.position.y, s.body.position.z);
      s.screenDepth = p?.depth ?? -1;
    }
    order.sort((a, b) => b.screenDepth.compareTo(a.screenDepth));

    for (final s in order) {
      if (s.screenDepth <= 0) continue;
      if (s.kind == _Kind.pack) {
        _paintPack(canvas, s);
      } else {
        _paintCig(canvas, s);
      }
    }

    for (final p in st._particles) {
      final t = (p.life / p.maxLife).clamp(0.0, 1.0);
      canvas.drawCircle(Offset(p.x, p.y), p.size * t,
          Paint()..color = const Color(0xFFC9B79A).withValues(alpha: 0.7 * t));
    }
  }

  // rotate local vector by body quaternion
  List<double> _qrot(_Solid s, double vx, double vy, double vz) {
    final q = s.body.orientation;
    final qx = q.x, qy = q.y, qz = q.z, qw = q.w;
    final tx = 2 * (qy * vz - qz * vy);
    final ty = 2 * (qz * vx - qx * vz);
    final tz = 2 * (qx * vy - qy * vx);
    return [
      vx + qw * tx + (qy * tz - qz * ty),
      vy + qw * ty + (qz * tx - qx * tz),
      vz + qw * tz + (qx * ty - qy * tx),
    ];
  }

  _P2? _vert(_Solid s, double lx, double ly, double lz, double sc) {
    final r = _qrot(s, lx * sc, ly * sc, lz * sc);
    return st._project(
        s.body.position.x + r[0], s.body.position.y + r[1], s.body.position.z + r[2]);
  }

  void _paintPack(Canvas canvas, _Solid s) {
    final sc = s.pop >= 1 ? 1.0 : _easeOutBack(s.pop);
    final hw = s.dimX / 2, hh = s.dimY / 2, hd = s.dimZ / 2;
    var body = s.color;
    final aging = s.aging;
    if (aging > 0.05) body = Color.lerp(body, const Color(0xFF6A5836), aging * 0.45)!;
    // simplified, real-pack-like color blocks
    final accent = packShade(body, -0.30);
    final logo = packShade(body, -0.50);
    const light = Color(0xFFF1EEE6);

    final v = [
      _vert(s, -hw, hh, hd, sc),
      _vert(s, hw, hh, hd, sc),
      _vert(s, hw, hh, -hd, sc),
      _vert(s, -hw, hh, -hd, sc),
      _vert(s, -hw, -hh, hd, sc),
      _vert(s, hw, -hh, hd, sc),
      _vert(s, hw, -hh, -hd, sc),
      _vert(s, -hw, -hh, -hd, sc),
    ];
    if (v.any((e) => e == null)) return;

    // contact shadow under the body (project floor point)
    final fs = st._project(s.body.position.x, 0.02, s.body.position.z);
    if (fs != null) {
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(fs.x, fs.y), width: s.dimZ * 26, height: s.dimZ * 12),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.28 * s.pop)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }

    // faces: [i0,i1,i2,i3, nx,ny,nz]; i0→i3 & i1→i2 run along pack length
    const defs = [
      [0, 1, 2, 3, 0, 1, 0], // top
      [4, 5, 6, 7, 0, -1, 0], // bottom
      [0, 1, 5, 4, 0, 0, 1], // front
      [3, 2, 6, 7, 0, 0, -1], // back
      [1, 2, 6, 5, 1, 0, 0], // right
      [0, 3, 7, 4, -1, 0, 0], // left
    ];
    final seed = s.rec.id.hashCode;
    final faces = <(List<_P2>, double, bool, double, int)>[];
    var fi = 0;
    for (final f in defs) {
      final p = [v[f[0]]!, v[f[1]]!, v[f[2]]!, v[f[3]]!];
      final wn = _qrot(s, f[4].toDouble(), f[5].toDouble(), f[6].toDouble());
      final dot = wn[0] * _lx + wn[1] * _ly + wn[2] * _lz;
      final b = (0.45 + 0.75 * dot.clamp(0.0, 1.0)).clamp(0.2, 1.2);
      final depth = (p[0].depth + p[1].depth + p[2].depth + p[3].depth) / 4;
      faces.add((p, b.toDouble(), f[5].abs() == 1, depth, fi++));
    }
    faces.sort((a, b) => b.$4.compareTo(a.$4)); // far first

    for (final f in faces) {
      final p = f.$1;
      final b = f.$2;
      final fseed = seed + f.$5 * 1000;
      final o0 = Offset(p[0].x, p[0].y), o1 = Offset(p[1].x, p[1].y);
      final o2 = Offset(p[2].x, p[2].y), o3 = Offset(p[3].x, p[3].y);

      if (f.$3) {
        // brand color-block design mapped over the face (u across, t along)
        Offset uv(double u, double t) {
          final top = Offset.lerp(o0, o1, u)!;
          final bot = Offset.lerp(o3, o2, u)!;
          return Offset.lerp(top, bot, t)!;
        }

        _design(canvas, s.brand, s.brandColor, uv, b, body, accent, light, logo,
            fseed);
      } else {
        _handFill(canvas, [o0, o1, o2, o3], _mul(body, b), fseed);
      }
    }
  }

  // ── per-brand crayon color-block designs (brandColor = variant accent) ──
  void _design(Canvas canvas, _Brand brand, Color brandColor,
      Offset Function(double, double) uv, double b, Color body, Color accent,
      Color light, Color logo, int seed) {
    var blk = 0;
    void band(double t0, double t1, Color col) => _handFill(
        canvas,
        [uv(0, t0), uv(1, t0), uv(1, t1), uv(0, t1)],
        _mul(col, b),
        seed + blk++);
    void poly(List<Offset> pts, Color col) =>
        _handFill(canvas, pts, _mul(col, b), seed + blk++);

    switch (brand) {
      case _Brand.mevius: // 白底 + 變體藍帶 + 藍橢圓
        band(0, 1, light);
        band(0.0, 0.13, brandColor);
        band(0.84, 1.0, brandColor);
        poly(_oval(uv, 0.5, 0.46, 0.32, 0.12), brandColor);
      case _Brand.marlboro: // 白底 + 變體色頂三角
        band(0, 1, light);
        poly([uv(0, 0), uv(1, 0), uv(1, 0.10), uv(0.5, 0.34), uv(0, 0.10)],
            brandColor);
        band(0.93, 1.0, brandColor);
      case _Brand.longlife: // 變體綠底 + 米帶 + 金橢圓
        band(0, 1, brandColor);
        band(0.0, 0.16, packShade(brandColor, -0.16));
        band(0.42, 0.60, const Color(0xFFEDE6C8));
        poly(_oval(uv, 0.5, 0.51, 0.24, 0.085), const Color(0xFFC9A227));
      case _Brand.generic: // 程序化模板
        band(0.0, 0.22, accent);
        band(0.22, 0.27, light);
        band(0.27, 0.72, body);
        band(0.72, 1.0, light);
        poly([uv(0.30, 0.40), uv(0.70, 0.40), uv(0.70, 0.56), uv(0.30, 0.56)],
            logo);
    }
  }

  // crayon-style fill: wobbly hand-drawn edge + soft feather
  static void _handFill(Canvas c, List<Offset> pts, Color col, int seed) {
    if (pts.length < 3) return;
    c.drawPath(
      _handPath(pts, seed),
      Paint()
        ..color = col
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, _crayonFeather),
    );
  }

  static Path _handPath(List<Offset> pts, int seed) {
    final path = Path();
    const segs = 3;
    var started = false;
    for (int e = 0; e < pts.length; e++) {
      final a = pts[e], bb = pts[(e + 1) % pts.length];
      final dx = bb.dx - a.dx, dy = bb.dy - a.dy;
      final len = sqrt(dx * dx + dy * dy);
      final nx = len > 1e-3 ? -dy / len : 0.0;
      final ny = len > 1e-3 ? dx / len : 0.0;
      for (int sg = 0; sg < segs; sg++) {
        final t = sg / segs;
        final j = _jit(seed + e * 17 + sg) * _crayonAmp;
        final x = a.dx + dx * t + nx * j;
        final y = a.dy + dy * t + ny * j;
        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }
    }
    path.close();
    return path;
  }

  static double _jit(int seed) {
    var h = (seed * 1103515245 + 12345) & 0x7fffffff;
    h ^= h >> 13;
    h = (h * 1274126177) & 0x7fffffff;
    return (h % 1000) / 500.0 - 1.0;
  }

  static List<Offset> _oval(Offset Function(double, double) uv, double cu,
      double ct, double ru, double rt) {
    final pts = <Offset>[];
    for (int i = 0; i < 16; i++) {
      final a = 2 * pi * i / 16;
      pts.add(uv((cu + ru * cos(a)).clamp(0.0, 1.0),
          (ct + rt * sin(a)).clamp(0.0, 1.0)));
    }
    return pts;
  }

  void _paintCig(Canvas canvas, _Solid s) {
    final sc = s.pop >= 1 ? 1.0 : _easeOutBack(s.pop);
    const n = 14;
    final r = s.dimX / 2, hl = s.dimY / 2;

    // floor shadow
    final fs = st._project(s.body.position.x, 0.02, s.body.position.z);
    if (fs != null) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(fs.x, fs.y), width: 38, height: 16),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.22 * s.pop)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }

    final ring0 = <_P2?>[], ring1 = <_P2?>[];
    final bright = <double>[];
    for (int i = 0; i <= n; i++) {
      final ang = 2 * pi * i / n;
      final cx = r * cos(ang), cz = r * sin(ang);
      ring0.add(_vert(s, cx, -hl, cz, sc));
      ring1.add(_vert(s, cx, hl, cz, sc));
      final wn = _qrot(s, cos(ang), 0, sin(ang));
      final dot = wn[0] * _lx + wn[1] * _ly + wn[2] * _lz;
      bright.add((0.4 + 0.72 * dot.clamp(0.0, 1.0)).clamp(0.2, 1.2));
    }
    if (ring0.any((e) => e == null) || ring1.any((e) => e == null)) return;

    final quads = <_Face>[];
    for (int i = 0; i < n; i++) {
      final depth = (ring0[i]!.depth +
              ring0[i + 1]!.depth +
              ring1[i]!.depth +
              ring1[i + 1]!.depth) /
          4;
      final b = (bright[i] + bright[i + 1]) / 2;
      quads.add(_Face(
          [ring0[i]!, ring0[i + 1]!, ring1[i + 1]!, ring1[i]!], _mul(_cigBody, b),
          depth));
    }
    quads.sort((a, b) => b.depth.compareTo(a.depth));
    for (final q in quads) {
      final path = Path()..moveTo(q.pts[0].x, q.pts[0].y);
      for (int i = 1; i < 4; i++) {
        path.lineTo(q.pts[i].x, q.pts[i].y);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = q.color);
    }

    // near end cap = filter
    final c0 = _vert(s, 0, -hl, 0, sc), c1 = _vert(s, 0, hl, 0, sc);
    if (c0 == null || c1 == null) return;
    final near = c0.depth >= c1.depth ? ring0 : ring1;
    final capColor = c0.depth >= c1.depth ? _cigFilter : _cigBody;
    final cap = Path()..moveTo(near[0]!.x, near[0]!.y);
    for (int i = 1; i <= n; i++) {
      cap.lineTo(near[i]!.x, near[i]!.y);
    }
    cap.close();
    canvas.drawPath(cap, Paint()..color = capColor);
  }

  static Color _mul(Color c, double f) => Color.from(
        alpha: 1.0,
        red: (c.r * f).clamp(0.0, 1.0),
        green: (c.g * f).clamp(0.0, 1.0),
        blue: (c.b * f).clamp(0.0, 1.0),
      );

  static double _easeOutBack(double t) {
    const c1 = 1.70158, c3 = c1 + 1;
    final x = t - 1;
    return 1 + c3 * x * x * x + c1 * x * x;
  }

  @override
  bool shouldRepaint(covariant _Scene3D old) => true;
}

class _Face {
  final List<_P2> pts;
  final Color color;
  final double depth;
  _Face(this.pts, this.color, this.depth);
}

// ══════════════════════════════════════════════════════════════
//  Data
// ══════════════════════════════════════════════════════════════

enum _Kind { pack, cig }

enum _Brand { generic, mevius, marlboro, longlife }

class _Solid {
  final oimo.RigidBody body;
  final _Kind kind;
  final double dimX, dimY, dimZ; // world-unit full extents
  final Color color;
  final String label;
  final _Brand brand;
  final Color brandColor;
  final SmokingRecord rec;
  double pop = 0.0;
  double prevSpeed = 0.0;
  double lastImpactAt = -1.0;
  double screenDepth = 0.0;

  _Solid({
    required this.body,
    required this.kind,
    required this.dimX,
    required this.dimY,
    required this.dimZ,
    required this.color,
    required this.label,
    required this.rec,
    this.brand = _Brand.generic,
    this.brandColor = const Color(0xFF1564B0),
  });

  double get aging => rec.agingProgress;
}

class _Particle {
  double x, y, vx, vy, life;
  final double maxLife, size;
  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.maxLife,
    required this.size,
  });
}
