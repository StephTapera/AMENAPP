# POST-01 — "Discard Post" does not clear the auto-saved draft

- **Flow:** Post composer → discard
- **File:** `CreatePostView.swift:~797-800`
- **Severity:** broken-flow
- **Scope:** IN-SCOPE
- **Status:** FIXED (Tier-1) — build GREEN 2026-06-17 (0 errors); runtime verify still pending

**Expected:** Tapping "Discard Post" in the confirmation dialog clears the auto-saved draft.
**Actual:** Handler sets `shouldPersistDraftOnExit = false` and calls `dismiss()` but never calls `clearRecoveredDraft()` / removes the `autoSavedDraft` UserDefaults key — so the discarded draft re-appears as a recovery prompt on next launch.

**Static repro:** The discard button action block has no draft-clear call; auto-save key persists.

**Suspected fix:** Call `clearRecoveredDraft()` (or `UserDefaults.standard.removeObject(forKey: "autoSavedDraft")`) inside the Discard handler before `dismiss()`.
