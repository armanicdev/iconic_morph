import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../motion.dart';

import '../icon_geometry.dart';
import '../icon_effect.dart';

/// A stroke-**weight** "emphasis" pulse — the line swells from its base width to
/// a touch heavier and settles back, with an optional hair of scale. Impossible
/// with a baked bitmap icon (the weight is re-stroked each frame) and calmer than
/// a bounce: a quiet "saved / confirmed" beat.
///
/// Cheapest class of effect, like [IconBreathe]: it strokes the crisp
/// un-flattened path once with a cloned [Paint] whose width it modulates — no
/// per-point transform.
///
///  * One-shot by default: a single smooth swell up and back ([restValue] 0 =
///    base weight), so reduced-motion shows the plain icon.
///  * [IconWeightPulse.heartbeat] loops as a slow, living pulse (drive with a
///    ping-pong controller — [loops] + [autoReverse]).
class IconWeightPulse extends IconEffect {
  const IconWeightPulse({
    this.duration = IconMotion.iconWeightPulse,
    this.weightGain = 0.6,
    this.scaleGain = 0.05,
    this.loops = false,
    this.autoReverse = false,
  });

  /// A gentle perpetual pulse. Pairs with a ping-pong controller; the eased t
  /// oscillates 0→1→0 for a calm swell in/out.
  const IconWeightPulse.heartbeat({
    Duration duration = IconMotion.iconBreathe,
    double weightGain = 0.45,
    double scaleGain = 0.03,
  }) : this(
          duration: duration,
          weightGain: weightGain,
          scaleGain: scaleGain,
          loops: true,
          autoReverse: true,
        );

  @override
  final Duration duration;

  /// Peak extra stroke weight as a fraction of the base (0.6 = +60%).
  final double weightGain;

  /// Peak extra scale about the center (0.05 = +5%); 0 disables the scale.
  final double scaleGain;

  @override
  final bool loops;

  @override
  final bool autoReverse;

  @override
  double get restValue => 0; // base weight

  @override
  void paint(Canvas canvas, Size size, IconGeometry geom, double t, Paint paint) {
    final tt = t.clamp(0.0, 1.0);
    // Ping-pong loops: the controller already reflects the t value back, so a
    // monotonic eased ramp gives the in/out swell. One-shot: a half-sine does
    // the up-and-back on a single forward pass.
    final pulse = (loops && autoReverse)
        ? Curves.easeInOut.transform(tt)
        : math.sin(math.pi * tt);

    // Modulate the SHARED base paint's width in place (restored below) rather than
    // cloning a new Paint every frame — a const effect can hold no scratch state,
    // and using the base paint directly inherits any future field (blendMode,
    // maskFilter…) automatically instead of silently dropping it.
    final baseWidth = paint.strokeWidth;
    paint.strokeWidth = baseWidth * (1 + weightGain * pulse);

    final s = 1 + scaleGain * pulse;
    if (s == 1) {
      canvas.drawPath(geom.path, paint);
    } else {
      final c = size.width / 2;
      canvas.save();
      canvas.translate(c, c);
      canvas.scale(s);
      canvas.translate(-c, -c);
      canvas.drawPath(geom.path, paint);
      canvas.restore();
    }
    paint.strokeWidth = baseWidth; // restore for any later contour / sequence step
  }
}
