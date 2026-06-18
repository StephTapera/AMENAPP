# SIGNOUT-01 — signOut error path leaves app authenticated

- **Flow:** Sign out (Settings → signOut)
- **File:** `AuthenticationViewModel.swift:~1015`
- **Severity:** broken-flow
- **Scope:** IN-SCOPE
- **Status:** FIXED (Tier-1) — build GREEN 2026-06-17 (0 errors); runtime verify still pending

**Expected:** If `Auth.auth().signOut()` throws, the app still resolves to a signed-out UI state.
**Actual:** On throw, `errorMessage` is set but `isAuthenticated` is not set to `false`, so the user can be shown an error while remaining on Settings (inconsistent state).

**Static repro:** Inspect the `catch` branch of `signOut()` — `isAuthenticated = false` only on the success path.

**Suspected fix:** Set `isAuthenticated = false` in both success and error paths (or in a `defer`), so local sign-out always completes even if the Firebase call fails.
