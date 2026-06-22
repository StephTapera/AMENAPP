# FROZEN - Shared Components Contract - Spiritual OS
> Version 1.3 - 2026-06-11 - Lead Orchestrator
> FROZEN. Implementations live in `AMENAPP/AMENAPP/AMENAPP/SpiritualOS/SharedComponents/SOSharedComponents.swift`.
> Surface enum and context mode: `AMENAPP/AMENAPP/AMENAPP/SpiritualOS/SOSurface.swift`
> Color tokens: `AMENAPP/AMENAPP/AMENAPP/SpiritualOS/SOColors.swift`
> Agents use ONLY these 8 components. No new glass primitives. Escalate API gaps to Lead.

---

## Existing GlassKit Binding

`SOSharedComponents.swift` is a facade over the existing app GlassKit/LiquidGlass layer, not a new component library. Implementations must extend, wrap, or alias existing primitives such as `LiquidGlassCard`, `livingGlassMaterial`, `AmenLiquidGlassComponents`, `CommunicationOSGlassKit`, and related `GlassEffectContainer` helpers. Agents may not define new glass materials, duplicate token systems, or create parallel card/bar/chip implementations outside this facade.

---

## Component Inventory

1. `GlassCard` — navigational glass content card
2. `GlassBar` — full-width or floating glass bar
3. `GlassSheet` — modal bottom sheet with glass header + matte body
4. `GlassChip` — tag / filter / role badge pill
5. `HeroCard` — Space/community featured card with cover + action row
6. `TimelineRow` — single row in a timeline list (planner, digest, hub)
7. `AssistantBar` — persistent/embeddable Berean prompt bar
8. `MemberAvatarRow` — overlapping avatar stack with overflow count

---

## 1. GlassCard

```swift
struct GlassCard<Content: View>: View {
    var tint: Color? = nil
    var elevated: Bool = false
    var isPressed: Bool = false
    var scrollDepth: CGFloat = 0
    @ViewBuilder var content: () -> Content
}
```

- `isContentCard: true` → renders amenCream/amenCharcoal matte, no ultraThinMaterial
- Never nest GlassCard inside GlassCard (glass-on-glass forbidden)

---

## 2. GlassBar

```swift
enum GlassBarPlacement { case bottom, top, floating }

struct GlassBar<Content: View>: View {
    var placement: GlassBarPlacement = .bottom
    var tint: Color? = nil
    @ViewBuilder var content: () -> Content
}
```

---

## 3. GlassSheet

```swift
struct GlassSheet<Content: View>: View {
    var title: String
    var tint: Color? = nil
    var showDismissButton: Bool = true
    var onDismiss: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content
}
```

- Header area: GlassBar treatment with drag handle
- Body area: matte (amenCream / amenCharcoal)

---

## 4. GlassChip

```swift
enum GlassChipSize { case compact, regular, large }

struct GlassChip: View {
    var label: String
    var icon: String? = nil
    var tint: Color? = nil
    var size: GlassChipSize = .regular
    var isActive: Bool = false
    var action: (() -> Void)? = nil
}
```

Predefined faith-native tag labels: "Prayer", "Testimony", "Church", "Community", "Mention", "Berean", "Event"

---

## 5. HeroCard

```swift
struct HeroCard: View {
    var title: String
    var subtitle: String? = nil
    var coverImageURL: URL? = nil
    var tint: Color
    var memberAvatars: [URL]
    var memberCount: Int
    var nextEvent: HeroCardEvent? = nil
    var actions: [HeroCardAction]
    var onTap: () -> Void
}

struct HeroCardEvent { let title: String; let date: Date; let icon: String }
struct HeroCardAction { let label: String; let icon: String; let action: () -> Void }
```

Standard Space actions:
```
pray:     "hands.sparkles"       "Pray Together"
schedule: "calendar.badge.plus"  "Schedule"
notes:    "doc.text"             "Open Notes"
berean:   "sparkles"             "Ask Berean"
```

- Primary content region renders on matte scrim overlay — NOT glass
- Action row at bottom: GlassBar treatment
- activePrayerCount: prayer icon badge only, NOT labeled as social metric

---

## 6. TimelineRow

```swift
enum TimelineRowBadge { case tag(String, Color), count(Int), dot(Color) }

struct TimelineRow: View {
    var icon: String
    var iconTint: Color = .accentColor
    var title: String
    var subtitle: String? = nil
    var timestamp: Date? = nil
    var badge: TimelineRowBadge? = nil
    var isCompleted: Bool = false
    var onTap: (() -> Void)? = nil
}
```

- Completed items: 50% opacity, strikethrough on title
- Renders on matte background parent — NOT on glass directly

---

## 7. AssistantBar

```swift
struct AssistantBar: View {
    var placeholder: String
    var contextSurface: SOSurface
    var onSubmit: (String) -> Void
    var onCamera: () -> Void
    var onVoice: () -> Void
    var quickPrompts: [String]
}
```

- Renders inside GlassBar container (floats above content + tab bar)
- All AI calls → getAssistantResponse CF only. No client-side model calls.
- Quick prompts injected by each surface's ViewModel; AssistantBar is stateless

---

## 8. MemberAvatarRow

```swift
struct MemberAvatarRow: View {
    var avatarURLs: [URL]
    var memberCount: Int
    var size: CGFloat = 32
    var overlap: CGFloat = 10
    var borderColor: Color = .white
}
```

- Overlap offset: -(size * 0.3)
- Overflow "+N" styled as GlassChip .small
- Avatars clipped to circle, 1.5pt white ring border
- Falls back to "person.fill" SF Symbol on load failure

---

## Actual Implementation Files (Lead only)
All 8 components fully implemented:
- `AMENAPP/AMENAPP/SpiritualOS/SharedComponents/SOSharedComponents.swift` — all 8 component bodies
- `AMENAPP/AMENAPP/SpiritualOS/SOSurface.swift` — `SOSurface` + `SOContextMode` enums
- `AMENAPP/AMENAPP/SpiritualOS/SOColors.swift` — color token extensions

The signatures above are the frozen Swift signatures. Agents must use these exact APIs unless the Lead re-freezes this contract.
