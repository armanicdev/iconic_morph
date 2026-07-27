import 'package:flutter/widgets.dart';

import '../motion.dart';

import '../icon_geometry.dart';
import '../icon_effect.dart';
import '../stroke_taper.dart';

/// Trim-path "draw-on" — the icon is drawn as if by a pen, growing from 0 to its
/// full length. Walks the pre-sampled polylines + cumulative arc-length (no
/// per-frame [Path.computeMetrics]), interpolating the final partial segment so
/// the leading edge moves smoothly rather than snapping point to point.
///
///  * [continuous] true: one global pen travels contour after contour (a single
///    connected reveal). false: every contour draws simultaneously from its own
///    start (a blooming reveal) — nice for multi-stroke glyphs.
///  * [reversed] erases instead of draws (full → empty).
///
/// The vanishing end carries `StrokeTaper`'s no-dot law: a round-capped stroke
/// shorter than its own width renders as a DOT, so the first sliver of a draw-on
/// (and the last sliver of a [reversed] erase) loses WEIGHT along with length —
/// the pen starts and finishes as ink, never as a stamped dot that pops.
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
      final drawn = geom.totalLength * f;
      var budget = drawn;
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
      // One pen, one length: weight the whole trail by how much ink it has.
      final p = StrokeTaper.weighted(
        paint,
        StrokeTaper.lengthClamp(drawn, geom.totalLength, paint.strokeWidth),
      );
      if (p != null) canvas.drawPath(path, p);
      return;
    }

    // Bloom: every contour draws from its own start, so each has its OWN sliver
    // to protect and its own weight. Those weights are 1 for every frame but the
    // first few, so the shared path is accumulated as before and the common case
    // stays exactly one drawPath — the per-contour path is built only for a
    // contour that is actually still tapering.
    final tapering = <IconContour, Paint>{};
    for (final c in geom.contours) {
      final w = StrokeTaper.lengthClamp(c.length * f, c.length, paint.strokeWidth);
      if (w >= 1) {
        appendContourUpTo(path, c, c.length * f);
        continue;
      }
      final p = StrokeTaper.weighted(paint, w);
      if (p != null) tapering[c] = p;
    }
    canvas.drawPath(path, paint);
    for (final entry in tapering.entries) {
      final one = Path();
      appendContourUpTo(one, entry.key, entry.key.length * f);
      canvas.drawPath(one, entry.value);
    }
  }
}
