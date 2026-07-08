// SVG path-data reader — turns a `<path d="…">` string into moveTo / lineTo /
// cubicTo / close calls on an [SvgPathSink]. One pass over the string, no
// allocation beyond a single small segment record at a time, and — like the
// rest of iconic_morph — free of any pub dependency: the only thing it leans on
// is the in-package [Matrix4] for the arc→cubic step.
//
// Lineage: the path grammar and the arc-normalization math derive from Dan
// Field's `path_parsing` (MIT, © 2018 — full text in LICENSE_path_parsing),
// itself a port of Chromium/blink's SVG path parser. The numeric behavior is
// kept byte-for-byte, so geometry stays identical to flutter_svg's; everything
// else is reshaped for this engine — our names, our two-call surface, none of
// the upstream dead weight.

import 'dart:math' as math show atan2, cos, max, pi, pow, sin, sqrt, tan;

import '../math/mat4.dart';

/// Parses [d] — the value of an SVG `<path d="…">` attribute — and drives [sink]
/// with the normalized drawing commands. Relative coordinates, smooth and
/// quadratic curves, and elliptical arcs are all resolved down to absolute
/// moveTo / lineTo / cubicTo / close. A null or empty [d] emits nothing.
void parseSvgPathData(String? d, SvgPathSink sink) {
  if (d == null || d.isEmpty) return;
  final scanner = _PathScanner(d);
  final normalizer = _PathNormalizer();
  for (final segment in scanner.parseSegments()) {
    normalizer.emitSegment(segment, sink);
  }
}

/// Receiver for the normalized output of [parseSvgPathData]. Only these four
/// commands are ever emitted — every arc and quadratic is decomposed to cubics.
abstract class SvgPathSink {
  void moveTo(double x, double y);
  void lineTo(double x, double y);
  void cubicTo(
      double x1, double y1, double x2, double y2, double x3, double y3);
  void close();
}

const double _twoPi = math.pi * 2.0;
const double _halfPi = math.pi / 2.0;
const double _oneThird = 1.0 / 3.0;

/// A tiny immutable 2-D point/offset with just the vector ops the parser needs —
/// no `dart:ui` or `vector_math` dependency.
class _Vec2 {
  const _Vec2(this.dx, this.dy);
  static const _Vec2 zero = _Vec2(0, 0);

  final double dx;
  final double dy;

  double get direction => math.atan2(dy, dx);

  _Vec2 translate(double tx, double ty) => _Vec2(dx + tx, dy + ty);

  _Vec2 operator +(_Vec2 o) => _Vec2(dx + o.dx, dy + o.dy);
  _Vec2 operator -(_Vec2 o) => _Vec2(dx - o.dx, dy - o.dy);
  _Vec2 operator *(double s) => _Vec2(dx * s, dy * s);

  @override
  bool operator ==(Object other) =>
      other is _Vec2 && other.dx == dx && other.dy == dy;

  @override
  int get hashCode => Object.hash(dx, dy);
}

/// SVG path commands, one per letter — uppercase absolute, lowercase relative.
enum _Cmd {
  unknown,
  close, // Z z
  moveToAbs, // M
  moveToRel, // m
  lineToAbs, // L
  lineToRel, // l
  cubicToAbs, // C
  cubicToRel, // c
  quadToAbs, // Q
  quadToRel, // q
  arcToAbs, // A
  arcToRel, // a
  lineToHAbs, // H
  lineToHRel, // h
  lineToVAbs, // V
  lineToVRel, // v
  smoothCubicToAbs, // S
  smoothCubicToRel, // s
  smoothQuadToAbs, // T
  smoothQuadToRel, // t
}

/// The ASCII code units the scanner recognizes, plus the command-letter lookup.
/// Only the subset the parser actually touches, not the full table.
abstract final class _Ascii {
  /// The command a leading letter [ch] introduces, or [_Cmd.unknown].
  static _Cmd command(int ch) => _byLetter[ch] ?? _Cmd.unknown;

