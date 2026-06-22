# AMEN Community OS — Phase 0 Contracts

**Version:** 0.1.0-contracts
**Frozen:** 2026-06-05
**Status:** AWAITING HUMAN SIGN-OFF

---

## Contracts in this version

| Contract | File | Status |
|----------|------|--------|
| C1 — Universal object model + graph schema | `contracts/C1-object-model.md` | COMPLETE |
| C2 — Intent set + transform matrix | `contracts/C2-intent-taxonomy.md` | COMPLETE |
| C3 — White Liquid Glass token system | `contracts/C3-design-tokens.md` | LOCKED |
| C4 — Cloud Function signatures | `contracts/C4-cf-signatures.md` | COMPLETE |
| C5 — Security rules skeleton + RBAC matrix | `contracts/C5-security-rules.md` | COMPLETE |
| C6 — Navigation contract + deep-link scheme | `contracts/C6-navigation.md` | **FROZEN 2026-06-05** |

---

## Decision Register — OPEN (human sign-off required before unfreeze)

1. **Graph cost ceiling** — max edge fan-out per write before denormalize vs. queue async
2. **Minor age gate** — confirm age threshold and guardian tool scope for v1
3. **NCMEC integration timing** — human authorization required before pipeline activates
4. **Anonymous prayer / identity shielding scope** — how far identity shielding goes for public objects

---

## Design Direction — LOCKED

White Liquid Glass (Apple Photos / Mail). No dark theme, no gold, no purple, no Cormorant
Garamond. See C3 for complete token spec.

---

## Unfreeze conditions

All four Decision Register questions answered + human sign-off on this document.

Once unfrozen, Phase 1 agents may begin. No Phase 1–6 code merges until unfrozen.

---

## Appendix — Known navigation issues discovered during C6 audit

These are pre-existing bugs flagged during Phase 0 survey. They do not block contract
sign-off but must be resolved before Phase 1 code is merged.

| ID | Severity | Description | File |
|----|----------|-------------|------|
| NAV-01 | High | `DeepLinkRouter` routes `.settings` to `selectedTab = 4` (Notifications) instead of `selectedTab = 5` (Profile) | `AMENAPP/DeepLinkRouter.swift:157` |
| NAV-02 | Medium | `amen://` and `amenapp://` are parallel deep-link schemes with independent parsers; risk of routing divergence | `DeepLinkRouter.swift`, `NotificationDeepLinkRouter.swift` |
| NAV-03 | Medium | `ONENavigationShell` (iOS 26 only) is not yet wired to any `ContentView` tab index | `AMENAPP/AMENAPP/ONE/Navigation/ONENavigationShell.swift` |
| NAV-04 | Low | `UserProfileView` is presented as sheet in `NavigationHelpers.swift` but push navigation in other paths; inconsistent back behavior | `AMENAPP/NavigationHelpers.swift` |
