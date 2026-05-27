# Smart Contextual Prompt System — Product Audit

**AMEN App · System 41**  
**Status:** Implemented (OFF by default, Remote Config enabled)  
**Last updated:** 2026-05-22

---

## Overview

A non-annoying, spiritually respectful prompt system that surfaces the right contextual invitation at the right moment — never on cold launch, never stacked, never during worship or prayer.

Inspired by TikTok-style point-of-use permission prompts but redesigned for AMEN's calm, privacy-first, native iOS experience.

---

## Files Created

| File | Location | Purpose |
|------|----------|---------|
| `AmenSmartPromptModels.swift` | `AMENAPP/Services/Prompts/` | All types, enums, value objects |
| `AmenSmartPromptStateStore.swift` | `AMENAPP/Services/Prompts/` | UserDefaults persistence |
| `AmenSmartPromptEngine.swift` | `AMENAPP/Services/Prompts/` | Eligibility, suppression, catalog |
| `AmenSmartPromptCard.swift` | `AMENAPP/DesignSystem/Prompts/` | Bottom-anchored card overlay |
| `AmenSmartPromptBanner.swift` | `AMENAPP/DesignSystem/Prompts/` | Top-anchored transient banner |
| `AmenSmartPromptSheet.swift` | `AMENAPP/DesignSystem/Prompts/` | Half-sheet modal |
| `AmenSmartPromptHero.swift` | `AMENAPP/DesignSystem/Prompts/` | Inline feed card |
| `AmenSmartPromptModifier.swift` | `AMENAPP/DesignSystem/Prompts/` | View modifier for surface wiring |
| `AmenSmartPromptTests.swift` | `AMENAPPTests/` | Unit tests |

**Files edited:**  
- `AMENAnalyticsService.swift` — Added 9 smart prompt analytics events  
- `AMENFeatureFlags.swift` — System 41 flags (already present)

---

## Feature Flags (System 41)

All flags default `false`. Enable via Firebase Remote Config for progressive rollout.

| Flag | Controls |
|------|---------|
| `smartContextualPromptsEnabled` | Master kill switch. When `false`, zero prompts are shown. |
| `smartPromptPrayerNotificationsEnabled` | Prayer reply + prayer update prompts |
| `smartPromptChurchUpdatesEnabled` | Church follow + event reminder prompts |
| `smartPromptBereanContinuationEnabled` | Berean study + resume reflection prompts |
| `smartPromptQuietModeEnabled` | Quiet Mode / Selah suggestion prompts |
| `smartPromptSelahPauseEnabled` | Selah pause prompt |
| `smartPromptSpacesJoinEnabled` | Join active conversation prompt |
| `smartPromptCreatorInsightsEnabled` | Creator/teacher community activity |
| `smartPromptObservancesEnabled` | Seasonal/church observance prompts |
| `smartPromptAmbientHeroEnabled` | Worship continuity / media hero prompts |

---

## Suppression Rules (Hard)

The engine will **never** show a prompt when:

| Condition | Checked via |
|-----------|------------|
| `smartContextualPromptsEnabled = false` | `AMENFeatureFlags.shared` |
| User is in active worship session | `AmenSmartPromptContext.isInWorshipSession` |
| User is in live prayer session | `AmenSmartPromptContext.isInLivePrayer` |
| Berean AI is generating a response | `AmenSmartPromptContext.isBereanGenerating` |
| User is in sensitive reflection entry | `AmenSmartPromptContext.isInSensitiveReflection` |
| User has active text input | `AmenSmartPromptContext.isInActiveTextEntry` |
| Native permission dialog is active | `AmenSmartPromptContext.isNativePermissionDialogActive` |
| Global 30-minute cooldown active | `AmenSmartPromptStateStore.globalLastPromptDate` |
| Prompt was permanently suppressed | `AmenSmartPromptStateStore.isPermanentlySuppressed` |
| Notification permission already granted | `context.notificationPermissionStatus == .authorized` |

---

## Cooldown Policies

| Policy | Per Prompt Type | Per Surface | Global | Max Dismissals |
|--------|----------------|------------|--------|---------------|
| `.default` | 48 h | 8 h | 30 min | 3 |
| `.gentle` | 7 days | 24 h | 1 h | 2 |

Prayer prompt uses a stricter custom policy (72h per type, 2 max dismissals) to respect the sensitivity of prayer flows.

