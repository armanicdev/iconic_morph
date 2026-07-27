/// # iconic_morph
///
/// Path-level icon animation for Flutter — morph one SVG icon into another, plus
/// 3D constant-stroke spins, draw-on, trace, and idle loops — drawn from your own
/// SVGs. **No Rive, no Lottie, no new assets, and ZERO external dependencies**
/// (the SVG path parser and the 4×4 matrix math are vendored in-tree).
///
/// ```dart
/// import 'package:iconic_morph/iconic_morph.dart';
///
/// // Morph the bundled demo icons (works out of the box):
/// IconicMorph(MorphIcons.user, MorphIcons.face);
///
/// // Or bring your own SVG — an asset path or a raw string:
/// IconicMorph.svg(myUserSvg, myFaceSvg);
///
/// // A single icon, animated (3D unlock spin):
/// IconicAnimatedIcon(MorphIcons.lock, effect: const IconSpin3D.unlock());
/// ```
library;

// Core geometry + the constant-stroke 3D projector.
export 'src/icon_geometry.dart'
    show IconGeometry, IconContour, IconGeometryResolver;
export 'src/projection_3d.dart' show Projector3D, Spin3DAxis;

// Effect framework + the static-icon primitive + motion tokens.
export 'src/icon_effect.dart'
    show
        IconEffect,
        IconEffectPainter,
        IconStep,
        IconSequence,
        tintStroke,
        appendContourUpTo,
        kIconStrokeWidth;
export 'src/stroke_taper.dart' show StrokeTaper;
export 'src/icon_image.dart' show IconImage;
export 'src/motion.dart' show IconMotion;
export 'src/morph_icons.dart' show MorphIcons;

// Declarative per-icon profiles + the animated-icon widget.
export 'src/icon_animation_profile.dart'
    show IconAnimationProfile, IconAnimations;
export 'src/animated_icon.dart'
    show IconicAnimatedIcon, IconicAnimatedIconController;

// The effect catalog.
export 'src/effects/icon_spin3d.dart' show IconSpin3D;
export 'src/effects/icon_trim_draw.dart' show IconTrimDraw;
export 'src/effects/icon_breathe.dart' show IconBreathe;
export 'src/effects/icon_blink.dart' show IconBlink;
export 'src/effects/icon_trace.dart' show IconTrace;
export 'src/effects/icon_converge.dart' show IconConverge;
export 'src/effects/icon_weight_pulse.dart' show IconWeightPulse;
export 'src/effects/icon_detail_spin.dart' show IconDetailSpin;
export 'src/effects/icon_grid_pop.dart' show IconGridPop;
export 'src/effects/icon_line_shrink.dart' show IconLineShrink;
export 'src/effects/icon_shuffle.dart' show IconShuffle;
export 'src/effects/icon_inbox_riffle.dart' show IconInboxRiffle;
export 'src/effects/icon_lock_engage.dart' show IconLockEngage;

// The cross-icon morph.
export 'src/morph/morph_plan.dart'
    show IconMorphPlan, MorphAssemble, MorphExit;
export 'src/morph/morph_geometry.dart' show MorphGeometry;
export 'src/morph/path_morph.dart' show PathMorph;
export 'src/morph/icon_morph.dart' show IconicMorph, IconicMorphPainter;
export 'src/morph/morph_hero.dart' show IconicMorphHero;
export 'src/morph/morph_sequence.dart' show IconicMorphSequence;
