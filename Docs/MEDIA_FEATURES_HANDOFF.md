# Media Features — Agent Handoff Document

This document is the coordination contract between Agent 0 (Foundation) and Agents 1–7.
Every downstream agent must import types from this file rather than re-defining them.

---

## Swift Models (`AMENAPP/AMENAPP/Shared/MediaInteractions/`)

### `MediaInteractionProtocol.swift`
```swift
protocol MediaInteraction: Identifiable, Codable {
    var id: String? { get }
    var mediaId: String { get }
    var userId: String { get }
    var createdAt: Date { get }
}
```

### `MediaReaction.swift`
```swift
enum MediaReactionType: String, Codable, CaseIterable
    // .heart | .laugh | .prayer | .fire | .cross | .custom

struct MediaReaction: Identifiable, Codable, MediaInteraction
    // id, mediaId, userId, type, emoji?, note?, prayerExpiresAt?, createdAt
```
> **Firestore path:** `/reactions/{reactionId}`
> **Used by:** Agent 1 (Reactions)

### `SavedItem.swift`
```swift
struct SavedItem: Identifiable, Codable, MediaInteraction
    // id, mediaId, userId, collectionId?, savedAt, note?
```
> **Firestore path:** `/saves/{userId}/items/{saveId}`
> **Used by:** Agent 4 (Save & Translate)

### `MediaCollection.swift`
```swift
struct MediaCollection: Identifiable, Codable
    // id, userId, name, icon (SF Symbol), color (hex), itemCount, createdAt
```
> **Firestore path:** `/collections/{userId}/items/{collectionId}`
> **Used by:** Agent 4 (Save & Translate)

### `VerseAttachment.swift`
```swift
struct VerseAttachment: Identifiable, Codable
    // id, reference ("John 3:16"), translation, text, attachedToId, attachedToType, createdAt

enum VerseAttachmentTarget: String, Codable, CaseIterable
    // .reaction | .comment | .post
```
> **Firestore path:** `/verseAttachments/{attachmentId}`
> **Used by:** Agent 7 (Faith Layer)

### `MoodTag.swift`
```swift
enum MoodTag: String, Codable, CaseIterable, Identifiable
    // .encouraged | .convicted | .grateful | .joyful | .prayerful | .challenged | .comforted
    // Properties: .label (String), .emoji (String), .tintColor (Color)
```
> **Used by:** Agent 7 (Faith Layer)

---

## LiquidGlass Primitives (`AMENAPP/AMENAPP/LiquidGlass/`)

All primitives respect `@Environment(\.accessibilityReduceMotion)` and
`@Environment(\.accessibilityReduceTransparency)`. None hardcode colors — use
`Color.amenGold`, `Color.amenPurple`, etc. from `AmenAdaptiveColors.swift`.

### `GlassTray.swift`
```swift
struct GlassTray<Content: View>: View
    // isVisible: Binding<Bool>
    // alignment: HorizontalAlignment = .center
    // content: () -> Content
    // Spring scale 0.85→1.0 from bottom; auto-respects Reduce Motion.
```
> **Used by:** Agent 1 (reactions emoji tray), Agent 4 (collection picker).

### `GlassHUD.swift`
```swift
struct GlassHUD<Content: View>: View
    // triggerValue: AnyHashable  — change triggers show; starts dismiss timer
    // timeout: Double = 1.2
    // content: () -> Content
    // Auto-dismisses; allowsHitTesting(false).

// Convenience modifier:
extension View {
    func glassHUD<T: Hashable>(for value: T, timeout: Double, content: () -> some View) -> some View
}
```
> **Used by:** Agent 3 (speed HUD, volume indicator).

### `GlassPill.swift`
```swift
struct GlassPill<Content: View>: View
    // isProminent: Bool = false  — upgrades to regularMaterial for legibility over media
    // horizontalPadding / verticalPadding: CGFloat

// Convenience modifier:
extension View {
    func glassPill(prominent: Bool = false) -> some View
}
```
> **Used by:** Agent 2 (quote-reply preview), Agent 5 (share UI), Agent 7 (mood tags).

### `GlassThumbBubble.swift`
```swift
struct GlassThumbBubble: View
    // xOffset: CGFloat   — horizontal position matching scrubber thumb
    // image: UIImage?    — thumbnail from AVAssetImageGenerator; nil shows shimmer
    // isVisible: Bool
```
> **Used by:** Agent 3 (scrub preview bubble).

