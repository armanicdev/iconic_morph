import 'package:flutter/widgets.dart';

import '../motion.dart';

import '../icon_geometry.dart';
import '../icon_effect.dart';

/// Trim-path "draw-on" — the icon is drawn as if by a pen, growing from 0 to its
/// full length. Walks the pre-sampled polylines + cumulative arc-length (no
/// per-frame [Path.computeMetrics]), interpolating the final partial segment so
/// the leading edge moves smoothly rather than snapping point to point.
///
///  * [continuous] true: one global pen travels contour after contour (a single
///    connected reveal). false: every contour draws simultaneously from its own
///    start (a blooming reveal) — nice for multi-stroke glyphs.
///  * [reversed] erases instead of draws (full → empty).
class IconTrimDraw extends IconEffect {
  const IconTrimDraw({
    this.duration = IconMotion.iconDraw,
    this.curve = Curves.easeInOutCubic,
    this.continuous = true,
    this.reversed = false,
    this.loops = false,
  });

  @override
  final Duration duration;

  final Curve curve;
  final bool continuous;
  final bool reversed;

  @override
  final bool loops;

  @override
  double get restValue => 1; // rest fully drawn

  @override
  void paint(Canvas canvas, Size size, IconGeometry geom, double t, Paint paint) {
    final e = curve.transform(t.clamp(0, 1));
    final f = reversed ? 1 - e : e;
    final path = Path();

    if (continuous) {
      var budget = geom.totalLength * f;
      for (final c in geom.contours) {
        if (budget <= 0) break;
        if (budget >= c.length) {
          appendContourUpTo(path, c, c.length);
          budget -= c.length;
        } else {
          appendContourUpTo(path, c, budget);
          break;
        }
      }
    } else {
      for (final c in geom.contours) {
        appendContourUpTo(path, c, c.length * f);
      }
    }

    canvas.drawPath(path, paint);
  }
}
