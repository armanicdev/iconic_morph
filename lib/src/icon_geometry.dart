import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart' show rootBundle;

import 'svg/extract.dart';
import 'svg/svg_path.dart';

/// Supplies an icon's geometry from your own store — the return shape of
/// [IconGeometry.resolver]. `pathData` is the raw `d` attribute(s) from the
/// icon's `<path>` element(s), `viewBox` is the square viewBox edge length, and
/// `isFill` marks a filled glyph (vs a stroked outline). Return `null` for an
/// asset to fall back to the default SVG-asset loader.
typedef IconGeometryResolver = Future<
        ({double viewBox, bool isFill, List<String> pathData})?>
    Function(String asset);

/// One contour (subpath) of an icon, pre-flattened to a polyline with the
/// cumulative arc-length at each point. This is the data every transform-based
/// effect (3D spin, trim draw-on) walks — sampled ONCE at load and cached, so
/// the paint loop never touches [Path.computeMetrics] (which crosses into native
/// Skia and is not free).
class IconContour {
  IconContour(this.points, this.cumLength, this.isClosed);

  /// On-curve points in viewBox space (e.g. 0..24). Always >= 2.
  final List<Offset> points;

  /// Arc length from the contour start to each point; `cumLength[0] == 0` and
  /// `cumLength.last == length`. Same length as [points].
  final List<double> cumLength;

  /// True if the source subpath was closed (`Z`) — effects re-close it.
  final bool isClosed;

  double get length => cumLength.isEmpty ? 0 : cumLength.last;

  /// The whole contour as a polygon [Path], built ONCE and cached. The polyline
  /// never changes after sampling, so any effect that redraws the entire contour
  /// each frame (blink, lock-engage, converge, the morph's assemble pieces) must
  /// reuse this instead of rebuilding `Path()..addPolygon(...)` every tick — that
  /// rebuild crosses into native Skia and is pure per-frame waste. To move it,
  /// transform the canvas and draw this; never mutate the returned path (it is a
  /// shared draw/transform source, not a scratch).
  Path get polygon => _polygon ??= (Path()..addPolygon(points, isClosed));
  Path? _polygon;
}

/// Parsed, sampled, cached geometry for an icon — the input to every
/// [IconEffect]. Built from the icon's SVG via the in-package zero-dep reader
/// [parseSvgPathData] (arcs and smooth curves handled) and sampled into
/// [contours]. The raw [path] is kept
/// for effects that want crisp un-flattened geometry (e.g. a breathe scale).
///
/// Recoloring is the effect's job (it strokes with a passed-in [Paint]); the
/// source `currentColor` in the SVG is irrelevant here.
class IconGeometry {
  IconGeometry({
    required this.path,
    required this.contours,
    required this.viewBox,
    required this.isFill,
  }) : totalLength =
           contours.fold(0, (sum, c) => sum + c.length);

  /// Un-flattened path in viewBox space (cubics intact). For non-transform
  /// effects that can stroke/scale it directly.
  final Path path;

  /// Pre-sampled contours (one per surviving subpath). Note: a genuinely
  /// zero-length subpath is dropped by [Path.computeMetrics]; our icons author
  /// dots as a tiny (>=0.01px) line, which survives as a 2-point contour and
  /// renders as a round-cap dot.
  final List<IconContour> contours;

  /// The viewBox edge length (icons are square). Defaults to 24.
  final double viewBox;

  /// True when the source SVG is a filled glyph rather than a stroked outline.
  /// The constant-stroke 3D trick is meaningful for stroke icons; fill icons
  /// still animate but their "centerline" is the silhouette.
  final bool isFill;

  /// Sum of every contour's arc length — the budget for a continuous draw-on.
  final double totalLength;

  static final Map<String, IconGeometry> _cache = <String, IconGeometry>{};

  /// Clear the geometry cache. The cache is process-lifetime by default; call
  /// this in test tearDown to avoid geometry leaking across test cases, or when
  /// dynamically varying [sampleStep] to release superseded entries. The cache
  /// warms again on the next [load].
  static void evict() => _cache.clear();

  /// Cache key — the asset AND its sample step, because two callers asking for
  /// different [sampleStep]s want DIFFERENT geometry; keying on the asset alone
  /// silently hands the second caller the first's resolution.
  static String _key(String asset, double sampleStep) => '$asset@$sampleStep';

  /// Synchronous cache peek — returns null on a cold cache (caller shows a
  /// static fallback until [load] resolves). After the first load of an asset
  /// every remount is instant and flash-free. Peeks at the [sampleStep] variant
  /// (default), matching the widgets that load at the default step.
  static IconGeometry? peek(String asset, {double sampleStep = 0.6}) =>
      _cache[_key(asset, sampleStep)];

  /// Optional override that supplies an icon's geometry from your own store —
  /// e.g. a baked manifest — instead of loading and parsing an SVG asset at
  /// runtime. Set it once at startup. Return `null` for an asset to fall back to
  /// the default SVG-asset loader (or throw to fail loudly on a missing entry).
  ///
  /// ```dart
  /// IconGeometry.resolver = (asset) async {
  ///   final e = myManifest[asset];
  ///   if (e == null) return null;
  ///   return (viewBox: e.viewBox, isFill: e.isFill, pathData: e.dList);
  /// };
  /// ```
  static IconGeometryResolver? resolver;

