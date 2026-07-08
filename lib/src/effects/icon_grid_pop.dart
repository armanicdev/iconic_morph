import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import '../math/mat4.dart' as vm;

import '../motion.dart';

import '../icon_geometry.dart';
import '../icon_effect.dart';
import '../projection_3d.dart';

/// A staggered **pop** for a grid-style glyph (e.g. a circle + two squares + a
/// plus). Each piece scales up about its own centre and settles in reading order
/// — circle first, then the squares, then the plus — and the plus ALSO does a
/// constant-stroke **3D turn** about its own centre as it pops. Snappy; rests as
/// the plain icon ([restValue] 0), so the pop is an emphasis on tap, not an
/// entrance.
///
/// Classification (path-level, order-independent): open contours are the plus;
/// closed contours are the circle and squares, and the circle is the closed one
/// nearest the top-left (smallest `cx+cy`). Each piece is one of the glyph's
/// real sampled contours — nothing moves as a whole.
class IconGridPop extends IconEffect {
  const IconGridPop({
    this.duration = IconMotion.iconPress,
    this.scaleAmp = 0.18,
    this.spinTurns = 1,
    this.tiltAmp = 0.32,
    this.perspective = 0.0026,
  });

  @override
  final Duration duration;

  /// Peak scale bump (e.g. 0.18 → pops to 1.18× then settles).
  final double scaleAmp;

  /// Whole 3D turns the plus makes about the vertical axis (1 = 360°, lands flat).
  final double spinTurns;

  /// Peak X-axis tilt (radians) layered onto the spin so the plus tumbles
  /// obliquely (a real 3D tilt) instead of a flat card-flip; eases 0 → peak → 0
  /// so it rests flat. ~0.32 rad ≈ 18°.
  final double tiltAmp;

  final double perspective;

  @override
  double get restValue => 0; // rests as the plain icon

  // Stagger windows on the 0..1 timeline (overlapping = a flowing cascade).
  static const double _circle0 = 0.0, _circle1 = 0.42;
  static const double _sq0 = 0.20, _sq1 = 0.66;
  static const double _plus0 = 0.38, _plus1 = 1.0;

  @override
  void paint(Canvas canvas, Size size, IconGeometry geom, double t, Paint paint) {
    final cs = geom.contours;
    final n = cs.length;
    if (n == 0) return;
    final e = t.clamp(0.0, 1.0);

    // Split: open contours = the plus; closed = circle + squares.
    final open = <int>[];
    final closed = <int>[];
    for (var i = 0; i < n; i++) {
      (cs[i].isClosed ? closed : open).add(i);
    }
    // Circle = the closed contour nearest the top-left; the rest are squares.
    closed.sort((a, b) {
      final ca = _centroid(cs[a]);
      final cb = _centroid(cs[b]);
      return (ca.dx + ca.dy).compareTo(cb.dx + cb.dy);
    });

    double localOf(double a, double b) => ((e - a) / (b - a)).clamp(0.0, 1.0);

    // ── Circle: scale-pop about its centre ────────────────────────────────────
    if (closed.isNotEmpty) {
      _drawScaled(canvas, cs[closed.first],
          1 + scaleAmp * _hump(localOf(_circle0, _circle1)), paint);
    }
    // ── Squares: scale-pop together (after the circle) ────────────────────────
    final sSq = 1 + scaleAmp * _hump(localOf(_sq0, _sq1));
    for (var i = 1; i < closed.length; i++) {
      _drawScaled(canvas, cs[closed[i]], sSq, paint);
    }
    // ── Plus: scale-pop + constant-stroke 3D turn about its own centre ────────
    if (open.isNotEmpty) {
      final lp = localOf(_plus0, _plus1);
      final sP = 1 + scaleAmp * _hump(lp);
      // Calm full turn about Y, with an X tilt that humps in + out so the plus
      // tumbles on an oblique axis (reads 3D) and still rests flat.
      // Emphasized ease: quick wind-up, long graceful settle onto the flat rest.
      final angleY =
          spinTurns * 2 * math.pi * Curves.easeInOutCubicEmphasized.transform(lp);
      final angleX = tiltAmp * _hump(lp);

      // Centre of the plus (it sits on the diagonal, so a scalar centre is exact).
      var sx = 0.0, sy = 0.0, cnt = 0;
      for (final i in open) {
        for (final p in cs[i].points) {
          sx += p.dx;
          sy += p.dy;
          cnt++;
        }
      }
      final cx = cnt == 0 ? size.width / 2 : sx / cnt;
      final cy = cnt == 0 ? size.height / 2 : sy / cnt;

      // Combined perspective · rotateY · rotateX, centred on the plus (so the
      // vanishing point is its own centre). Projector3D is single-axis, so build
      // the two-axis matrix here and project through it.
      final m = vm.Matrix4.identity()
        ..translateByDouble(cx, cy, 0, 1)
        ..multiply(vm.Matrix4.identity()..setEntry(3, 2, -perspective))
        ..rotateY(angleY)
        ..rotateX(angleX)
        ..translateByDouble(-cx, -cy, 0, 1);
      final scratch = vm.Vector3.zero();
      final plus = Path();
      for (final i in open) {
        Projector3D(perspective: perspective)
            .projectInto(plus, cs[i].points, m, scratch, closed: cs[i].isClosed);
      }

      canvas.save();
      canvas.translate(cx, cy);
      canvas.scale(sP);
      canvas.translate(-cx, -cy);
      canvas.drawPath(plus, paint);
      canvas.restore();
    }
  }

  /// Scale [c] about its own centroid and stroke it.
  static void _drawScaled(Canvas canvas, IconContour c, double s, Paint paint) {
    final ce = _centroid(c);
    canvas.save();
    canvas.translate(ce.dx, ce.dy);
    canvas.scale(s);
    canvas.translate(-ce.dx, -ce.dy);
    canvas.drawPath(c.polygon, paint);
    canvas.restore();
  }

  /// 0 → 1 → 0 over a local 0..1 window — a scale pop that rests at 1.
  static double _hump(double x) => math.sin(math.pi * x.clamp(0.0, 1.0));

  static Offset _centroid(IconContour c) {
    if (c.points.isEmpty) return Offset.zero;
    var sx = 0.0, sy = 0.0;
    for (final p in c.points) {
      sx += p.dx;
      sy += p.dy;
    }
    return Offset(sx / c.points.length, sy / c.points.length);
  }
}
