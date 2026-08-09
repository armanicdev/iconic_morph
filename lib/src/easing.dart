import 'dart:math' as math;

import 'package:flutter/animation.dart';

/// The engine's easing vocabulary — the handful of velocity profiles its
/// motion is tuned around, named by FEEL so a caller picks a word, not a
/// four-number cubic.
///
/// Every timing knob in the engine that takes a [Curve] defaults to one of
/// these, and all of them accept any curve you hand them — the vocabulary is
/// the calibrated starting point, not a fence.
abstract final class IconicEase {
  /// Symmetric ease-in-out — accelerates in, breathes out. The calm profile:
  /// right when a change should read as one unhurried gesture (an idle icon
  /// re-arranging itself, a passive state change nobody triggered).
  static const Curve glide = Curves.easeInOutCubic;

  /// Fast-launch ease-out — peak velocity at the first frame, decelerating
  /// into a long, soft settle. The worm morph's signature clock ([IconMorphPlan.curve]
  /// defaults to it): a line LEAVING somewhere should leave decisively and
  /// arrive gently.
  static const Curve flight = Cubic(0.25, 1.0, 0.5, 1.0);

  /// The critically-damped spring settle ([IconicSpringCurve] at its tuned
  /// defaults) — the profile platform-native motion rides. Responds instantly
  /// (the attack a triggered change deserves — it feels like the tap CAUSED
  /// it), covers most of the distance in the first half, then settles on an
  /// exponential tail that never quite hurries and never quite stops. The
  /// shape morph's default clock ([ShapeMorphSpec.curve]).
  static const Curve snap = IconicSpringCurve();
}

/// A critically-damped spring as a [Curve] — the exact displacement profile a
/// platform spring animation follows, folded into curve space so any plain
/// `AnimationController` can ride it.
///
/// Solves the critically-damped oscillator toward the target with initial
/// displacement 1 and initial VELOCITY [velocity]:
///
/// ```
/// progress(t) = 1 − (1 + (ω − v)·t) · e^(−ω·t)
/// ```
///
/// normalized so `transform(1) == 1`. Two knobs, both in "per animation"
/// units:
///
///  * [omega] — stiffness. Higher = the spring closes the gap earlier; the
///    exponential tail is always silk regardless.
///  * [velocity] — how fast the motion is already moving at frame ONE. This is
///    what cubics cannot give you: a genuine non-zero launch velocity, so a
///    triggered transition reads as *caused* rather than *scheduled*. Keep it
///    below [omega] and the curve is strictly monotone — no overshoot, which
///    is the right law for stroke geometry (an overshooting line wobbles).
///    Above [omega] it overshoots once and returns, a deliberate "pop".
class IconicSpringCurve extends Curve {
  const IconicSpringCurve({this.omega = 7.0, this.velocity = 2.5})
      : assert(omega > 0, 'a spring needs positive stiffness');

  /// Stiffness (rad per animation). Default 7 lands ≈63% of the travel by
  /// quarter-time and ≈90% by half-time.
  final double omega;

  /// Normalized launch velocity at t = 0 (units of "full travels per
  /// animation"). Default 2.5 — moving at 2.5× the average speed on the first
  /// frame, still under [omega] so the settle is monotone.
  final double velocity;

  @override
  double transformInternal(double t) {
    double p(double x) => 1 - (1 + (omega - velocity) * x) * math.exp(-omega * x);
    return p(t) / p(1);
  }

  // Value equality so specs/plans carrying a spring compare == when tuned the
  // same — geometry caches key on the spec.
  @override
  bool operator ==(Object other) =>
      other is IconicSpringCurve &&
      other.omega == omega &&
      other.velocity == velocity;

  @override
  int get hashCode => Object.hash(omega, velocity);

  @override
  String toString() => 'IconicSpringCurve(omega: $omega, velocity: $velocity)';
}
