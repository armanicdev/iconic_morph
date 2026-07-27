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
  /// How thin a taper is allowed to take the ink. **1 = never thin**, the
  /// default: modulating stroke weight per contour makes a glyph read UNBALANCED
  /// — with a staggered exit, one contour sits at full weight while its neighbour
  /// is half, and the icon stops looking like one drawing. [fade] removes ink
  /// without touching weight, so it is the whole vanish by default.
  ///
  /// Lower it (e.g. 0.5) only for a deliberate pen-lift, and note that a floor
  /// below 1 also enables the no-dot clamp ([exitWeight] / [entryWeight]).
  static const double kFloor = 1;

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
  /// Anchored to the CLOCK, so it only removes ink cleanly on a contour long
  /// enough that its last frames are still a line. Prefer [exitAlpha], which
  /// anchors the same fade to the GEOMETRY instead. `start >= 1` disables it.
  static double fade(double prog, double start) {
    final s = start.clamp(0.0, 1.0);
    if (s >= 1) return 1;
    final u = ((prog - s) / (1 - s)).clamp(0.0, 1.0);
    if (u <= 0) return 1;
    return 1 - Curves.easeInOut.transform(u);
  }

  /// How many stroke-widths of length a stroke needs to still read as a LINE.
  /// Below this the round caps dominate and it is a dot, whatever the geometry
  /// says it is.
  static const double kDotWidths = 2;

  /// **The dot horizon** — the exit progress at which a retracting contour of
  /// [fullLength] stops reading as a line and becomes a round-cap dot, assuming
  /// its visible length tracks `1 - prog`. This is the instant the ink must
  /// already be GONE.
  ///
  /// A contour that is short to begin with is dot-shaped for most of its own
  /// retract, so the horizon is also capped at half its length — that keeps a
  /// hair-length authored dot (a keyhole) fading over its own second half
  /// instead of being deleted on frame one.
  static double dotHorizon(double fullLength,
      [double strokeWidth = kIconStrokeWidth]) {
    if (fullLength <= 0) return 0;
    final dotLen = math.min(kDotWidths * strokeWidth, fullLength * 0.5);
    return (1 - dotLen / fullLength).clamp(0.0, 1.0);
  }

  /// Inverse of the Hermite smoothstep `3y² - 2y³` — the input that produces
  /// [y]. The exit's per-contour progress is smoothstepped, so this is what
  /// converts a point in PROGRESS space back into a point in the window's real
  /// TIME. Without it, a fade specified as "a quarter of the progress" lands
  /// wherever the smoothstep happens to be moving fastest and can be over in a
  /// couple of frames.
  static double unSmooth(double y) {
    final c = y.clamp(0.0, 1.0);
    return 0.5 - math.sin(math.asin(1 - 2 * c) / 3);
  }

  /// **The dissolve, in real time.** Alpha for a leaving stroke at timeline
  /// position [t], fading to nothing over the [span] of timeline that ends at
  /// [end]. Zero from [end] onward.
  ///
  /// Both arguments are fractions of the WHOLE animation, not of the exit's
  /// progress — that distinction is the fix for a fade that measured 25% on
  /// paper and 43 ms (under three frames) on screen. Feed [end] the dot horizon
  /// mapped through [unSmooth], and the dissolve both lasts a real duration and
  /// finishes before the ink could become a dot.
  static double dissolve(double t, double end, double span) {
    if (span <= 0) return t >= end ? 0 : 1;
    if (t >= end) return 0;
    final start = end - span;
    if (t <= start) return 1;
    return 1 - Curves.easeInOut.transform((t - start) / span);
  }

  /// **The exit dissolve in PROGRESS space** — alpha for a contour of
  /// [fullLength] at exit progress [prog].
  ///
  /// Correct but easy to misjudge: a span given here is a span of progress, and
  /// progress is rarely linear in time. Prefer [dissolve] with [unSmooth]
  /// whenever the caller knows the timeline, which is what the morph does.
  ///
  /// The fade still lasts the requested slice of the timeline (`1 - [fadeStart]`,
  /// e.g. the last quarter), but it **finishes at [dotHorizon] rather than at
  /// the end of the exit**, and nothing is drawn after that. That difference is
  /// the whole point: a fade that merely ends when the LENGTH ends still shows
  /// the dot, because the stroke turns into one a good stretch before its length
  /// reaches zero — visibly, at 30–70% alpha. Ending the dissolve on the horizon
  /// means the ink is already invisible by the time it would have become a dot,
  /// so a trim-out never has a dot frame at all.
  static double exitAlpha(
    double prog,
    double fadeStart,
    double fullLength, [
    double strokeWidth = kIconStrokeWidth,
  ]) {
    final end = dotHorizon(fullLength, strokeWidth);
    if (prog >= end) return 0;
    final span = (1 - fadeStart.clamp(0.0, 0.98));
    final start = math.max(0.0, end - span);
    if (prog <= start) return 1;
    return 1 - Curves.easeInOut.transform((prog - start) / (end - start));
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

  /// **The exit's weight factor**, all of it: the [out] taper and the no-dot
  /// clamp combined, with the one rule that keeps a glyph balanced —
  /// **`floor >= 1` means the stroke width is never touched at all**, clamp
  /// included, and [fade] alone does the vanishing.
  ///
  /// That gate is deliberate. Weight modulation is per-contour, and a staggered
  /// exit therefore paints neighbours at different weights: the icon stops
  /// reading as one drawing. Ink either keeps its weight, or the taper is on and
  /// the clamp comes with it (there is no coherent middle where a contour thins
  /// only when its geometry degenerates).
  static double exitWeight({
    required double prog,
    required double start,
    required double floor,
    required double visibleLength,
    required double fullLength,
    double strokeWidth = kIconStrokeWidth,
  }) {
    if (floor >= 1) return 1;
    return math.min(
      out(prog, start, floor),
      lengthClamp(visibleLength, fullLength, strokeWidth),
    );
  }

  /// The draw-on mirror of [exitWeight] — the [into] press-down plus the no-dot
  /// clamp, and the same `floor >= 1` gate that leaves weight untouched.
  static double entryWeight({
    required double local,
    required double end,
    required double floor,
    required double drawnLength,
    required double fullLength,
    double strokeWidth = kIconStrokeWidth,
  }) {
    if (floor >= 1) return 1;
    return math.min(
      into(local, end, floor),
      lengthClamp(drawnLength, fullLength, strokeWidth),
    );
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
