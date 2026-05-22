# AMEN Living Hero System Audit

## Product Definition
The Amen Living Hero System is an app-wide Ambient Spatial Motion Hero / Living Editorial Banner framework for AMEN. It adapts Apple-style editorial motion cards to AMEN's white-background, black-text, Liquid Glass, spiritual, accessibility-first design language.

The system is not an advertising carousel, autoplay video surface, or decorative animation layer. It is a governed contextual surface that presents scripture, reflection, community rhythm, church moments, discovery context, and worship/event momentum with calm spatial depth and static fallbacks.

## Naming
System name: Amen Living Hero System.

Core components:
- AmenLivingHeroView
- AmenLivingHeroCard
- AmenLivingHeroScene
- AmenLivingHeroMotionEngine
- AmenLivingHeroContentResolver
- AmenLivingHeroTelemetry
- AmenLivingHeroReduceMotionFallback

Preferred product language:
- Living Hero
- Living Daily Verse
- Today's Reflection
- Scripture Focus
- Community Rhythm
- Featured Teaching
- Current Church Moment

Disallowed language:
- Spirit-led by AI
- God told you
- Divine recommendation
- Prophetic AI
- AI discerned God's will

## Surface Map

### GO
Daily Verse Banner: GO. First pilot. Keep Classic mode intact and add Living mode as optional or Automatic. Content source is the existing daily verse data.

Amen Daily Digest: GO. Strong fit for weather, Christian calendar, holidays, verse reflection, and action routing. Use as a calm daily context hero.

Selah: GO. Strong spiritual fit. Use subtle scripture and reflection depth. Keep reading text static and high contrast.

Amen Discover / Explore: GO. Strong editorial fit. Use for featured churches, teachings, topics, Selah moments, and discovery transparency.

Church Profile / Church Discovery: GO. Use as a church identity hero for current series, services, worship nights, location, and first-visit context.

Berean Pulse: GO. Already uses contextual signals and glass surfaces. Add a living header only when safe and contextual.

Creator Kit Home: GO. Use to orient creation tools and approved AI-assisted workflows. Keep action buttons static.

Live Events / Worship Experiences: GO. Strong cinematic fit for countdowns, worship nights, sermon live, and event context.

### GO WITH CAVEATS
Home Feed: Caveat. High impact but must not feel like ads or repeat between posts. Ship only after first-wave surfaces prove stable.

Media Detail Views: Caveat. Motion must never compete with playback. Fade or freeze while media is playing.

Prayer Rooms: Caveat. Users may be vulnerable. Motion must be minimal, optional, and static by default under accessibility or safety states.

Berean AI / AI Companion: Caveat. Good for study context but must not imply divine authority or mystical AI confidence.

Creator Profiles: Caveat. Good for identity and featured teaching, but avoid busy profile headers.

Organization Hubs / School / Church / Enterprise Spaces: Caveat. Require admin controls, brand governance, and safe default themes.

Community Discussions: Caveat. Use only as a topic context banner. Never animate active conversation text.

Onboarding: Caveat. Useful for first impression, but must not slow sign-up, auth, permissions, or comprehension.

Seasonal / Holiday / Church Event Surfaces: Caveat. Strong contextual value, but require content governance and theological review.

### NO-GO For Full Hero
Messaging: No full hero. Use micro context pills only.

Notifications: No full hero. Preserve scan speed and clarity.

Active Search: No full hero while typing or viewing results. Empty discovery state only.

Media Upload / Composer Flows: No full hero. Preserve focus, disclosure, moderation, and review clarity.

Admin / Moderation / Analytics Consoles: No full hero. Operational density wins.

Access Pass Admin / Request Inbox: No full hero. Static status banners only.

## Rollout Order
1. Daily Verse Banner Living mode
2. Amen Daily Digest
3. Selah
4. Amen Discover
5. Church Profile / Church Discovery
6. Berean Pulse
7. Creator Kit Home
8. Live Events / Worship
9. Home Feed only after proven stable

## Feature Flags
Master flags:
- ambientSpatialHeroEnabled
- livingEditorialBannerEnabled
- spatialHeroReduceMotionFallbackEnabled
- spatialHeroPerformanceTelemetryEnabled

