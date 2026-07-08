import 'package:flutter/widgets.dart';

import 'icon_effect.dart';
import 'morph/morph_plan.dart';

/// A declarative animation profile for ONE icon — how it **introduces** itself,
/// how it **idles** at rest, and the plan other glyphs use to **morph into** it.
///
/// Pure, immutable data. Bind it to an icon once in [IconAnimations] and every
/// animated-icon widget (`IconicMorphHero`, `IconicMorphSequence`) can resolve the right
/// behaviour for that glyph without bespoke per-screen wiring — the icon carries
/// its own animation identity. Leave a field null to mean "no intro / still idle"
/// and the widgets fall back to their own defaults.
@immutable
class IconAnimationProfile {
  const IconAnimationProfile({
    this.intro,
    this.idle,
    this.morphInto = const IconMorphPlan(),
  });

  /// Effect for the FIRST appearance (e.g. a draw-on, a 3D tumble). Null = appear
  /// straight into idle/still.
  final IconEffect? intro;

  /// Looping "alive" effect at rest (e.g. a subtle tilt, a blink). Null = still.
  final IconEffect? idle;

  /// The [IconMorphPlan] used when another glyph morphs INTO this icon — anchors
  /// and flight tuned for this destination (e.g. a `heroAnchor` on a smile so a
  /// line lands on the mouth). Defaults to a plain plan.
  final IconMorphPlan morphInto;

  IconAnimationProfile copyWith({
    IconEffect? intro,
    IconEffect? idle,
    IconMorphPlan? morphInto,
  }) =>
      IconAnimationProfile(
        intro: intro ?? this.intro,
        idle: idle ?? this.idle,
        morphInto: morphInto ?? this.morphInto,
      );
}

/// The central, declarative registry binding icons → [IconAnimationProfile].
///
/// Register an icon's animation identity once (typically at app start) and any
/// animated-icon widget resolves intro/idle/morph for it automatically:
/// ```dart
/// IconAnimations.registerAll({
///   MorphIcons.face: const IconAnimationProfile(
///     idle: IconBlink(),
///     morphInto: IconMorphPlan(heroAnchor: Offset(12, 16)),
///   ),
///   MorphIcons.lock: const IconAnimationProfile(intro: IconSpin3D.unlock()),
/// });
/// ```
/// This is what makes the engine *scalable*: applying a polished idle/morph to a
/// new glyph is a one-line registration, not a new widget. Unregistered icons
/// resolve to [fallback] (a plain, still profile by default — override it to give
/// every glyph a baseline idle).
class IconAnimations {
  IconAnimations._();

  static final Map<String, IconAnimationProfile> _profiles = {};

  /// Profile returned for any unregistered icon. Override to set an app-wide
  /// baseline (e.g. a shared subtle idle on every glyph).
  static IconAnimationProfile fallback = const IconAnimationProfile();

  /// Bind one icon to a profile (overwrites any existing).
  static void register(String icon, IconAnimationProfile profile) =>
      _profiles[icon] = profile;

  /// Bind many at once — the idiomatic "configure at app start" call.
  static void registerAll(Map<String, IconAnimationProfile> profiles) =>
      _profiles.addAll(profiles);

  /// Clear all registrations (mainly for tests).
  static void reset() => _profiles.clear();

  /// Whether [icon] has an explicit profile.
  static bool has(String icon) => _profiles.containsKey(icon);

  /// The profile for [icon], or [fallback] if none is registered.
  static IconAnimationProfile of(String icon) => _profiles[icon] ?? fallback;

  /// Convenience resolvers used by the widgets.
  static IconEffect? idleFor(String icon) => of(icon).idle;
  static IconEffect? introFor(String icon) => of(icon).intro;
  static IconMorphPlan planFor(String icon) => of(icon).morphInto;
}
