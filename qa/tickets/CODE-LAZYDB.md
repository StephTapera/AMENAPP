# CODE-LAZYDB — `lazy var db = Firestore.firestore()` inside async functions

- **Flow:** Auth (SignInView) + deep-link content existence check
- **Files:** `SignInView.swift:~1088, ~1128`; `NotificationDeepLinkRouter.swift:~385`
- **Severity:** broken-flow / code-quality (explorers flagged crash-risk; assessed lower — Firestore handle is a singleton)
- **Scope:** IN-SCOPE
- **Status:** FIXED (Tier-1) — all 3 sites converted; build GREEN 2026-06-17

**Expected:** A simple `let db = Firestore.firestore()` local — `firestore()` is a cheap singleton accessor.
**Actual:** Declared `lazy var` inside async function bodies. Not a confirmed crash, but `lazy var` locals across suspension points are an unnecessary smell and harder to reason about.

**Suspected fix:** Replace `lazy var db` with `let db = Firestore.firestore()` at each site.
