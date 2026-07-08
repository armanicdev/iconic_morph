import 'dart:math' as math;
import 'dart:ui';

import '../icon_geometry.dart';

/// Pure geometry utilities for icon morphing — no Flutter widget dependencies,
/// so they are unit-testable on the VM.
///
/// Sampling:
///  * [resampleContour] — resamples a contour to N arc-evenly-spaced points,
///    the input the morph painter uses.
///  * [flatten] / [hash01] — utilities for a "whole-icon unravel into a single
///    string" style morph; not used by the default worm painter but available as
///    building blocks for custom effects.
///
/// Path windowing:
///  * [trimmedContour] / [trimmedRange] — draw-on and un-draw via arc-length
///    windows, used by both the morph's assemble/exit choreography and custom
///    effects.
abstract final class PathMorph {
  /// Resample [pts] (with cumulative arc-length [cum]) into [n] points spaced
  /// evenly by ARC LENGTH (not index), endpoints included. [n] must be >= 2.
  static List<Offset> resamplePolyline(
    List<Offset> pts,
    List<double> cum,
    int n,
  ) {
    final total = cum.isEmpty ? 0.0 : cum.last;
    if (pts.length < 2 || total <= 0) {
      final p = pts.isEmpty ? Offset.zero : pts.first;
      return List<Offset>.filled(n, p);
    }
    final out = <Offset>[];
    for (var i = 0; i < n; i++) {
      final d = total * i / (n - 1);
      out.add(_pointAt(pts, cum, d));
    }
    return out;
  }

  /// Resample one icon contour to [n] arc-evenly-spaced points.
  static List<Offset> resampleContour(IconContour c, int n) =>
      resamplePolyline(c.points, c.cumLength, n);

  /// Flatten an ENTIRE icon into [n] points in one continuous order — contour
  /// after contour, distributed by arc length across the glyph's total length.
  /// This is the source "string": drawn as one polyline, the short chords
  /// between contour ends read as the icon unravelling into a single thread.
  static List<Offset> flatten(IconGeometry g, int n) {
    final contours = g.contours;
    if (contours.isEmpty) return List<Offset>.filled(n, Offset.zero);
    final total = g.totalLength;
    if (total <= 0) {
      return List<Offset>.filled(n, contours.first.points.first);
    }
    final out = <Offset>[];
    for (var i = 0; i < n; i++) {
      out.add(_globalPoint(contours, total * i / (n - 1)));
    }
    return out;
  }

  /// Pick the orientation of [dst] (as-is or reversed) that makes points travel
  /// the SHORT way from [src] — the "smart connection" so the morph reads as a
  /// settle, not a scramble. Same-length lists required; returns [dst] untouched
  /// when lengths differ.
  static List<Offset> alignTo(List<Offset> src, List<Offset> dst) {
    if (src.length != dst.length) return dst;
    double cost(List<Offset> d) {
      var s = 0.0;
      for (var i = 0; i < src.length; i++) {
        s += (src[i] - d[i]).distance;
      }
      return s;
    }

    final rev = dst.reversed.toList();
    return cost(dst) <= cost(rev) ? dst : rev;
  }

  /// Build a path of the first [fraction] (0..1) of contour [c]'s arc length — a
  /// trim-path "draw-on" of ONE contour, lerping the final partial segment so the
  /// leading edge moves smoothly (not point-to-point). [fraction] >= 1 returns the
  /// whole contour (re-closed if it's a ring). Pure + reusable: the morph uses it
  /// to draw the target's non-hero contours on as the hero line lands.
  ///
  /// A thin alias over [trimmedRange] (= the window `0..fraction`) — the one
  /// trim-path walk, never re-copied.
  static Path trimmedContour(IconContour c, double fraction) =>
      trimmedRange(c, 0, fraction);

