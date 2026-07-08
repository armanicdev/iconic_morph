import 'package:flutter/widgets.dart';

import '../motion.dart';

import '../icon_geometry.dart';
import '../icon_effect.dart';

/// A **path-level** shuffle that works on the glyph's OWN contours — it does NOT
/// move the whole icon. Each contour (e.g. the inbox lid / body / tray) is dealt
/// **down + faded out** and immediately respawns **from above + fades in**, in a
/// staggered top→bottom cascade — the icon's layers riffle through themselves
/// like a shuffled stack.
///
/// Every piece is one of the glyph's real sampled contours
/// ([IconContour.polygon], cached), translated/tinted on its own — so the strokes
/// genuinely reshuffle. Seamless (frame 0 == frame 1, no jump), pure 2D (no 3D),
/// snappy. Cheap: a couple of `drawPath`s of cached polylines per contour.
class IconShuffle extends IconEffect {
  const IconShuffle({
    this.duration = IconMotion.iconPress,
    this.drop = 5,
    this.enter = 4,
    this.span = 0.6,
    this.holdBottom = 0,
  });

  @override
  final Duration duration;

  /// How far (viewBox px) a contour travels DOWN as it deals out.
  final double drop;

  /// How far (viewBox px) ABOVE its slot the respawning contour starts.
  final double enter;

  /// Each contour's active window length on the 0..1 timeline; the rest is the
  /// top→bottom stagger spread (`1 - span`).
  final double span;

  /// How many of the BOTTOM-most contours (by centroid y) are held STATIC — they
  /// draw once and never deal. e.g. 1 keeps the inbox tray planted while only the
  /// papers above it shuffle.
  final int holdBottom;

  @override
  double get restValue => 0; // rests as the settled glyph (seamless cycle)

  // Deal-out / deal-in windows WITHIN a contour's local span; they overlap in the
  // middle so a contour never fully blanks (a soft crossfade, not a flicker).
  static const double _outEnd = 0.55;
  static const double _inStart = 0.45;

  @override
  void paint(Canvas canvas, Size size, IconGeometry geom, double t, Paint paint) {
    final contours = geom.contours;
    final n = contours.length;
    if (n == 0) return;
    final e = t.clamp(0.0, 1.0);

    // Rank the contours top→bottom (by centroid y). Paint order follows this
    // (back paper first, front paper last → front stays ON TOP; the held bottom
    // tray paints last of all, so its rim sits in front of the papers).
    final order = List<int>.generate(n, (i) => i)
      ..sort((a, b) => _centroidY(contours[a]).compareTo(_centroidY(contours[b])));

    // The bottom [holdBottom] contours stay planted; only the ones above cascade.
    final animated = (n - holdBottom).clamp(0, n);
    final spread = 1 - span;

    for (var rank = 0; rank < n; rank++) {
      final path = contours[order[rank]].polygon;

      // Held-static contour (e.g. the inbox tray): draw once, no deal.
      if (rank >= animated) {
        canvas.drawPath(path, paint);
        continue;
      }

      // Deal the FRONT (lowest, nearest) paper FIRST, then back toward the top.
      // Front-first is what reads correctly: the paper on top of the stack is the
      // one a hand takes first. Reverse the rank for the start time (paint order
      // is untouched, so depth stays right).
      final start = animated > 1
          ? (animated - 1 - rank) / (animated - 1) * spread
          : 0.0;
      final local = ((e - start) / span).clamp(0.0, 1.0);

      // deal out: down + fade
      final out = (local / _outEnd).clamp(0.0, 1.0);
      if (out < 1) {
        final oe = Curves.easeInCubic.transform(out);
        canvas.save();
        canvas.translate(0, drop * oe);
        canvas.drawPath(path, tintStroke(paint, 1 - oe));
        canvas.restore();
      }
      // respawn: in from above + fade
      final inn = ((local - _inStart) / (1 - _inStart)).clamp(0.0, 1.0);
      if (inn > 0) {
        final ie = Curves.easeOutCubic.transform(inn);
        canvas.save();
        canvas.translate(0, -enter * (1 - ie));
        canvas.drawPath(path, tintStroke(paint, ie));
        canvas.restore();
      }
    }
  }

  static double _centroidY(IconContour c) {
    if (c.points.isEmpty) return double.infinity;
    var sum = 0.0;
    for (final p in c.points) {
      sum += p.dy;
    }
    return sum / c.points.length;
  }
}
