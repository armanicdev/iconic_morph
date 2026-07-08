import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../motion.dart';

import '../icon_geometry.dart';
import '../icon_effect.dart';

/// Shrinks each of the glyph's contours along its long axis by [shrink] viewBox
/// units (both ends pull in toward the center) and lets it spring back, one at
/// a time in top-to-bottom order. Works well on glyphs with horizontal bars (e.g.
/// a hamburger menu) — each bar briefly shortens in sequence, a clean ripple
/// with no spin.
///
/// Each contour is scaled about its own bounding-box center. Rests as the plain
/// icon ([restValue] 0), so the ripple is an emphasis on tap; reduced-motion
/// shows the static glyph.
class IconLineShrink extends IconEffect {
  const IconLineShrink({
    this.duration = IconMotion.iconPress,
    this.shrink = 10,
    this.span = 0.6,
  });

  @override
  final Duration duration;

  /// How much (viewBox px) each contour loses off its length at the peak.
  final double shrink;

  /// Each contour's active window length on the 0..1 timeline; the rest
  /// (`1 - span`) is the one-by-one stagger spread.
  final double span;

  @override
  double get restValue => 0; // rests as the plain icon

  @override
  void paint(Canvas canvas, Size size, IconGeometry geom, double t, Paint paint) {
    final cs = geom.contours;
    final n = cs.length;
    if (n == 0) return;
    final e = t.clamp(0.0, 1.0);

    // Bbox per contour, ranked top→bottom.
    final boxes = [for (final c in cs) c.polygon.getBounds()];
    final order = List<int>.generate(n, (i) => i)
      ..sort((a, b) => boxes[a].center.dy.compareTo(boxes[b].center.dy));
    final spread = 1 - span;

    for (var rank = 0; rank < n; rank++) {
      final i = order[rank];
      final box = boxes[i];
      final start = n > 1 ? rank / (n - 1) * spread : 0.0;
      final local = ((e - start) / span).clamp(0.0, 1.0);

      // Shrink the LONG axis by `shrink` px at the peak, easing back to full.
      final horizontal = box.width >= box.height;
      final extent = horizontal ? box.width : box.height;
      final scaleMin = extent <= shrink ? 0.05 : (extent - shrink) / extent;
      final f = 1 - (1 - scaleMin) * _hump(local);

      canvas.save();
      canvas.translate(box.center.dx, box.center.dy);
      canvas.scale(horizontal ? f : 1, horizontal ? 1 : f);
      canvas.translate(-box.center.dx, -box.center.dy);
      canvas.drawPath(cs[i].polygon, paint);
      canvas.restore();
    }
  }

  /// 0 → 1 → 0 over a local 0..1 window — shrink in, spring back to rest.
  static double _hump(double x) => math.sin(math.pi * x.clamp(0.0, 1.0));
}
