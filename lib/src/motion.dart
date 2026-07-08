import 'package:flutter/widgets.dart';

/// Motion durations for the icon-animation engine. Every effect's default
/// [duration] reads from here, so timing stays consistent and easy to tune in
/// one place.
abstract final class IconMotion {
  /// Generic base beat (e.g. the lock-engage clunk).
  static const Duration base = Duration(milliseconds: 200);

  /// Full 3D unlock/flip spin.
  static const Duration iconSpin = Duration(milliseconds: 820);

  /// Edge-on → flat flip-in entrance.
  static const Duration iconFlipIn = Duration(milliseconds: 560);

  /// Pen draw-on of a whole glyph.
  static const Duration iconDraw = Duration(milliseconds: 720);

  /// Gentle idle breathe loop.
  static const Duration iconBreathe = Duration(milliseconds: 1600);

  /// Choreographed multi-step sequence (e.g. draw → spin).
  static const Duration iconSequence = Duration(milliseconds: 760);

  /// Button-press knock / detail spin.
  static const Duration iconPress = Duration(milliseconds: 400);

  /// The nav-tap press beat — quick enough to feel snappy under the finger,
  /// with the ease-out settle carrying the elegance (curves front-load the
  /// motion; the beat itself stays short).
  static const Duration iconPressCalm = Duration(milliseconds: 360);

  /// Verify-pulse glow tracing the centerline.
  static const Duration iconTrace = Duration(milliseconds: 1200);

  /// Assemble / converge entrance.
  static const Duration iconConverge = Duration(milliseconds: 640);

  /// Stroke-weight emphasis pulse.
  static const Duration iconWeightPulse = Duration(milliseconds: 520);

  /// Slow small-angle idle tilt (ping-pong).
  static const Duration iconIdleTilt = Duration(milliseconds: 2600);

  /// Idle blink loop.
  static const Duration iconBlink = Duration(milliseconds: 3200);

  /// Cross-icon morph (the worm + flight).
  static const Duration iconMorph = Duration(milliseconds: 640);

  /// Long shimmer sweep period.
  static const Duration shimmerSweep = Duration(milliseconds: 3600);

  /// True when the OS reduce-motion accessibility setting is active. Effects
  /// honour it by snapping to their end state instead of animating. Cache the
  /// result in `didChangeDependencies`; never call it from async callbacks or
  /// listeners where the widget may already be deactivated.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}
