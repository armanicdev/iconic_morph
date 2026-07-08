import 'package:flutter/widgets.dart';

import '../motion.dart';

import '../icon_geometry.dart';
import '../icon_effect.dart';

/// A realistic two-sheet **riffle** for a stacked-tray glyph (e.g. `inbox-04`):
/// the BACK sheet and FRONT sheet deal out and return in a **nested ping-pong** —
/// the back leaves first and returns last, the front nested inside (back-out →
/// front-out → front-in → back-in) — while every moving sheet is **occluded** by
/// whatever sits in front of it. Each sheet is masked OUTSIDE the silhouettes of
/// the sheets/tray drawn after it, so the back sheet truly slides BEHIND the stack
/// (sinking behind the front sheet + the planted tray, then rising back up from
/// below into its slot) instead of floating over it.
///
/// Z-order is the glyph's own contour ranking, top→bottom by centroid y: the
/// top-most contour is the BACK sheet, the next is the FRONT sheet, and the bottom
/// [holdTray] contour(s) are the planted tray (drawn last, never move, mask both
/// sheets). It rests as the settled glyph ([restValue] 0 → seamless cycle,
/// reduced-motion shows the plain icon).
///
/// Cost is a couple of `Path.combine`s + a `clipPath` per moving sheet per frame
/// (only while the tap animation runs) — the "mask outside" the realism needs,
/// kept cheap by masking against cached silhouettes, not a saveLayer.
///
/// Every timing/offset is a knob — each nav glyph is special and tuned on its own.
class IconInboxRiffle extends IconEffect {
  const IconInboxRiffle({
    this.duration = IconMotion.iconPress,
    this.drop = 6,
    this.rise = 7,
    this.holdTray = 1,
    this.backOutEnd = 0.30,
    this.frontOutStart = 0.22,
    this.frontOutEnd = 0.52,
    this.frontInEnd = 0.80,
    this.backInStart = 0.72,
  });

  @override
  final Duration duration;

  /// How far (viewBox px) a sheet sinks DOWN as it deals out.
  final double drop;

  /// How far (viewBox px) BELOW its slot a returning sheet starts before rising
  /// back up into place (the "from bottom to top" re-entry).
  final double rise;

  /// How many BOTTOM-most contours (by centroid y) are the planted tray — drawn
  /// once, never moved, and used as a front occluder. `1` for `inbox-04`.
  final int holdTray;

  // Nested phase windows on the 0..1 timeline. The back sheet wraps the OUTSIDE
  // (out first, in last); the front sheet nests INSIDE (out then straight back).
  // Small overlaps at the hand-offs keep it one fluid riffle, not four steps.
  final double backOutEnd; // back deals out over [0, backOutEnd]
  final double frontOutStart; // front deals out over [frontOutStart, frontOutEnd]
  final double frontOutEnd;
  final double frontInEnd; // front returns over [frontOutEnd, frontInEnd]
  final double backInStart; // back returns over [backInStart, 1]

  @override
  double get restValue => 0; // settled glyph; seamless out-and-back cycle

  @override
  void paint(Canvas canvas, Size size, IconGeometry geom, double t, Paint paint) {
    final contours = geom.contours;
    final n = contours.length;
    if (n == 0) return;
    final e = t.clamp(0.0, 1.0);

    // Rank top→bottom by centroid y: rank 0 = BACK sheet, last [holdTray] = tray.
    final order = List<int>.generate(n, (i) => i)
      ..sort((a, b) => _centroidY(contours[a]).compareTo(_centroidY(contours[b])));
    final trayFrom = (n - holdTray).clamp(0, n);

    final rect = Offset.zero & size;

    // Draw BACK → FRONT → TRAY. Each moving sheet is clipped OUTSIDE the union of
    // the silhouettes drawn AFTER it (the sheets/tray in front), so it rides
    // behind them — the realism the flat paint order can't give an outline glyph.
    for (var rank = 0; rank < n; rank++) {
      final (dy, alpha) = _state(rank, trayFrom, e);
      if (alpha <= 0) continue; // a fully-gone sheet paints nothing this frame

      // Occluder = union of every in-front contour's CURRENT silhouette.
      Path? occluder;
      for (var f = rank + 1; f < n; f++) {
        final (fdy, fAlpha) = _state(f, trayFrom, e);
        if (fAlpha <= 0) continue; // a vanished sheet can't occlude
        final sil = _silhouette(contours[order[f]], fdy);
        occluder =
            occluder == null ? sil : Path.combine(PathOperation.union, occluder, sil);
      }

      canvas.save();
      if (occluder != null) {
        // Clip to everything EXCEPT the occluder → the sheet shows only where it
        // is NOT behind a front sheet/tray ("mask outside" the front one).
        canvas.clipPath(
          Path.combine(PathOperation.difference, Path()..addRect(rect), occluder),
        );
      }
      canvas.translate(0, dy);
      canvas.drawPath(contours[order[rank]].polygon, tintStroke(paint, alpha));
      canvas.restore();
    }
  }

  /// Current vertical offset + alpha for a ranked contour at timeline [e].
  (double, double) _state(int rank, int trayFrom, double e) {
    if (rank >= trayFrom) return (0, 1); // tray: planted, opaque

    if (rank == 0) {
      // BACK: sink+fade out early, hide through the middle, rise+fade in late.
      // Ease-OUT on the deal-out: the sheet moves the instant the finger lands
      // (responsive), then decelerates — ease-in here reads as input lag.
      if (e <= backOutEnd) {
        final o = Curves.easeOutCubic.transform((e / backOutEnd).clamp(0.0, 1.0));
        return (drop * o, 1 - o);
      }
      if (e >= backInStart) {
        final o = Curves.easeOutCubic
            .transform(((e - backInStart) / (1 - backInStart)).clamp(0.0, 1.0));
        return (-rise * (1 - o), o); // starts low, rises into its slot
      }
      return (drop, 0); // gone, parked low behind the stack
    }

    // FRONT (and any sheet between back and tray): deal out, then straight back.
    if (e <= frontOutStart) return (0, 1); // still settled
    if (e <= frontOutEnd) {
      final o = Curves.easeOutCubic.transform(
          ((e - frontOutStart) / (frontOutEnd - frontOutStart)).clamp(0.0, 1.0));
      return (drop * o, 1 - o);
    }
    if (e <= frontInEnd) {
      final o = Curves.easeOutCubic
          .transform(((e - frontOutEnd) / (frontInEnd - frontOutEnd)).clamp(0.0, 1.0));
      return (-rise * (1 - o), o);
    }
    return (0, 1); // settled again
  }

  /// A filled silhouette of a contour (open arcs are closed into a sheet region),
  /// optionally shifted down by [dy] — the mask used to occlude sheets behind it.
  Path _silhouette(IconContour c, double dy) {
    final p = Path()..addPolygon(c.points, true);
    return dy == 0 ? p : p.shift(Offset(0, dy));
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
