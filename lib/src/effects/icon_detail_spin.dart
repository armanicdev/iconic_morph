import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import '../math/mat4.dart' as vm;

import '../motion.dart';

import '../icon_geometry.dart';
import '../icon_effect.dart';
import '../projection_3d.dart';
import '../stroke_taper.dart';

/// A "knock" press animation composed per-contour on one timeline:
///  1. the icon's small **accent** detail trims OUT (e.g. a home-screen smile),
///  2. the **body** (every other contour) does a full constant-stroke **3D turn**,
///  3. the accent trims back **IN** as the body lands front-facing.
///
/// Unlike [IconSequence] (which plays whole-glyph effects in turn), this splits
/// the glyph: the accent contour(s) trim while the body spins through
/// [Projector3D]. The windows overlap slightly at hand-offs so it reads as one
/// fluid beat, not three distinct steps.
///
/// Efficient: per frame it projects the body polyline once (one matrix, one
/// scratch vector) and trims the accent by arc length — two [Canvas.drawPath]
/// calls, no per-frame [Path.computeMetrics]. Rests as the complete icon
/// ([restValue] 0), so reduced-motion shows the plain glyph.
class IconDetailSpin extends IconEffect {
  const IconDetailSpin({
    this.duration = IconMotion.iconPress,
    this.turns = 1,
    this.axis = Spin3DAxis.vertical,
    this.perspective = 0.0026,
    this.accentIndices,
  });

  @override
  final Duration duration;

  /// Whole turns the body makes (1 = 360°, so it lands exactly front-facing).
  final double turns;

  final Spin3DAxis axis;
  final double perspective;

  /// Which contours are the ACCENT detail that trims out/in. Null → auto-pick the
  /// single SHORTEST contour (the small feature, e.g. the smile on home-smile) —
  /// order-independent, so it survives subpath reordering.
  final Set<int>? accentIndices;

  @override
  double get restValue => 0; // rests as the complete, settled icon

  // Phase windows on the raw 0..1 timeline; the small overlaps are the buttery
  // hand-offs (accent finishes leaving as the body starts turning, and starts
  // returning as the body finishes).
  static const double _outEnd = 0.30; // accent trims OUT over [0, .30]
  static const double _spinStart = 0.18; // body spins over [.18, .82]
  static const double _spinEnd = 0.82;
  static const double _inStart = 0.70; // accent trims IN over [.70, 1]

  @override
  void paint(Canvas canvas, Size size, IconGeometry geom, double t, Paint paint) {
    final accent = accentIndices ?? {_shortestContour(geom)};
    final c = size.width / 2;

    // ── BODY: every non-accent contour, projected through the 3D turn ──────────
    final spinLocal =
        ((t - _spinStart) / (_spinEnd - _spinStart)).clamp(0.0, 1.0);
    // Emphasized ease: quick wind-up, long graceful deceleration into the
    // front-facing rest — snappier attack + softer landing than a symmetric
    // easeInOut at this beat length.
    final angle =
        turns * 2 * math.pi * Curves.easeInOutCubicEmphasized.transform(spinLocal);
    final proj = Projector3D(perspective: perspective, axis: axis);
    final m = proj.matrixFor(angle, c);
    final scratch = vm.Vector3.zero();
    final body = Path();
    for (var i = 0; i < geom.contours.length; i++) {
      if (accent.contains(i)) continue;
      final contour = geom.contours[i];
      proj.projectInto(body, contour.points, m, scratch, closed: contour.isClosed);
    }
    canvas.drawPath(body, paint);

    // ── ACCENT: ONE-DIRECTIONAL trim — sweeps start→end BOTH on the way out and
    // back in, so it never ping-pongs (retraces). OUT = a feed-through DRAIN (the
    // start climbs 0→L while the end stays at L, emptying the stroke toward the
    // end); IN = a normal draw-on (the end climbs 0→L from a fixed start). The
    // accent is fully gone in between (behind the body spin), so the redraw
    // beginning at the start reads as a continuation, not a reversal. ───────────
    final accentPath = Path();
    var hasAccent = false;
    // The accent is the glyph's SHORTEST contour, so its trim spends most of its
    // life near the length where a round-capped stroke degenerates into a dot.
    // Weight it by the ink it still has (min across accents — they share one
    // drawPath), so it drains away and returns as a stroke, never as a stamp.
    var weight = 1.0;
    if (t <= _outEnd) {
      // Ease-OUT attack: the drain starts the instant the finger lands (the
      // responsive tick), then softens — an ease-in here reads as input lag.
      final g = Curves.easeOutCubic.transform(t / _outEnd); // drain 0 → 1
      if (g < 1) {
        for (final i in accent) {
          if (i < 0 || i >= geom.contours.length) continue;
          final contour = geom.contours[i];
          appendContourRange(
            accentPath,
            contour,
            contour.length * g,
            contour.length,
          );
          weight = math.min(
            weight,
            StrokeTaper.lengthClamp(
                contour.length * (1 - g), contour.length, paint.strokeWidth),
          );
          hasAccent = true;
        }
      }
    } else if (t >= _inStart) {
      final f =
          Curves.easeOutCubic.transform((t - _inStart) / (1 - _inStart)); // 0→1
      if (f > 0) {
        for (final i in accent) {
          if (i < 0 || i >= geom.contours.length) continue;
          final contour = geom.contours[i];
          // appendContourUpTo re-closes a fully-drawn closed contour so the final
          // join is a miter rather than an open round-cap seam.
          appendContourUpTo(accentPath, contour, contour.length * f);
          weight = math.min(
            weight,
            StrokeTaper.lengthClamp(
                contour.length * f, contour.length, paint.strokeWidth),
          );
          hasAccent = true;
        }
      }
    }
    if (!hasAccent) return;
    final accentPaint = StrokeTaper.weighted(paint, weight);
    if (accentPaint != null) canvas.drawPath(accentPath, accentPaint);
  }

  static int _shortestContour(IconGeometry geom) {
    var best = 0;
    var bestLen = double.infinity;
    for (var i = 0; i < geom.contours.length; i++) {
      final l = geom.contours[i].length;
      if (l < bestLen) {
        bestLen = l;
        best = i;
      }
    }
    return best;
  }
}
