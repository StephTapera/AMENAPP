# Shared Components Contract — Spiritual OS
## STATUS: FROZEN · Do not edit without Lead Orchestrator sign-off

All Spiritual OS surfaces MUST use these primitives. Agents must not invent
their own card/sheet/bar components. The Lead implements skeleton versions
in `SpiritualOS/SharedComponents/` before agents begin Phase 2.

---

## Component Registry

### 1. `GlassCard`

```swift
struct GlassCard<Content: View>: View {
    var tint: Color? = nil           // Space theme tint (amenGold/Purple/Blue)
    var elevated: Bool = false       // lensed vs contextual treatment
    var isPressed: Bool = false      // scale feedback (0.985)
    var scrollDepth: CGFloat = 0     // shadow intensity modifier from scroll offset
    @ViewBuilder var content: () -> Content
}
```

**Behavior:** Wraps `LiquidGlassCard` (existing). Agents use `GlassCard`, not `LiquidGlassCard` directly, so Lead can adjust globally.  
**No glass-on-glass.** Content inside must be on matte backgrounds.

---

### 2. `GlassBar`

```swift
struct GlassBar<Content: View>: View {
    var placement: GlassBarPlacement  // .bottom, .top, .floating
    var tint: Color? = nil
    @ViewBuilder var content: () -> Content
}

enum GlassBarPlacement { case bottom, top, floating }
```

**Behavior:** Full-width (`maxWidth: .infinity`) glass strip using `blurThin` material + hairline top border. Used for: tab bar chrome, Assistant Bar, composer bars, Worship Mode control strip.  
**Accessibility:** minimum 44pt hit targets for all children.

---

### 3. `GlassSheet`

```swift
struct GlassSheet<Content: View>: View {
    var title: String
    var tint: Color? = nil
    var showDismissButton: Bool = true
    var onDismiss: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content
}
```

**Behavior:** Presented via `.sheet` or `.fullScreenCover`. Uses `lensed` glass treatment with drag indicator. Title in AMEN type scale (title3, semibold). Dismiss button uses `amenSlate` chevron, not system X (faith-native affordance).

---

### 4. `GlassChip`

```swift
struct GlassChip: View {
    var label: String
    var icon: String? = nil          // SF Symbol name
    var tint: Color? = nil
    var size: GlassChipSize = .regular
    var isActive: Bool = false
    var action: (() -> Void)? = nil

    enum GlassChipSize { case compact, regular, large }
}
```

**Behavior:** Capsule shape (`capsuleRadius`). Active state: fills with `tint ?? amenGold` at 20% opacity + border at 60% opacity. Inactive: `compressed` glass treatment. Icon renders before label at 13pt symbol weight. Never used for vanity metrics.

---

### 5. `HeroCard`

```swift
struct HeroCard: View {
    var title: String
    var subtitle: String? = nil
    var coverImageURL: URL? = nil
    var tint: Color                  // required — must be amenGold/Purple/Blue
    var memberAvatars: [URL]         // up to 5 shown
    var memberCount: Int
    var nextEvent: HeroCardEvent?
    var actions: [HeroCardAction]    // up to 4 primary actions
    var onTap: () -> Void
}

struct HeroCardEvent {
    let title: String
    let date: Date
    let icon: String   // SF Symbol
}

struct HeroCardAction {
    let label: String
    let icon: String   // SF Symbol
    let action: () -> Void
}
```

**Behavior:** Full-width card with `lensed` glass treatment. Cover image rendered as background with linear gradient scrim (bottom 60%, amenBlack at 0.6 opacity). Member avatars rendered as `MemberAvatarRow` (see below). Next event shown as `GlassChip` at bottom-leading. Actions rendered as 2-up `GlassChip` rail. Tint bleeds into glass material as Space color.

---

### 6. `TimelineRow`

```swift
struct TimelineRow: View {
    var icon: String                 // SF Symbol
    var iconTint: Color = .amenGold
    var title: String
    var subtitle: String? = nil
    var timestamp: Date? = nil
    var badge: TimelineRowBadge? = nil
    var isCompleted: Bool = false
    var onTap: (() -> Void)? = nil

    enum TimelineRowBadge {
        case tag(String, Color)      // faith tag label + color
        case count(Int)              // private count (only in personal surfaces)
        case dot(Color)              // unread indicator
    }
}
```

**Behavior:** `compressed` glass treatment row with leading vertical line connector (for adjacent rows). Completed items show checkmark icon in `amenGold`, title in `amenSlate`. Timestamp renders as relative string ("2h ago", "Tomorrow"). Badge renders trailing. No engagement metrics via `.count` badge in shared surfaces — Lead enforces this at review.

---

### 7. `AssistantBar`

```swift
struct AssistantBar: View {
    var placeholder: String          // "Hey {name}, how can I help?"
    var contextSurface: SOSurface    // current surface for context prompts
    var onSubmit: (String) -> Void
    var onCamera: () -> Void         // Vision OCR trigger
    var onVoice: () -> Void          // Voice session trigger
    var quickPrompts: [String]       // surface-aware suggestions (max 3)
}
```

**Behavior:** Mounted via `GlassBar(.floating)` pinned above the tab bar. Prompt field is a tappable pill that expands to a full sheet (`GlassSheet`) on tap. Camera and voice icons use `amenPurple`. Quick prompts render as `GlassChip` row above the bar when the bar is focused. Dismisses by tapping outside.

---

### 8. `MemberAvatarRow`

```swift
struct MemberAvatarRow: View {
    var avatarURLs: [URL]            // up to 5 shown, excess shows "+N" chip
    var size: CGFloat = 32
    var overlap: CGFloat = 10        // pixel overlap between avatars
    var borderColor: Color = .white
}
```

**Behavior:** Horizontal stack of circular avatar images, right-to-left z-order (first avatar on top). Excess count shown as `GlassChip(.compact)` in `amenSlate`. Renders synchronously via `CachedAsyncImage` (existing) — no placeholder flash.

---

## Surface Enum (used by AssistantBar and Context Engine)

```swift
enum SOSurface: String, Codable {
    case dailyDigest   = "daily_digest"
    case unifiedHub    = "unified_hub"
    case lifePlanner   = "life_planner"
    case spaceDashboard = "space_dashboard"
    case createSpace   = "create_space"
    case commandCenter = "command_center"
    case assistantBar  = "assistant_bar"
    case contextEngine = "context_engine"
}
```

---

## Skeleton Implementation Note

The Lead will create `SpiritualOS/SharedComponents/SOSharedComponents.swift` containing
stub implementations of each component (buildable, no-op bodies) before Phase 2 agents
begin. Agents import from this file only — they never copy-paste component internals.