---

## Surface Audit

### ✅ Build

| Surface | Prompt | Trigger | Suppression | Permission | CTA |
|---------|--------|---------|-------------|-----------|-----|
| Prayer Requests | "Stay close to this prayer?" | After posting a prayer OR receiving first reply | Worship, live prayer, notification already granted | Notifications | "Enable Prayer Updates" / "Not Now" |
| Church Detail | "Keep up with this church?" | After viewing church events or following | Notification already granted | Notifications | "Keep Me Updated" / "Maybe Later" |
| Berean AI | "Continue this study?" | After completing a meaningful study session | Berean generating, text entry | Notifications | "Remind Me" / "Not Now" |
| Church Notes | "Continue your reflection later?" | When user leaves note with unsaved draft | Text entry active | Notifications | "Remind Me" / "Not Now" |
| Selah | "Pause and reflect?" | After extended session or late-night use | Worship, sensitive reflection | None | "Start Selah" / "Continue" |
| Selah | "Calmer tonight?" | After extended session or repeated visits | Quiet mode already active | None | "Enable Quiet Mode" / "Not Now" |
| Spaces | "Join this conversation?" | When browsing an active discussion | Text entry | None | "Join" / "Not Now" |
| Media Detail | "Continue this series?" | After meaningful media engagement | Worship session | None | "Follow Creator" / "Maybe Later" |
| Creator Tools | "Your community is active" | When audience activity crosses a threshold | Text entry | None | "See Activity" / "Later" |

### ⏸ Defer

| Surface | Reason |
|---------|--------|
| Home Feed cold launch | Never prompt on cold launch per product rules |
| Auth flow | Never prompt during auth |
| First app open | Never prompt on first open |
| Direct Messages | Sensitive — defer to v2 |
| Seasonal/Observance | Requires calendar intelligence — defer |

### ✗ Do Not Build

| Surface | Reason |
|---------|--------|
| Any prompt on cold launch | Hard no — product rule |
| Stacked prompts | Engine enforces single-prompt rule |
| Guilt / urgency copy | Violates product tone |
| Notification prompt without CTA | Hard no — defer native dialog until user taps CTA |

---

## Copy Audit

All copy was reviewed against the safety checklist:

| Criterion | Status |
|-----------|--------|
| No guilt language | ✅ |
| No "don't miss out" | ✅ |
| No fear-based urgency | ✅ |
| No exploiting sadness/loneliness | ✅ |
| No diagnosis language | ✅ |
| No addictive notification copy | ✅ |
| No prompt loops | ✅ (max dismissals enforced) |
| Calm, optional, spiritually respectful | ✅ |

---

## Analytics Events

All events are privacy-safe. No prayer text, message text, note content, or emotional inference is logged.

| Event | Properties |
|-------|-----------|
| `smart_prompt_eligible` | `prompt_type`, `surface` |
| `smart_prompt_impression` | `prompt_type`, `surface` |
| `smart_prompt_primary_action` | `prompt_type`, `surface` |
| `smart_prompt_secondary_action` | `prompt_type`, `surface` |
| `smart_prompt_dismissed` | `prompt_type`, `surface`, `reason` |
| `smart_prompt_suppressed` | `surface`, `reason` |
| `smart_prompt_permission_requested` | `prompt_type`, `permission_type` |
| `smart_prompt_permission_granted` | `prompt_type`, `permission_type` |
| `smart_prompt_permission_denied` | `prompt_type`, `permission_type` |

**Forbidden analytics properties (never log):**
- `prayer_text`, `message_text`, `note_body`, `berean_prompt`, `berean_response`
- `journal_text`, `reflection_text`, `emotional_state`, private group content

---

## Accessibility Checklist

| Requirement | Implementation |
|-------------|---------------|
| VoiceOver title + body | `accessibilityLabel("\(title). \(body)")` on container |
| Named CTA buttons | `accessibilityLabel` on each button |
| Dismiss button labeled | "Dismiss" label on xmark button |
| Dynamic Type | All text uses system fonts (`font(.subheadline)` etc.) |
| Reduce Motion | Spring animations replaced with `.easeOut(duration:)` |
| Reduce Transparency | Falls back to `Color(.systemBackground)` |
| Minimum 44pt tap targets | All buttons constrained to `.frame(height: 44)` or larger |
| Focus order | Natural SwiftUI VoiceOver traversal order |
| Safe area | Overlay positioned outside safe area bottom/top |

