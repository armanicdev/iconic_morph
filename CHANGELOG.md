# Changelog

## 1.2.0

**The lift is a thin-then-dissolve, not a thin-to-nothing.** 1.1.0 removed the
terminal dot by tapering ink to zero width, but a stroke that keeps thinning
reads as starving rather than as a pen lifting — and it still ends on a hard cut
at whatever width the last visible frame had. The taper now stops at half weight
and an alpha dissolve over the end of the exit does the removing.

### Added
- **`StrokeTaper.fade(prog, start)`** — the dissolve: alpha 1 → 0 over the end of
  a trim-out.
- **`StrokeTaper.kFloor`** (0.5) and a `floor` parameter on `out` / `into`.
- **`IconMorphPlan.exitFade`** (default `0.75`) — where the dissolve starts.
  `1` disables it (removal by length alone).
- **`IconMorphPlan.taperFloor`** (default `0.5`) — how thin a taper may ever take
  the stroke, at either end. `1` = never thin.
- `StrokeTaper.weighted` takes an `alpha:` argument and returns `null` once
  fully faded, so a dissolved stroke skips its draw entirely.

### Changed
- `StrokeTaper.out` now eases to `floor` instead of to 0; `StrokeTaper.into`
  ramps *from* `floor` instead of from 0.
- `MorphExit.trim`'s length now tracks its (already smoothstepped) window
  progress directly. Both front-loaded curves tried on top of it — 1.0.x's
  `easeOutCubic` and 1.1.0's `easeOutQuad` — turned the ink into a stub while it
  was still fully opaque, which is the very thing that reads as a dot.

## 1.1.0

**The ink now runs out.** A trim-path that animates length alone cannot vanish
cleanly: a round-capped stroke shorter than its own width *is* a dot, so every
un-draw used to end on a fixed-size dot that then blinked out of existence, and
every draw-on began by stamping one. Ink is now weighted by the length it has,
so a stroke starts and finishes as a stroke.

### Added
- **`StrokeTaper`** — the weight law for a trim-path end, and the one home for
  it: `out` (the pen lift), `into` (the nib pressing down), `lengthClamp` (the
  unconditional no-dot safety net — ink is never wider than a third of the
  length it has left), and `weighted`, which returns the `Paint` to stroke with
  or **`null` once the ink is spent**. That null matters: `strokeWidth = 0` is
  Skia's *hairline* mode (a 1px line), not invisibility, so a width animated to
  zero would otherwise end on a flash. Below a minimum renderable width it holds
  the floor and pays the remainder in alpha, so the vanish stays smooth instead
  of aliasing into sub-pixel shimmer.
- **`IconMorphPlan.exitTaper`** (default `0.5`) — where in a leaving contour's
  exit its weight starts running out. `1` restores constant weight.
- **`IconMorphPlan.assembleTaper`** (default `0.18`) — how much of an arriving
  contour's draw-on the nib takes to reach full weight. `0` disables it.

### Changed
- `MorphExit.trim` no longer double-eases. The per-contour window is already a
  Hermite smoothstep; an `easeOutCubic` on top of it spent 99% of the length in
  the first 70% of the exit and then parked the remaining stub on screen for the
  rest — which is what read as "a dot that hangs, then cuts". One `easeOutQuad`
  now shapes it: still decisive (three quarters of the ink gone by the midpoint,
  clearing well before the target assembles), without the park.
- `MorphAssemble.trim`, `IconTrimDraw` (both directions, continuous and bloom)
  and `IconDetailSpin`'s accent trim all carry the no-dot law. Genuine authored
  dots — contours whose whole length is a hair — keep full weight and shrink
  out, rather than being erased for being short.
- `IconMorphPlan.hashCode` moved to `Object.hashAll`: the field list passed
  `Object.hash`'s 20-argument ceiling, where a further field would have been
  silently dropped from the hash.

## 1.0.2

- Packaging & docs only — no API or behaviour changes. Rename the vendored
  `path_parsing` MIT notice from `LICENSE_path_parsing` to
  `THIRD_PARTY_NOTICES.md` so hosts report a single project license (MIT)
  instead of two. Dan Field's notice is retained in full as MIT requires.

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