  static const Map<int, _Cmd> _byLetter = <int, _Cmd>{
    upperZ: _Cmd.close, lowerZ: _Cmd.close,
    upperM: _Cmd.moveToAbs, lowerM: _Cmd.moveToRel,
    upperL: _Cmd.lineToAbs, lowerL: _Cmd.lineToRel,
    upperC: _Cmd.cubicToAbs, lowerC: _Cmd.cubicToRel,
    upperQ: _Cmd.quadToAbs, lowerQ: _Cmd.quadToRel,
    upperA: _Cmd.arcToAbs, lowerA: _Cmd.arcToRel,
    upperH: _Cmd.lineToHAbs, lowerH: _Cmd.lineToHRel,
    upperV: _Cmd.lineToVAbs, lowerV: _Cmd.lineToVRel,
    upperS: _Cmd.smoothCubicToAbs, lowerS: _Cmd.smoothCubicToRel,
    upperT: _Cmd.smoothQuadToAbs, lowerT: _Cmd.smoothQuadToRel,
  };

  // Whitespace.
  static const int tab = 9;
  static const int newline = 10;
  static const int formFeed = 12;
  static const int carriageReturn = 13;
  static const int space = 32;

  // Number syntax.
  static const int plus = 43;
  static const int comma = 44;
  static const int minus = 45;
  static const int period = 46;
  static const int digit0 = 48;
  static const int digit1 = 49;
  static const int digit9 = 57;
  static const int upperE = 69;
  static const int lowerE = 101;
  static const int lowerX = 120;

  // Command letters.
  static const int upperA = 65;
  static const int upperC = 67;
  static const int upperH = 72;
  static const int upperL = 76;
  static const int upperM = 77;
  static const int upperQ = 81;
  static const int upperS = 83;
  static const int upperT = 84;
  static const int upperV = 86;
  static const int upperZ = 90;
  static const int lowerA = 97;
  static const int lowerC = 99;
  static const int lowerH = 104;
  static const int lowerL = 108;
  static const int lowerM = 109;
  static const int lowerQ = 113;
  static const int lowerS = 115;
  static const int lowerT = 116;
  static const int lowerV = 118;
  static const int lowerZ = 122;
}

/// Walks a path-data string left to right, yielding one raw [_Segment] per
/// command (resolving implicit command repeats along the way).
class _PathScanner {
  _PathScanner(this._d)
      : _prev = _Cmd.unknown,
        _idx = 0,
        _len = _d.length {
    _skipSpaces();
  }

  final String _d;
  _Cmd _prev;
  int _idx;
  final int _len;

  bool get hasMoreData => _idx < _len;

  Iterable<_Segment> parseSegments() sync* {
    while (hasMoreData) {
      yield parseSegment();
    }
  }

  bool _isSpace(int ch) =>
      ch <= _Ascii.space &&
      (ch == _Ascii.space ||
          ch == _Ascii.newline ||
          ch == _Ascii.tab ||
          ch == _Ascii.carriageReturn ||
          ch == _Ascii.formFeed);

  /// Advances past whitespace; returns the next non-space code unit, or -1 at
  /// end of string.
  int _skipSpaces() {
    while (_idx < _len) {
      final ch = _d.codeUnitAt(_idx);
      if (!_isSpace(ch)) return ch;
      _idx++;
    }
    return -1;
  }

  void _skipSpacesOrComma() {
    if (_skipSpaces() == _Ascii.comma) {
      _idx++;
      _skipSpaces();
    }
  }

  static bool _startsNumber(int ch) =>
      (ch >= _Ascii.digit0 && ch <= _Ascii.digit9) ||
      ch == _Ascii.plus ||
      ch == _Ascii.minus ||
      ch == _Ascii.period;

  /// A coordinate with no command letter repeats the previous command — except
  /// a moveto repeats as a lineto, and close (which takes no operands) never
  /// continues. Returns [next] unchanged when there is no implicit repeat.
  _Cmd _implicitCommand(int lookahead, _Cmd next) {
    if (!_startsNumber(lookahead) || _prev == _Cmd.close) return next;
    if (_prev == _Cmd.moveToAbs) return _Cmd.lineToAbs;
    if (_prev == _Cmd.moveToRel) return _Cmd.lineToRel;
    return _prev;
  }

