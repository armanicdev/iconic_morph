# Changelog

## 1.5.0

**The dissolve is measured in real time, and now actually lasts.** 1.4.0 put the
fade in the right place — ending at the dot horizon — but specified its length as
a quarter of the exit's *progress*. Progress is smoothstepped across each
contour's window, so that quarter landed exactly where the smoothstep moves
fastest: 19% of the window, **43 ms, under three frames at 60 Hz**. On paper a
quarter; on screen a cut. It is now a quarter of the **timeline** — 160 ms, ten
frames at 60 Hz and nineteen at 120 Hz.

### Added
- **`StrokeTaper.unSmooth(y)`** — inverse of the Hermite smoothstep, which is
  what converts a point in progress space back into the window's real time.
- **`StrokeTaper.dissolve(t, end, span)`** — the fade in timeline units. The
  morph feeds it the dot horizon mapped through `unSmooth`, so the dissolve both
  lasts a real duration and finishes before the ink could become a dot.

### Changed
- `IconMorphPlan.exitFade` (still `0.75`) now means *the dissolve spans the last
  quarter of the animation*, not of the exit's progress.
- The trim exit window widens from `0.35` to `0.45` of the timeline, so the
  un-draw reads at full ink for ~60 ms before the dissolve starts instead of the
  two overlapping into one hurried beat. The ink is still gone by t ≈ 0.35, well
  before the target assembles at `flipStart` 0.55.
- `StrokeTaper.exitAlpha` (progress space) is kept for callers that have no
  timeline, but the morph no longer uses it.

## 1.4.0

**The dissolve is anchored to the geometry, not to the clock.** 1.3.0 faded a
leaving contour's alpha over the last quarter of its exit, ending when its length
ended — which still showed the dot. A stroke becomes a round-cap dot a good
stretch *before* its length reaches zero (at 2 stroke-widths of remaining
length), and a clock-timed fade was still at 30–70% alpha there. So the dot was
visible, then cut. The fade now **finishes at the dot horizon** and nothing is
drawn past it: a trim-out has no dot frame at all, by construction.

### Added
- **`StrokeTaper.dotHorizon(fullLength, [strokeWidth])`** — the exit progress at
  which a retracting contour stops reading as a line. Capped at half a contour's
  length, so a hair-length authored dot (a keyhole) fades over its own second
  half instead of being deleted on frame one.
- **`StrokeTaper.exitAlpha(prog, fadeStart, fullLength, [strokeWidth])`** — the
  dissolve that ends there. The requested span (`1 - fadeStart`, e.g. the last
  quarter) is honoured but slid earlier, per contour, by its own length.
- `StrokeTaper.kDotWidths` (2) — how many stroke-widths of length a stroke needs
  to still read as a line.

### Changed
- `MorphExit.trim` uses `exitAlpha`. `IconMorphPlan.exitFade` keeps its name and
  `0.75` default but now means *the dissolve spans the last quarter*, not *it
  starts at 0.75*.
- `StrokeTaper.fade` (the clock-anchored version) is retained for custom effects
  that have no geometry to anchor to.

## 1.3.0

**Weight is never modulated; the exit vanishes by alpha.** Thinning ink is
per-contour, and a staggered exit therefore paints neighbouring contours at
different weights — the glyph stops reading as one balanced drawing. So the
taper is off by default and an alpha dissolve over the last quarter of the exit
is the whole vanish. It also solves the terminal dot properly: a round-capped
stroke shorter than its own width *is* a dot, and no length curve can hide that,
but a transparent one is simply not there.

### Changed
- **`IconMorphPlan.taperFloor` now defaults to `1`** — stroke weight untouched at
  both ends. `exitTaper` / `assembleTaper` remain, inert until the floor is
  lowered.
- **`StrokeTaper.kFloor` is `1`**, and the new `StrokeTaper.exitWeight` /
  `entryWeight` fold in the rule that a floor of 1 bypasses the taper *and* the
  no-dot clamp together. There is no middle setting where weight is modulated
  only for degenerate geometry.
- `IconTrimDraw` and `IconDetailSpin` are back to constant weight (1.1.0 had put
  the no-dot clamp on them; same balance argument applies).
- `IconMorphPlan.exitFade` (`0.75`) is now the documented vanish, not a finisher
  for the taper.

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