### `GlassSheet.swift`
```swift
enum GlassSheetDetent    // .small (~40%) | .medium (~55%) | .large | .adaptive([...])

struct GlassSheet<SheetContent: View>: ViewModifier
    // isPresented: Binding<Bool>
    // detent: GlassSheetDetent = .medium
    // cornerRadius: CGFloat = 28

// Convenience modifier:
extension View {
    func glassSheet<SheetContent: View>(isPresented: Binding<Bool>, detent: GlassSheetDetent, content: () -> SheetContent) -> some View
}
```
> **Used by:** Agent 4 (collection picker `.medium`), Agent 7 (verse picker, worship lyrics).

### `GlassBadge.swift`
```swift
struct GlassBadge: View
    // icon: String      — SF Symbol name
    // label: String     — optional text beside icon
    // tint: Color = .white
    // isVisible: Bool = true

// Convenience modifier:
extension View {
    func glassBadge(icon: String, label: String, tint: Color, alignment: Alignment, isVisible: Bool) -> some View
}
```
> **Used by:** Agent 1 (pinned reply badge), Agent 6 (view-once badge).

---

## Cloud Functions (`functions/src/mediaInteractions/index.js`)

All functions require authentication. Stubs throw `unimplemented` until the owning
agent fills in the body.

| Export            | Owner   | Input fields                                    | Output fields                      |
|-------------------|---------|-------------------------------------------------|------------------------------------|
| `addReaction`     | Agent 1 | `mediaId`, `type`, `emoji?`, `note?`, `prayerExpiresAt?` | `{ reactionId }`          |
| `removeReaction`  | Agent 1 | `reactionId`                                    | `{ success }`                      |
| `pinReply`        | Agent 1 | `mediaId`, `commentId`                          | `{ success }`                      |
| `saveToCollection`| Agent 4 | `mediaId`, `collectionId?`, `note?`             | `{ savedItemId }`                  |
| `translateText`   | Agent 4 | `text`, `targetLocale`                          | `{ translatedText, sourceLocale }` |
| `attachVerse`     | Agent 7 | `reference`, `attachedToId`, `attachedToType`   | `{ attachmentId, text, translation }` |

Registered in `functions/index.js` as `exports.addReaction`, etc.

---

## Firestore Schema

Full schema with index requirements and Firestore rules stubs:
→ `firestore/SCHEMA.md`

New collection paths:
- `/reactions/{reactionId}`
- `/saves/{userId}/items/{saveId}`
- `/collections/{userId}/items/{collectionId}`
- `/verseAttachments/{attachmentId}`
- `/mediaSettings/{mediaId}`

---

## Design Tokens Reference

| Token                     | Value                              |
|---------------------------|------------------------------------|
| `LiquidGlassTokens.blurThin`     | `.ultraThinMaterial`        |
| `LiquidGlassTokens.blurElevated` | `.regularMaterial`          |
| `LiquidGlassTokens.cornerRadiusSmall`  | 14 pt                |
| `LiquidGlassTokens.cornerRadiusMedium` | 22 pt                |
| `LiquidGlassTokens.cornerRadiusLarge`  | 32 pt                |
| `Animation.amenSpring`           | `spring(response:0.42, damping:0.82)` |
| `Color.amenGold`                 | `(0.83, 0.69, 0.22)`        |
| `Color.amenPurple`               | see `AmenAdaptiveColors.swift` |
| `Color.amenBlue`                 | see `AmenAdaptiveColors.swift` |

---

## Agent Dependency Map

```
Agent 0 (Foundation) — COMPLETE
  ├── Agent 1 (Reactions)       needs: MediaReaction, GlassTray, GlassBadge, addReaction, removeReaction, pinReply
  ├── Agent 2 (Reply Modalities) needs: GlassPill, GlassSheet
  ├── Agent 3 (Media Player)    needs: GlassThumbBubble, GlassHUD
  ├── Agent 4 (Save & Translate) needs: SavedItem, MediaCollection, GlassSheet, saveToCollection, translateText
  ├── Agent 5 (Share & Schedule) needs: GlassSheet, GlassPill
  ├── Agent 6 (Privacy & Controls) needs: /mediaSettings, GlassBadge, GlassSheet
  └── Agent 7 (Faith Layer)     needs: VerseAttachment, MoodTag, GlassSheet, attachVerse
```

---

*Last updated: Agent 0 — Foundation pass complete.*
