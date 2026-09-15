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

For a control that changes STATE between two unrelated glyphs, `IconicBlurSwap(icon)`
plays a blur cross-dissolve when `icon` changes — the old glyph loses focus and
slips away as the new one sharpens and springs in over the same centre
(copy → check, play → pause). Neither a morph (no meaningless in-between shape)
nor a cross-fade (no two ghosts). `BlurSwapFrame` exposes its timing law for
hosts that paint their own glyphs.

Compose them with `IconSequence([IconStep(...), …])`. Drive playback with an
`IconicAnimatedIconController`, or declare per-icon defaults via `IconAnimations`
+ `IconAnimationProfile`. For multi-state morphs use `IconicMorphHero` /
`IconicMorphSequence([a, b, c])`.

All effects honour the OS reduce-motion setting (`IconMotion.reduced`) by
snapping to their end state.

## Two morphs: strangers fly, siblings become

`IconicMorph` is the **worm** — for icons that share nothing. One real line of
the source becomes a travelling worm (head launching along its own tangent, a
tail catching up over a smooth flight), while the rest of the target draws
itself on.

`IconicShapeMorph` is the **shape morph** — for icons that are siblings. Any
contour present in both icons is detected automatically and held perfectly
still; the differing features are paired and point-lerped so a line physically
bends from one shape into the other; anything unpaired pen-retracts out or
draws on. Ink lerps with the geometry — the morphing shapes and the still
chrome each take a begin → end colour on the same eased clock.

```dart
// Auto: shared chrome stands still, closest features become each other.
IconicShapeMorph('assets/icons/face-id.svg', 'assets/icons/face-id-check.svg')

// Authored choreography + verdict colours:
IconicShapeMorph(
  'assets/icons/face-id.svg', 'assets/icons/face-id-alert.svg',
  spec: const ShapeMorphSpec(pairs: [
    (Offset(12, 10.5), Offset(12, 10)), // the nose becomes the "!" stem
    (Offset(11, 16.3), Offset(12, 16)), // the smile becomes its dot
  ]),
  color: Color(0xFF0095E8), colorEnd: Color(0xFFDC2626), // mark → red
  chromeColorEnd: Color(0xFF6E737D), // frame → secondary ink
)
```

For a morph living inside a larger stateful glyph (several destinations,
bespoke rest states), build a `ShapeMorphGeometry` per transition and drive a
`ShapeMorphPainter` with your own controller.

## Easing by feel

The whole engine takes its velocity profiles from `IconicEase` — four curated
profiles, named by feel, and every knob accepts any `Curve` of your own. As of
1.9.0 the vocabulary is total: every effect default speaks one of these names,
so nothing in the library moves on an unnamed curve.

| Profile | What it is | Feels like |
| --- | --- | --- |
| `IconicEase.glide` | symmetric ease-in-out | calm — a passive change nobody triggered |
| `IconicEase.arrive` | deceleration-only ease-out | triggered detail — already moving at frame one, all settle |
| `IconicEase.flight` | fast-launch ease-out | the worm's signature — leaves decisively, lands gently |
| `IconicEase.snap` | critically-damped spring | platform-native — responds on the first frame, settles on an exponential tail |

`snap` is an `IconicSpringCurve(omega, velocity)` — a real spring solution as
a plain `Curve`, with genuine non-zero launch velocity (what cubics can't
give you). Keep `velocity < omega` and it is strictly monotone: no overshoot,
the right law for stroke geometry.

```dart
// The worm on a spring launch instead of its cubic:
IconicMorph(a, b, plan: const IconMorphPlan(curve: IconicEase.snap))

// A calm shape morph whose INK announces the verdict early:
IconicShapeMorph(a, b, spec: const ShapeMorphSpec(
  curve: IconicEase.glide, colorCurve: Curves.easeOutCubic))
```

Defaults: the worm rides `flight` (unchanged since 1.0), the shape morph rides
`snap` at `IconMotion.shapeMorph` (460 ms).

## Ink that lifts away (how a trim-path ends)

A trim-path that animates *length* alone cannot vanish cleanly — a round-capped
stroke shorter than its own width **is** a dot, so an un-draw ends on a
fixed-size dot and then blinks out. The fix is an **alpha dissolve**: the ink
retracts at its true weight, then fades. A transparent dot is simply not there.

A trim has **two** ends and both fade: a draw-on that arrives at full opacity on
its first frame pops into existence and only then draws, which is the same hard
edge in reverse.

```dart
IconicMorph(MorphIcons.user, MorphIcons.face,
  plan: const IconMorphPlan(
    exitFade: 0.75,     // dissolve spans the last quarter of the timeline (1 = off)
    assembleFade: 0.35, // fade in over the first third of each draw (0 = off)
  ));
```

Two timing details matter, and both are easy to get wrong:

- **Where it ends.** At each contour's *dot horizon* — the moment its shrinking
  ink would stop reading as a line (`StrokeTaper.dotHorizon`) — and nothing is
  drawn after that. A fade merely timed to the end of the exit still shows the
  dot at 30–70% alpha, because a stroke becomes one well before its length hits
  zero.
- **How long it lasts.** `exitFade` is a fraction of the **timeline**, not of the
  exit's progress. Exit progress is smoothstepped, so "a quarter of the progress"
  lands where the smoothstep moves fastest and can be over in 43 ms — under three
  frames. A quarter of the timeline is 160 ms.

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
