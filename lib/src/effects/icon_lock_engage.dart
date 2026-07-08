import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../motion.dart';

import '../icon_geometry.dart';
import '../icon_effect.dart';

/// One-shot **"lock engages"** — the lock physically CLICKS shut without changing
/// icon (no morph): the whole glyph gives a quick grow-and-settle (a clunk), a
/// small damped vertical bob, and the center keyhole "dot" spins as if a mechanism
/// turned. Use to confirm a passcode is set / something locked; pair with a medium
/// haptic for the physical intent.
///
/// The center "dot" is found geometrically (no per-icon config): the contour whose
/// bounding box fits within [dotMaxExtent] viewBox units (e.g. a lock's short
/// keyhole tick). 0 such contours → it just does the grow + bob (a harmless lock
/// pulse on any glyph).
class IconLockEngage extends IconEffect {
  const IconLockEngage({
    this.duration = IconMotion.iconSequence,
    this.spinTurns = 1.0,
    this.grow = 0.12,
    this.bob = 0.07,
    this.dotMaxExtent = 4.0,
  });

  @override
  final Duration duration;

  /// Full turns the center dot spins before settling upright.
  final double spinTurns;

  /// Peak extra scale of the whole glyph mid-strike (the "clunk"), settling to 1.
  final double grow;

  /// Peak vertical bob as a fraction of the glyph size (damped to rest).
  final double bob;

  /// Max contour bounding-box dimension (viewBox units) to count as the center
  /// "dot" that spins.
  final double dotMaxExtent;

  @override
  double get restValue => 1; // rest = fully locked, still

  @override
  void paint(Canvas canvas, Size size, IconGeometry geom, double t, Paint paint) {
    final tt = t.clamp(0.0, 1.0);
    final e = Curves.easeOutCubic.transform(tt);
    final decay = (1 - tt) * (1 - tt); // strong at the strike, gone by the end

    // Grow pulse: up past 1 mid-strike then settle to 1 — a physical clunk.
    final scale = 1 + grow * math.sin(tt * math.pi) * (1 - tt);
    // A couple of quick vertical bobs that settle.
    final dy = bob * size.height * math.sin(tt * math.pi * 3) * decay;
    // Center dot spins fast then eases to [spinTurns] full turns (rests upright).
    final spin = spinTurns * 2 * math.pi * e;

    final cx = size.width / 2, cy = size.height / 2;
    canvas.save();
    canvas.translate(0, dy);
    canvas.translate(cx, cy);
    canvas.scale(scale);
    canvas.translate(-cx, -cy);

    for (final c in geom.contours) {
      final dot = _dotCenter(c.points);
      if (dot != null && spin != 0) {
        canvas.save();
        canvas.translate(dot.dx, dot.dy);
        canvas.rotate(spin);
        canvas.translate(-dot.dx, -dot.dy);
        canvas.drawPath(c.polygon, paint); // cached; never rebuilt per frame
        canvas.restore();
      } else {
        canvas.drawPath(c.polygon, paint);
      }
    }
    canvas.restore();
  }

  /// Centroid of a contour IF it is small enough to be the center "dot"/keyhole
  /// (bounding box within [dotMaxExtent]), so it can spin about itself; else null.
  Offset? _dotCenter(List<Offset> pts) {
    if (pts.isEmpty) return null;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    var sx = 0.0, sy = 0.0;
    for (final p in pts) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
      sx += p.dx;
      sy += p.dy;
    }
    if (math.max(maxX - minX, maxY - minY) > dotMaxExtent) return null;
    return Offset(sx / pts.length, sy / pts.length);
  }
}
