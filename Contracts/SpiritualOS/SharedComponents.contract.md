# FROZEN — Shared Components Contract · Spiritual OS
> Version 1.1 · 2026-06-02 · Lead Orchestrator (updated to match existing implementations)
> ⚠️ FROZEN. Implementations live in `AMENAPP/AMENAPP/SpiritualOS/SharedComponents/SOSharedComponents.swift`.
> Surface enum and context mode: `AMENAPP/AMENAPP/SpiritualOS/SOSurface.swift`
> Color tokens: `AMENAPP/AMENAPP/SpiritualOS/SOColors.swift`
> Agents use ONLY these 8 components. No new glass primitives. Escalate API gaps to Lead.

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
    var cornerRadius: CGFloat = 20
    var padding: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
    var shadowOpacity: Double = 0.08
    /// true = devotional/scripture content inside → renders matte, NOT glass
    var isContentCard: Bool = false
    @ViewBuilder var content: () -> Content
}
```

- `isContentCard: true` → renders amenCream/amenCharcoal matte, no ultraThinMaterial
- Never nest GlassCard inside GlassCard (glass-on-glass forbidden)

---

## 2. GlassBar

```swift
struct GlassBar<Content: View>: View {
    /// true = capsule floating pill; false = edge-to-edge pinned bar
    var floats: Bool = false
    /// When pinned, extend safe area for this edge
    var safeAreaEdge: VerticalEdge? = nil
    var blurIntensity: Double = 1.0
    @ViewBuilder var content: () -> Content
}
```

---

## 3. GlassSheet

```swift
struct GlassSheet<Content: View>: View {
    var title: String
    var subtitle: String? = nil
    var topCornerRadius: CGFloat = 28
    /// true = 20pt all corners (card modal); false = square bottom (full-screen)
    var isCardStyle: Bool = false
    var onDismiss: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content
}
```

- Header area: GlassBar treatment with drag handle
- Body area: matte (amenCream / amenCharcoal)

---

## 4. GlassChip

```swift
struct GlassChip: View {
    var label: String
    var icon: String? = nil            // SF Symbol name
    var style: GlassChipStyle = .default
    var isSelected: Bool = false
    var action: (() -> Void)? = nil    // nil = display only
}

enum GlassChipStyle {
    case small       // 28pt height
    case `default`   // 32pt height
    case large       // 40pt height
    case role        // pastoral role badge — amenGold tint always
}
```

Predefined faith-native tag labels: "Prayer", "Testimony", "Church", "Community", "Mention", "Berean", "Event"

---

## 5. HeroCard

```swift
struct HeroCard: View {
    var coverImageURL: URL?
    var title: String
    var subtitle: String? = nil
    var memberAvatars: [URL]
    var memberCount: Int
    var nextEvent: HeroCardEvent? = nil
    var activePrayerCount: Int = 0
    var actions: [HeroCardAction]      // max 4
}

struct HeroCardEvent { var title: String; var date: Date }

struct HeroCardAction {
    var id: String
    var icon: String                   // SF Symbol
    var label: String
    var action: () -> Void
}
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
struct TimelineRow: View {
    var title: String
    var subtitle: String? = nil
    var timestamp: Date? = nil
    var tag: TimelineTag? = nil
    var isCompleted: Bool = false
    var leadingIcon: String? = nil     // SF Symbol
    var action: (() -> Void)? = nil
}

struct TimelineTag { var label: String; var color: Color }
```

- Completed items: 50% opacity, strikethrough on title
- Renders on matte background parent — NOT on glass directly

---

## 7. AssistantBar

```swift
struct AssistantBar: View {
    var greeting: String               // "Hey {name}, how can we help?"
    var quickPrompts: [AssistantPrompt] // max 3
    var onTextSubmit: (String) -> Void
    var onCameraAction: () -> Void     // AMEN Vision OCR
    var onVoiceAction: () -> Void
    var isExpanded: Bool = false
}

struct AssistantPrompt {
    var id: String
    var label: String                  // chip label, max 24 chars
    var prompt: String                 // full prompt sent to Berean on tap
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
    var maxVisible: Int = 5
    var size: CGFloat = 32
    var memberCount: Int? = nil        // auto-computed from avatarURLs.count if nil
    var onTap: (() -> Void)? = nil
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

NOTE: The actual signatures in `SOSharedComponents.swift` use slightly different parameter names
than the contract-level API above (e.g. `GlassChipSize` instead of `GlassChipStyle`,
`placement: GlassBarPlacement` instead of `floats: Bool`). The contract defines the INTENT;
the implementation has equivalent semantics. Agents must use the actual signatures from
`SOSharedComponents.swift` when writing Swift code, not the contract pseudocode above.

Key signature notes for agents:
- `GlassBar` uses `placement: GlassBarPlacement` (.bottom/.top/.floating) not `floats: Bool`
- `GlassChip` uses `size: GlassChipSize` (.compact/.regular/.large), `tint:`, `isActive:` not `isSelected:`
- `GlassSheet` uses `showDismissButton: Bool`, no `isCardStyle` parameter
- `HeroCard` requires `tint: Color` and `onTap: () -> Void`
- `AssistantBar` uses `placeholder:`, `contextSurface: SOSurface`, `onSubmit:`, `onCamera:`, `onVoice:`, `quickPrompts: [String]`
- `MemberAvatarRow` requires `memberCount: Int` (not optional), uses `CachedAsyncImage`
- `TimelineRow` requires `icon: String` leading icon (not optional), uses `badge: TimelineRowBadge?`
