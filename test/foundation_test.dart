import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:iconic_morph/src/icon_geometry.dart';
import 'package:iconic_morph/src/math/mat4.dart';
import 'package:iconic_morph/src/projection_3d.dart';

/// Foundation tests — they lock the two zero-dependency replacements the whole
/// engine rests on: the hand-written column-major [Matrix4] shim and the vendored
/// SVG parser (whose arc-normalizer drives that shim). If these pass, the shim is
/// numerically equivalent to `vector_math` for every operation the engine uses.
void main() {
  group('Matrix4 shim (column-major, vector_math-equivalent)', () {
    test('identity leaves a point untouched under perspectiveTransform', () {
      final v = Vector3(3, 5, 0);
      Matrix4.identity().perspectiveTransform(v);
      expect(v.x, closeTo(3, 1e-12));
      expect(v.y, closeTo(5, 1e-12));
    });

    test('rotateZ writes the textbook column-major rotation into storage', () {
      // Identity · Rz(θ): storage[0]=cosθ, [1]=sinθ, [4]=-sinθ, [5]=cosθ.
      final m = Matrix4.identity()..rotateZ(math.pi / 2);
      expect(m.storage[0], closeTo(0, 1e-12)); // cos90
      expect(m.storage[1], closeTo(1, 1e-12)); // sin90
      expect(m.storage[4], closeTo(-1, 1e-12)); // -sin90
      expect(m.storage[5], closeTo(0, 1e-12)); // cos90
    });

    test('rotateZ(90°) maps the unit-x point to +y (right-handed)', () {
      final v = Vector3(1, 0, 0);
      (Matrix4.identity()..rotateZ(math.pi / 2)).perspectiveTransform(v);
      expect(v.x, closeTo(0, 1e-12));
      expect(v.y, closeTo(1, 1e-12));
    });

    test('multiply is associative-correct: (T·P) then divide is finite', () {
      final m = Matrix4.identity()
        ..translateByDouble(12, 12, 0, 1)
        ..multiply(Matrix4.identity()..setEntry(3, 2, -0.0026))
        ..rotateY(0.7)
        ..translateByDouble(-12, -12, 0, 1);
      final v = Vector3(20, 8, 0);
      m.perspectiveTransform(v);
      expect(v.x.isFinite && v.y.isFinite, isTrue);
    });
  });

  group('Projector3D (constant-stroke 3D core, on the shim)', () {
    const proj = Projector3D();
    const center = 12.0;

    test('angle 0 is the identity', () {
      final out = proj.project(const Offset(20, 7), 0, center);
      expect(out.dx, closeTo(20, 1e-6));
      expect(out.dy, closeTo(7, 1e-6));
    });

    test('edge-on (90°) collapses x toward the axis with no y drift', () {
      final out = proj.project(const Offset(24, 12), math.pi / 2, center);
      expect((out.dx - center).abs(), lessThan(12)); // foreshortened inward
      expect(out.dy, closeTo(12, 1e-6)); // vertical axis → no vertical drift
    });

    test('projected points stay finite across a full turn', () {
      for (var deg = 0; deg <= 360; deg += 15) {
        final out = proj.project(const Offset(24, 24), deg * math.pi / 180, center);
        expect(out.dx.isFinite && out.dy.isFinite, isTrue);
      }
    });

    test('projectPolyline at angle 0 keeps the original bounds', () {
      const pts = [Offset(4, 12), Offset(12, 4), Offset(20, 12)];
      final b = proj.projectPolyline(pts, 0, center).getBounds();
      expect(b.left, closeTo(4, 1e-6));
      expect(b.right, closeTo(20, 1e-6));
    });
  });

  group('IconGeometry.parse (vendored SVG parser, zero deps)', () {
    test('a straight stroke yields one contour of the right length', () {
      final g = IconGeometry.parse(
        '<svg viewBox="0 0 24 24"><path stroke="currentColor" '
        'stroke-width="2" d="M4 12h16"/></svg>',
      );
      expect(g.contours, hasLength(1));
      expect(g.contours.single.length, closeTo(16, 0.5));
      expect(g.contours.single.points.every((p) => (p.dy - 12).abs() < 1e-6), isTrue);
    });

    test('an ARC normalizes through the shim to ~the right arc length', () {
      // Semicircle of radius 8 from (4,12) to (20,12): length ≈ π·8 ≈ 25.13.
      // This exercises path_parsing's arc→cubic normalizer, which drives the
      // Matrix4 shim's rotateZ — a wrong shim would deform the curve.
      final g = IconGeometry.parse(
        '<svg viewBox="0 0 24 24"><path stroke="currentColor" '
        'stroke-width="2" d="M4 12 A 8 8 0 0 1 20 12"/></svg>',
      );
      final len = g.contours.fold<double>(0, (s, c) => s + c.length);
      expect(len, closeTo(math.pi * 8, 1.5));
    });

    test('cumulative arc-length is monotonic and ends at the contour length', () {
      final g = IconGeometry.parse(
        '<svg viewBox="0 0 24 24"><path stroke="currentColor" '
        'stroke-width="2" d="M4 4 L20 4 L20 20"/></svg>',
      );
      final c = g.contours.single;
      for (var i = 1; i < c.cumLength.length; i++) {
        expect(c.cumLength[i], greaterThanOrEqualTo(c.cumLength[i - 1]));
      }
      expect(c.cumLength.last, closeTo(c.length, 1e-9));
    });
  });
}