  bool _inRange(double x) => -double.maxFinite <= x && x <= double.maxFinite;
  bool _validExponent(double x) => -37 <= x && x <= 38;

  /// Reads one code unit and advances; -1 at end of string.
  @pragma('vm:prefer-inline')
  int _read() => _idx >= _len ? -1 : _d.codeUnitAt(_idx++);

  /// Parses a number left to right, carrying full precision so the geometry
  /// never loses bits to an intermediate round.
  double _parseNumber() {
    _skipSpaces();

    var sign = 1;
    var c = _read();
    if (c == _Ascii.plus) {
      c = _read();
    } else if (c == _Ascii.minus) {
      sign = -1;
      c = _read();
    }

    if ((c < _Ascii.digit0 || c > _Ascii.digit9) && c != _Ascii.period) {
      throw StateError('First character of a number must be one of [0-9+-.].');
    }

    var integer = 0.0;
    while (_Ascii.digit0 <= c && c <= _Ascii.digit9) {
      integer = integer * 10 + (c - _Ascii.digit0);
      c = _read();
    }
    if (!_inRange(integer)) throw StateError('Numeric overflow');

    var decimal = 0.0;
    if (c == _Ascii.period) {
      c = _read();
      if (c < _Ascii.digit0 || c > _Ascii.digit9) {
        throw StateError('There must be at least one digit following the .');
      }
      var frac = 1.0;
      while (_Ascii.digit0 <= c && c <= _Ascii.digit9) {
        frac *= 0.1;
        decimal += (c - _Ascii.digit0) * frac;
        c = _read();
      }
    }

    var number = (integer + decimal) * sign;

    // Exponent — but an 'e'/'E' that begins a following token (…x/…m) is not one.
    if (_idx < _len &&
        (c == _Ascii.upperE || c == _Ascii.lowerE) &&
        _d.codeUnitAt(_idx) != _Ascii.lowerX &&
        _d.codeUnitAt(_idx) != _Ascii.lowerM) {
      c = _read();
      var negativeExponent = false;
      if (c == _Ascii.plus) {
        c = _read();
      } else if (c == _Ascii.minus) {
        c = _read();
        negativeExponent = true;
      }
      if (c < _Ascii.digit0 || c > _Ascii.digit9) {
        throw StateError('Missing exponent');
      }
      var exponent = 0.0;
      while (c >= _Ascii.digit0 && c <= _Ascii.digit9) {
        exponent = exponent * 10.0 + (c - _Ascii.digit0);
        c = _read();
      }
      if (negativeExponent) exponent = -exponent;
      if (!_validExponent(exponent)) throw StateError('Invalid exponent $exponent');
      if (exponent != 0) number *= math.pow(10.0, exponent);
    }

    if (!_inRange(number)) throw StateError('Numeric overflow');

    // c holds one unconsumed char and _idx is already past it. Put it back, then
    // swallow the trailing separator so the next number starts clean; -1 is EOF.
    if (c != -1) {
      _idx--;
      _skipSpacesOrComma();
    }
    return number;
  }

  bool _parseFlag() {
    if (!hasMoreData) throw StateError('Expected more data');
    final flag = _d.codeUnitAt(_idx++);
    _skipSpacesOrComma();
    if (flag == _Ascii.digit0) return false;
    if (flag == _Ascii.digit1) return true;
    throw StateError('Invalid flag value');
  }

