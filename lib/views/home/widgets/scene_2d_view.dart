import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:async';
import '../../../models/smoking_record.dart';
import '../../../providers/app_providers.dart';
import '../../../utils/theme.dart';

// ══════════════════════════════════════════════════════════════════
//  3D Math primitives
// ══════════════════════════════════════════════════════════════════

class Vec3 {
  final double x, y, z;
  const Vec3(this.x, this.y, this.z);
  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);
  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;
  Vec3 cross(Vec3 o) => Vec3(
    y * o.z - z * o.y,
    z * o.x - x * o.z,
    x * o.y - y * o.x,
  );
  double get length => sqrt(x * x + y * y + z * z);
  Vec3 get normalized {
    final l = length;
    return l > 0.0001 ? Vec3(x / l, y / l, z / l) : const Vec3(0, 0, 0);
  }
}

class Face {
  final List<Vec3> vertices;
  final Color color;
  Face(this.vertices, this.color);

  Vec3 get center {
    double cx = 0, cy = 0, cz = 0;
    for (final v in vertices) { cx += v.x; cy += v.y; cz += v.z; }
    final n = vertices.length.toDouble();
    return Vec3(cx / n, cy / n, cz / n);
  }

  Vec3 get normal {
    final a = vertices[1] - vertices[0];
    final b = vertices[2] - vertices[0];
    return a.cross(b).normalized;
  }
}

// ══════════════════════════════════════════════════════════════════
//  Camera & projection
// ══════════════════════════════════════════════════════════════════

class Camera {
  // Slightly angled top-down, looking at the table
  static const _pitch = -0.85; // radians (~49° from horizontal)
  static const _fov = 500.0;

  static Offset project(Vec3 p, Size screen) {
    // Rotate around X axis (pitch)
    final cosP = cos(_pitch), sinP = sin(_pitch);
    final ry = p.y * cosP - p.z * sinP;
    final rz = p.y * sinP + p.z * cosP;

    // Perspective divide
    final depth = rz + 600; // camera distance
    final scale = _fov / max(depth, 1);

    return Offset(
      screen.width / 2 + p.x * scale,
      screen.height * 0.45 + ry * scale,
    );
  }

  static double depth(Vec3 p) {
    final cosP = cos(_pitch), sinP = sin(_pitch);
    return p.y * sinP + p.z * cosP + 600;
  }
}

// ══════════════════════════════════════════════════════════════════
//  3D Cigarette Box geometry
// ══════════════════════════════════════════════════════════════════

List<Face> buildBoxFaces(
  double cx, double cz, // position on ground plane
  double w, double h, double d, // width, height, depth
  double rotY, // rotation around Y axis
  double crushY, // 0=full height, 1=completely flat
  Color baseColor,
  double aging,
) {
  final halfW = w / 2;
  final halfD = d / 2;
  final actualH = h * (1.0 - crushY * 0.8);

  // 8 vertices of the box (Y is up)
  final cosR = cos(rotY), sinR = sin(rotY);
  Vec3 rot(double lx, double ly, double lz) {
    final rx = lx * cosR - lz * sinR;
    final rz = lx * sinR + lz * cosR;
    return Vec3(cx + rx, ly, cz + rz);
  }

  final v0 = rot(-halfW, 0, -halfD);
  final v1 = rot(halfW, 0, -halfD);
  final v2 = rot(halfW, 0, halfD);
  final v3 = rot(-halfW, 0, halfD);
  final v4 = rot(-halfW, -actualH, -halfD);
  final v5 = rot(halfW, -actualH, -halfD);
  final v6 = rot(halfW, -actualH, halfD);
  final v7 = rot(-halfW, -actualH, halfD);

  // Face colors with lighting
  final hsl = HSLColor.fromColor(baseColor);
  final top = hsl.withLightness((hsl.lightness + 0.12).clamp(0, 0.95)).toColor();
  final front = baseColor;
  final right = hsl.withLightness((hsl.lightness - 0.08).clamp(0.05, 1)).toColor();
  final left = hsl.withLightness((hsl.lightness - 0.05).clamp(0.05, 1)).toColor();
  final back = hsl.withLightness((hsl.lightness - 0.15).clamp(0.05, 1)).toColor();
  final bottom = hsl.withLightness((hsl.lightness - 0.25).clamp(0.05, 1)).toColor();

  // Dirt tint for aged boxes
  Color aged(Color c) {
    if (aging <= 0) return c;
    return Color.lerp(c, const Color(0xFF5C4830), (aging * 0.35).clamp(0, 0.35))!;
  }

  return [
    Face([v3, v2, v6, v7], aged(front)),   // front
    Face([v0, v1, v5, v4], aged(back)),     // back
    Face([v1, v2, v6, v5], aged(right)),    // right
    Face([v0, v3, v7, v4], aged(left)),     // left
    Face([v4, v5, v6, v7], aged(top)),      // top
    Face([v0, v1, v2, v3], aged(bottom)),   // bottom
  ];
}

