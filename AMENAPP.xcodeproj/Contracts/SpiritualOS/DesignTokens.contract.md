# Spiritual OS Design Tokens Contract

Status: FROZEN for Phase 1 and Phase 2. Agents may consume this contract but may not change it without Lead approval and re-freeze.

## Reference

Apple SwiftUI Liquid Glass APIs are the reference for iOS 26 chrome: `glassEffect(_:in:)`, `Glass`, `GlassEffectContainer`, `glassEffectID(_:in:)`, `glassEffectTransition(_:)`, and `glassEffectUnion(id:namespace:)`. Standard controls may use `.buttonStyle(.glass)` or `.buttonStyle(.glass(_:)`) when they remain visually consistent with this contract.

## Brand Colors

| Token | SwiftUI Name | Purpose | Usage Boundary |
| --- | --- | --- | --- |
| Amen Gold | `Color.amenGold` | Warm spiritual accent, prayer affordances, candlelight highlights | Accent only; never body text on glass |
| Amen Purple | `Color.amenPurple` | Berean intelligence, assistant actions, study prompts | Controls and assistant chrome |
| Amen Blue | `Color.amenBlue` | Calendar, context, live status, travel and event hints | Secondary accent and status |
| Amen Black | `Color.amenBlack` | Primary text and deep scrim color | Matte content foreground or image scrim |
| Amen Cream | `Color.amenCream` | Matte reading surfaces and page background | Scripture, long-form text, forms |
| Amen Slate | `Color.amenSlate` | Secondary text and muted metadata | Metadata, captions, subdued controls |

## Core Rule

Content is matte, chrome is glass.

Scripture, prayer request bodies, notes, generated answers, message text, calendar descriptions, and form inputs render on matte backgrounds. Controls, bars, chips, cards, sheets, navigation, and assistant entry points may use Liquid Glass.

## Canonical Treatments

| Treatment | SwiftUI Primitive | Shape | Use For | Constraints |
| --- | --- | --- | --- | --- |
| Standard Card Glass | `GlassCard` | Rounded rectangle, medium radius | Hub rows, digest modules, planner suggestions | No nested card inside card |
| Elevated Hero Glass | `HeroCard` | Large rounded rectangle | Space dashboard hero surfaces | May sit over cover media with text scrim |
| Bar Glass | `GlassBar` | Full-width or capsule based on placement | Assistant bar, tab-attached controls, top/bottom chrome | Avoid more than one persistent bar per edge |
| Sheet Glass | `GlassSheet` | Bottom sheet container | Create Space, curation, settings, review flows | Header/footer chrome only; body matte |
| Chip Glass | `GlassChip` | Capsule | Tags, actions, quick prompts, filters | Labels must remain short and scannable |
| Morphing Glass | `GlassEffectContainer` + IDs | Matched shapes | Assistant suggestions, context mode transitions | Use sparingly for performance |

## Liquid Glass Performance Rules

Use `GlassEffectContainer` when multiple glass controls appear together. Limit simultaneous Liquid Glass elements in scroll-heavy views. Prefer matte rows with glass controls rather than glass-on-glass stacks. Respect Reduce Transparency with system backgrounds and Reduce Motion through `Motion.adaptive`.

## Motion

All Spiritual OS animation uses `Motion.adaptive(...)` or an existing repo wrapper that delegates to it. Springs are allowed for chrome and control state. Reading content, scripture surfaces, and sensitive safety prompts use low-motion fades or no animation.

## Faith Formation UI Rules

No public vanity metrics. No infinite scroll. Any streak or formation count is private, opt-in, gentle, and never comparative. Screens orient and invite; they do not use urgency, guilt, engagement bait, or competitive ranking.
