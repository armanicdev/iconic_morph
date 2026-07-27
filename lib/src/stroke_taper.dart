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
///    then eased down to [kFloor]. It thins, it does NOT thin away to nothing —
///    ink that keeps thinning reads as a stroke starving, not as a pen lifting.
///  * [fade] — what actually removes it: an alpha dissolve over the END of the
///    exit. Thinning sets up the lift; the fade finishes it.
///  * [into] — the mirror on the way in: the nib presses from [kFloor] up to full
///    over the first fraction of a draw-on, instead of stamping a full-weight dot
///    on frame one.
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
  /// How thin a taper is allowed to take the ink: **half weight**. A stroke that
  /// keeps thinning toward zero reads as starving rather than lifting, so the
  /// taper stops here and [fade] does the removing.
  static const double kFloor = 0.5;

  /// Ink is never allowed to be fatter than `1 / [kLengthRatio]` of the length it
  /// still has — the ratio at which a round-capped stroke stops reading as a
  /// line and starts reading as a blob. This is a SAFETY NET, not the taper: it
  /// may go below [kFloor], but only once the ink is a sliver the [fade] has
  /// already made near-transparent.
  static const double kLengthRatio = 3;

  /// Smallest width (viewBox units) that still renders as a clean stroke. Below
  /// this a thinning line stops looking thinner and starts aliasing, so [weighted]
  /// holds this width and takes the rest out of alpha instead.
  static const double kMinWidth = 0.35;

  /// Width (viewBox units) at or below which the ink counts as spent — [weighted]
  /// returns `null` and the caller draws nothing. Deliberately tiny so the ink is
  /// already a whisper when it goes, and never 0 (see the hairline note above).
  static const double kVanish = 0.02;

  /// **Trim-OUT taper.** Weight factor (1 → [floor]) for a contour that is
  /// un-drawing, at exit progress [prog] (0 = fully present, 1 = gone).
  ///
  /// Holds full weight until [start] of the exit — so the retract still reads as
  /// a real line being pulled back — then eases down to [floor] on an S-curve and
  /// stays there. It deliberately does NOT reach zero: removing the ink is
  /// [fade]'s job, and a stroke that thins the whole way out reads as starving.
  /// `start >= 1` disables the taper (constant weight).
  static double out(double prog, double start, [double floor = kFloor]) {
    final s = start.clamp(0.0, 1.0);
    final f = floor.clamp(0.0, 1.0);
    if (s >= 1) return 1;
    final u = ((prog - s) / (1 - s)).clamp(0.0, 1.0);
    if (u <= 0) return 1;
    // Same S-shape as the engine's other smooth ramps: flat at both ends, so the
    // taper neither snaps on nor snaps off.
    return 1 - (1 - f) * Curves.easeInOut.transform(u);
  }

  /// **The dissolve.** Alpha factor (1 → 0) over the END of a trim-out: 1 until
  /// [start] of the exit, then eased to nothing at 1.
  ///
  /// This is what actually removes the ink. Pairing a short thinning with a late
  /// fade is what makes a pen lift read like a pen lift — the alternative,
  /// thinning all the way to zero, is a stroke starving to death, and it still
  /// ends on a hard cut at whatever width the last visible frame had.
  /// `start >= 1` disables the fade (a hard cut when the length runs out).
  static double fade(double prog, double start) {
    final s = start.clamp(0.0, 1.0);
    if (s >= 1) return 1;
    final u = ((prog - s) / (1 - s)).clamp(0.0, 1.0);
    if (u <= 0) return 1;
    return 1 - Curves.easeInOut.transform(u);
  }

  /// **Trim-IN ramp.** Weight factor ([floor] → 1) for a contour that is drawing
  /// on, at draw progress [local] (0 = nothing drawn, 1 = complete).
  ///
  /// The nib presses down over the first [end] of the draw and holds full weight
  /// for the rest, so a draw-on begins as ink rather than as a full-weight dot —
  /// and starts at half weight rather than at nothing, the mirror of [out].
  /// `end <= 0` disables the ramp.
  static double into(double local, double end, [double floor = kFloor]) {
    final e = end.clamp(0.0, 1.0);
    final f = floor.clamp(0.0, 1.0);
    if (e <= 0) return 1;
    final u = (local / e).clamp(0.0, 1.0);
    // Ease-out: reaches full weight quickly, so the piece matches the static icon
    // for most of its draw and only the entry is soft.
    return f + (1 - f) * Curves.easeOutCubic.transform(u);
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

  /// Applies a weight [factor] and an [alpha] to [base], returning the [Paint] to
  /// stroke with — or **`null` when the ink is gone**, meaning: draw nothing.
  ///
  /// Returning `null` rather than a zero-width paint is load-bearing: Skia renders
  /// `strokeWidth == 0` as a 1-pixel hairline, so "animate the width to zero"
  /// ends on a visible flash unless the draw is skipped.
  ///
  /// Below [kMinWidth] the width is held and the remainder is folded into alpha
  /// — a sub-pixel stroke stops getting thinner and starts aliasing, so trading
  /// the last of the width for transparency keeps the vanish perceptually smooth.
  static Paint? weighted(Paint base, double factor, {double alpha = 1}) {
    final f = factor.clamp(0.0, 1.0);
    final a = alpha.clamp(0.0, 1.0);
    if (a <= 0) return null; // fully faded
    if (f >= 1 && a >= 1) return base; // untouched — no allocation, common path
    final w = base.strokeWidth * f;
    if (w <= kVanish) return null; // spent
    if (w >= kMinWidth) return _copy(base, w, a);
    return _copy(base, kMinWidth, a * (w / kMinWidth));
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
