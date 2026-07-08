import 'dart:math' as math;

/// Degrees → radians (drop-in for `vector_math`'s `radians`).
double radians(double degrees) => degrees * math.pi / 180.0;

/// A minimal column-major 4×4 matrix — an in-package replacement for
/// `package:vector_math`'s `Matrix4` so this engine ships with zero pub
/// dependencies. Implements only the operations the engine needs:
///
///  * For the SVG arc-normalizer: `identity()`, `rotateZ`, and the `storage`
///    2×3 affine read.
///  * For the constant-stroke 3D projector: `identity()`, `translateByDouble`,
///    `setEntry`, `multiply`, `rotateY` / `rotateX`, and `perspectiveTransform`
///    (the homogeneous w-divide).
///
/// Storage is column-major: element `(row, col)` lives at `storage[col * 4 + row]`,
/// matching `vector_math`'s layout so results are numerically identical.
class Matrix4 {
  Matrix4.identity() : storage = List<double>.filled(16, 0.0) {
    storage[0] = 1.0;
    storage[5] = 1.0;
    storage[10] = 1.0;
    storage[15] = 1.0;
  }

  /// Column-major 16-element backing store (`storage[col * 4 + row]`).
  final List<double> storage;

  /// Set element `(row, col)` — same signature/semantics as `vector_math`.
  void setEntry(int row, int col, double v) => storage[col * 4 + row] = v;

  /// Reset to the identity matrix in place (matches `vector_math`).
  void setIdentity() {
    for (var i = 0; i < 16; i++) {
      storage[i] = 0.0;
    }
    storage[0] = 1.0;
    storage[5] = 1.0;
    storage[10] = 1.0;
    storage[15] = 1.0;
  }

  /// `this = this * Scale(x, y ?? x, z ?? x)`.
  /// Matches `vector_math`'s `scale(double x, [double? y, double? z])` signature.
  void scale(double x, [double? y, double? z]) {
    final s = Matrix4.identity();
    s.storage[0] = x;
    s.storage[5] = y ?? x;
    s.storage[10] = z ?? x;
    multiply(s);
  }

  /// In-place right-multiply: `this = this * arg` (column-major). The single
  /// primitive every other mutator is built on.
  void multiply(Matrix4 arg) {
    final a = storage, b = arg.storage;
    final r = List<double>.filled(16, 0.0);
    for (var col = 0; col < 4; col++) {
      for (var row = 0; row < 4; row++) {
        var sum = 0.0;
        for (var k = 0; k < 4; k++) {
          sum += a[k * 4 + row] * b[col * 4 + k];
        }
        r[col * 4 + row] = sum;
      }
    }
    for (var i = 0; i < 16; i++) {
      storage[i] = r[i];
    }
  }

  /// `this = this * Translate(x, y, z; w)`.
  /// Matches `vector_math`'s `translateByDouble` signature.
  void translateByDouble(double x, double y, double z, double w) {
    final t = Matrix4.identity();
    t.storage[12] = x;
    t.storage[13] = y;
    t.storage[14] = z;
    t.storage[15] = w;
    multiply(t);
  }

  /// `this = this * Rx(angle)`.
  void rotateX(double angle) => multiply(_rotX(angle));

  /// `this = this * Ry(angle)`.
  void rotateY(double angle) => multiply(_rotY(angle));

  /// `this = this * Rz(angle)`.
  void rotateZ(double angle) => multiply(_rotZ(angle));

  /// Transforms [v] by this matrix and applies the homogeneous w-divide,
  /// mutating [v] in place. Matches `vector_math`'s `perspectiveTransform`.
  Vector3 perspectiveTransform(Vector3 v) {
    final s = storage;
    final x = s[0] * v.x + s[4] * v.y + s[8] * v.z + s[12];
    final y = s[1] * v.x + s[5] * v.y + s[9] * v.z + s[13];
    final z = s[2] * v.x + s[6] * v.y + s[10] * v.z + s[14];
    final w = 1.0 / (s[3] * v.x + s[7] * v.y + s[11] * v.z + s[15]);
    v
      ..x = x * w
      ..y = y * w
      ..z = z * w;
    return v;
  }

  static Matrix4 _rotX(double a) {
    final c = math.cos(a), s = math.sin(a);
    final m = Matrix4.identity();
    m.storage[5] = c; //  (1,1)
    m.storage[6] = s; //  (2,1)
    m.storage[9] = -s; // (1,2)
    m.storage[10] = c; // (2,2)
    return m;
  }

  static Matrix4 _rotY(double a) {
    final c = math.cos(a), s = math.sin(a);
    final m = Matrix4.identity();
    m.storage[0] = c; //  (0,0)
    m.storage[2] = -s; // (2,0)
    m.storage[8] = s; //  (0,2)
    m.storage[10] = c; // (2,2)
    return m;
  }

  static Matrix4 _rotZ(double a) {
    final c = math.cos(a), s = math.sin(a);
    final m = Matrix4.identity();
    m.storage[0] = c; //  (0,0)
    m.storage[1] = s; //  (1,0)
    m.storage[4] = -s; // (0,1)
    m.storage[5] = c; //  (1,1)
    return m;
  }
}

/// A minimal mutable 3-vector, implementing the subset of `vector_math`'s
/// `Vector3` that the [Projector3D] uses: construction, [zero], [setValues],
/// and mutable [x] / [y] / [z] fields.
class Vector3 {
  Vector3(this.x, this.y, this.z);
  Vector3.zero()
      : x = 0.0,
        y = 0.0,
        z = 0.0;

  double x;
  double y;
  double z;

  void setValues(double nx, double ny, double nz) {
    x = nx;
    y = ny;
    z = nz;
  }
}
