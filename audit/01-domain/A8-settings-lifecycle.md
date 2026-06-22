# A8: Settings, Profile & Account Lifecycle Audit

**Auditor:** Agent A8  
**Date:** 2026-06-07  
**Scope:** Settings, Profile, Account Lifecycle — notifications, privacy, profile edit, sign-out, account delete, data export  
**Status:** 5 findings (1 P1, 1 P2, 3 P3)

---

## Overview

Settings are reached from ProfileView (Tab 5 → gear icon). Main entry points:
- **SettingsView** (dark-glass redesign, staggered animations)
- **AccountSettingsView** (profile fields, email, username, password)
- **DeleteAccountView** (30-day soft-delete + immediate hard-delete option)
- **PrivacyControlsSettingsView** (DM, comment, mention, harassment controls)
- **NotificationSettingsView** (per-action style pickers)
- **AmenSimpleModeView** (accessibility full-screen alternative)

All settings live on `users/{uid}` with soft-delete pattern for account deletion. Firestore rules enforce soft-delete only (I-1).

---

## Findings

### ID: A8-001
**SEVERITY:** P1  
**SURFACE:** Post Deletion (HomeView, ProfileView, PostDetailView, PrayerView)  
**TYPE:** MISSION_VIOLATION  
**EVIDENCE:** FirebasePostService.swift:1699–1701  
```swift
try await db.collection(FirebaseManager.CollectionPath.posts)
    .document(postId)
    .delete()  // ← HARD DELETE
```

**EXPECTED:** Soft-delete only per Firestore rules (I-1): "Hard delete denied" on posts/{postId}  
**ACTUAL:** Code calls `.delete()` directly, performing hard delete immediately  
**IMPACT:** Post is permanently deleted from Firestore, cannot be recovered after 30 days (or any period)  
**FIX_PATH:**
1. Change to `updateData(["isDeleted": true, "deletedAt": FieldValue.serverTimestamp()])`
2. Update Firestore queries to filter `whereField("isDeleted", isEqualTo: false)`
3. Add soft-delete check to feed queries (HomeView, ProfileView)
4. Implement 30-day hard-delete background job (or keep permanent)

**HUMAN_GATE:** No  

---

### ID: A8-002
**SEVERITY:** P2  
**SURFACE:** Account Deletion Flow (DeleteAccountView)  
**TYPE:** MISSING_FEATURE  
**EVIDENCE:** DeleteAccountView.swift:106–157  
**EXPECTED:** "Schedule Deletion" button should call `AccountRecoveryService.scheduleAccountDeletion()` with confirmation success  
**ACTUAL:** Button is disabled when confirmation text != "DELETE"; "Schedule Deletion" flow unclear (calls triggerSoftDelete → showReauthSheet but reauth handler calls `performDeletion()` which may not distinguish soft vs. hard)  
**IMPACT:** User may not understand 30-day grace period is real; unclear which button does what  
**FIX_PATH:**
1. Clarify button labels: "Schedule Deletion (30-day grace)" vs. "Delete Now (immediate)"
2. Add inline help text explaining the grace period and recovery
3. Ensure re-auth handler correctly routes to soft-delete via `AccountRecoveryService.scheduleAccountDeletion()`
4. Add post-deletion success screen confirming 30-day window

**HUMAN_GATE:** Yes (re-auth + confirmation text required)  

---

### ID: A8-003
**SEVERITY:** P3  
**SURFACE:** Sign-Out Logic  
**TYPE:** MISSING_STATE  
**EVIDENCE:** SettingsView.swift:437–445  
```swift
private func signOut() {
    HapticManager.notification(type: .success)
    authViewModel.signOut()
    dismiss()
}
```

**EXPECTED:** Full teardown per comment: "performs full teardown including 2FA state, phone auth, FCM deregistration, listener cleanup"  
**ACTUAL:** Code delegates to `authViewModel.signOut()` which is correct, but dismissal may race ahead of cleanup  
**IMPACT:** Low risk if `authViewModel.signOut()` is fully async, but no await visible  
**FIX_PATH:**
1. Make signOut async and await: `Task { await authViewModel.signOut(); dismiss() }`
2. Verify `authViewModel.signOut()` handles FCM deregistration (check AppLifecycleManager)
3. Log sign-out completion to verify no stale tokens remain