  _Segment parseSegment() {
    assert(hasMoreData);
    final segment = _Segment();
    final lookahead = _d.codeUnitAt(_idx);
    var command = _Ascii.command(lookahead);

    if (_prev == _Cmd.unknown) {
      // A path must open with a moveto.
      if (command != _Cmd.moveToRel && command != _Cmd.moveToAbs) {
        throw StateError('Expected to find moveTo command');
      }
      _idx++;
    } else if (command == _Cmd.unknown) {
      // No letter here — it may be an implicit repeat of the previous command.
      command = _implicitCommand(lookahead, command);
      if (command == _Cmd.unknown) throw StateError('Expected a path command');
    } else {
      _idx++;
    }

    segment.command = _prev = command;

    switch (segment.command) {
      case _Cmd.cubicToRel:
      case _Cmd.cubicToAbs:
        segment.point1 = _Vec2(_parseNumber(), _parseNumber());
        continue cubicSmooth;
      case _Cmd.smoothCubicToRel:
      cubicSmooth:
      case _Cmd.smoothCubicToAbs:
        segment.point2 = _Vec2(_parseNumber(), _parseNumber());
        continue quadSmooth;
      case _Cmd.moveToRel:
      case _Cmd.moveToAbs:
      case _Cmd.lineToRel:
      case _Cmd.lineToAbs:
      case _Cmd.smoothQuadToRel:
      quadSmooth:
      case _Cmd.smoothQuadToAbs:
        segment.targetPoint = _Vec2(_parseNumber(), _parseNumber());
      case _Cmd.lineToHRel:
      case _Cmd.lineToHAbs:
        segment.targetPoint = _Vec2(_parseNumber(), segment.targetPoint.dy);
      case _Cmd.lineToVRel:
      case _Cmd.lineToVAbs:
        segment.targetPoint = _Vec2(segment.targetPoint.dx, _parseNumber());
      case _Cmd.close:
        _skipSpaces();
      case _Cmd.quadToRel:
      case _Cmd.quadToAbs:
        segment.point1 = _Vec2(_parseNumber(), _parseNumber());
        segment.targetPoint = _Vec2(_parseNumber(), _parseNumber());
      case _Cmd.arcToRel:
      case _Cmd.arcToAbs:
        segment.point1 = _Vec2(_parseNumber(), _parseNumber());
        segment.arcAngle = _parseNumber();
        segment.arcLarge = _parseFlag();
        segment.arcSweep = _parseFlag();
        segment.targetPoint = _Vec2(_parseNumber(), _parseNumber());
      case _Cmd.unknown:
        throw StateError('Unknown segment command');
    }

    return segment;
  }
}

/// One parsed command and its operands. Arc radii reuse [point1] and the arc
/// x-axis rotation reuses [point2].dx, matching how [_PathScanner] fills them.
class _Segment {
  _Segment()
      : command = _Cmd.unknown,
        arcSweep = false,
        arcLarge = false;

  _Cmd command;
  _Vec2 targetPoint = _Vec2.zero;
  _Vec2 point1 = _Vec2.zero;
  _Vec2 point2 = _Vec2.zero;
  bool arcSweep;
  bool arcLarge;

  _Vec2 get arcRadii => point1;

  /// Arc x-axis rotation, in degrees.
  double get arcAngle => point2.dx;
  set arcAngle(double degrees) => point2 = _Vec2(degrees, point2.dy);

  double get x => targetPoint.dx;
  double get y => targetPoint.dy;
  double get x1 => point1.dx;
  double get y1 => point1.dy;
  double get x2 => point2.dx;
  double get y2 => point2.dy;
}

/// Reflects [point] through [center] — synthesizes the implied control point of
/// a smooth (S/T) curve.
_Vec2 _reflect(_Vec2 center, _Vec2 point) =>
    _Vec2(2 * center.dx - point.dx, 2 * center.dy - point.dy);

/// Blends a quadratic control point toward its cubic equivalent at a 1:2 ratio.
_Vec2 _blend(_Vec2 a, _Vec2 b) =>
    _Vec2((a.dx + 2 * b.dx) * _oneThird, (a.dy + 2 * b.dy) * _oneThird);

bool _isCubic(_Cmd c) =>
    c == _Cmd.cubicToAbs ||
    c == _Cmd.cubicToRel ||
    c == _Cmd.smoothCubicToAbs ||
    c == _Cmd.smoothCubicToRel;

bool _isQuadratic(_Cmd c) =>
    c == _Cmd.quadToAbs ||
    c == _Cmd.quadToRel ||
    c == _Cmd.smoothQuadToAbs ||
    c == _Cmd.smoothQuadToRel;

