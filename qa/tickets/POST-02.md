# POST-02 — Redundant `shouldPersistDraftOnExit = false` (dead code)

- **Flow:** Post composer → back/cancel
- **File:** `CreatePostView.swift:~2320-2325`
- **Severity:** visual / code-quality
- **Scope:** IN-SCOPE
- **Status:** FIXED (Tier-1) — hoisted shared assignment (NOT the ticket's "delete else", which would regress); build GREEN 2026-06-17

**Expected:** Branch sets persistence flag only where it changes behavior.
**Actual:** Both the has-content and no-content branches set `shouldPersistDraftOnExit = false`, making the conditional meaningless (no functional bug, but confusing).

**Suspected fix:** Remove the redundant assignment in the else branch (relies on the `@State` default).
