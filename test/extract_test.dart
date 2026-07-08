import 'package:flutter_test/flutter_test.dart';
import 'package:iconic_morph/src/svg/extract.dart';

/// Pins the extraction scope: only VISIBLE geometry feeds the morph. Paths
/// living inside `<defs>`/`<clipPath>`/`<mask>` are plumbing (clip shapes,
/// mask stencils) — splicing them into the contour list corrupts the glyph.
void main() {
  group('extractSvgGeometry', () {
    test('collects every visible path in document order', () {
      const svg = '<svg viewBox="0 0 24 24">'
          '<path d="M1 1L2 2" stroke="#000"/>'
          '<path d="M3 3L4 4" stroke="#000"/>'
          '</svg>';
      final g = extractSvgGeometry(svg);
      expect(g.pathData, ['M1 1L2 2', 'M3 3L4 4']);
      expect(g.viewBox, 24);
      expect(g.isFill, isFalse);
    });

    test('paths inside defs/clipPath/mask are NOT extracted', () {
      const svg = '<svg viewBox="0 0 24 24">'
          '<defs><path d="M9 9h1" fill="#fff"/></defs>'
          '<clipPath id="c"><path d="M8 8v8" fill="#fff"/></clipPath>'
          '<mask id="m"><path d="M0 0h24v24" fill="#fff"/></mask>'
          '<path d="M1 1L2 2" stroke="#000"/>'
          '</svg>';
      final g = extractSvgGeometry(svg);
      expect(g.pathData, ['M1 1L2 2']);
    });

    test('fill/stroke inside plumbing blocks cannot flip isFill', () {
      // The only stroke lives on the mask stencil; the visible glyph is a
      // fill — the icon must classify as a fill, not a stroked outline.
      const svg = '<svg viewBox="0 0 24 24">'
          '<mask id="m"><path d="M0 0h24" stroke="#fff"/></mask>'
          '<path d="M1 1h2z" fill="#000"/>'
          '</svg>';
      expect(extractSvgGeometry(svg).isFill, isTrue);
    });

    test('case-insensitive close tags still strip', () {
      const svg = '<svg viewBox="0 0 24 24">'
          '<clippath id="c"><path d="M8 8v8"/></clippath>'
          '<path d="M1 1L2 2" stroke="#000"/>'
          '</svg>';
      expect(extractSvgGeometry(svg).pathData, ['M1 1L2 2']);
    });

    test('symbol and pattern containers are plumbing too', () {
      const svg = '<svg viewBox="0 0 24 24">'
          '<symbol id="s"><path d="M5 5h5"/></symbol>'
          '<pattern id="p"><path d="M6 6h6"/></pattern>'
          '<path d="M1 1L2 2" stroke="#000"/>'
          '</svg>';
      expect(extractSvgGeometry(svg).pathData, ['M1 1L2 2']);
    });
  });
}
