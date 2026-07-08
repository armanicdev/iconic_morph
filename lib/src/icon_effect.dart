import 'package:flutter/widgets.dart';

import 'icon_geometry.dart';

/// Default stroke width in viewBox units (2px at a 24-unit viewBox). Matches the
/// typical stroke weight SVG icons are authored at, so an animated re-stroke is
/// weight-for-weight identical to the static [IconImage]. Painters are
/// parameterized so individual effects can override, but this constant is the
/// shared default.
const double kIconStrokeWidth = 2;

/// A pure, immutable icon-animation strategy. Given parsed [IconGeometry] and a
/// raw linear progress [t] (0..1 from the controller), it paints ONE frame.
///
/// Contract for scalability:
///  * Effects are immutable and hold NO per-frame mutable state — one instance
///    may be shared across frames, icons, and widgets.
///  * Effects own their easing: apply [curve]-style shaping to [t] **inside**
///    [paint], so they compose correctly inside an [IconSequence] (which hands
///    each step a re-normalized local [t]).
///  * Painting happens in viewBox space (e.g. 24×24); the base painter has
///    already scaled the canvas to the render size, so the supplied [paint] has
///    the correct constant stroke width. Stroke/fill with [paint]; copy it (via
///    [Paint] cloning) only to change alpha.
@immutable
abstract class IconEffect {
  const IconEffect();

  /// Play time for one cycle. The widget sizes its controller to this.
  Duration get duration;

  /// When true the controller [AnimationController.repeat]s (pair with
  /// [autoReverse] for a ping-pong such as a breathe).
  bool get loops => false;
  bool get autoReverse => false;

  /// The progress value to show at rest — when autoplay is off, before the
  /// first play, and (crucially) under reduced-motion, which renders this single
  /// settled frame instead of animating. e.g. 1.0 for a draw-on that should rest
  /// fully drawn, 0.0 for a spin that rests front-facing.
  double get restValue => 0;

  /// Paint one frame. [size] is the icon's viewBox space; [t] is raw 0..1.
  void paint(Canvas canvas, Size size, IconGeometry geom, double t, Paint paint);
}

/// Returns a copy of [base] with its alpha multiplied by [alpha], optionally
/// lerped [towardT] of the way toward [toward] (for a glow or lighten effect).
/// Returns [base] unchanged when alpha is 1 and no lerp is requested, so the
/// common fully-opaque path allocates nothing.
Paint tintStroke(Paint base, double alpha, {Color? toward, double towardT = 0}) {
  final a = alpha.clamp(0.0, 1.0);
  final lerp = toward != null && towardT > 0;
  if (a >= 1.0 && !lerp) return base;
  final color = lerp ? Color.lerp(base.color, toward, towardT.clamp(0, 1))! : base.color;
  return Paint()
    ..style = base.style
    ..strokeWidth = base.strokeWidth
    ..strokeCap = base.strokeCap
    ..strokeJoin = base.strokeJoin
    ..isAntiAlias = true
    // Multiply the (possibly lerped) colour's OWN alpha by [alpha] — using
    // base.color.a here would silently drop the alpha contributed by `toward`
    // (an alpha-bearing glow colour). When not lerping, color == base.color, so
    // the common path is unchanged.
    ..color = color.withValues(alpha: (color.a * a).clamp(0, 1));
}

/// Appends the first [upTo] arc-length units of contour [c] onto [path],
/// interpolating the final partial segment so the leading edge moves smoothly.
/// Re-closes a fully-drawn closed contour so its final join is a miter rather
/// than an open round-cap seam.
void appendContourUpTo(Path path, IconContour c, double upTo) {
  if (upTo <= 0 || c.points.isEmpty) return;
  path.moveTo(c.points.first.dx, c.points.first.dy);
  for (var i = 1; i < c.points.length; i++) {
    final segEnd = c.cumLength[i];
    if (segEnd <= upTo) {
      path.lineTo(c.points[i].dx, c.points[i].dy);
      // Whole contour drawn — re-close it so joins read correctly.
      if (i == c.points.length - 1 && c.isClosed && upTo >= c.length) {
        path.close();
      }
    } else {
      final segStart = c.cumLength[i - 1];
      final span = segEnd - segStart;
      final frac = span <= 0 ? 0.0 : ((upTo - segStart) / span).clamp(0.0, 1.0);
      final p = Offset.lerp(c.points[i - 1], c.points[i], frac)!;
      path.lineTo(p.dx, p.dy);
      return;
    }
  }
}

