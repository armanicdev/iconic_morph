import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../motion.dart';

import '../icon_geometry.dart';
import '../icon_effect.dart';

/// An idle **blink** — the "eye" contours briefly squash shut and reopen on a
/// loop, with a long rest gap between blinks, so a face glyph feels alive at rest
/// (e.g. `MorphIcons.face`). Everything else is drawn untouched.
///
/// Eyes are detected geometrically (no per-icon config needed, so it's reusable
/// on any glyph): a contour counts as an eye when it is small (bounding-box height
/// ≤ [eyeMaxHeight] viewBox units) AND sits in the upper [eyeRegion] of the glyph.
/// Each eye squashes vertically about its own centroid so lids "close" in place.
/// Tune [eyeMaxHeight] / [eyeRegion] for a different glyph; if no eyes are found
/// the effect draws the icon unchanged (a harmless no-op idle).
class IconBlink extends IconEffect {
  const IconBlink({
    this.duration = IconMotion.iconBlink,
    this.eyeMaxHeight = 3.0,
    this.eyeRegion = 0.55,
    this.blinkFraction = 0.12,
    this.minOpen = 0.06,
  });

  @override
  final Duration duration;

  /// Max contour bounding-box height (viewBox units) to count as an eye.
  final double eyeMaxHeight;

  /// Eyes must sit in the top this-fraction of the glyph (0..1).
  final double eyeRegion;

  /// Portion of the cycle spent blinking; the rest is the eyes-open rest gap.
  final double blinkFraction;

  /// How far the lids close (0 = fully shut; 0.06 leaves a sliver so the round
  /// stroke caps never fully vanish).
  final double minOpen;

  @override
  bool get loops => true;

  @override
  bool get autoReverse => false;

  @override
  void paint(Canvas canvas, Size size, IconGeometry geom, double t, Paint paint) {
    // Closure over the cycle: a single quick close→open inside [blinkFraction],
    // flat (eyes open) for the rest — so blinks are occasional, not constant.
    final bf = blinkFraction.clamp(0.02, 0.9);
    final phase = t.clamp(0.0, 1.0);
    final close = phase < bf ? math.sin(math.pi * (phase / bf)) : 0.0;
    final squashY = 1 - (1 - minOpen) * close;

    final eyeCutoff = size.height * eyeRegion;
    for (final c in geom.contours) {
      final path = c.polygon; // cached; never rebuilt per frame
      final eye = _eye(c.points, eyeCutoff);
      if (eye != null && squashY < 0.999) {
        // Squash this eye vertically about its own centroid (lids meeting).
        canvas.save();
        canvas.translate(0, eye);
        canvas.scale(1, squashY);
        canvas.translate(0, -eye);
        canvas.drawPath(path, paint);
        canvas.restore();
      } else {
        canvas.drawPath(path, paint);
      }
    }
  }

  /// Eye test: returns the contour's centroid-Y if it is small enough and high
  /// enough to be an eye (so it can squash about that line), else null.
  double? _eye(List<Offset> points, double eyeCutoff) {
    if (points.isEmpty) return null;
    var minY = double.infinity, maxY = -double.infinity, sumY = 0.0;
    for (final p in points) {
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
      sumY += p.dy;
    }
    final cy = sumY / points.length;
    return (maxY - minY <= eyeMaxHeight && cy <= eyeCutoff) ? cy : null;
  }
}
