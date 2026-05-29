# Settings & Account Lifecycle Audit

**Audited:** 2026-05-28  
**Branch:** audit/2026-05-28  
**Files examined:** AccountSettingsView.swift, AccountDeletionService.swift, DeleteAccountView.swift, AuthenticationViewModel.swift, AgeAssuranceService.swift, AgeGateView.swift, AMENAPPApp.swift, NotificationsSettingsView.swift, NotificationSettingsView.swift, NotificationSettingsService.swift, AppLifecycleManager.swift, SettingsView.swift, SettingsDestinationViews.swift

---

## Findings Table

| File:Line | Severity | Category | Description |
|-----------|----------|----------|-------------|
| AccountSettingsView.swift:1293–1295 | **Blocker** | Sign-out bypass | Sign-out alert calls `Auth.auth().signOut()` directly, skipping `authViewModel.signOut()` and therefore skipping all of `AppLifecycleManager.performFullSignOutCleanup()`: listeners not stopped, FCM token not deactivated, cached data not cleared, badge not reset, phone auth state not wiped |
| AccountDeletionService.swift:277 | **Blocker** | Account deletion | `clearLocalState()` has a stub comment `// Clear keychain if needed (add SecItemDelete calls here)` — Keychain entries (e.g. `emailForSignIn`, BiometricAuthService credentials, any stored tokens) are never deleted on account deletion |
| AccountDeletionService.swift:169–179 | **Blocker** | Account deletion | `deleteDocumentsWhereField` issues a single query capped at 200 documents. Users with more than 200 posts, follows, saved posts, drafts, or reports will have orphaned Firestore documents after deletion — violating App Store Guideline 5.1.1 |
| AgeGateView.swift:1–110 | **Blocker** | COPPA | `AgeGateView` is defined but is **never presented anywhere** in the app. `AMENAPPApp` declares `@State private var ageGateEligible = false` and `@AppStorage("hasCompletedAgeVerification")` but no `fullScreenCover` or conditional branch actually shows `AgeGateView`. The only COPPA enforcement is DOB entry inside `SignInView` during sign-up — a user can log in with an existing account from any device without encountering the gate |
| AccountSettingsView.swift:1139 | **Blocker** | Rate AMEN / App Store link | "Rate AMEN" uses `itms-apps://itunes.apple.com/app/id0000000000?action=write-review` — placeholder App Store ID `id0000000000` will silently do nothing. This will also cause App Review to flag it |
| AccountSettingsView.swift:1091, 1115 | High | Privacy / ToS URLs | `https://amenapp.com/terms` and `https://amenapp.com/privacy` return HTTP 000 (domain does not resolve). Both must be live before App Store submission. App Review will load these links |
| DeleteAccountView.swift:287–306, 303–307 | High | Account deletion — Google re-auth | Google Sign-In re-authentication flow shows a static text label ("Please sign in with Google again to confirm.") with no button and no `GIDSignIn.sharedInstance.signIn(...)` call. Google users tapping the confirmation sheet have no mechanism to re-authenticate, making account deletion impossible for Google-authenticated users |
| AccountDeletionService.swift:43–116 | High | Account deletion — subcollection gaps | `posts/{postId}/comments`, `posts/{postId}/likes`, `prayerRequests/{reqId}/intercessors`, `churchNotes/{id}/attachments` subcollections are not enumerated and not deleted. Nested subcollections under deleted root documents remain readable via direct path access and are not automatically cleaned up by Firestore |
| NotificationsSettingsView.swift:811–854 | High | Notification toggles | `saveNotificationSettings()` persists preferences to `users/{uid}.notificationSettings` in Firestore. However, there is no corresponding Cloud Function or backend code shown that reads this map and gates FCM delivery. Toggles write to Firestore but their effect on actual push delivery depends entirely on the server-side fan-out functions also checking these flags — confirm that `notificationsService.ts` (or equivalent) gates on these keys before considering this wired |
| NotificationSettingsView.swift (SettingsView row) | Med | Duplicate notification settings | `SettingsView` routes "Notifications" to `NotificationSettingsView` (dark glass style). `AccountSettingsView` routes its Notifications row to `NotificationsSettingsView` (a different file with a different UI). Two separate notification settings UIs exist; writes from one view are not observed by the other; user can configure different values in each and the last write wins |
| AMENAPPApp.swift:314–321 | Med | ATT timing | ATT `requestTrackingAuthorization` is fired inside an `.onAppear` Task, which runs on **every** cold launch immediately after the first frame renders. ATT best practice is to request only after the user has experienced meaningful app value (e.g., after onboarding). Current implementation shows the OS dialog on cold launch — immediately, on first open, before the user has engaged — which is the pattern Apple's App Review guidelines warn against and which lowers opt-in rates. This will not cause a rejection but is a significant user-experience and conversion issue |
| AccountSettingsView.swift:998–1019 | Med | Export My Data — stub | "Export My Data" button opens a pre-composed mailto: link to `privacy@amenapp.com`. This is a manual email request, not an automated data export. GDPR Article 20 and CCPA require a mechanism to provide a machine-readable copy of data. A mailto: stub satisfies neither. It also silently fails if no Mail app is configured |
| AccountSettingsView.swift:1022–1026 | Med | Clear App Cache — incomplete | `clearCache()` calls only `URLCache.shared.removeAllCachedResponses()`. It does not clear: Firestore offline persistence, Firebase Storage URLSession caches, `NSURLCache` for image loading (SDWebImage/Kingfisher), the in-memory caches in `ImageCache.swift`, or `BereanFastMode.swift`'s `memoryCache` |
| AccountSettingsView.swift:915, 931, 953, 976 | Med | Content preference toggles — persistence | `filterMatureContent`, `showFaithBasedSuggestions`, `autoPlayVideos` save to `users/{uid}/settings/contentPreferences` in Firestore. These are loaded on `.onAppear`. If Firestore is offline, changes are written to local cache but may not propagate — no error feedback is shown to the user on a failed save |
| AgeAssuranceService.swift:39–73 | Med | COPPA — migration path | Pre-existing users without a DOB on file are defaulted to `.teen` tier with `needsVerification = true`. The app is expected to "prompt for DOB on next session," but there is no UI gate that forces DOB entry before accessing the app for these migrated users. `needsVerification` is set but nothing in `ContentView` or `AMENAPPApp` blocks access on `needsVerification == true` |
| AccountSettingsView.swift:1290–1303 | Med | Sign-out — no authViewModel reference | The sign-out alert does not have access to `@EnvironmentObject var authViewModel: AuthenticationViewModel`. It uses raw `Auth.auth().signOut()`. The `authViewModel` environment object is not injected into `AccountSettingsView`. If `authViewModel.signOut()` is the intended path, the view must receive the environment object |
| AccountDeletionService.swift:197–233 | Low | Storage deletion — nested prefix depth | `deleteStorageFiles` only recurses one level deep (items → prefixes → nested items). If Storage paths have two or more levels of nesting (e.g. `post_media/{uid}/{groupId}/{thumbnails}/file.jpg`), the deepest files are missed |
| AccountSettingsView.swift:288–316 | Low | Date of Birth — read only | The DOB row shows birth year and tier but has a lock icon and no action. There is no UI path from AccountSettings to correct a wrong DOB. `AgeAssuranceService.requestAgeChange()` exists but is not surfaced anywhere in settings |
| AccountSettingsView.swift:64–122 | Low | Biometric toggle persistence | `BiometricSettingRow` reads/writes from `BiometricAuthService`. The persisted state backing (`isBiometricEnabled`) should be confirmed as Keychain-backed — if it is UserDefaults-backed it would be cleared by the account deletion `clearLocalState()` but also by an iCloud backup restore to a new device, which would silently re-enable biometric without the user's consent |
| DeleteAccountView.swift:165 | Low | Deletion confirmation screen — sign-out coupling | `AccountDeletedConfirmationView` calls `Auth.auth().signOut()` directly in the Done button, which again bypasses `AppLifecycleManager.performFullSignOutCleanup()`. After deletion the cleanup is less critical (the account is gone) but listener teardown and cache clearing should still happen to avoid residual state for the next user of the device |

