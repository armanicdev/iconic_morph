import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../motion.dart';

import '../icon_geometry.dart';
import '../icon_effect.dart';

/// A **verify pulse** — a soft glowing node runs along the icon's own centerline
/// (a short bright tail trailing behind it) and exits, leaving the plain icon.
/// Because the glow follows the *sampled path geometry* rather than a flat
/// diagonal, the light visibly travels the glyph's actual shape — around a
/// shield and out through its check, down a lock's shackle — reading as the icon
/// being energized / authenticated, not a generic sheen sliding over it. Sibling
/// to the constant-stroke 3D spin: both exploit the centerline the engine
/// already samples, so it works on every icon with no per-icon authoring.
///
/// Polish guarantees:
///  * The base glyph is always drawn at full strength, and a `sin(π·t)` envelope
///    scales the glow to zero at t = 0 and t = 1 — so the pulse fades fully in
///    and out and rests as the plain icon ([restValue] 0 / reduced-motion safe).
///  * The glow is built from a few short sub-segments brightening toward the
///    head (round caps blend them), so it reads as one soft comet, not slices.
///
///  * One-shot by default; [IconTrace.idle] loops slowly (the envelope gives a
///    natural rest gap between passes and a seamless loop boundary).
class IconTrace extends IconEffect {
  const IconTrace({
    this.duration = IconMotion.iconTrace,
    this.curve = Curves.easeInOut,
    this.tailFraction = 0.34,
    this.intensity = 0.95,
    this.loops = false,
  });

  /// A slow, perpetual pulse — a calm "alive" idle affordance. Reuses the
  /// [IconMotion.shimmerSweep] period (the app's "slow calm glide + rest" tempo).
  const IconTrace.idle({
    Duration duration = IconMotion.shimmerSweep,
    double tailFraction = 0.3,
    double intensity = 0.8,
  }) : this(
          duration: duration,
          curve: Curves.easeInOut,
          tailFraction: tailFraction,
          intensity: intensity,
          loops: true,
        );

  @override
  final Duration duration;

  final Curve curve;

  /// Glowing tail length as a fraction of the glyph's total arc-length.
  final double tailFraction;

  /// Peak lighten toward white at the head of the pulse (0..1).
  final double intensity;

  @override
  final bool loops;

  @override
  double get restValue => 0; // envelope is 0 here → plain icon

  /// How many sub-segments the tail is built from (more = smoother glow ramp).
  static const int _slices = 8;

  /// The color the glow head brightens toward (a hot white core).
  static const Color _glowColor = Color(0xFFFFFFFF);

  @override
  void paint(Canvas canvas, Size size, IconGeometry geom, double t, Paint paint) {
    // Base glyph, full strength — always present, so rest is the plain icon.
    canvas.drawPath(geom.path, paint);

    final total = geom.totalLength;
    if (total <= 0) return;

    final tt = t.clamp(0.0, 1.0);
    // Envelope: 0 at both ends, 1 in the middle — the glow fades fully in and out
    // so nothing lingers at rest.
    final env = math.sin(math.pi * tt);
    if (env <= 0.001) return;

    final tail = (total * tailFraction).clamp(0.0001, total);
    final e = curve.transform(tt);
    // The head travels from the start to past the end (by one tail length), so
    // the whole pulse runs through the glyph and exits cleanly.
    final head = e * (total + tail);

    for (var k = 0; k < _slices; k++) {
      final a0 = head - tail + tail * k / _slices;
      final a1 = head - tail + tail * (k + 1) / _slices;
      // Brightness rises toward the head (k = slices-1 is the leading edge).
      final u = (k + 0.5) / _slices;
      final lift = intensity * env * (u * u);
      final seg = _band(geom, a0, a1);
      // Glow segment = base stroke brightened `lift` toward the hot core, base
      // alpha kept. Shared clone helper — no bespoke per-slice Paint build.
      if (seg != null) {
        canvas.drawPath(seg, tintStroke(paint, 1, toward: _glowColor, towardT: lift));
      }
    }
  }

  /// Extract the sub-path covering global arc-length [from]..[to] across all
  /// contours (clamped to each contour). Returns null if it lands off the glyph.
  static Path? _band(IconGeometry geom, double from, double to) {
    if (to <= 0) return null;
    final path = Path();
    var emitted = false;
    var base = 0.0; // global arc-length at the start of the current contour
    for (final c in geom.contours) {
      final a = from - base;
      final b = to - base;
      if (b > 0 && a < c.length) {
        if (_appendBetween(
          path,
          c,
          a.clamp(0.0, c.length),
          b.clamp(0.0, c.length),
        )) {
          emitted = true;
        }
      }
      base += c.length;
    }
    return emitted ? path : null;
  }

  /// Append the slice of contour [c] between arc-lengths [from]..[to], lerping
  /// both partial end segments so the glow edges land exactly. Consecutive
  /// in-band segments stay one connected stroke (no moveTo between them).
  static bool _appendBetween(Path path, IconContour c, double from, double to) {
    if (to <= from) return false;
    Offset? prev;
    var started = false;
    for (var i = 1; i < c.points.length; i++) {
      final segStart = c.cumLength[i - 1];
      final segEnd = c.cumLength[i];
      if (segEnd <= from) continue; // entirely before the glow
      if (segStart >= to) break; // entirely after the glow
      final span = segEnd - segStart;
      final s0 = segStart < from ? from : segStart;
      final s1 = segEnd > to ? to : segEnd;
      final f0 = span <= 0 ? 0.0 : (s0 - segStart) / span;
      final f1 = span <= 0 ? 1.0 : (s1 - segStart) / span;
      final p0 = Offset.lerp(c.points[i - 1], c.points[i], f0)!;
      final p1 = Offset.lerp(c.points[i - 1], c.points[i], f1)!;
      if (!started || prev != p0) path.moveTo(p0.dx, p0.dy);
      path.lineTo(p1.dx, p1.dy);
      prev = p1;
      started = true;
    }
    return started;
  }
}