  /// One-line setup for the common case: read all geometry from a baked JSON
  /// manifest instead of parsing SVG assets at runtime. Call once at startup
  /// (before any icon paints):
  ///
  /// ```dart
  /// void main() {
  ///   WidgetsFlutterBinding.ensureInitialized();
  ///   IconGeometry.useManifest('assets/icons.json');
  ///   runApp(const MyApp());
  /// }
  /// ```
  ///
  /// [manifestAsset] is a JSON asset of shape
  /// `{ "<iconAssetPath>": {"vb": 24, "fill": false, "d": ["M…", …]}, … }` —
  /// exactly what `dart run iconic_morph:bake` produces. The manifest is decoded
  /// once and cached. An icon missing from the manifest falls back to loading
  /// its SVG asset (so a partial manifest still works).
  static void useManifest(String manifestAsset) {
    Map<String, dynamic>? manifest;
    resolver = (asset) async {
      manifest ??= json.decode(await rootBundle.loadString(manifestAsset))
          as Map<String, dynamic>;
      final entry = manifest![asset];
      if (entry == null) return null; // fall back to the SVG-asset loader
      final m = entry as Map;
      return (
        viewBox: (m['vb'] as num).toDouble(),
        isFill: m['fill'] as bool,
        pathData: <String>[for (final d in m['d'] as List) d as String],
      );
    };
  }

  /// Load and sample an icon (cached by path + sampleStep). Geometry comes from
  /// [resolver] when one is set and returns a spec for [asset]; otherwise the
  /// SVG asset is loaded and parsed.
  static Future<IconGeometry> load(String asset, {double sampleStep = 0.6}) async {
    final key = _key(asset, sampleStep);
    final hit = _cache[key];
    if (hit != null) return hit;

    final IconGeometry geom;
    final spec = await resolver?.call(asset);
    if (spec != null) {
      geom = _fromPathData(
        viewBox: spec.viewBox,
        isFill: spec.isFill,
        pathData: spec.pathData,
        sampleStep: sampleStep,
      );
    } else {
      final svg = await rootBundle.loadString(asset);
      geom = parse(svg, sampleStep: sampleStep);
    }
    _cache[key] = geom;
    return geom;
  }

  /// Parse an SVG string directly (used by [load] and by tests). [sampleStep]
  /// is the arc-length between samples in viewBox units — smaller = smoother
  /// curves at the cost of more points.
  static IconGeometry parse(String svg, {double sampleStep = 0.6}) {
    final g = extractSvgGeometry(svg);
    return _fromPathData(
      viewBox: g.viewBox,
      isFill: g.isFill,
      pathData: g.pathData,
      sampleStep: sampleStep,
    );
  }

  /// Build sampled geometry from raw `d` path data — the single path shared by
  /// [parse] (from an SVG string) and [load] (from a [resolver] spec), so the
  /// two can't diverge. The reader emits only moveTo/lineTo/cubicTo/close.
  static IconGeometry _fromPathData({
    required double viewBox,
    required bool isFill,
    required Iterable<String> pathData,
    required double sampleStep,
  }) {
    final path = Path();
    final sink = _UiPathSink(path);
    for (final d in pathData) {
      parseSvgPathData(d, sink);
    }
    return IconGeometry(
      path: path,
      contours: _sample(path, sampleStep),
      viewBox: viewBox,
      isFill: isFill,
    );
  }

  static List<IconContour> _sample(Path path, double step) {
    // len/step feeds (…).ceil(); a zero/negative step makes that Infinity.ceil(),
    // which throws UnsupportedError before the clamp below can catch it.
    assert(step > 0, 'sampleStep must be > 0 (got $step).');
    final out = <IconContour>[];
    for (final metric in path.computeMetrics()) {
      final len = metric.length;
      // n segments => n+1 points; the i==n sample lands exactly on the endpoint
      // (getTangentForOffset clamps to [0,len]), so corners are never clipped.
      final n = (len / step).ceil().clamp(1, 4096);
      final points = <Offset>[];
      final cum = <double>[];
      for (var i = 0; i <= n; i++) {
        final d = len * i / n;
        final tan = metric.getTangentForOffset(d);
        if (tan == null) continue; // only a zero-length contour, already excluded
        points.add(tan.position);
        cum.add(d);
      }
      if (points.length >= 2) out.add(IconContour(points, cum, metric.isClosed));
    }
    return out;
  }

}

/// Forwards [SvgPathSink] callbacks into a single [Path]. Appending several
/// `d` strings just adds more subpaths.
class _UiPathSink extends SvgPathSink {
  _UiPathSink(this.path);
  final Path path;

  @override
  void moveTo(double x, double y) => path.moveTo(x, y);

  @override
  void lineTo(double x, double y) => path.lineTo(x, y);

  @override
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) =>
      path.cubicTo(x1, y1, x2, y2, x3, y3);

  @override
  void close() => path.close();
}