// ══════════════════════════════════════════════════════════════════
//  Physics body for each cigarette box
// ══════════════════════════════════════════════════════════════════

class CigBody {
  double x, z; // ground position
  double y; // height (0 = on ground, negative = above)
  double vx, vz, vy;
  double rotY, rotVelY;
  final double boxW, boxH, boxD;
  final Color color;
  final String label;
  final double aging;
  final SmokingRecord record;

  CigBody({
    required this.x,
    required this.z,
    required this.y,
    required this.vx,
    required this.vz,
    required this.vy,
    required this.rotY,
    required this.rotVelY,
    required this.boxW,
    required this.boxH,
    required this.boxD,
    required this.color,
    required this.label,
    required this.aging,
    required this.record,
  });
}

// ══════════════════════════════════════════════════════════════════
//  Scene widget
// ══════════════════════════════════════════════════════════════════

class Scene2dView extends ConsumerStatefulWidget {
  const Scene2dView({super.key});

  @override
  ConsumerState<Scene2dView> createState() => _Scene2dViewState();
}

class _Scene2dViewState extends ConsumerState<Scene2dView>
    with SingleTickerProviderStateMixin {
  double _tiltX = 0;
  double _tiltZ = 0;
  StreamSubscription? _accelSub;
  final List<CigBody> _bodies = [];
  late Ticker _ticker;
  Size _screenSize = Size.zero;
  int _lastRecordCount = -1;
  final _rng = Random();

  // Ground plane bounds (world coords)
  static const _groundW = 280.0;
  static const _groundD = 200.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();

    _accelSub = accelerometerEventStream().listen((event) {
      _tiltX = -event.x * 0.6;
      _tiltZ = (event.y - 9.8) * 0.4;
    });
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  void _syncBodies(List<SmokingRecord> records) {
    if (records.length == _lastRecordCount) return;

    final brandDb = ref.read(brandDatabaseProvider);
    final existingIds = _bodies.map((b) => b.record.id).toSet();

    for (final record in records) {
      if (existingIds.contains(record.id)) continue;

      final brand = brandDb.findByBarcode(record.brandBarcode);
      final aging = record.agingProgress;
      final isSlim = brand?.packType.name == 'slim';
      final isHeat = brand?.packType.name == 'heatStick';

      double w = isSlim ? 25 : (isHeat ? 22 : 30);
      double h = isSlim ? 44 : (isHeat ? 32 : 48);
      double d = isSlim ? 10 : (isHeat ? 10 : 12);

      _bodies.add(CigBody(
        x: (_rng.nextDouble() - 0.5) * _groundW * 0.7,
        z: (_rng.nextDouble() - 0.5) * _groundD * 0.5,
        y: -250 - _rng.nextDouble() * 150, // drop from above
        vx: (_rng.nextDouble() - 0.5) * 1.5,
        vz: (_rng.nextDouble() - 0.5) * 1.0,
        vy: 0,
        rotY: _rng.nextDouble() * pi * 2,
        rotVelY: (_rng.nextDouble() - 0.5) * 0.05,
        boxW: w,
        boxH: h,
        boxD: d,
        color: brand != null ? Color(brand.colorValue) : AppColors.ashGrey,
        label: brand?.nameZH ?? '?',
        aging: aging,
        record: record,
      ));
    }

    final recordIds = records.map((r) => r.id).toSet();
    _bodies.removeWhere((b) => !recordIds.contains(b.record.id));
    _lastRecordCount = records.length;
  }

  void _onTick(Duration elapsed) {
    if (_bodies.isEmpty) return;

    const gravity = 3.0;
    const friction = 0.96;
    const bounce = 0.35;
    const halfGW = _groundW / 2;
    const halfGD = _groundD / 2;

    for (final b in _bodies) {
      // Gravity (y goes negative = up, 0 = ground)
      b.vy += gravity * 0.2;
      b.vx += _tiltX * 0.08;
      b.vz += _tiltZ * 0.06;

      b.vx *= friction;
      b.vz *= friction;

      b.x += b.vx;
      b.z += b.vz;
      b.y += b.vy;

      b.rotY += b.rotVelY;
      b.rotVelY *= 0.98;

      // Ground collision
      if (b.y > 0) {
        b.y = 0;
        if (b.vy > 0.8) {
          b.vy = -b.vy * bounce;
          b.rotVelY += (_rng.nextDouble() - 0.5) * 0.04;
        } else {
          b.vy = 0;
        }
      }

      // Walls
      if (b.x < -halfGW) { b.x = -halfGW; b.vx = -b.vx * bounce; }
      if (b.x > halfGW) { b.x = halfGW; b.vx = -b.vx * bounce; }
      if (b.z < -halfGD) { b.z = -halfGD; b.vz = -b.vz * bounce; }
      if (b.z > halfGD) { b.z = halfGD; b.vz = -b.vz * bounce; }
    }

    // Box-box collisions
    for (int i = 0; i < _bodies.length; i++) {
      for (int j = i + 1; j < _bodies.length; j++) {
        final a = _bodies[i], b = _bodies[j];
        final dx = a.x - b.x, dz = a.z - b.z;
        final minDist = (a.boxW + b.boxW) / 2;
        final dist = sqrt(dx * dx + dz * dz);
        if (dist < minDist && dist > 0.01) {
          final nx = dx / dist, nz = dz / dist;
          final overlap = (minDist - dist) / 2;
          a.x += nx * overlap;
          a.z += nz * overlap;
          b.x -= nx * overlap;
          b.z -= nz * overlap;
          // Velocity exchange
          final relV = (a.vx - b.vx) * nx + (a.vz - b.vz) * nz;
          if (relV > 0) {
            a.vx -= relV * nx * 0.4;
            a.vz -= relV * nz * 0.4;
            b.vx += relV * nx * 0.4;
            b.vz += relV * nz * 0.4;
          }
        }
      }
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(filteredRecordsProvider);
    final showButts = ref.watch(cigaretteButtModeProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        _screenSize = Size(constraints.maxWidth, constraints.maxHeight);
        _syncBodies(records);

        if (records.isEmpty) {
          return Container(
            color: AppColors.background,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.view_in_ar, size: 64, color: Color(0xFF333333)),
                  SizedBox(height: 16),
                  Text('還沒有記錄', style: TextStyle(color: AppColors.textSecondary, fontSize: 16, fontWeight: FontWeight.w500)),
                  SizedBox(height: 4),
                  Text('點下方「手動記錄」新增第一根菸', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ],
              ),
            ),
          );
        }

        return GestureDetector(
          onPanUpdate: (d) {
            // Find nearest body to finger and flick it
            final closest = _findClosestBody(d.localPosition);
            if (closest != null) {
              closest.vx += d.delta.dx * 0.6;
              closest.vz += d.delta.dy * 0.4;
              closest.rotVelY += d.delta.dx * 0.005;
            }
          },
          child: Container(
            color: AppColors.background,
            child: CustomPaint(
              size: _screenSize,
              painter: _Scene3DPainter(
                bodies: _bodies,
                screenSize: _screenSize,
                showButts: showButts,
              ),
              child: _buildTapTargets(),
            ),
          ),
        );
      },
    );
  }

  CigBody? _findClosestBody(Offset touchPos) {
    CigBody? closest;
    double minDist = double.infinity;
    for (final b in _bodies) {
      final projected = Camera.project(Vec3(b.x, b.y, b.z), _screenSize);
      final dist = (projected - touchPos).distance;
      if (dist < minDist && dist < 80) {
        minDist = dist;
        closest = b;
      }
    }
    return closest;
  }

  Widget _buildTapTargets() {
    return Stack(
      children: _bodies.where((b) => b.y > -10).map((body) {
        final pos = Camera.project(Vec3(body.x, body.y - body.boxH / 2, body.z), _screenSize);
        final depth = Camera.depth(Vec3(body.x, body.y, body.z));
        final size = 500 / max(depth, 1) * body.boxW * 0.8;
        return Positioned(
          left: pos.dx - size / 2,
          top: pos.dy - size / 2,
          child: GestureDetector(
            onTap: () => _showBoxDetail(body),
            child: SizedBox(width: size, height: size),
          ),
        );
      }).toList(),
    );
  }

  void _showBoxDetail(CigBody body) {
    final brandDb = ref.read(brandDatabaseProvider);
    final brand = brandDb.findByBarcode(body.record.brandBarcode);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.surfaceLight, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 48, height: 66,
                  decoration: BoxDecoration(
                    color: body.color,
                    borderRadius: BorderRadius.circular(5),
                    boxShadow: [BoxShadow(color: body.color.withAlpha(80), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: Center(child: Text(body.label, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(brand?.nameZH ?? '未知品牌', style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(brand?.name ?? '', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  ],
                )),
              ],
            ),
            const SizedBox(height: 20),
            if (brand != null) ...[
              _row('製造商', brand.manufacturer),
              _row('焦油', '${brand.tar} mg'),
              _row('尼古丁', '${brand.nicotine} mg'),
              _row('價格', 'NT\$${brand.packPrice}'),
            ],
            _row('記錄時間', '${body.record.createdAt.month}/${body.record.createdAt.day} ${body.record.createdAt.hour.toString().padLeft(2, '0')}:${body.record.createdAt.minute.toString().padLeft(2, '0')}'),
            _row('老化', '${(body.aging * 100).round()}%'),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _row(String l, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(l, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
        Text(v, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
      ],
    ),
  );
}

// ══════════════════════════════════════════════════════════════════
//  3D Scene Painter
// ══════════════════════════════════════════════════════════════════

class _Scene3DPainter extends CustomPainter {
  final List<CigBody> bodies;
  final Size screenSize;
  final bool showButts;

  _Scene3DPainter({required this.bodies, required this.screenSize, required this.showButts});

  @override
  void paint(Canvas canvas, Size size) {
    _drawGround(canvas, size);

    // Collect all faces from all boxes
    final allFaces = <_FaceWithDepth>[];

    for (final body in bodies) {
      // Box shadow on ground
      _drawShadow(canvas, size, body);

      final crushY = body.aging;
      final faces = buildBoxFaces(
        body.x, body.z,
        body.boxW, body.boxH, body.boxD,
        body.rotY,
        crushY,
        body.color,
        body.aging,
      );

      // Offset Y for drop animation
      final yOff = body.y;
      for (final face in faces) {
        final shifted = Face(
          face.vertices.map((v) => Vec3(v.x, v.y + yOff, v.z)).toList(),
          face.color,
        );
        allFaces.add(_FaceWithDepth(shifted, Camera.depth(shifted.center), body));
      }

      // Cigarette butts
      if (showButts) {
        _drawButt3D(canvas, size, body);
      }
    }

    // Sort by depth (far first)
    allFaces.sort((a, b) => b.depth.compareTo(a.depth));

    // Draw all faces
    for (final fd in allFaces) {
      _drawFace(canvas, size, fd.face, fd.body);
    }
  }

  void _drawGround(Canvas canvas, Size size) {
    // Ground plane as a subtle grid
    const gridSize = 40.0;
    final linePaint = Paint()
      ..color = const Color(0xFF252525)
      ..strokeWidth = 0.5;

    for (double gx = -160; gx <= 160; gx += gridSize) {
      final p1 = Camera.project(Vec3(gx, 0, -120), size);
      final p2 = Camera.project(Vec3(gx, 0, 120), size);
      canvas.drawLine(p1, p2, linePaint);
    }
    for (double gz = -120; gz <= 120; gz += gridSize) {
      final p1 = Camera.project(Vec3(-160, 0, gz), size);
      final p2 = Camera.project(Vec3(160, 0, gz), size);
      canvas.drawLine(p1, p2, linePaint);
    }
  }

  void _drawShadow(Canvas canvas, Size size, CigBody body) {
    final shadowY = 0.5; // just above ground
    final spread = 1.2 + (-body.y * 0.003).clamp(0, 0.5);
    final alpha = (40 * (1 + body.y * 0.01).clamp(0.2, 1.0)).round();

    final hw = body.boxW / 2 * spread;
    final hd = body.boxD / 2 * spread;
    final cosR = cos(body.rotY), sinR = sin(body.rotY);

    final points = [
      Vec3(body.x + (-hw * cosR - (-hd) * sinR), shadowY, body.z + (-hw * sinR + (-hd) * cosR)),
      Vec3(body.x + (hw * cosR - (-hd) * sinR), shadowY, body.z + (hw * sinR + (-hd) * cosR)),
      Vec3(body.x + (hw * cosR - hd * sinR), shadowY, body.z + (hw * sinR + hd * cosR)),
      Vec3(body.x + (-hw * cosR - hd * sinR), shadowY, body.z + (-hw * sinR + hd * cosR)),
    ];

    final path = Path();
    final p0 = Camera.project(points[0], size);
    path.moveTo(p0.dx, p0.dy);
    for (int i = 1; i < points.length; i++) {
      final p = Camera.project(points[i], size);
      path.lineTo(p.dx, p.dy);
    }
    path.close();

    final shadowPaint = Paint()
      ..color = Colors.black.withAlpha(alpha)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawPath(path, shadowPaint);
  }

  void _drawFace(Canvas canvas, Size size, Face face, CigBody body) {
    // Back-face culling
    final projVerts = face.vertices.map((v) => Camera.project(v, size)).toList();

    // Check winding order (skip if face points away)
    final edge1 = Offset(projVerts[1].dx - projVerts[0].dx, projVerts[1].dy - projVerts[0].dy);
    final edge2 = Offset(projVerts[2].dx - projVerts[0].dx, projVerts[2].dy - projVerts[0].dy);
    final cross = edge1.dx * edge2.dy - edge1.dy * edge2.dx;
    if (cross > 0) return; // back-facing

    // Lighting
    final normal = face.normal;
    final lightDir = const Vec3(0.3, -0.8, -0.5).normalized;
    final diffuse = max(0.0, normal.dot(lightDir));
    final ambient = 0.35;
    final brightness = (ambient + diffuse * 0.65).clamp(0.0, 1.0);

    // Lit color
    final hsl = HSLColor.fromColor(face.color);
    final litColor = hsl.withLightness((hsl.lightness * brightness).clamp(0.05, 0.95)).toColor();

    final path = Path();
    path.moveTo(projVerts[0].dx, projVerts[0].dy);
    for (int i = 1; i < projVerts.length; i++) {
      path.lineTo(projVerts[i].dx, projVerts[i].dy);
    }
    path.close();

    // Fill
    canvas.drawPath(path, Paint()..color = litColor);

    // Edge highlight
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withAlpha(15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );

    // Brand label on front face (the one facing camera most)
    if (normal.z > 0.3 && normal.y < 0.3) {
      _drawLabel(canvas, size, face, body);
    }
    // Also draw on top face
    if (normal.y < -0.5) {
      _drawTopLabel(canvas, size, face, body);
    }
  }

  void _drawLabel(Canvas canvas, Size size, Face face, CigBody body) {
    final center = face.center;
    final projected = Camera.project(center, size);
    final depth = Camera.depth(center);
    final textScale = (400 / max(depth, 1)).clamp(0.3, 1.2);

    final tp = TextPainter(
      text: TextSpan(
        text: body.label,
        style: TextStyle(
          color: Colors.white.withAlpha(220),
          fontSize: 10 * textScale,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(color: Colors.black.withAlpha(150), blurRadius: 2)],
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 2,
    );
    tp.layout(maxWidth: 60 * textScale);
    tp.paint(canvas, Offset(projected.dx - tp.width / 2, projected.dy - tp.height / 2));
  }

  void _drawTopLabel(Canvas canvas, Size size, Face face, CigBody body) {
    if (body.aging < 0.3) return; // only show on aged/crushed boxes
    final center = face.center;
    final projected = Camera.project(center, size);
    final depth = Camera.depth(center);
    final textScale = (350 / max(depth, 1)).clamp(0.2, 0.9);

    final tp = TextPainter(
      text: TextSpan(
        text: body.label,
        style: TextStyle(
          color: Colors.white.withAlpha(120),
          fontSize: 8 * textScale,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: 50 * textScale);
    tp.paint(canvas, Offset(projected.dx - tp.width / 2, projected.dy - tp.height / 2));
  }

  void _drawButt3D(Canvas canvas, Size size, CigBody body) {
    final buttPos = Vec3(body.x + body.boxW * 0.6, 0.2, body.z + body.boxD * 0.5);
    final p = Camera.project(buttPos, size);
    final depth = Camera.depth(buttPos);
    final scale = (400 / max(depth, 1)).clamp(0.3, 1.5);

    // Filter
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: p, width: 16 * scale, height: 4 * scale),
        Radius.circular(2 * scale),
      ),
      Paint()..color = const Color(0xFFF0E6D2),
    );
    // Burnt tip
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(p.dx + 9 * scale, p.dy), width: 6 * scale, height: 4 * scale),
        Radius.circular(1 * scale),
      ),
      Paint()..color = const Color(0xFF3A3A3A),
    );
    // Ember
    if (body.aging < 0.2) {
      canvas.drawCircle(
        Offset(p.dx + 11 * scale, p.dy),
        3 * scale,
        Paint()
          ..color = const Color(0xFFE8650B).withAlpha(100)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * scale),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _Scene3DPainter oldDelegate) => true;
}

class _FaceWithDepth {
  final Face face;
  final double depth;
  final CigBody body;
  _FaceWithDepth(this.face, this.depth, this.body);
}