Surface flags:
- dailyVerseLivingHeroEnabled
- dailyDigestLivingHeroEnabled
- discoverLivingHeroEnabled
- selahLivingHeroEnabled
- bereanPulseLivingHeroEnabled
- churchProfileLivingHeroEnabled
- liveEventLivingHeroEnabled
- creatorKitLivingHeroEnabled

Default rollout policy:
- First-wave GO surfaces may be enabled locally and remotely gated.
- GO WITH CAVEATS surfaces remain off until separately audited.
- NO-GO surfaces must not receive full hero integrations.

## Accessibility Rules
- Respect Reduce Motion by rendering AmenLivingHeroReduceMotionFallback.
- Respect Reduce Transparency by using opaque white cards, strokes, and static symbols instead of blur-heavy glass.
- Respect Increase Contrast by increasing text contrast and reducing decorative opacity.
- VoiceOver reads a single grouped label with title, subtitle, context, and actions.
- Decorative floating layers are accessibilityHidden(true).
- Dynamic Type must not clip verse, heading, button, or disclosure text.
- Primary text never animates, rotates, blurs, or parallax-shifts independently.
- User choice must support Classic, Living, and Automatic where applicable.

## Performance Limits
- No unbounded CADisplayLink or runaway timers.
- No full-screen GPU-heavy effects for list surfaces.
- Pause or simplify motion when offscreen.
- Disable motion in Low Power Mode.
- Reduce motion during fast scroll or scroll stress.
- Limit simultaneous Liquid Glass effects onscreen.
- Prefer SwiftUI animation state changes over per-frame rendering.
- Use static fallback during loading, errors, empty content, low power, Reduce Motion, and Reduce Transparency.

## Motion Rules
Allowed:
- slow spatial drift
- floating icon clusters
- subtle parallax
- gentle scale
- spring settling
- layered blur
- low-frequency light response
- contextual transitions

Not allowed:
- aggressive motion
- autoplay video
- GIF-like loops
- moving readable text
- glass-on-glass stacking
- animation that obscures labels or buttons
- repeated in-feed hero spam
- mystical or fake-intelligent presentation

## Safety, Theology, And Content Governance
The hero must never claim divine authority, personal prophecy, or AI spiritual certainty. It may suggest, summarize, or feature human/community/scripture-grounded context.

Approved language:
- Suggested
- Today's reflection
- Community rhythm
- Scripture focus
- Featured teaching
- Current church moment
- Continue reflection

Content sources must be traceable to existing app data: daily verse, digest, church profile, events, discover items, Selah state, Berean Pulse cards, or Creator Kit actions. Do not fabricate production content.

## QA Checklist
- Xcode build succeeds.
- Feature flags compile and Remote Config keys map correctly.
- Daily Verse Classic mode remains available.
- Reduce Motion renders static fallback.
- Reduce Transparency renders opaque fallback.
- VoiceOver reads meaningful grouped labels.
- Dynamic Type does not clip.
- Low Power Mode disables motion.
- Empty/loading/error states show static fallback.
- NO-GO surfaces contain no full hero.
- No placeholder production content.
- No broken buttons or blocked routing.

## Implementation Plan
1. Create this audit document.
2. Add shared SwiftUI system files under AIIntelligence/LivingHero.
3. Add feature flags to AMENFeatureFlags with Remote Config keys.
4. Implement a content resolver with real per-surface contexts and static fallbacks.
5. Wire only first-wave GO surfaces where the insertion point is safe.
6. Keep Daily Verse Classic mode unchanged and add Living as optional.
7. Add telemetry hooks without forcing analytics dependency into rendering logic.
8. Validate diagnostics and build.
9. Keep GO WITH CAVEATS and NO-GO surfaces documented but unwired.

## Production Readiness Verdict
GO WITH CAVEATS.

Proceed only through feature flags, static fallbacks, accessibility safeguards, and a phased rollout. Daily Verse and Daily Digest are the safest first surfaces. Home Feed should wait until the system proves stable elsewhere.