/// Turns raw [_Segment]s into absolute moveTo / lineTo / cubicTo / close calls:
/// relative coordinates become absolute, smooth curves recover their reflected
/// control point, and quadratics and arcs are converted to cubics.
class _PathNormalizer {
  _Vec2 _current = _Vec2.zero;
  _Vec2 _subPathStart = _Vec2.zero;
  _Vec2 _control = _Vec2.zero;
  _Cmd _last = _Cmd.unknown;

  void emitSegment(_Segment seg, SvgPathSink sink) {
    // 1. Resolve relative operands against the current point.
    switch (seg.command) {
      case _Cmd.quadToRel:
        seg.point1 += _current;
        seg.targetPoint += _current;
      case _Cmd.cubicToRel:
        seg.point1 += _current;
        continue smoothRel;
      smoothRel:
      case _Cmd.smoothCubicToRel:
        seg.point2 += _current;
        continue arcRel;
      case _Cmd.moveToRel:
      case _Cmd.lineToRel:
      case _Cmd.lineToHRel:
      case _Cmd.lineToVRel:
      case _Cmd.smoothQuadToRel:
      arcRel:
      case _Cmd.arcToRel:
        seg.targetPoint += _current;
      case _Cmd.lineToHAbs:
        seg.targetPoint = _Vec2(seg.targetPoint.dx, _current.dy);
      case _Cmd.lineToVAbs:
        seg.targetPoint = _Vec2(_current.dx, seg.targetPoint.dy);
      case _Cmd.close:
        // Snap back to the sub-path's start for the next segment.
        seg.targetPoint = _subPathStart;
      default:
        break;
    }

    // 2. Emit — decomposing smooth, quadratic and arc segments into cubics.
    switch (seg.command) {
      case _Cmd.moveToRel:
      case _Cmd.moveToAbs:
        _subPathStart = seg.targetPoint;
        sink.moveTo(seg.targetPoint.dx, seg.targetPoint.dy);
      case _Cmd.lineToRel:
      case _Cmd.lineToAbs:
      case _Cmd.lineToHRel:
      case _Cmd.lineToHAbs:
      case _Cmd.lineToVRel:
      case _Cmd.lineToVAbs:
        sink.lineTo(seg.targetPoint.dx, seg.targetPoint.dy);
      case _Cmd.close:
        sink.close();
      case _Cmd.smoothCubicToRel:
      case _Cmd.smoothCubicToAbs:
        seg.point1 = _isCubic(_last) ? _reflect(_current, _control) : _current;
        continue cubicAbs;
      case _Cmd.cubicToRel:
      cubicAbs:
      case _Cmd.cubicToAbs:
        _control = seg.point2;
        sink.cubicTo(seg.point1.dx, seg.point1.dy, seg.point2.dx, seg.point2.dy,
            seg.targetPoint.dx, seg.targetPoint.dy);
      case _Cmd.smoothQuadToRel:
      case _Cmd.smoothQuadToAbs:
        seg.point1 =
            _isQuadratic(_last) ? _reflect(_current, _control) : _current;
        continue quadAbs;
      case _Cmd.quadToRel:
      quadAbs:
      case _Cmd.quadToAbs:
        // Keep the raw quadratic control point, then lift it to two cubic ones.
        _control = seg.point1;
        seg.point1 = _blend(_current, _control);
        seg.point2 = _blend(seg.targetPoint, _control);
        sink.cubicTo(seg.point1.dx, seg.point1.dy, seg.point2.dx, seg.point2.dy,
            seg.targetPoint.dx, seg.targetPoint.dy);
      case _Cmd.arcToRel:
      case _Cmd.arcToAbs:
        if (!_emitArcAsCubics(_current, seg, sink)) {
          // A degenerate arc (zero radius or zero length) draws as a line.
          sink.lineTo(seg.targetPoint.dx, seg.targetPoint.dy);
        }
      default:
        throw StateError('Invalid command type in path');
    }

    _current = seg.targetPoint;
    if (!_isCubic(seg.command) && !_isQuadratic(seg.command)) {
      _control = _current;
    }
    _last = seg.command;
  }

