# Changelog

## 1.0.1

- Packaging & docs only — no API or behaviour changes. Use the canonical MIT
  license text so GitHub and pub.dev detect the license cleanly, and point the
  author link at the pub.dev publisher page.

## 1.0.0

Initial public release on pub.dev.

### Animations
- **`IconicMorph`** — path-level cross-icon morph: a travelling "worm" rides a
  quintic-Hermite flight curve from one glyph to the next, with decoupled
  assemble (trim / scale / 3D-flip) and exit (un-draw / fade / scale) modes.
- **`IconicAnimatedIcon`** + effect catalog — `IconSpin3D` (constant-stroke 3D
  spin/unlock/flip), `IconTrimDraw`, `IconTrace`, `IconBreathe`, `IconBlink`,
  `IconConverge`, `IconWeightPulse`, `IconDetailSpin`, `IconGridPop`,
  `IconLineShrink`, `IconShuffle`, `IconInboxRiffle`, `IconLockEngage`.
- **`IconicMorphHero` / `IconicMorphSequence`** — declarative multi-state morph
  (one element, no remounts → no flicker).
- **`IconImage`** — dependency-free static icon; strokes the parsed SVG path at a
  constant width, pixel-consistent with every animated effect at rest.

### Foundations
- **Zero runtime dependencies** — the SVG path parser and the 4×4 matrix math are
  vendored in-tree; a consumer's `flutter pub get` pulls in nothing beyond the
  Flutter SDK.
- **`IconGeometry.useManifest()` / `IconGeometry.resolver`** — read geometry from
  a baked JSON manifest instead of parsing SVG at runtime (cheaper, and you can
  ship no SVGs).
- **`dart run iconic_morph:bake <svg-dir> <out.json>`** — generate that manifest
  from a folder of SVGs.
- Reduced-motion aware (`IconMotion.reduced`): effects snap to their end state.
- Bundled demo glyphs — `MorphIcons.user` / `.face` / `.lock`.