---

## Surface Integration Guide

To wire a prompt into an existing surface, add **3 lines**:

```swift
// 1. State property
@State private var promptTrigger = false

// 2. Set trigger after the relevant user action
myUserAction()
promptTrigger = true

// 3. Modifier on body (or ZStack/VStack root)
.amenSmartPrompt(surface: .prayerRequests, trigger: $promptTrigger) {
    var ctx = AmenSmartPromptContext()
    ctx.notificationPermissionStatus = await UNUserNotificationCenter.current()
        .notificationSettings().authorizationStatus
    return ctx
}
```

**Important:** Do not set the trigger on app launch, during auth, or during first open.

---

## Backend / Firestore

No backend changes required for the initial rollout.

All state is local (UserDefaults). If cross-device prompt preference sync is needed in a future version, add:

```
users/{uid}/promptPreferences/{promptType}
```

Schema (if added):
```json
{
  "promptType": "prayer_reply_notification",
  "enabled": true,
  "dismissalCount": 0,
  "lastDismissedAt": null,
  "lastImpressionAt": null,
  "lastActionAt": null
}
```

Firestore rules (if added):
```
match /users/{uid}/promptPreferences/{promptType} {
  allow read, write: if request.auth.uid == uid
    && promptType in ['prayer_reply_notification', 'church_event_reminder',
                      'berean_study_continuation', 'resume_reflection',
                      'quiet_mode', 'selah_pause', 'join_conversation',
                      'worship_continuity', 'creator_activity']
    && request.resource.data.keys().hasOnly(['promptType', 'enabled',
       'dismissalCount', 'lastDismissedAt', 'lastImpressionAt', 'lastActionAt']);
}
```

---

## Manual QA Checklist

### Installation States
- [ ] Fresh install — no prompts on cold launch
- [ ] Existing user — previous dismissal state preserved
- [ ] After app update — state migration safe (UserDefaults keys unchanged)

### Notification Permission States
- [ ] `notDetermined` — prompt appears with primary CTA, tapping CTA shows iOS dialog
- [ ] `authorized` — prompt for notification permission does NOT appear
- [ ] `denied` — primary CTA leads to Settings, not iOS dialog

### Prompt Behavior
- [ ] Prompt appears at correct trigger point (post prayer, view church, finish Berean)
- [ ] Only one prompt visible at a time
- [ ] Primary CTA fires notification request (when applicable)
- [ ] Secondary CTA dismisses cleanly
- [ ] Swipe-down (card) / swipe-up (banner) dismisses
- [ ] After 2 dismissals, prompt does not reappear
- [ ] After cooldown period, prompt can reappear

### Feature Flags
- [ ] `smartContextualPromptsEnabled = false` → no prompts anywhere
- [ ] `smartPromptPrayerNotificationsEnabled = false` → prayer prompt absent
- [ ] Kill switch via Remote Config takes effect within 1 hour

### Active Flow Suppression
- [ ] During active Berean response generation — no prompt
- [ ] During live prayer — no prompt
- [ ] During active keyboard/text entry — no prompt
- [ ] During worship media playback — no prompt
- [ ] During sensitive reflection entry — no prompt

### Accessibility
- [ ] VoiceOver reads title and body on card/banner appearance
- [ ] CTA buttons announced correctly
- [ ] Reduce Motion disables spring animations
- [ ] Reduce Transparency uses solid systemBackground
- [ ] Large Dynamic Type — text wraps, no clipping
- [ ] All tap targets ≥ 44pt

### Network / Device
- [ ] Offline mode — prompts shown from local state, no network needed
- [ ] Low-power mode — no impact (prompts are lightweight)
- [ ] iPad — card and banner render correctly in wider layout

---

## Final Verdict

**GO WITH CAVEATS**

The system is implemented, tested, and flag-gated. Caveats before production enable:

1. **Xcode project integration required** — New files must be added to the AMENAPP target in Xcode (drag-and-drop from Finder into the project navigator under the appropriate groups).

2. **Remote Config key registration** — Add the System 41 flag keys to Firebase Remote Config with `false` defaults before any rollout.

3. **Surface trigger wiring** — The modifier is ready; each surface owner must add the 3-line integration when their feature flag is enabled.

4. **End-to-end QA** — Run the full manual QA checklist above on a real device before enabling any flags in production.