  /// Decomposes an elliptical arc into cubic Béziers, per the W3C SVG
  /// implementation notes (endpoint-to-center parameterization). Returns false
  /// when the arc is degenerate and the caller should draw a straight line.
  bool _emitArcAsCubics(_Vec2 start, _Segment seg, SvgPathSink sink) {
    // A zero radius, or coincident endpoints, collapses the arc to a line.
    var rx = seg.arcRadii.dx.abs();
    var ry = seg.arcRadii.dy.abs();
    if (rx == 0 || ry == 0) return false;
    if (seg.targetPoint == start) return false;

    final angle = radians(seg.arcAngle);
    final midDistance = (start - seg.targetPoint) * 0.5;

    final transform = Matrix4.identity()..rotateZ(-angle);
    final mid = _mapPoint(transform, _Vec2(midDistance.dx, midDistance.dy));

    final squareRx = rx * rx;
    final squareRy = ry * ry;
    final squareX = mid.dx * mid.dx;
    final squareY = mid.dy * mid.dy;

    // Scale the radii up if they're too small to span the endpoints.
    final radiiScale = squareX / squareRx + squareY / squareRy;
    if (radiiScale > 1.0) {
      rx *= math.sqrt(radiiScale);
      ry *= math.sqrt(radiiScale);
    }

    transform.setIdentity();
    transform
      ..scale(1.0 / rx, 1.0 / ry)
      ..rotateZ(-angle);

    var point1 = _mapPoint(transform, start);
    var point2 = _mapPoint(transform, seg.targetPoint);
    var delta = point2 - point1;

    final d = delta.dx * delta.dx + delta.dy * delta.dy;
    final scaleFactorSquared = math.max(1.0 / d - 0.25, 0.0);
    var scaleFactor = math.sqrt(scaleFactorSquared);
    if (!scaleFactor.isFinite) scaleFactor = 0.0;
    if (seg.arcSweep == seg.arcLarge) scaleFactor = -scaleFactor;

    delta = delta * scaleFactor;
    final center = ((point1 + point2) * 0.5).translate(-delta.dy, delta.dx);

    final theta1 = (point1 - center).direction;
    final theta2 = (point2 - center).direction;
    var thetaArc = theta2 - theta1;
    if (thetaArc < 0.0 && seg.arcSweep) {
      thetaArc += _twoPi;
    } else if (thetaArc > 0.0 && !seg.arcSweep) {
      thetaArc -= _twoPi;
    }

    transform.setIdentity();
    transform
      ..rotateZ(angle)
      ..scale(rx, ry);

    // atan2 rounding on some platforms over-counts the segments; the +0.001
    // nudge pulls the count back to the geometrically expected value.
    final segments = (thetaArc / (_halfPi + 0.001)).abs().ceil();
    for (var i = 0; i < segments; i++) {
      final startTheta = theta1 + i * thetaArc / segments;
      final endTheta = theta1 + (i + 1) * thetaArc / segments;

      final t = (8.0 / 6.0) * math.tan(0.25 * (endTheta - startTheta));
      if (!t.isFinite) return false;

      final sinStart = math.sin(startTheta);
      final cosStart = math.cos(startTheta);
      final sinEnd = math.sin(endTheta);
      final cosEnd = math.cos(endTheta);

      point1 = _Vec2(cosStart - t * sinStart, sinStart + t * cosStart)
          .translate(center.dx, center.dy);
      final target = _Vec2(cosEnd, sinEnd).translate(center.dx, center.dy);
      point2 = target.translate(t * sinEnd, -t * cosEnd);

      final c1 = _mapPoint(transform, point1);
      final c2 = _mapPoint(transform, point2);
      final end = _mapPoint(transform, target);
      sink.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
    }
    return true;
  }

  /// Applies the 2×3 affine part of [m] to [p] (rotation/scale/translation).
  _Vec2 _mapPoint(Matrix4 m, _Vec2 p) => _Vec2(
        m.storage[0] * p.dx + m.storage[4] * p.dy + m.storage[12],
        m.storage[1] * p.dx + m.storage[5] * p.dy + m.storage[13],
      );
}