---

## Not Fully Wired

### Settings Rows That Are Stubs or Incomplete

**"Export My Data"** (`AccountSettingsView.swift:998`)
- Opens a mailto: link. Not a real data export mechanism. Requires a Cloud Function to package and deliver user data.

**"Rate AMEN"** (`AccountSettingsView.swift:1139`)
- Hard-coded placeholder App Store ID (`id0000000000`). Link does nothing. Must be replaced with the real App Store ID before submission.

**"Clear App Cache"** (`AccountSettingsView.swift:1022`)
- Only clears `URLCache.shared`. Does not flush image caches, Firestore offline persistence, or AI response caches.

**Date of Birth row** (`AccountSettingsView.swift:288`)
- Read-only with no path to correct an incorrect DOB. `AgeAssuranceService.requestAgeChange()` is dead code from the UI perspective.

### Incomplete Deletion Flows

**Google re-authentication for account deletion** (`DeleteAccountView.swift:303`)
- `ReauthenticationSheet` shows a text label only for Google users. No `GIDSignIn.sharedInstance.signIn(...)` call. Google users cannot delete their account.

**Keychain not cleared on account deletion** (`AccountDeletionService.swift:277`)
- Comment `// Clear keychain if needed` is a stub. Any Keychain entries survive account deletion.

