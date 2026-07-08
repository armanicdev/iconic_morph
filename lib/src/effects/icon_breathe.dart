import 'package:flutter/widgets.dart';

import '../motion.dart';

import '../icon_geometry.dart';
import '../icon_effect.dart';

/// A gentle idle "breathe" — the icon scales up and back about its center, on a
/// loop. Cheapest effect in the set: it strokes the crisp un-flattened path once
/// and only applies a uniform [Canvas.scale], so there is no per-point transform.
///
/// Drive it with a ping-pong controller ([loops] + [autoReverse]); the eased t
/// oscillates 0→1→0 for a calm inhale/exhale.
class IconBreathe extends IconEffect {
  const IconBreathe({
    this.duration = IconMotion.iconBreathe,
    this.amplitude = 0.06,
    this.curve = Curves.easeInOut,
  });

  @override
  final Duration duration;

  /// Peak scale increase (0.06 = +6%).
  final double amplitude;

  final Curve curve;

  @override
  bool get loops => true;

  @override
  bool get autoReverse => true;

  @override
  void paint(Canvas canvas, Size size, IconGeometry geom, double t, Paint paint) {
    final e = curve.transform(t.clamp(0, 1));
    final scale = 1 + amplitude * e;
    final c = size.width / 2;

    canvas.save();
    canvas.translate(c, c);
    canvas.scale(scale);
    canvas.translate(-c, -c);
    canvas.drawPath(geom.path, paint);
    canvas.restore();
  }
}
