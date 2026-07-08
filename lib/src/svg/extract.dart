/// Pure-Dart SVG → geometry-fields extraction — NO Flutter / `dart:ui` imports,
/// so it runs under a plain `dart` (the `iconic_morph:bake` CLI) AND backs the
/// runtime parser ([IconGeometry.parse]). One source of truth means a baked
/// manifest can never drift from what a live parse would have produced.
library;

/// The minimal geometry an icon needs from its source SVG: the square viewBox
/// edge, whether it's a filled glyph (vs a stroked outline), and every
/// `<path d="…">` string in document order. Same shape as the spec returned by
/// [IconGeometry.resolver].
({double viewBox, bool isFill, List<String> pathData}) extractSvgGeometry(
    String svg) {
  // Paths inside <defs>/<clipPath>/<mask> are plumbing (clip shapes, mask
  // stencils, reusable defs), not visible glyph geometry — an unscoped scan
  // would splice them into the contour list and corrupt the morph. Strip
  // those blocks before extraction; fill/stroke detection runs on the same
  // stripped document so plumbing attributes can't flip [isFill] either.
  final visible = svg.replaceAll(_hiddenBlockRe, '');
  final hasStroke = _strokeRe.hasMatch(visible);
  final hasFill = _fillRe.hasMatch(visible);
  return (
    viewBox: parseSvgViewBox(svg),
    isFill: hasFill && !hasStroke,
    pathData: <String>[
      for (final m in _dRe.allMatches(visible)) m.group(1) ?? ''
    ],
  );
}

/// The viewBox edge length, asserting a 0-origin square box (every painter scales
/// geometry by `size/viewBox` from origin assuming square — fail loud in debug on
/// a non-conforming asset rather than silently offset/clip the glyph).
double parseSvgViewBox(String svg) {
  final m = _viewBoxRe.firstMatch(svg);
  if (m == null) return 24;
  final minX = double.tryParse(m.group(1) ?? '');
  final minY = double.tryParse(m.group(2) ?? '');
  final w = double.tryParse(m.group(3) ?? '');
  final h = double.tryParse(m.group(4) ?? '');
  assert(
    (minX == null || minX == 0) && (minY == null || minY == 0),
    'iconic_morph expects a 0-origin viewBox; got "${m.group(0)}"',
  );
  assert(
    w == null || h == null || (w - h).abs() < 0.01,
    'iconic_morph expects a square viewBox; got "${m.group(0)}"',
  );
  return (w == null || w <= 0) ? 24 : w;
}

final RegExp _dRe = RegExp(r'\sd="([^"]*)"');
// Non-visible container blocks, stripped before extraction (non-greedy to the
// matching close tag; case-insensitive for hand-written `clippath` variants).
// KNOWN LIMIT: a same-name block NESTED inside another (defs-in-defs) closes
// at the inner tag — pathological SVG this regex deliberately doesn't chase;
// run such an asset through SVGO first (the app's own icon pipeline already
// does, so bundled icons never hit this).
final RegExp _hiddenBlockRe = RegExp(
  r'<(defs|clipPath|mask|symbol|pattern)\b[\s\S]*?</\1\s*>',
  caseSensitive: false,
);
final RegExp _strokeRe = RegExp(r'stroke="(?!none)[^"]+"');
final RegExp _fillRe = RegExp(r'fill="(?!none)[^"]+"');
// Allow a negative origin in the match so the 0-origin assert can catch it
// (a `[\d.]+` origin would silently fall through to the default instead).
final RegExp _viewBoxRe =
    RegExp(r'viewBox="(-?[\d.]+)\s+(-?[\d.]+)\s+([\d.]+)\s+([\d.]+)"');