**Subcollection orphans** (`AccountDeletionService.swift:43`)
- `posts/{postId}/comments`, `posts/{postId}/likes`, `prayerRequests/{id}/intercessors`, and `churchNotes/{id}/attachments` subcollections are not walked and deleted. Nested subcollections under deleted top-level documents are NOT automatically deleted by Firestore.

**Content collection deletion truncated at 200** (`AccountDeletionService.swift:172`)
- `deleteDocumentsWhereField` has `.limit(to: 200)`. Power users with more than 200 posts, follows, or other content will have orphaned records.

### ATT — Not Wrong Timing, But Suboptimal

ATT fires on cold launch after first frame render (`AMENAPPApp.swift:314`), before any user value is delivered. The dialog should fire after onboarding or first meaningful action (e.g., after seeing the feed). Not an App Store rejection risk, but lowers opt-in rate.

### COPPA Age Gate — Not Gating the App

`AgeGateView` is defined but never presented. The `ageGateEligible` state declared in `AMENAPPApp` is never consumed to gate the UI. COPPA enforcement currently only occurs inside `SignInView` during sign-up (via `DateOfBirthCollectionView`). Existing returning users are not re-gated on new devices.

---

## Fix Recommendations

### Blocker Fixes

**1. Wire sign-out through `authViewModel.signOut()`**

`AccountSettingsView.swift:1290–1303`: inject `@EnvironmentObject var authViewModel: AuthenticationViewModel` and replace the alert action with `authViewModel.signOut()`.

```swift
// Before (line 1292–1296):
Button("Sign Out", role: .destructive) {
    Task {
        do { try Auth.auth().signOut() } catch { ... }
    }
}

// After:
Button("Sign Out", role: .destructive) {
    authViewModel.signOut()
}
```

**2. Implement Keychain clearing in `AccountDeletionService.clearLocalState()`**

Add `SecItemDelete` calls for all app Keychain items (emailForSignIn, biometric token, any stored credentials):

```swift
private func clearLocalState() {
    if let bundleId = Bundle.main.bundleIdentifier {
        UserDefaults.standard.removePersistentDomain(forName: bundleId)
    }
    let keychainAccounts = ["emailForSignIn", "biometricEnabled", "sessionToken"]
    for account in keychainAccounts {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

**3. Paginate `deleteDocumentsWhereField` beyond 200 documents**

Change the method to loop until all matching documents are deleted, mirroring the existing `deleteCollectionBatch` pagination pattern.

**4. Add Google re-auth button for account deletion**

In `ReauthenticationSheet` for `isGoogle == true`, add a real `GIDSignIn.sharedInstance.signIn(...)` button analogous to the Apple re-auth button already present.

**5. Present `AgeGateView` or enforce age gate on cold launch**

In `AMENAPPApp`, add a `fullScreenCover` gated on `!hasCompletedAgeVerification`:

```swift
.fullScreenCover(isPresented: Binding(
    get: { !hasCompletedAgeVerification },
    set: { _ in }
)) {
    AgeGateView(isEligible: $ageGateEligible)
}
```

Alternatively, wire `ageGateEligible` into `ContentView`'s routing so unauthenticated users see the gate before any other app content.

**6. Replace placeholder App Store ID**

`AccountSettingsView.swift:1139`: replace `id0000000000` with the real App Store numeric ID before submission.

**7. Delete post/prayer subcollections in `AccountDeletionService.deleteAccount()`**

After step 3 (user-authored content), walk and delete subcollections under those documents:

```swift
// After deleteDocumentsWhereField for "posts":
let postsSnap = try await db.collection("posts")
    .whereField("userId", isEqualTo: userId)
    .getDocuments()
for post in postsSnap.documents {
    try await deleteCollectionBatch(path: "posts/\(post.documentID)/comments")
    try await deleteCollectionBatch(path: "posts/\(post.documentID)/likes")
}
```

### High Priority Fixes

**8. Implement real Terms and Privacy Policy URLs**
Both `https://amenapp.com/terms` and `https://amenapp.com/privacy` must resolve before App Store submission. Deploy or redirect to existing legal pages.

**9. Verify notification toggle → FCM delivery chain**
Audit `functions/src/notifications*.ts` (or equivalent) to confirm that every fan-out function reads `users/{uid}.notificationSettings` and skips delivery when the relevant key is false. If not, add the check server-side. Document the complete end-to-end path.