  /// Build a path of contour [c] over the arc-length WINDOW [from]..[to] (each a
  /// 0..1 fraction of the contour length), lerping BOTH partial end segments so
  /// the window's edges move smoothly (not point-to-point). Generalizes
  /// [trimmedContour]:
  ///  * `trimmedRange(c, 0, f)` draws the first `f` — the pen draws ON.
  ///  * shrinking [to] from 1 → 0 **un-draws** the contour from its open end
  ///    (the morph's trim-OUT exit — the temporal mirror of the draw-on, a pen
  ///    lifting and pulling the ink back).
  ///  * sliding [from] 0 → 1 erases it from the START instead.
  /// A window that fully covers a CLOSED ring (`from <= 0 && to >= 1`) is
  /// re-closed so its final join is a miter, not an open round-cap seam. Pure +
  /// reusable; returns an empty path for a degenerate window.
  static Path trimmedRange(IconContour c, double from, double to) {
    final path = Path();
    final pts = c.points;
    final cum = c.cumLength;
    final len = c.length;
    if (pts.length < 2 || len <= 0) return path;
    final a = from.clamp(0.0, 1.0) * len;
    final b = to.clamp(0.0, 1.0) * len;
    if (b - a <= 1e-9) return path;

    var started = false;
    for (var i = 1; i < pts.length; i++) {
      final segStart = cum[i - 1];
      final segEnd = cum[i];
      if (segEnd < a) continue; // segment lies entirely before the window
      final span = segEnd - segStart;
      if (!started) {
        // Enter the window: lerp to the exact start point inside this segment.
        final fa = span <= 0 ? 0.0 : ((a - segStart) / span).clamp(0.0, 1.0);
        final pa = Offset.lerp(pts[i - 1], pts[i], fa)!;
        path.moveTo(pa.dx, pa.dy);
        started = true;
      }
      if (segEnd <= b) {
        path.lineTo(pts[i].dx, pts[i].dy);
        if (i == pts.length - 1 && c.isClosed && from <= 0 && to >= 1.0) {
          path.close();
        }
      } else {
        // Exit the window mid-segment: lerp to the exact end point.
        final fb = span <= 0 ? 0.0 : ((b - segStart) / span).clamp(0.0, 1.0);
        final pb = Offset.lerp(pts[i - 1], pts[i], fb)!;
        path.lineTo(pb.dx, pb.dy);
        break;
      }
    }
    return path;
  }

  /// Centroid (mean) of a point list — used to score which target contour is the
  /// morph's hero feature line (nearest a given anchor).
  static Offset centroid(List<Offset> pts) {
    if (pts.isEmpty) return Offset.zero;
    var x = 0.0, y = 0.0;
    for (final p in pts) {
      x += p.dx;
      y += p.dy;
    }
    return Offset(x / pts.length, y / pts.length);
  }

  /// Deterministic per-index pseudo-random in [0, 1). Stable across frames and
  /// runs (no `Math.random`), so the wandering string is reproducible and
  /// testable while still looking chaotic.
  static double hash01(int i) {
    final x = math.sin(i * 12.9898 + 78.233) * 43758.5453;
    return x - x.floorToDouble();
  }

  // ── internals ─────────────────────────────────────────────────────────────

  /// Point at arc-length [d] along a single polyline.
  static Offset _pointAt(List<Offset> pts, List<double> cum, double d) {
    for (var i = 1; i < cum.length; i++) {
      if (cum[i] >= d) {
        final a = cum[i - 1], b = cum[i];
        final span = b - a;
        final f = span <= 0 ? 0.0 : ((d - a) / span).clamp(0.0, 1.0);
        return Offset.lerp(pts[i - 1], pts[i], f)!;
      }
    }
    return pts.last;
  }

  /// Point at GLOBAL arc-length [d] across a list of contours (concatenated).
  static Offset _globalPoint(List<IconContour> contours, double d) {
    var base = 0.0;
    for (final c in contours) {
      if (d <= base + c.length || identical(c, contours.last)) {
        return _pointAt(c.points, c.cumLength, (d - base).clamp(0.0, c.length));
      }
      base += c.length;
    }
    return contours.last.points.last;
  }
}
