/// # iconic_morph — SVG path reader
///
/// The zero-dependency SVG path-data reader that backs the whole engine, exposed
/// as its own entry point for direct use. Turn a `<path d="…">` string into
/// `moveTo` / `lineTo` / `cubicTo` / `close` calls on your own [SvgPathSink] —
/// relative coordinates, smooth and quadratic curves, and elliptical arcs are all
/// normalized down to absolute cubics. No pub dependency, no `flutter_svg`, no
/// async decode.
///
/// This is a deliberately separate library from the main `iconic_morph.dart`
/// barrel: the barrel is the curated icon-animation API (morph, spin, draw-on),
/// while this is the low-level parser for consumers that just want the reader.
///
/// ```dart
/// import 'dart:ui';
/// import 'package:iconic_morph/svg.dart';
///
/// class _ToPath extends SvgPathSink {
///   _ToPath(this.path);
///   final Path path;
///   @override void moveTo(double x, double y) => path.moveTo(x, y);
///   @override void lineTo(double x, double y) => path.lineTo(x, y);
///   @override void cubicTo(double x1, double y1, double x2, double y2,
///       double x3, double y3) => path.cubicTo(x1, y1, x2, y2, x3, y3);
///   @override void close() => path.close();
/// }
///
/// final path = Path();
/// parseSvgPathData('M4 12 A 8 8 0 0 1 20 12', _ToPath(path));
/// ```
library;

export 'src/svg/svg_path.dart' show parseSvgPathData, SvgPathSink;
