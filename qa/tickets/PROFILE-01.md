# PROFILE-01 — Reformatted bio URL may not be the value saved

- **Flow:** Profile edit → save
- **File:** `ProfileView.swift:~4039`
- **Severity:** logic-bug
- **Scope:** IN-SCOPE
- **Status:** OPEN (static, not runtime-verified) — medium confidence

**Expected:** The validated/normalized bio URL (prefixed with `https://`) is the value written to Firestore.
**Actual:** The URL is reformatted with `https://` during validation, but the `updateData` dictionary appears to use the original input rather than the reformatted value, so the normalized form may be lost.

**Static repro:** Compare the reformatted local value vs the field placed into the update dictionary.

**Suspected fix:** Persist the reformatted `bioURL` consistently — assign the normalized value back to state before building `updateData`.
