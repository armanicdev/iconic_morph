import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import '../math/mat4.dart' as vm;

import '../motion.dart';

import '../icon_geometry.dart';
import '../icon_effect.dart';
import '../projection_3d.dart';

/// True 3D rotation with a **constant stroke width**.
///
/// The naive approach — `Transform(Matrix4..rotateY, child: widget)` — rotates
/// an already-stroked bitmap, so the stroke foreshortens and thins to nothing
/// edge-on. This effect projects only the icon's centerline points through
/// `perspective · rotate(θ)`, perspective-divides them to 2D, rebuilds a fresh
/// path in screen space, and strokes THAT at a constant width. The shape
/// foreshortens and collapses to a sliver at 90° (and [depthFade] dims it as it
/// turns edge-on), but the line weight never changes — exactly the look of a real
/// object spinning while keeping crisp strokes.
///
/// Implementation notes:
///  * Perspective is applied in centered space, so the vanishing point is the
///    icon's own center and a horizontal spin has zero vertical drift.
///  * `perspectiveTransform` performs the homogeneous w-divide and mutates its
///    `Vector3` argument in place, so a fresh scratch is written per point.
///  * Projected points are NaN/∞-guarded for robustness.
class IconSpin3D extends IconEffect {
  const IconSpin3D({
    this.duration = IconMotion.iconSpin,
    this.curve = Curves.easeInOutCubic,
    this.fromAngle = 0,
    this.toAngle = 2 * math.pi,
    this.axis = Spin3DAxis.vertical,
    this.perspective = 0.0022,
    this.depthFade = false,
    this.depthFadeFloor = 0.22,
    this.fadeIn = false,
    this.loops = false,
    this.autoReverse = false,
    this.restValue = 0,
  });

  /// A full 360° unlock turn — the lock tumbles once in depth and lands facing
  /// forward. A good default for a tap-to-confirm or "unlock" affordance.
  const IconSpin3D.unlock({
    Duration duration = IconMotion.iconSpin,
    double perspective = 0.0026,
  }) : this(
          duration: duration,
          curve: Curves.easeInOutCubic,
          fromAngle: 0,
          toAngle: 2 * math.pi,
          perspective: perspective,
        );

  /// A 3D entrance: the icon swings in from edge-on (just past 90°) to flat,
  /// fading up as it arrives. Rests fully settled (restValue 1).
  const IconSpin3D.flipIn({
    Duration duration = IconMotion.iconFlipIn,
    Curve curve = Curves.easeOutCubic,
    Spin3DAxis axis = Spin3DAxis.vertical,
    double perspective = 0.0028,
  }) : this(
          duration: duration,
          curve: curve,
          fromAngle: Projector3D.kEdgeOnEntryAngle,
          toAngle: 0,
          axis: axis,
          perspective: perspective,
          fadeIn: true,
          restValue: 1,
        );

  /// A living idle **tilt** — a slow, small-angle 3D ping-pong about the
  /// vertical axis, the glyph subtly catching depth as if alive. Drives with
  /// [loops] + [autoReverse]; rests flat ([restValue] 0.5 → the timeline midpoint
  /// is angle 0). Keep [tilt] small (≈0.16 rad / 9°) — this is ambient, not a
  /// spin.
  const IconSpin3D.idleTilt({
    Duration duration = IconMotion.iconIdleTilt,
    double tilt = 0.16,
    Spin3DAxis axis = Spin3DAxis.vertical,
    double perspective = 0.003,
  }) : this(
          duration: duration,
          curve: Curves.easeInOut,
          fromAngle: -tilt,
          toAngle: tilt,
          axis: axis,
          perspective: perspective,
          loops: true,
          autoReverse: true,
          restValue: 0.5,
        );

  @override
  final Duration duration;

  final Curve curve;

  /// Rotation sweep in radians, mapped across the eased timeline.
  final double fromAngle;
  final double toAngle;

  final Spin3DAxis axis;

  /// Perspective strength = 1/eyeDistance in viewBox units. ~0.002 is a clean UI
  /// tilt; larger (~0.02) is a dramatic edge-on snap.
  final double perspective;

  /// Dim the stroke toward edge-on (the "too deep to see" cue).
  final bool depthFade;

  /// Lowest alpha [depthFade] reaches at exactly edge-on (keeps a faint sliver).
  final double depthFadeFloor;

  /// Fade the whole icon up over the sweep — used by [IconSpin3D.flipIn].
  final bool fadeIn;

  @override
  final bool loops;

  @override
  final bool autoReverse;

  @override
  final double restValue;

  /// This effect's reusable [Projector3D] — the constant-stroke 3D core, shared
  /// with the cross-icon morph engine. Cheap to allocate; built per paint pass.
  Projector3D get _projector =>
      Projector3D(perspective: perspective, axis: axis);

  /// Project one viewBox-space point through the spin at [angle]. The stroke is
  /// never touched here — it is applied in 2D after projection — so it stays a
  /// constant width while this collapses the shape toward the axis edge-on.
  /// Exposed for tests that assert the foreshortening + no-drift properties.
  @visibleForTesting
  Offset projectPoint(Offset p, double angle, double center) =>
      _projector.project(p, angle, center);

  @override
  void paint(Canvas canvas, Size size, IconGeometry geom, double t, Paint paint) {
    final e = curve.transform(t.clamp(0, 1));
    final angle = fromAngle + (toAngle - fromAngle) * e;
    final c = size.width / 2;
    final proj = _projector;

    // Build the projection matrix and scratch vector once, then project every
    // contour through it — the whole glyph spins at one angle, so sharing one
    // matrix avoids 2·N Matrix4 allocations per frame.
    final m = proj.matrixFor(angle, c);
    final scratch = vm.Vector3.zero();
    final projected = Path();
    for (final contour in geom.contours) {
      proj.projectInto(projected, contour.points, m, scratch,
          closed: contour.isClosed);
    }

    canvas.drawPath(projected, _withAlpha(paint, angle, e));
  }

  Paint _withAlpha(Paint base, double angle, double easedT) {
    if (!depthFade && !fadeIn) return base;
    var a = 1.0;
    if (depthFade) {
      // cos(angle) -> 1 facing forward, 0 edge-on, regardless of axis.
      final facing = math.cos(angle).abs();
      a *= depthFadeFloor + (1 - depthFadeFloor) * facing;
    }
    if (fadeIn) a *= Curves.easeOut.transform(easedT);
    return tintStroke(base, a);
  }
}
