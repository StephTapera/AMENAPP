# NOTIF-02 — onOpenURL runs handlers without early-return guards

- **Flow:** Deep links / notification open
- **File:** `AMENAPPApp.swift:~431-471` (onOpenURL)
- **Severity:** broken-flow
- **Scope:** IN-SCOPE
- **Status:** OPEN (static, not runtime-verified) — medium confidence

**Expected:** Once a URL is claimed by a handler (email auth, note share, church note, live activity, coordinator), later handlers are skipped.
**Actual:** Handlers run sequentially with no `return` after a successful claim, so a single URL can be processed by more than one handler.

**Static repro:** No `if handled { return }` between the chained handler calls in the onOpenURL block.

**Suspected fix:** Make each handler return a `Bool` (handled) and early-return after the first that claims the URL, preserving the existing priority order (Firebase Auth → Google → coordinator → legacy).