**10. Consolidate duplicate notification settings UIs**
`SettingsView` → `NotificationSettingsView` and `AccountSettingsView` → `NotificationsSettingsView` are separate views writing to different Firestore paths. Merge into one canonical view and one canonical Firestore path (`users/{uid}/settings/notifications`).

### Medium Priority Fixes

**11. Surface DOB correction UI**
Add a NavigationLink on the DOB row in `AccountSettingsView` that opens `AgeVerificationOnboardingView` or a similar flow to correct a wrong date of birth.

**12. Gate on `needsVerification` in `ContentView`**
If `AgeAssuranceService.needsVerification == true`, show a DOB entry prompt before giving access to restricted features. Currently this flag is set but never acted on in the main navigation flow.

**13. Improve "Clear App Cache" scope**
Add `AgeAssuranceService.shared.clearCache()`, image cache clearing (via the app's `ImageCache`), and optionally `Firestore.firestore().clearPersistence()` (with a user-visible progress indicator, since this call can take 1–2 seconds).

**14. Delay ATT prompt past onboarding**
Gate `requestTrackingAuthorization` on `hasCompletedOnboarding == true` so the dialog appears after the user has seen value in the app, not on the first cold launch.

**15. Wire `AccountDeletedConfirmationView` "Done" button through lifecycle cleanup**
Replace `Auth.auth().signOut()` with `AppLifecycleManager.shared.performFullSignOutCleanup()` followed by `try? Auth.auth().signOut()`.

---

## Stress Test Script

1. **Sign-out hygiene**: Sign in as User A. Navigate to Account Settings → Sign Out. Immediately sign in as User B. Verify no posts, notifications, or profile data from User A appears anywhere in User B's session. Check badge count is 0. Check FCM token in Firestore is marked inactive for User A.

2. **Account deletion — email user**: Create a test account with email/password. Create 5+ posts, send 3 messages, follow 2 users. Navigate to Settings → Account Settings → Danger Zone → Delete Account. Enter password, confirm. Verify: Firestore `users/{uid}` document deleted; `posts` with `userId` deleted; `follows` deleted; Firebase Auth account deleted; Firebase Storage paths under `post_media/{uid}` empty.

3. **Account deletion — Google user**: Sign in with Google. Navigate to Delete Account. Verify the re-auth sheet shows a functional Google Sign-In button (not just text). Complete deletion.

4. **Account deletion — large content volume**: Create a test account with 250+ posts. Run deletion. Verify all 250+ posts are deleted (not just the first 200).

5. **COPPA gate bypass attempt**: On a fresh device install, skip age verification (if no `fullScreenCover` gate exists). Verify whether under-13 users can access the full app without providing a DOB.

6. **Notification toggle persistence**: Turn off "Amens" in Notifications Settings. Force-quit and reopen the app. Verify toggle is still off. Send an amen on a test post. Verify no push notification is received.

7. **Rate AMEN link**: Tap "Rate AMEN" in About section. Verify App Store opens to the correct app page (will fail until placeholder ID is replaced).

8. **Privacy and Terms links**: Tap "Privacy Policy" and "Terms of Service" in About section. Verify both load a real page (will fail until URLs are live).

9. **ATT dialog timing**: Fresh install → first launch. Record exactly when the ATT dialog appears. Should appear after onboarding completes, not before the user sees any app content.

10. **Keychain after deletion**: After account deletion, check Keychain (via a debug tool or instrument) for any remaining AMEN entries. Verify all are removed.

---

## Acceptance Criteria Checklist

- [ ] Sign-out from AccountSettingsView calls `authViewModel.signOut()` (not raw `Auth.auth().signOut()`)
- [ ] Account deletion clears Keychain entries
- [ ] Account deletion paginates through all user content (no 200-doc cap)
- [ ] Account deletion removes post/prayerRequest/churchNotes subcollections
- [ ] Google users can complete account deletion (real re-auth button present)
- [ ] `AgeGateView` is shown on first launch to all users; `ageGateEligible` gates app entry
- [ ] `https://amenapp.com/terms` returns HTTP 200 with real content
- [ ] `https://amenapp.com/privacy` returns HTTP 200 with real content
- [ ] "Rate AMEN" link uses real App Store ID (not `id0000000000`)
- [ ] Notification toggles in Firestore gate actual FCM push delivery server-side
- [ ] Duplicate `NotificationSettingsView` / `NotificationsSettingsView` consolidated
- [ ] ATT prompt fires after onboarding, not on cold launch
- [ ] "Export My Data" links to or triggers a real data package mechanism
- [ ] "Clear App Cache" clears image caches and Firestore offline persistence
- [ ] `needsVerification == true` from `AgeAssuranceService` triggers a DOB entry prompt
- [ ] Account deleted confirmation screen "Done" button invokes full lifecycle cleanup