/// Appends the arc-length sub-range `[fromLen, toLen]` of contour [c] onto [path]
/// as an open stroke, interpolating both ends. Unlike [appendContourUpTo] (which
/// always starts at 0), this lets a trim advance its START — the basis of a
/// one-directional **feed-through** erase: the stroke drains from the start toward
/// the end (`fromLen` climbing 0→length while `toLen` stays at length), travelling
/// the SAME direction as the draw-on instead of retracting back the way it came
/// (which reads as a ping-pong bounce).
void appendContourRange(Path path, IconContour c, double fromLen, double toLen) {
  if (c.points.isEmpty) return;
  final lo = fromLen.clamp(0.0, c.length);
  final hi = toLen.clamp(0.0, c.length);
  if (hi - lo <= 0) return;
  var started = false;
  for (var i = 1; i < c.points.length; i++) {
    final segStart = c.cumLength[i - 1];
    final segEnd = c.cumLength[i];
    if (segEnd < lo) continue; // wholly before the window
    if (segStart > hi) break; // wholly past the window
    final span = segEnd - segStart;
    // Open the window: lerp the entry point inside the first overlapping segment.
    if (!started) {
      final f = span <= 0 ? 0.0 : ((lo - segStart) / span).clamp(0.0, 1.0);
      final p = Offset.lerp(c.points[i - 1], c.points[i], f)!;
      path.moveTo(p.dx, p.dy);
      started = true;
    }
    // Close the window inside this segment → lerp the exit point and stop.
    if (segEnd >= hi) {
      final f = span <= 0 ? 0.0 : ((hi - segStart) / span).clamp(0.0, 1.0);
      final p = Offset.lerp(c.points[i - 1], c.points[i], f)!;
      path.lineTo(p.dx, p.dy);
      break;
    }
    // The segment's end vertex sits inside the window — line straight to it.
    path.lineTo(c.points[i].dx, c.points[i].dy);
  }
}

/// The [CustomPainter] behind every [IconEffect]. Handles repaint wiring
/// (driven by the animation controller via `super(repaint:)` — no widget
/// rebuild), canvas scaling to viewBox space so effects paint at a constant
/// stroke width, and [shouldRepaint] comparisons. Pass this to a [CustomPaint]
/// widget when you want direct control; otherwise [IconicAnimatedIcon] manages it
/// for you.
class IconEffectPainter extends CustomPainter {
  IconEffectPainter({
    required this.effect,
    required this.geom,
    required this.color,
    required this.progress,
    this.strokeWidth = kIconStrokeWidth,
  }) : super(repaint: progress);

  final IconEffect effect;
  final IconGeometry geom;
  final Color color;
  final Animation<double> progress;

  /// Stroke width in viewBox units (the design token is 2 at a 24 viewBox).
  /// Constant across rotation: foreshortening lives in the projected geometry,
  /// while [Canvas.scale] only zooms uniformly — never thinning the stroke.
  final double strokeWidth;

  // Base stroke paint, built once per painter instance and reused every frame
  // (the painter is long-lived via super(repaint:), so this avoids one Paint
  // allocation per tick).
  Paint? _paint;
  Paint get _basePaint => _paint ??= (Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = strokeWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true
    ..color = color);

  @override
  void paint(Canvas canvas, Size size) {
    final vb = geom.viewBox;
    final s = size.shortestSide / vb;
    final paint = _basePaint;

    canvas.save();
    canvas.scale(s);
    effect.paint(canvas, Size(vb, vb), geom, progress.value.clamp(0, 1), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(IconEffectPainter old) =>
      old.effect != effect ||
      old.geom != geom ||
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      // If the parent widget rebuilds with a different controller, the old painter
      // stays alive (it still listens via super(repaint:)) and the new controller
      // is never wired. Identity-compare so a swapped controller forces a fresh
      // painter with the correct repaint subscription.
      !identical(old.progress, progress);
}

/// One step of an [IconSequence]: an effect that plays over the [start]..[end]
/// window of the parent's normalized timeline. Windows may overlap (cross-fade);
/// after its window a step holds at local t = 1 (its settled frame).
@immutable
class IconStep {
  const IconStep(this.effect, {required this.start, required this.end});
  final IconEffect effect;
  final double start;
  final double end;
}

/// Composes effects on a single timeline — e.g. "draw the icon on, then flip it
/// in 3D". Each [IconStep] receives a LOCAL t re-normalized to its window and
/// paints additively onto the same canvas. This is the seam that scales the
/// engine from a handful of effects to rich, choreographed sequences.
class IconSequence extends IconEffect {
  const IconSequence(
    this.steps, {
    required this.duration,
    this.restValue = 1,
    this.loops = false,
    this.autoReverse = false,
  });

  final List<IconStep> steps;

  @override
  final Duration duration;

  @override
  final double restValue;

  /// A composed sequence can itself loop (e.g. draw-on → spin, repeat) — pair
  /// with [autoReverse] for a ping-pong. Defaults to a one-shot.
  @override
  final bool loops;

  @override
  final bool autoReverse;

  @override
  void paint(Canvas canvas, Size size, IconGeometry geom, double t, Paint paint) {
    // The last step that has started. A finished step keeps painting (held at
    // local 1) ONLY if it is still the last-started one — otherwise the next
    // step has taken over and the finished one must stop, or two copies of the
    // icon stack (a static drawn copy under the spinning copy). During a window
    // overlap both the finishing and the starting step paint → a real crossfade.
    var last = -1;
    for (var i = 0; i < steps.length; i++) {
      if (t >= steps[i].start) last = i;
    }
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      if (t < step.start) continue; // not started yet
      if (t >= step.end && i != last) continue; // handed off to a later step
      final span = step.end - step.start;
      final local = span <= 0 ? 1.0 : ((t - step.start) / span).clamp(0.0, 1.0);
      step.effect.paint(canvas, size, geom, local, paint);
    }
  }
}
