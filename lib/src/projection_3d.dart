import 'dart:math' as math;
import 'dart:ui';

import 'math/mat4.dart';

/// Which way a glyph tumbles in depth.
enum Spin3DAxis {
  /// Spin about the vertical axis (rotateY) — left/right edges swing in depth.
  /// The default "card flip".
  vertical,

  /// Spin about the horizontal axis (rotateX) — top/bottom edges swing in depth.
  horizontal,
}

/// Projects an icon's centerline points through a perspective+rotation matrix,
/// returning a screen-space [Path] to stroke at a **constant width**.
///
/// This is the engine's constant-stroke 3D trick: instead of rotating an
/// already-stroked bitmap (which would thin the stroke to nothing edge-on), only
/// the path's geometry is projected and the stroke is applied AFTER. The shape
/// foreshortens and collapses to a sliver at 90°, but the line weight never
/// changes — the look of a real object spinning while keeping crisp strokes.
///
/// Used by [IconSpin3D] (whole-glyph spin/flip) and by [IconicMorph] (the
/// 3D-flip assemble mode). Immutable and cheap to allocate — create one per paint
/// pass and reuse it across every contour.
///
/// Implementation notes:
///  * Perspective is applied in centered space, so the vanishing point is the
///    icon's own center and a horizontal spin has zero vertical drift.
///  * [perspectiveTransform] performs the homogeneous w-divide and mutates its
///    [Vector3] argument in place. Projected points are NaN/∞-guarded.
class Projector3D {
  const Projector3D({
    this.perspective = 0.0026,
    this.axis = Spin3DAxis.vertical,
  });

  /// Entry angle for a "flip-in" effect — just past edge-on (90° × 1.12) so a
  /// glyph swinging in from here reads as arriving from behind the plane. Used by
  /// [IconSpin3D.flipIn] and the [MorphAssemble.flip3d] assemble mode.
  static const double kEdgeOnEntryAngle = -math.pi / 2 * 1.12;

  /// Perspective strength = 1/eyeDistance in viewBox units. ~0.002 is a clean UI
  /// tilt; larger (~0.02) is a dramatic edge-on snap.
  final double perspective;

  final Spin3DAxis axis;

  /// perspective · rotate, applied in CENTERED space so the vanishing point is
  /// the icon center (a horizontal spin then has zero vertical drift).
  Matrix4 matrixFor(double angle, double center) {
    final m = Matrix4.identity()
      ..translateByDouble(center, center, 0, 1)
      ..multiply(Matrix4.identity()..setEntry(3, 2, -perspective));
    if (axis == Spin3DAxis.vertical) {
      m.rotateY(angle);
    } else {
      m.rotateX(angle);
    }
    return m..translateByDouble(-center, -center, 0, 1);
  }

  /// Project one viewBox-space point through the spin at [angle]. The stroke is
  /// never touched here — it is applied in 2D after projection — so it stays a
  /// constant width while this collapses the shape toward the axis edge-on.
  Offset project(Offset p, double angle, double center) {
    final v = Vector3(p.dx, p.dy, 0);
    matrixFor(angle, center).perspectiveTransform(v); // does the w-divide
    return Offset(v.x, v.y);
  }

  /// Project a whole polyline into a fresh screen-space [Path] at [angle]. Builds
  /// one matrix + one scratch vector and delegates to [projectInto]. Convenience
  /// for a single contour (and the tests); when projecting MANY contours at the
  /// same angle, build the matrix once with [matrixFor] and call [projectInto] in
  /// the loop so the matrix isn't reallocated per contour.
  Path projectPolyline(
    List<Offset> points,
    double angle,
    double center, {
    bool closed = false,
  }) {
    final path = Path();
    projectInto(path, points, matrixFor(angle, center), Vector3.zero(),
        closed: closed);
    return path;
  }

  /// Append [points] projected through a prebuilt [m] into [out], reusing the
  /// caller's [scratch] vector. The performance-critical path: build [m] and
  /// [scratch] once per frame and call this for each contour so a multi-contour
  /// glyph allocates one matrix + one vector per frame total. A NaN/∞ point
  /// breaks the current polyline and a fresh subpath resumes after it.
  void projectInto(
    Path out,
    List<Offset> points,
    Matrix4 m,
    Vector3 scratch, {
    bool closed = false,
  }) {
    var moved = false;
    for (final p in points) {
      scratch.setValues(p.dx, p.dy, 0);
      m.perspectiveTransform(scratch); // mutates scratch; does the w-divide
      final x = scratch.x;
      final y = scratch.y;
      if (!x.isFinite || !y.isFinite) {
        moved = false; // skip the degenerate point, break the polyline here
        continue;
      }
      if (moved) {
        out.lineTo(x, y);
      } else {
        out.moveTo(x, y);
        moved = true;
      }
    }
    if (closed && moved) out.close();
  }
}
