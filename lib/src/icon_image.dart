import 'package:flutter/widgets.dart';

import 'icon_effect.dart' show kIconStrokeWidth;
import 'icon_geometry.dart';

/// Renders a static (un-animated) icon by stroking its SVG path at a constant
/// width — the same geometry the animated effects use, so it stays
/// pixel-consistent with every [IconicAnimatedIcon] at rest.
///
/// No `flutter_svg` or `vector_graphics` dependency needed. Also serves as the
/// loading fallback shown by the animated widgets while geometry resolves, so
/// the first frame is never blank.
///
/// ```dart
/// IconImage.asset('packages/iconic_morph/assets/icons/face-id.svg')
/// IconImage.svg('<svg viewBox="0 0 24 24">…</svg>', color: Colors.indigo)
/// ```
class IconImage extends StatefulWidget {
  /// Load and render [asset] (any asset path resolvable by `rootBundle`, e.g.
  /// `MorphIcons.lock` or your own SVG asset). Cached after first load.
  const IconImage.asset(
    this.asset, {
    super.key,
    this.size = 24,
    this.color,
    this.strokeWidth = kIconStrokeWidth,
    this.semanticLabel,
  }) : svg = null;

  /// Parse a raw SVG [svg] string directly — bring-your-own, no assets needed.
  const IconImage.svg(
    this.svg, {
    super.key,
    this.size = 24,
    this.color,
    this.strokeWidth = kIconStrokeWidth,
    this.semanticLabel,
  }) : asset = null;

  final String? asset;
  final String? svg;

  /// Width and height in logical pixels (icons are square). Defaults to 24.
  final double size;

  /// Stroke tint. Null resolves to the ambient [DefaultTextStyle] color (the
  /// idiomatic "currentColor" for a dependency-free widget), then black.
  final Color? color;

  /// Stroke width in viewBox units (2 at a 24 viewBox by default).
  final double strokeWidth;

  final String? semanticLabel;

  @override
  State<IconImage> createState() => _IconImageState();
}

class _IconImageState extends State<IconImage> {
  IconGeometry? _geom;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(IconImage old) {
    super.didUpdateWidget(old);
    if (old.asset != widget.asset || old.svg != widget.svg) {
      _geom = null;
      _resolve();
    }
  }

  void _resolve() {
    final svg = widget.svg;
    if (svg != null) {
      _geom = IconGeometry.parse(svg);
      return;
    }
    final asset = widget.asset!;
    final cached = IconGeometry.peek(asset);
    if (cached != null) {
      _geom = cached;
      return;
    }
    IconGeometry.load(asset).then((g) {
      if (mounted && asset == widget.asset) setState(() => _geom = g);
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ??
        DefaultTextStyle.of(context).style.color ??
        const Color(0xFF000000);
    final geom = _geom;

    final Widget child = SizedBox(
      width: widget.size,
      height: widget.size,
      child: geom == null
          ? null // cold: a sized blank until geometry resolves (no flash)
          : CustomPaint(
              size: Size.square(widget.size),
              painter: _StaticIconPainter(
                geom: geom,
                color: color,
                strokeWidth: widget.strokeWidth,
              ),
            ),
    );

    final label = widget.semanticLabel;
    if (label == null) return child;
    return Semantics(label: label, image: true, child: child);
  }
}

/// Strokes a parsed icon path at a constant width, scaled from its viewBox to the
/// requested size. The static sibling of the animated effect painters.
class _StaticIconPainter extends CustomPainter {
  _StaticIconPainter({
    required this.geom,
    required this.color,
    required this.strokeWidth,
  });

  final IconGeometry geom;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / geom.viewBox;
    final paint = Paint()
      ..style = geom.isFill ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true
      ..color = color;
    canvas.save();
    canvas.scale(s);
    canvas.drawPath(geom.path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StaticIconPainter old) =>
      !identical(old.geom, geom) ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}
