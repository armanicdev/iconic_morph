import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'icon_effect.dart';

/// The **weight law for a trim-path end** — how the ink's THICKNESS behaves while
/// a stroke draws on or un-draws. The companion to the arc-length window
/// (`PathMorph.trimmedRange`), which only ever owns the ink's LENGTH.
///
/// ## Why this exists
///
/// A trim-path that animates length alone cannot vanish cleanly. Two hard facts
/// of stroked geometry:
///
///  1. **A round-capped stroke shorter than its own width renders as a DOT.**
///     Retract a 2px-wide line and the last ~2 units of length stop reading as a
///     line at all — the ink becomes a fixed-size dot that then blinks out of
///     existence on the frame the window underflows. That "final dot, then sharp
///     gone" is the artifact this file exists to kill.
///  2. **`Paint.strokeWidth = 0` is NOT invisible** — Skia treats it as *hairline*
///     mode and draws a 1-device-pixel line. So a width that animates to zero
///     ends on a hairline flash unless the draw is skipped outright.
///
/// The cure is to let the ink LOSE WEIGHT as it loses length, so the stroke
/// physically runs out instead of collapsing to a dot:
///
///  * [out] — the trim-OUT taper: full weight until a chosen point of the exit,
///    then eased to nothing, so the pen lifts and the ink thins away.
///  * [into] — the mirror on the way in: the nib presses down over the first
///    fraction of a draw-on instead of stamping a full-weight dot on frame one.
///  * [lengthClamp] — the unconditional safety net: ink may never be wider than
///    a third of the length it still has, whatever the taper says. This is what
///    guarantees no dot for a contour of ANY size (and it leaves genuine
///    authored dots — contours whose whole length is a hair — at full weight,
///    shrinking them out rather than erasing them).
///  * [weighted] — turns a factor into a [Paint], holding a minimum renderable
///    width and paying the remainder in alpha (below ~0.35 units a stroke stops
///    thinning and just aliases), and returning `null` once the ink has run out
///    so the caller skips the draw entirely — never a width-0 hairline.
///
/// Pure and stateless: every method is a function of its arguments, so a
/// reversed/scrubbed playback rewinds the weight exactly like the geometry.
abstract final class StrokeTaper {
  /// Ink is never allowed to be fatter than `1 / [kLengthRatio]` of the length it
  /// still has — the ratio at which a round-capped stroke stops reading as a
  /// line and starts reading as a blob.
  static const double kLengthRatio = 3;

  /// Smallest width (viewBox units) that still renders as a clean stroke. Below
  /// this a thinning line stops looking thinner and starts aliasing, so [weighted]
  /// holds this width and takes the rest out of alpha instead.
  static const double kMinWidth = 0.35;

  /// Width (viewBox units) at or below which the ink counts as spent — [weighted]
  /// returns `null` and the caller draws nothing. Deliberately tiny so the ink is
  /// already a whisper when it goes, and never 0 (see the hairline note above).
  static const double kVanish = 0.02;

  /// **Trim-OUT taper.** Weight factor (1 → 0) for a contour that is un-drawing,
  /// at exit progress [prog] (0 = fully present, 1 = gone).
  ///
  /// Holds full weight until [start] of the exit — so the retract still reads as
  /// a real line being pulled back — then eases to nothing on an S-curve, landing
  /// on 0 exactly when the length does. `start >= 1` disables the taper (constant
  /// weight, the pre-1.1 behaviour).
  static double out(double prog, double start) {
    final s = start.clamp(0.0, 1.0);
    if (s >= 1) return 1;
    final u = ((prog - s) / (1 - s)).clamp(0.0, 1.0);
    if (u <= 0) return 1;
    // Same S-shape as the engine's other smooth ramps: flat at both ends, so the
    // taper neither snaps on nor snaps off.
    return 1 - Curves.easeInOut.transform(u);
  }

  /// **Trim-IN ramp.** Weight factor (0 → 1) for a contour that is drawing on, at
  /// draw progress [local] (0 = nothing drawn, 1 = complete).
  ///
  /// The nib presses down over the first [end] of the draw and holds full weight
  /// for the rest, so a draw-on begins as ink rather than as a full-weight dot.
  /// `end <= 0` disables the ramp.
  static double into(double local, double end) {
    final e = end.clamp(0.0, 1.0);
    if (e <= 0) return 1;
    final u = (local / e).clamp(0.0, 1.0);
    // Ease-out: reaches full weight quickly, so the piece matches the static icon
    // for most of its draw and only the entry is soft.
    return Curves.easeOutCubic.transform(u);
  }

  /// **The no-dot clamp.** Weight factor for ink that currently covers
  /// [visibleLength] of a contour whose whole length is [fullLength].
  ///
  /// Returns 1 while the stroke is comfortably longer than it is wide, then falls
  /// to 0 as the visible length approaches nothing — so the final stub thins out
  /// instead of turning into a round-cap dot. Unconditional: it applies whatever
  /// the [out]/[into] knobs are set to.
  ///
  /// A genuinely authored dot (a contour whose entire length is a hair, e.g. a
  /// keyhole) references its own length, so it sits at full weight when present
  /// and shrinks out when it leaves — never erased for being short.
  static double lengthClamp(
    double visibleLength,
    double fullLength, [
    double strokeWidth = kIconStrokeWidth,
  ]) {
    if (visibleLength <= 0) return 0;
    final ref = math.min(kLengthRatio * strokeWidth, fullLength);
    if (ref <= 0) return 1;
    return (visibleLength / ref).clamp(0.0, 1.0);
  }

  /// Applies a weight [factor] to [base], returning the [Paint] to stroke with —
  /// or **`null` when the ink has run out**, meaning: draw nothing at all.
  ///
  /// Returning `null` rather than a zero-width paint is load-bearing: Skia renders
  /// `strokeWidth == 0` as a 1-pixel hairline, so "animate the width to zero"
  /// ends on a visible flash unless the draw is skipped.
  ///
  /// Below [kMinWidth] the width is held and the remainder is taken out of alpha
  /// — a sub-pixel stroke stops getting thinner and starts aliasing, so trading
  /// the last of the width for transparency keeps the vanish perceptually smooth.
  static Paint? weighted(Paint base, double factor) {
    final f = factor.clamp(0.0, 1.0);
    if (f >= 1) return base; // full weight — no allocation on the common path
    final w = base.strokeWidth * f;
    if (w <= kVanish) return null; // spent
    if (w >= kMinWidth) return _copy(base, w, 1);
    return _copy(base, kMinWidth, w / kMinWidth);
  }

  static Paint _copy(Paint base, double width, double alpha) {
    final c = base.color;
    return Paint()
      ..style = base.style
      ..strokeWidth = width
      ..strokeCap = base.strokeCap
      ..strokeJoin = base.strokeJoin
      ..maskFilter = base.maskFilter
      ..isAntiAlias = true
      ..color = alpha >= 1
          ? c
          : c.withValues(alpha: (c.a * alpha).clamp(0.0, 1.0));
  }
}