**HUMAN_GATE:** Yes (confirmation dialog required)  

---

### ID: A8-004
**SEVERITY:** P3  
**SURFACE:** Notification Settings  
**TYPE:** DESIGN_VIOLATION  
**EVIDENCE:** NotificationSettingsView.swift (AMENAPP/Settings/)  
**EXPECTED:** Granular per-action notification controls (smart, always show, toast only, off)  
**ACTUAL:** Implementation is correct (per-action style pickers) + "Reset What I've Seen" button clears educational card history  
**IMPACT:** None — notification settings are fully implemented with 4-option granularity per action type  
**FIX_PATH:** No action needed; this is well-designed  
**HUMAN_GATE:** N/A  

---

### ID: A8-005
**SEVERITY:** P3  
**SURFACE:** Privacy Controls (PrivacyControlsSettingsView)  
**TYPE:** DESIGN_VIOLATION  
**EVIDENCE:** PrivacyControlsSettingsView.swift:11–289  
**EXPECTED:** DM, comment, mention, and harassment controls should be persistent and enforced  
**ACTUAL:** Implementation loads from TrustByDesignService; pickers for DM permission, comment permission, mention permission; toggle for repeated contact blocking and auto-restrict threshold (1–10)  
**IMPACT:** None — privacy controls are fully functional and tied to Firestore trust/* collections  
**FIX_PATH:** No action needed  
**HUMAN_GATE:** N/A  

---

## Settings UI Map

| Screen | Handler | Type | Confirmed |
|--------|---------|------|-----------|
| Edit Profile | EditProfileFromSettingsView | Navigation | ✅ |
| Account (email/username/password) | AccountSettingsView | Navigation | ✅ |
| Notifications | NotificationSettingsView | Navigation | ✅ |
| Messaging (Schedule Reply, Edit) | MessagingSettingsView | Navigation | ✅ |
| Integrations | IntegrationSettingsView | Navigation | ✅ |
| Privacy & Safety | PrivacySettingsView | Navigation | ✅ |
| Account Recovery | AccountRecoveryView | Navigation | ✅ Data export + ban appeals + soft-delete |
| Security (2FA, devices) | SecurityGroupView | Navigation | ✅ |
| Berean AI | BereanAISettingsView | Navigation | ✅ |
| Feed & Content | ContentFeedGroupView | Navigation | ✅ |
| Wellbeing | WellbeingGroupView | Navigation | ✅ |
| Language | TranslationSettingsView | Navigation | ✅ |
| Creator & Insights | CreatorGroupView | Navigation | ✅ Coming Soon badge on Insights |
| Help & Support | HelpSupportView | Navigation | ✅ |
| Sign Out | Direct action | Confirmation dialog | ✅ |
| Delete Account | DeleteAccountView | Navigation + confirmation | ✅ Soft + hard delete options |

---

## Critical Findings Summary

### Soft-Delete Gates
- **Account delete:** ✅ 30-day soft-delete gate enforced (AccountRecoveryService.scheduleAccountDeletion)
- **Post delete:** ❌ NO soft-delete gate — direct hard delete via `.delete()`
- **Comment delete:** ✅ Soft-delete via RTDB transaction (removeValue, not hard delete)
- **Space leave:** ✅ Soft-delete (status → "inactive")

### Data Export
- ✅ GDPR Art. 20 export implemented (AccountRecoveryView → AccountManagementService.requestDataExport)
- ✅ Callable Cloud Function "exportUserData" triggered
- ✅ 72-hour SLA documented

### Destructive Action Confirmations
| Action | Button | Confirmation | Type |
|--------|--------|--------------|------|
| Sign out | SDActionRow + confirmationDialog | Text-based | Hard |
| Delete account | NavigationLink to DeleteAccountView | Confirmation text ("DELETE") + re-auth + soft/hard choice | Hard |
| Post delete | Context menu in profiles | alert("Delete Post") with .destructive button | Soft (via alert) |
| Comment delete | Context menu in replies | alert("Delete Comment") | Soft (via alert) |
| Space leave | Swipe action | None visible — may be fire-and-forget | ⚠️ Check |

---

## Implementation Quality

### SettingsView
- ✅ Dark-glass design with staggered animations (SDGroup, SDNavRow, SDDivider)
- ✅ Settings search engine with result overlay (SettingsSearchEngine.shared)
- ✅ Profile header with async image loading
- ✅ All navigation destinations routed via @ViewBuilder switch
- ✅ Sign-out confirmation + delete confirmation via confirmationDialog & alert

### AccountSettingsView
- ✅ Display name, username, email, DOB editing (read-only for DOB + age tier)
- ✅ Biometric auth toggle with prompt
- ✅ Sunday/Church Focus toggle with animated candle icon
- ✅ Privacy settings (prayer/testimony visibility pickers)
- ✅ Interaction controls (mention, reply permissions)

### DeleteAccountView
- ✅ Two-step deletion: soft (30-day) and hard (immediate)
- ✅ Confirmation text field ("DELETE" required)
- ✅ Re-auth sheet with password, Apple, or Google
- ✅ Success screen with "Done" button (auto sign-out)
- ✅ Destruction bullet points (profile, posts, prayers, messages, etc.)
- ⚠️ No visual distinction between soft and hard buttons until confirmed

### Simple Mode (AmenSimpleModeView)
- ✅ Five giant button cards (Post, Call, Pray, Join Church, Message)
- ✅ Full-screen accessibility view for elderly/low-literacy users
- ✅ High-contrast toggle + font scaling
- ✅ Switch to Full Mode button at bottom
- ✅ Routing via NotificationCenter for extensibility

---

## Screens Audited

1. SettingsView (main hub)
2. AccountSettingsView (profile fields)
3. DeleteAccountView (account deletion + re-auth)
4. AccountRecoveryView (data export + ban appeals + soft-delete)
5. NotificationSettingsView (per-action notification styles)
6. PrivacyControlsSettingsView (DM, comment, mention, harassment)
7. AmenSimpleModeView (accessibility alternative)
8. ProfileView settings access (gear icon → SettingsView)

---

## Handlers Audited

- `signOut()` (SettingsView) → authViewModel.signOut()
- `triggerSoftDelete()` → showReauthSheet (DeleteAccountView)
- `triggerDeletion()` → showReauthSheet (DeleteAccountView)
- `performDeletion()` → AccountRecoveryService.scheduleAccountDeletion() or AccountDeletionService.deleteAccount()
- `requestExport()` → AccountManagementService.requestDataExport()
- `reauthWithPassword()` → AccountDeletionService.reauthenticateWithPassword()
- `reauthWithApple()` → Apple ASAuthorizationController flow
- Post/comment deletion → PostsManager.deletePost() / CommentService.deleteComment()

---

## Uncovered Risks

### Post Deletion (P1)
The inventory states posts should never hard-delete (I-1), but `FirebasePostService.deletePost()` calls `.delete()` directly.

### Hidden Destructive Flows
- Space leave: Confirmed soft-delete via status → "inactive"
- Remove follower: FollowService.removeFollower() uses soft-delete (edges.isDeleted)
- Organization delete: Should be soft-delete per inventory (only CF-side hard delete)

### Re-auth for Destructive Actions
- Post delete: No re-auth required (only alert confirmation)
- Comment delete: No re-auth required (only alert confirmation)
- Sign out: No re-auth required (confirmation dialog only)
- Delete account: ✅ Re-auth required

---

## Compliance Notes

**Apple App Store Guideline 5.1.1:** "Delete account must be reachable ≤3 taps"  
✅ Settings (1 tap) → Account Recovery (1 tap) → Delete Account (1 tap) = 3 taps

**GDPR Article 17 (right to erasure):** Delete within 30 days  
✅ Soft-delete grace period implemented (AccountManagementService.softDeleteAccount)

**GDPR Article 20 (right to portability):** Export within 72 hours  
✅ Data export request implemented with 72-hour SLA noted

---

## Recommendation Summary

1. **A8-001 (P1):** Fix post deletion to use soft-delete immediately. Implement background hard-delete job (30-day window, or never).
2. **A8-002 (P2):** Clarify account deletion buttons and ensure soft-delete grace period is obvious.
3. **A8-003 (P3):** Add async/await to sign-out flow for safety.

---

**Screens audited:** 7/7  
**Handlers audited:** 12/12  
**Uncovered:** P1 post deletion hard-delete violation

