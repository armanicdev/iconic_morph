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
///  * [fade] is the share of the timeline the ink spends fading IN as the pen
///    starts (or OUT as a [reversed] erase finishes). Without it the glyph is
///    fully opaque from its first pixel and simply stops existing on its last —
///    a hard edge at both ends, and a conspicuous one, because a round-capped
///    stroke shorter than its own width is a DOT. 0 disables it.
class IconTrimDraw extends IconEffect {
  const IconTrimDraw({
    this.duration = IconMotion.iconDraw,
    this.curve = Curves.easeInOutCubic,
    this.continuous = true,
    this.reversed = false,
    this.loops = false,
    this.fade = StrokeTaper.kEndFade,
  });

  @override
  final Duration duration;

  final Curve curve;
  final bool continuous;
  final bool reversed;

  /// Share of the timeline spent fading the ink in (or out, when [reversed]).
  /// Applied to the RAW t, which is linear in time — applying it to the eased
  /// length instead would make its duration a function of [curve].
  final double fade;

  @override
  final bool loops;

  @override
  double get restValue => 1; // rest fully drawn

  @override
  void paint(Canvas canvas, Size size, IconGeometry geom, double t, Paint paint) {
    final raw = t.clamp(0.0, 1.0);
    final e = curve.transform(raw);
    final f = reversed ? 1 - e : e;
    // The ink fades in as the pen starts, or out as an erase finishes — either
    // way over the END of the timeline where the stroke is a sliver, and settled
    // well before the trim itself reaches the other end.
    final p = StrokeTaper.weighted(paint, 1,
        alpha: StrokeTaper.emerge(reversed ? 1 - raw : raw, fade));
    if (p == null) return;
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

    canvas.drawPath(path, p);
  }
}
