# PROFILE-02 — Edit-profile error path dismisses instead of letting user retry

- **Flow:** Profile edit → save (error)
- **File:** `ProfileView.swift:~4115`
- **Severity:** visual / UX
- **Scope:** IN-SCOPE
- **Status:** OPEN (static, not runtime-verified) — low confidence

**Expected:** On save failure, the editor stays open so the user can retry.
**Actual:** `dismiss()` is reached on the error path as well as success, so a failed save can close the editor without re-offering save.

**Suspected fix:** Only `dismiss()` on success; on error keep the sheet and show a retry affordance.
