# Auto-Fix Changelog
Generated: 2026-06-16 | Branch: app-store-readiness-overnight

This file records all code changes applied automatically during the overnight audit pass.
No changes were deployed to production. All fixes are local Swift source edits.

---

## Applied Fixes (4 changes committed)

| ID | File | Change Summary | Why | Lane |
|---|---|---|---|---|
| A11Y-006 | AMENAPP/AMENAPP/AMENTabBar.swift | Added `.accessibilityValue` modifier to all 5 tab bar buttons to announce badge counts as "N unread" rather than only the tab label | VoiceOver users could not hear badge counts; the label alone says "Messages" with no indication of pending count | GREEN |
| PRIV-006 | AMENAPP/AMENAPP/AMENLogger.swift | Changed os_log format specifier from `%{public}@` to `%{private}@` for log message bodies | `%{public}@` makes values visible in Console.app even in production builds; log message bodies may contain PII such as user-authored content snippets | GREEN |
| SEC-003 | AMENAPP/AMENAPP/CloudFunctionsService.swift | Removed dead commented-out emulator `useEmulator` line | The commented line `// functions.useEmulator(withHost: "localhost", port: 5001)` created ambiguity about emulator state in production builds; removing it eliminates the confusion at zero functional cost | GREEN |
| SAFE-007 | AMENAPP/AMENAPP/PrivacySettingsView.swift | Wired `PermissionsCenterView` into the Capabilities Data & Context section of Privacy Settings | Users had no in-app path to discover or control the 10 AI consent edges (graphToBerean, messagesToPrayer, etc.); PermissionsCenterView existed but was unreachable; fix gates on existing `capabilitiesCoreEnabled` feature flag | GREEN |

---

## Deferred Items (47 GREEN findings — no code change needed)

| ID | Reason for Deferral |
|---|---|
| AUTH-001 | No action required — skipOnboarding() is a feature-sheet dismiss, not an auth bypass |
| AUTH-002 | No action required — COPPA age gate is correctly implemented with Keychain backing |
| AUTH-003 | No action required — account deletion is a full 10-step hard-delete pipeline |
| AUTH-005 | Verification task only (verify URLs are live before submission) — no code change needed |
| AUTH-007 | No action required — sign-out token revocation is comprehensive |
| AUTH-008 | No action required — no crash-risk force-unwraps in core auth ViewModel |
| AUTH-010 | No action required — 2FA bypass prevention is correctly implemented |
| AUTH-012 | No action required — AuthDebugView is correctly guarded by #if DEBUG |
| SAFE-001 | No action required — Report+Block is present on all core UGC surfaces |
| SAFE-004 | No action required — COPPA minor DM blocking is fail-closed; server-side verification is an ops task |
| SAFE-006 | No action required — moderation fails closed in production; DEBUG scheme check is an ops task |
| SAFE-009 | No action required — report/block infrastructure is robust |
| PRIV-002 | No action required — camera and contacts usage descriptions are AMEN-specific |
| PRIV-003 | No action required — PrivacyInfo.xcprivacy is complete |
| PRIV-004 | No action required — ATT is correctly implemented |
| PRIV-008 | No action required for consent infrastructure — pre-login surfacing gaps are addressed by PRIV-005/007 which are P1 human tasks |
| FIRE-001 | No action required — Firestore global default-deny catch-all is present |
| FIRE-002 | Low-priority architectural suggestion to move PII to /private/ subcollection — not a minimal reversible fix |
| FIRE-004 | No action required — DMs are private between sender/receiver only |
| FIRE-005 | No action required — moderation/admin collections are admin-only |
| FIRE-006 | No action required — reports are write-by-reporter and read-by-admin-only |
| FIRE-007 | No action required — counter/trust/entitlement fields are backend-only write |
| FIRE-011 | No action required — no callables trust request.data.uid as identity |
| FIRE-012 | No action required — auth checks are present on all user-facing callables |
| FIRE-014 | No action required — no hardcoded admin UIDs exist |
| FIRE-015 | No action required — no prayer content or PII is logged to Cloud Logging |
| FIRE-017 | No action required — payload validation is present on all callables |
| FIRE-018 | No action required — Storage default-deny catch-all is present |
| FIRE-019 | No action required — cross-user Storage path overwrite is not possible |
| FIRE-024 | No action required — NCMEC/legal collections completely deny all client access |
| BTN-010 | No action required — destructive delete flows have proper confirmation dialogs |
| BTN-011 | No action required — most sheets have explicit dismiss paths |
| BTN-012 | No action required — Features directory has zero TODO/FIXME/print stubs |
| A11Y-007 | No action required — GlassMaterial correctly handles Reduce Transparency |
| PERF-003 | No action required — CommentsView and UnifiedChatView cancel tasks correctly on disappear |
| PERF-004 | No action required — majority of Firestore snapshot listeners correctly store and remove ListenerRegistration |
| PERF-007 | No action required — assertionFailure in GlobalResilienceWiring is correctly guarded |
| PERF-008 | No action required — assertionFailure in FirebasePostService is wrapped in #if DEBUG |
| PERF-011 | No action required — as! force-cast in camera preview views is safe by design |
| PERF-015 | No action required — Combine .sink closures broadly use [weak self] |
| PERF-016 | Future improvement suggestion (add cleanup/endSession cancellation) — not a minimal reversible fix for this sweep |
| SEC-002 | No action required — bypassAuthForTesting() is correctly guarded by #if DEBUG |
| SEC-004 | No action required — aps-environment is set to production in both entitlements files |
| SEC-005 | No action required — NSAllowsArbitraryLoads is absent and ATS is fully enforced |
| SEC-009 | Verification task only (verify xcconfig files are not committed) — no code change needed |
| SEC-011 | No action required — no hardcoded API keys in Backend TypeScript source |
| SEC-012 | No action required — GroupAdminView isAdmin mutation is a legitimate local state update |

