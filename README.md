# iconic_morph

**Path-level icon animation for Flutter** — morph one SVG icon into another, plus
3D constant-stroke spins, draw-on, trace, and idle loops, all drawn from your own
SVGs.

- 🪶 **Zero dependencies.** The SVG path parser and the 4×4 matrix math are
  vendored in-tree. `flutter pub get` pulls in nothing beyond the Flutter SDK —
  no Rive, no Lottie, no `flutter_svg`.
- ✏️ **Real geometry, not frames.** Effects animate the icon's actual path
  (centerlines, arc-length), so a spin stays a crisp constant-width stroke
  edge-on instead of a thinning bitmap.
- 🎯 **Bring your own icons.** An asset path, a raw SVG string, or a baked
  manifest. Three demo glyphs are bundled so it runs out of the box.

> By [Armanic Studio](https://pub.dev/publishers/armanic.studio).

## Install

```yaml
dependencies:
  iconic_morph: ^1.0.0
```

```dart
import 'package:iconic_morph/iconic_morph.dart';
```

## Quick start

```dart
// Morph the bundled demo glyphs (works out of the box):
IconicMorph(MorphIcons.user, MorphIcons.face);

// A single icon, animated — a 3D unlock spin:
IconicAnimatedIcon(MorphIcons.lock, effect: const IconSpin3D.unlock());

// A static icon (no animation), stroked from its SVG path:
IconImage.asset(MorphIcons.user, size: 32);
```

Colour follows the ambient `DefaultTextStyle` (like `currentColor`) unless you
pass `color:`. So wrap your app in a `DefaultTextStyle`, or set it per-widget.

### Bring your own SVG

```dart
// From your own asset path (declare it under `flutter: assets:` as usual):
IconicMorph('assets/icons/menu.svg', 'assets/icons/close.svg');

// Or straight from a raw SVG string — no asset needed:
IconicMorph.svg(menuSvgString, closeSvgString);
IconImage.svg('<svg viewBox="0 0 24 24">…</svg>', color: Colors.indigo);
```

## The effect catalog

`IconicAnimatedIcon(asset, effect: …)` takes any of:

| Effect | What it does |
| --- | --- |
| `IconSpin3D` / `.unlock()` / `.flipIn()` | constant-stroke 3D spin / unlock / flip-in |
| `IconTrimDraw` | pen draws the glyph on |
| `IconTrace` | a glow pulse runs along the centerline |
| `IconBreathe` | gentle idle scale loop |
| `IconBlink` | idle blink |
| `IconConverge` | strokes assemble into place |
| `IconWeightPulse` | stroke-weight emphasis pulse |
| `IconDetailSpin` / `IconGridPop` / `IconLineShrink` / `IconShuffle` / `IconInboxRiffle` / `IconLockEngage` | misc. one-shots (press knocks, a riffle, a lock engage) |

Compose them with `IconSequence([IconStep(...), …])`. Drive playback with an
`IconicAnimatedIconController`, or declare per-icon defaults via `IconAnimations`
+ `IconAnimationProfile`. For multi-state morphs use `IconicMorphHero` /
`IconicMorphSequence([a, b, c])`.

All effects honour the OS reduce-motion setting (`IconMotion.reduced`) by
snapping to their end state.

## Ink that lifts away (how a trim-path ends)

A trim-path that animates *length* alone cannot vanish cleanly — a round-capped
stroke shorter than its own width **is** a dot, so an un-draw ends on a
fixed-size dot and then blinks out. The fix is an **alpha dissolve over the end
of the exit**: the ink retracts at its true weight, then fades. A transparent dot
is simply not there.

```dart
IconicMorph(MorphIcons.user, MorphIcons.face,
  plan: const IconMorphPlan(
    exitFade: 0.75,  // dissolve over the last quarter of the exit (1 = off)
  ));
```

**Why not thin the stroke instead?** Weight modulation is per-contour, and a
staggered exit paints neighbours at different weights, so the glyph stops reading
as one balanced drawing. The taper exists (`taperFloor`, `exitTaper`,
`assembleTaper` — a pen lift and a nib press-down, plus a no-dot clamp) but is
**off by default**; lower `taperFloor` below 1 to opt in.

`StrokeTaper` is exported, so custom effects get the same law — note that
`weighted()` returns **`null`** when the ink is gone, which means *draw nothing*
(`strokeWidth = 0` is Skia's hairline mode, not invisibility).

## Skip runtime SVG parsing (bake a manifest)

For production, parse your SVGs **once at build time** into a small JSON manifest
and ship that instead of the SVGs:

```bash
dart run iconic_morph:bake assets/icons assets/icons.json
```

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  IconGeometry.useManifest('assets/icons.json'); // before any icon paints
  runApp(const MyApp());
}
```

Now every `IconicMorph` / `IconicAnimatedIcon` / `IconImage` reads geometry from
the manifest — no runtime XML parse, and you don't have to bundle the raw SVGs.
For full control, set `IconGeometry.resolver` yourself.

## Supported SVGs

The parser is intentionally small. It reads **flat `<path>` elements** with a
**0-origin, square `viewBox`** (e.g. `viewBox="0 0 24 24"`) — the shape of a
typical icon export. It does **not** flatten `<g transform>`, `<rect>`/`<circle>`
primitives, or `<style>` blocks. Stroke-vs-fill is detected from the `stroke` /
`fill` attributes. Flatten such SVGs to `<path>`s first (most icon tools can).

## License

[MIT](LICENSE) © Armanic Studio. The SVG path reader (`lib/src/svg/svg_path.dart`)
derives from Dan Field's `path_parsing` (MIT, see `THIRD_PARTY_NOTICES.md`).
