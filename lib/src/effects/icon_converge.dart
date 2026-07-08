import 'package:flutter/widgets.dart';

import '../motion.dart';

import '../icon_geometry.dart';
import '../icon_effect.dart';

/// A calm "assemble" entrance: each contour drifts in from a small outward
/// offset — along its own direction from the icon center — while fading up, so a
/// multi-stroke glyph settles into place piece by piece. Softer than the 3D
/// [IconSpin3D.flipIn]: nothing rotates, the glyph just condenses into focus.
///
/// Per-contour [stagger] gives the assemble cascade (later contours arrive
/// later, all finishing together). With a single contour it reads as one gentle
/// drift-in. Rests fully assembled ([restValue] 1), so reduced-motion shows the
/// plain icon.
class IconConverge extends IconEffect {
  const IconConverge({
    this.duration = IconMotion.iconConverge,
    this.curve = Curves.easeOutCubic,
    this.spread = 3.2,
    this.stagger = 0.12,
  });

  @override
  final Duration duration;

  final Curve curve;

  /// Starting outward offset of each contour, in viewBox units.
  final double spread;

  /// Per-contour delay as a fraction of the timeline — but the CUMULATIVE delay
  /// is capped at [_maxSpread] so even a dense glyph (a QR/scan icon with dozens
  /// of subpaths) keeps a real drift-in window for its last contour. With few
  /// contours the full [stagger] is used; with many it shrinks to fit the cap.
  final double stagger;

  /// Largest total delay (last contour's start), as a fraction of the timeline.
  /// Guarantees every contour gets a span of at least `1 - _maxSpread` to animate.
  static const double _maxSpread = 0.5;

  @override
  double get restValue => 1; // assembled

  @override
  void paint(Canvas canvas, Size size, IconGeometry geom, double t, Paint paint) {
    final center = Offset(size.width / 2, size.height / 2);
    final n = geom.contours.length;
    final tt = t.clamp(0.0, 1.0);
    // Normalize the per-contour step so n-1 of them never overflow the timeline:
    // step ≤ _maxSpread / (n-1), so the last contour starts at ≤ _maxSpread and
    // still has ≥ (1 - _maxSpread) of the timeline to drift in.
    final step = n <= 1 ? 0.0 : stagger.clamp(0.0, _maxSpread / (n - 1));

    for (var i = 0; i < n; i++) {
      final c = geom.contours[i];
      // Window this contour over [delay .. 1] so later ones arrive later but all
      // land (local = 1) by t = 1.
      final delay = step * i;
      final span = 1 - delay;
      final local = span <= 0 ? 1.0 : ((tt - delay) / span).clamp(0.0, 1.0);
      if (local <= 0) continue; // not arrived yet → invisible
      final e = curve.transform(local);

      // Drift = a uniform offset of the whole contour, so translate the canvas
      // and draw the CACHED polygon rather than rebuilding an offset path point
      // by point every frame (identical result, no per-frame Path/point work).
      final off = _outward(c, center) * (spread * (1 - e));
      canvas.save();
      canvas.translate(off.dx, off.dy);
      canvas.drawPath(c.polygon, tintStroke(paint, e));
      canvas.restore();
    }
  }

  /// Unit vector from the icon center toward the contour's centroid (its own
  /// "out" direction). Falls back to straight up if the centroid sits dead
  /// center.
  static Offset _outward(IconContour c, Offset center) {
    var cx = 0.0, cy = 0.0;
    for (final p in c.points) {
      cx += p.dx;
      cy += p.dy;
    }
    final centroid = Offset(cx / c.points.length, cy / c.points.length);
    final d = centroid - center;
    final len = d.distance;
    if (len < 1e-3) return const Offset(0, -1);
    return d / len;
  }
}