---

## Not Applied — Human or Legal Gate Required (see HUMAN_GATE_QUEUE.md)

| ID | Reason Not Auto-Fixed |
|---|---|
| BTN-001 | Requires wiring AmenSpaceEntitlementService + Firestore membership write; too large for automated fix; needs E2E test |
| BTN-002 | 26 stubs require individual backend wiring decisions; some (Give Now) require Stripe integration |
| BTN-003 | Straightforward code fix but requires confirming VisitVerificationService Firestore contract |
| BTN-004 | Requires PDFKit wrapper redesign |
| SAFE-002 | Requires adding context-menu + ModerationService wiring to 3 views |
| SAFE-003 | Requires backend hash-scan deployment decision |
| SAFE-005 | Requires DiscoveryService + AMENDiscoveryView changes |
| SAFE-010 | Requires T&S Lead escalation on OPEN-2 before code change |
| AUTH-004 | Requires Google Sign-In SDK integration |
| AUTH-006 | Legal gate — requires counsel to confirm live URLs |
| AUTH-009 | Requires ReauthenticationSheet integration in AccountRecoveryView |
| AUTH-013 | Legal/backend gate — requires server-side scheduled job verification |
| PRIV-001 | Info.plist edit — straightforward but requires Xcode build validation |
| PRIV-005 | Requires first-run consent sheet design decision |
| PRIV-007 | Requires full privacy policy text accessible in a pre-login sheet |
| FIRE-010 | Backend CF code change; requires deploy |
| PERF-006 | MessageOutbox requires SwiftData fallback strategy decision |
| SEC-006 | Info.plist edit — requires encryption compliance decision (true vs false) |
| A11Y-002 | LiquidGlassModifiers change affects hundreds of call sites; needs visual QA |
| A11Y-003 | LiquidGlassAnimations change requires spring parameter audit |
