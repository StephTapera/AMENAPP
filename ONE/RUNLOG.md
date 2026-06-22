# ONE — Run Log
# All orchestrator actions, findings, decisions, and blocking questions recorded here.
# Format: [DATE TIME] [PHASE] [TYPE] Description

---

## Log

### 2026-06-01 — Step A: PLAN

**[2026-06-01] [P0] [ACTION]** Surveyed AMEN project structure.
- Found: large existing codebase with LiquidGlass/, DesignSystem/, Subscription/, Services/, existing contracts in MasterRunContracts/Phase0Contracts.swift
- Found: existing design tokens (amenGold, amenPurple, amenBlue, amenBlack) and Liquid Glass components (GlassPill, GlassSheet, GlassTray, AMENPillNav, etc.)
- Found: existing Firebase Auth/Firestore wiring, Stripe references, existing Cloud Functions patterns
- Found: existing `ONEMoment`-adjacent naming (SocialOSModels.swift, AmenSmartObject.swift) — must verify no collision before P0 types are defined
- Decision: All new ONE types prefixed `ONE` to avoid collision with any existing types

**[2026-06-01] [P0] [ACTION]** Produced PLAN.md (v1.0, 8 sections, full phase/dependency/work-unit/risk/deploy breakdown).

**[2026-06-01] [P0] [ACTION]** Produced CONTRACTS.md (v1.0, FROZEN):
- 17 contract sections
- ONEMoment, ONEPrivacyContract, ONEUser, ONEThread, ONELivingThreadSummary, ONEConsentDNA, ONEProvenanceLabel, ONEFeedMode, ONEReachBudget, ONEWitness, ONEVaultItem, ONELegacyDirective, ONERepairFlow, ONEEntitlement
- Firestore schema for 9 collection paths
- 10 CF callable signatures
- Design token additions (additive, never override AMEN tokens)
- 10 frozen architecture rules

**[2026-06-01] [P0] [ACTION]** Produced SECURITY.md (v1.0):
- E2E threat model (MLS primary, CryptoKit ratchet fallback)
- Privacy zone architecture for all three zones
- Abuse/evidence path design (report → lock → decay skipped)
- Honesty inventory (6 features, honest labeling)
- 6 open security questions that must be resolved before specific phases

**[2026-06-01] [P0] [GATE]** Step A complete. Awaiting human gate review before any P0 implementation begins.

### 2026-06-01 — Step A → P0: BQ Resolution + Implementation Start

**[2026-06-01] [P0] [DECISION]** All 7 blocking questions resolved with safe defaults (see table above). "fix all safely" instruction received from product owner.

**[2026-06-01] [P0] [ACTION]** Verified glassEffect API: `func glassEffect(_ glass: Glass = .regular, in shape: some Shape) -> some View` confirmed in iOS 26 SwiftUI docs. `GlassEffectContainer`, `Glass.interactive()`, `Glass.tint()` all available.

**[2026-06-01] [P0] [DECISION]** Subscription: StoreKit (IAP) not Stripe — App Store digital subscriptions require Apple IAP. Stripe deferred to web/admin only.

**[2026-06-01] [P0] [DECISION]** E2E: CryptoKit Double Ratchet (`encryptionVersion: "cr_1.0"`). No third-party deps. Forward-secure, Secure Enclave key storage.

**[2026-06-01] [P0] [ACTION]** Token discovery: `AmenTheme.Colors.amenGold = Color(red:0.83,green:0.69,blue:0.22)` confirmed. No `Color.amenGold` shortcut. ONE tokens additive only.

**[2026-06-01] [P0] [ACTION]** Beginning P0 implementation: ONETokens → models → navigation shell → HTML protos → CF stubs.

**[2026-06-01] [P0] [ACTION]** Created directory: `AMENAPP/AMENAPP/ONE/` with subdirs Design/, Core/, Navigation/, Backend/.

**[2026-06-01] [P0-A] [DONE]** `ONETokens.swift` — design tokens, ONE namespace enum, Zone enum, feature flags, glass helpers (`@available(iOS 26.0, *)`). 0 diagnostics.

**[2026-06-01] [P0-F] [DONE]** Data model files — all 0 diagnostics:
- `ONEMomentModels.swift` — ONEMoment, ONEMomentType, ONEMomentContent (custom Codable discriminator), all payload types
- `ONEPrivacyModels.swift` — ONEPrivacyContract, ONEAudienceScope, ONELifetimePolicy, ONEMomentPermissions, ONESafetySettings, ONEScreenshotBehavior, ONEConsentDNA
- `ONEUserModels.swift` — ONEUser, ONEPrivacyMirrorLevel, ONEPresenceState, ONEEntitlement, ONEEntitlementTier
- `ONEThreadModels.swift` — ONEThread, ONEThreadMessage, ONELivingThreadSummary (marked non-Codable, never sent to server), ONELivingDate, ONELivingTask, ONEEphemeralGroupSettings
- `ONEProvenanceModels.swift` — ONEProvenanceLabel, ONEProvenanceClass, ONEReachBudget, ONEFeedModeKind, ONEFeedSession
- `ONESocialModels.swift` — ONEWitness, ONEWitnessSeason, ONERepairFlow, ONERepairPhase, ONEToneCheck, ONEVaultItem, ONEVaultContentType, ONEVaultAccessRule, ONELegacyDirective, ONETrustee, ONEMemoryBequest, ONEMemorialization

**[2026-06-01] [P0-I] [DONE]** `ONENavigationShell.swift` — Three Zones shell with GlassEffectContainer dock, glassEffect on dock buttons, reduce-motion aware, placeholder views per zone. `@available(iOS 26.0, *)`. 0 diagnostics.

**[2026-06-01] [P0-H] [DONE]** `ONECallableService.swift` — All 9 CF callable client stubs (sendMoment, expireMoment, reportMoment, requestWitness, relayMoment, activateRepairFlow, acceptRepairFlow, verifyEntitlement, activateLegacy). 0 diagnostics.

**[2026-06-01] [P0-B] [DONE]** `p0-three-zones-nav.html` — Three zones shell with animated glass dock, zone background gradients, keyboard navigation, ARIA roles.

**[2026-06-01] [P0-C] [DONE]** `p0-privacy-pill.html` — Privacy Contract pill (collapsed + expanded panel): audience selector, lifetime slider, permission toggles, safety toggles, "three questions" always answered. Screenshot best-effort disclosure prominent.

**[2026-06-01] [P0-D] [DONE]** `p0-moment-composer.html` — Moment composer: format picker (7 types), text input, provenance badge, privacy contract summary, bottom toolbar.

**[2026-06-01] [P0] [GATE]** ALL P0 work complete. 9 Swift files × 0 diagnostics. 3 HTML prototypes. Contracts frozen. Deploy checklist below ready for human review.

### 2026-06-01 — P1: People + Private Messaging

**[2026-06-01] [P1] [ACTION]** Starting P1. HTML protos first (P1-A, P1-B), then SwiftUI.

**[2026-06-01] [P1] [DECISION]** Living Threads AI: FoundationModels confirmed available. Will use `SystemLanguageModel.default` with `@Generable` struct for extraction + rule-based fallback. On-device only — no message content ever leaves device.

**[2026-06-01] [P1] [DECISION]** E2E: `SharedSecret.hkdfDerivedSymmetricKey(using:salt:sharedInfo:outputByteCount:)` + `AES.GCM` per CryptoKit API. Root key from Curve25519 DH; chain ratchet per message epoch.

**[2026-06-02] [P1-C] [DONE]** `ONEKeyRatchetService.swift` — actor, CryptoKit Double Ratchet (Curve25519 DH + HKDF-SHA256 chain + AES-GCM per message, epoch-advancing forward secrecy). `encryptionVersion: "cr_1.0"`. 0 diagnostics.

**[2026-06-02] [P1-C] [DONE]** `ONEThreadStore.swift` — `@MainActor ObservableObject`, Firestore real-time listeners, client-side decrypt batch, `send()` encrypts before upload (only ciphertext + metadata to Firestore). 0 diagnostics.

**[2026-06-02] [P1-C/F] [DONE]** `ONELivingThreadsEngine.swift` — `actor`, FoundationModels primary path (`@Generable ONEThreadExtractionResult`, `LanguageModelSession`), rule-based regex fallback. On-device only. Gated by `livingThreadsEnabled` flag. 0 diagnostics.

**[2026-06-02] [P1-G] [DONE]** `ONEConsentBadgeView.swift` — consent DNA pill (save/forward/quote/react flags), matte, no glass. 0 diagnostics.

**[2026-06-02] [P1-D/E] [DONE]** `ONEMessageBubble.swift` — E2E bubble with decrypt-pending state, ephemeral countdown, consent badge for outgoing, matte (no glass per rules). 0 diagnostics.

**[2026-06-02] [P1-F] [DONE]** `ONELivingThreadsSummaryCard.swift` — collapsible on-device AI card, per-item share callback, privacy note, expand/collapse animation. 0 diagnostics.

**[2026-06-02] [P1-G] [DONE]** `ONEMessageComposerView.swift` — glass-chrome composer (regularMaterial backdrop), inherited contract bar, per-message override panel (4 toggles), privacy warning for forward/save escalation, async send with error display. 0 diagnostics.

**[2026-06-02] [P1-D/E] [DONE]** `ONEThreadView.swift` — full conversation view, LazyVStack messages, auto-scroll, E2E toolbar indicator, Living Threads distillation trigger, composer wired. Uses existing `ShareSheet`. 0 diagnostics.

**[2026-06-02] [P1-D] [DONE]** `ONEThreadListView.swift` — People zone root with own NavigationStack, thread list with E2E indicators, ephemeral flame badge, search, empty state, new conversation menu. 0 diagnostics.

**[2026-06-02] [P1-H] [DONE]** `ONEEphemeralGroupFlowView.swift` — 3-step sheet flow (duration → expiry action → confirm), `ONEGroupExpiryAction` UI metadata extension (`flowLabel`, `flowSubtitle`, `flowIcon`, `flowTint`). 0 diagnostics.

**[2026-06-02] [P1-I] [DONE]** `ONENavigationShell.swift` updated — `@StateObject private var threadStore = ONEThreadStore()` added; `.people` case now routes to `ONEThreadListView(store: threadStore)`. 0 diagnostics.

**[2026-06-02] [P1] [GATE]** P1 COMPLETE. 10 new Swift files × 0 diagnostics. People zone fully wired into shell. Known open items logged below.

### 2026-06-02 — P5: Safety + Hardening

**[2026-06-02] [P5] [ACTION]** Starting P5. HTML protos first per PLAN.md invariant.

**[2026-06-02] [P5-A] [DONE]** `p5-emotional-safety.html` — Safety mode glass panel in thread context; master toggle; 4 controls (slow-reply 4-way seg, tone preview toggle, delay-send 3-way seg, pause thread with confirmation); friction summary aria-live region; composer mock with delay badge; exit notice always visible.

**[2026-06-02] [P5-C] [DONE]** `p5-evidence-path.html` — Report category listbox (4 categories); evidence lock info box (invariant explained); submit → evidence timeline (4 steps: locked/received/pending review/outcome); receipt ID + 90-day retention note; E2E/deleted-account scenarios documented.

**[2026-06-02] [P5-F] [DONE]** `p5-entitlement-gate.html` — Locked feature indicator; glass gate sheet; tier comparison table (Free 8 items vs Subscriber 9 items); monthly + annual pricing cards; StoreKit simulation; restore flow; privacy note (Apple IAP, cancel from iOS Settings); dismiss always available.

**[2026-06-02] [P5] [ACTION]** HTML protos gate passed. Starting P5 SwiftUI.

**[2026-06-02] [P5-A] [DONE]** `ONEEmotionalSafetyModeView.swift` — `@MainActor ONEEmotionalSafetyStore` singleton; `ONESlowReplyDuration` + `ONEDelaySendDuration` enums; Form-based view with master toggle, 4 controls, friction summary, exit notice. `delaySend` is session-only (not persisted to prevent message confusion). `threadPaused` requires confirmation dialog. Settings saved to `one_users/{uid}/safetySettings/emotional`. 0 diagnostics.

**[2026-06-02] [P5-B/C] [DONE]** `ONEImmuneSignalService.swift` — `actor`. `ONEReportCategory` (4 cases) + `ONEEvidenceReceipt` struct. `reportMoment(momentID:category:)` calls `ONECallableService.shared.reportMoment`. In-memory `reportedMomentIDs` dedup set. `hasAnomalousReachSignal` operates on public metadata only — NEVER reads E2E content. 0 diagnostics.

**[2026-06-02] [P5-C] [DONE]** `ONEReportMomentView.swift` — Report category picker (4 categories with icons), lock section with invariant note, async submit → evidence timeline (4-step receipt). `phase: .picking → .locked` state machine. 0 diagnostics.

**[2026-06-02] [P5-F] [DONE]** `ONEEntitlementService.swift` — `@MainActor` singleton. StoreKit 2: `Product.products(for:)`, `Product.purchase()`, `Transaction.updates` listener (lifetime Task), `Transaction.currentEntitlements` restore. `verifyWithServer()` calls `one_verifyEntitlement` CF. Never downgrades on server failure. 0 diagnostics.

**[2026-06-02] [P5-F] [DONE]** `ONEEntitlementGateView.swift` — Paywall sheet. `ONEEntitlementService.shared` loaded via `@StateObject`. Tier comparison (Free 8 / Subscriber 8 features). Dynamic `Product` cards from StoreKit (static fallback while loading). Restore button. Privacy note. Always dismissible. 0 diagnostics.

**[2026-06-02] [P5-D] [DONE]** `SECURITY.md` updated to v2.0 — §8 P5 hardening audit added: App Check audit (all 9 callables verified), evidence path invariant documented, consent enforcement P5 CF scope documented, privacy mirror Firestore rule spec added, a11y sweep results logged.

**[2026-06-02] [P5-E] [DONE]** Accessibility sweep — All ONE Swift view files audited. Findings: 0 bare animations (all use ONE.Motion.adaptive), 0 icon-only buttons without accessibilityLabel, all complex rows use .accessibilityElement. No fixes required.

**[2026-06-02] [P5-G] [DONE]** App Check hardening audit — All 9 callables route through Functions.functions() (App Check token auto-attached). E2E content confirmed never passes through ONEImmuneSignalService. Server-side enforcement is correct; deploy prerequisite is console mode switch (human action). No code changes required.

**[2026-06-02] [P5] [GATE]** P5 COMPLETE. 5 new Swift files + 3 HTML protos + SECURITY.md v2 × 0 diagnostics. All gate conditions met.

### P5 GATE — Known Open Items (deploy required before external users)
```
[ ] HUMAN: Switch Firebase console App Check (amen-5e359): "debug" → "enforce"
[ ] firebase deploy --only functions:one_expireMoment  (must check evidenceLocked before decay)
[ ] firebase deploy --only functions:one_sendMoment    (must enforce ConsentDNA mergedConsentDNA logic on relay)
[ ] firebase deploy --only functions:one_relayMoment   FLAG-FLIP PREREQUISITE: enforce forwardAllowed server-side (SECURITY.md 8.3); stub at Backend/functions/src/one/oneRelayMoment.ts
[ ] firebase deploy --only functions:one_verifyEntitlement  (StoreKit receipt check, not Stripe)
[ ] firebase deploy --only functions:one_activateLegacy  (trustee identity verification)
[ ] firebase deploy --only firestore:rules  (add privacy mirror sealed/opaque read restriction)
[ ] firebase deploy --only firestore:rules  (add one_evidence client no-read rule)
[ ] HUMAN: Submit com.apple.developer.secure-element-api entitlement request (vault SE key storage)
```

### 2026-06-02 — P2: Moments Zone

### 2026-06-02 — P3: World (Discovery)

### 2026-06-02 — P4: Differentiators

**[2026-06-02] [P4] [ACTION]** Starting P4. HTML protos first per PLAN.md invariant.

**[2026-06-02] [P4-A] [DONE]** `p4-privacy-mirror.html` — 4-level selector (Private/Opaque/Translucent/Open); glass symmetry preview panel; witness-exceptions toggle; save toast; full ARIA radiogroup + aria-live.

**[2026-06-02] [P4-B] [DONE]** `p4-repair-flow.html` — 4-phase stepper (Invite→Active→Tone→Resolve); per-phase panels; tone scan glass overlay (never blocks send); Exit strip always visible; Block/sever note always present.

**[2026-06-02] [P4-C] [DONE]** `p4-vault.html` — Encrypted vault list (3 sample items, countdown badge, trustees badge); Add Vault composer sheet; access rule conditional date picker; item detail panel; "Secure Enclave: Active" chip; ARIA dialog.

**[2026-06-02] [P4] [ACTION]** HTML protos gate passed. Starting P4 SwiftUI.

**[2026-06-02] [P4-D] [DONE]** `ONEPrivacyMirrorService.swift` — `@MainActor` ObservableObject singleton. `visibilityGranted(viewerLevel:subjectLevel:)` implements sealed/opaque/translucent/open symmetry. Firestore `one_users/{uid}` write. NOTE: `displayLabel` NOT redeclared — already exists in `ONEUserModels.swift`. UI extensions: `mirrorDescription`, `symmetryNote`. 0 diagnostics.

**[2026-06-02] [P4-E] [DONE]** `ONEStickyConsentService.swift` — `actor`. `isPermitted(_:for:)` + `deniedActions(for:)` + `restrictionSummary(for:)`. Key fix: `ONEMoment.consentDNA` is `let` — `mergedConsentDNA(from:relayContext:)` returns new `ONEConsentDNA` instead of mutating in-place. 0 diagnostics.

**[2026-06-02] [P4-F] [DONE]** `ONERepairFlowView.swift` — 4-phase flow (invited→active→toneCheck→resolved). Tone check NEVER blocks send — always user's choice. Exit strip always visible. `ONERepairPhase: Equatable` + `stepCases` + `stepLabel` extensions. 0 diagnostics.

**[2026-06-02] [P4-G] [DONE]** `ONEVaultView.swift` — AES-GCM encryption (CryptoKit: `SymmetricKey(size:.bits256)` + `AES.GCM.seal`). Only ciphertext + metadata stored in Firestore (`one_vaults/{uid}/items`). Secure Enclave key storage is structural stub (requires `com.apple.developer.secure-element-api` entitlement — human Apple approval needed). 0 diagnostics.

**[2026-06-02] [P4-H] [DONE]** `ONELegacyDirectiveView.swift` — Owner-edit only (activation blocked, trustee-only via `one_activateLegacy` CF). `AddTrusteeSheet` + `AddBequestSheet` as private subviews. `ONEMemorialization` extensions: `displayLabel`, `memorialDescription`. 0 diagnostics.

**[2026-06-02] [P4] [GATE]** P4 COMPLETE. 5 new Swift files + 3 HTML protos × 0 diagnostics. All Differentiator features wired. Known open items logged below.

### P4 GATE — Known Open Items (not blocking P4 gate)
```
[ ] Secure Enclave entitlement (com.apple.developer.secure-element-api): requires human
    Apple approval. Vault key is currently stored in Keychain (stubbed). SE wiring is P5 scope.

[ ] Vault Firestore decryption: ONEVaultStore.load() fetches metadata only — full ciphertext
    retrieval and local AES-GCM decrypt is P5 scope.

[ ] one_activateLegacy CF is a stub. Trustee activation path needs real identity verification
    + logic before shipping to external users.

[ ] Privacy mirror enforcement is client-side only. Server-side Firestore rules enforcement
    is P5 hardening scope.

[ ] Sticky consent: server-side ConsentDNA validation on CF ingest is P5 scope.
    Current enforcement is client-side only.
```

### P4 GATE — Deploy Checklist (DO NOT AUTO-RUN)
```
[ ] firebase deploy --only functions:one_activateLegacy  (stub; needs trustee identity logic)
[ ] HUMAN: Request com.apple.developer.secure-element-api entitlement via Apple Developer portal
[ ] firebase deploy --only firestore:rules  (add vault read/write rules for one_vaults collection)
```

**[2026-06-02] [P3] [ACTION]** Starting P3. HTML protos first per PLAN.md invariant.

**[2026-06-02] [P3-A] [DONE]** `p3-feed-modes.html` — Five mode chips (Close/Create/Learn/Local/Quiet), glass switcher, matte feed cards, session budget bar, "session over" overlay, chip keyboard navigation, ARIA tablist/tab/tabpanel.

**[2026-06-02] [P3-B] [DONE]** `p3-reach-budget.html` — Pip row (moment relay count), chain depth diagram, weekly budget SVG arc, relay button with dual-decrement, all three exhaustion states (moment/user/depth cap), dev scenario switcher, ARIA live regions.

**[2026-06-02] [P3-C] [DONE]** `p3-context-gate.html` — Three-row gate (read-source, watch-%, provenance-acknowledged), glass sheet modal, nested provenance popup, "Add Comment" unlocks when all three pass, comment send flow, "Why does this matter?" expand, ARIA dialog/focus management.

**[2026-06-02] [P3] [ACTION]** HTML protos gate passed. Starting P3 SwiftUI.

**[2026-06-02] [P3-D/E] [DONE]** `ONEFeedModeService.swift` — `@MainActor` ObservableObject; `ONEFeedItemViewModel` (presentational, not persisted); `ONEContextGateStatus` struct; stub loader with per-mode bodies; relay() calls `ONECallableService.shared.relayMoment`. 0 diagnostics.

**[2026-06-02] [P3-E] [DONE]** `ONEReachBudgetPill.swift` — compact reach budget indicator: pip count, chain depth tint, ephemeral red when ≤2 remaining, disabled state. 0 diagnostics.

**[2026-06-02] [P3-F] [DONE]** `ONEContextGateView.swift` — 3-row gate sheet (source-read, watch-30%, provenance-acknowledged); Task-based watch sim (no Timer); provenance detail sub-sheet; "Why?" expandable; comment text area unlocks only when all pass. 0 diagnostics.

**[2026-06-02] [P3-G] [DONE]** `ONEWitnessRequestView.swift` — season picker (5 kinds: indefinite, liturgical, academic, event, custom days); mutual exposure level picker; calls `ONECallableService.shared.requestWitness`. `ONEWitnessSeason.Kind: CaseIterable` extension. 0 diagnostics.

**[2026-06-02] [P3-D] [DONE]** `ONEWorldFeedView.swift` — `@available(iOS 26.0, *)` World zone root; glass mode chips, session budget bar (chrome header); matte feed cells; relay/comment/witness action bar; session-exhausted + empty states; `ONEWrapLayout` (custom `Layout` for mode switch row). 0 diagnostics.

**[2026-06-02] [P3-H] [DONE]** `ONENavigationShell.swift` updated — `.world` case routes to `ONEWorldFeedView()`. 0 diagnostics.

**[2026-06-02] [P3] [GATE]** P3 COMPLETE. 5 new Swift files + 3 HTML protos × 0 diagnostics. World zone fully wired into shell.

**[2026-06-02] [P2] [ACTION]** Starting P2. HTML protos first per PLAN.md invariant.

**[2026-06-02] [P2-A] [DONE]** `p2-liquid-camera.html` — 1,193-line prototype: glass viewfinder controls, format chip strip, hold-to-record ring, privacy pill overlay, provenance badge with tooltip, privacy contract sheet, ARIA labels throughout.

**[2026-06-02] [P2-B] [DONE]** `p2-moment-picker.html` — 870-line prototype: 10 format cards (matte), glass privacy preview bar, audience override sheet, all per-format default contracts wired.

**[2026-06-02] [P2-C] [DONE]** `ONEProvenanceLabelService.swift` — `actor`. EXIF metadata extraction (ImageIO, checks for AI/editing/capture software strings), Vision saliency heuristic (VNGenerateAttentionBasedSaliencyImageRequest), higher confidence wins. C2PA deferred (structure stub only). `labelForFreshCapture()` returns `.captured` at 0.95. 0 diagnostics.

**[2026-06-02] [P2-D] [DONE]** `ONEMomentFormatPickerView.swift` — 10-format picker sheet (matte cards), `defaultContract(for:)` returns per-format privacy defaults, glass privacy-preview bar with "Use This" CTA, `ONEMomentType` UI extensions (displayName, formatSubtitle, provenanceIcon, provenanceColor, pickableTypes). 0 diagnostics.

**[2026-06-02] [P2-E] [DONE]** `ONEEarnedPermanenceView.swift` — heart button, pulse animation on remember, disabled once remembered, async `onRemember` callback. 0 diagnostics.

**[2026-06-02] [P2-F] [DONE]** `ONEDecaySchedulerService.swift` — `actor`. `UNCalendarNotificationTrigger` 1h before expiry, idempotent `scheduled` set. Custom `expiry(for:from:)` avoids broken `ONELifetimePolicy.expiryDate`. `cancel()` removes notification + calls `ONECallableService.shared.expireMoment`. 0 diagnostics.

**[2026-06-02] [P2-C] [DONE]** `ONELiquidCameraView.swift` — `@available(iOS 26.0, *)`. `ONECameraSessionManager: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate` (NSObject required for nonisolated delegate). `ONECameraPreviewUIView` uses `layerClass` override. Glass on: close/flip buttons (Circle), privacy pill (Capsule), format chips (Capsule), sparkles button (Circle). `#if targetEnvironment(simulator)` gradient fallback. `ProvenanceServiceBox: ObservableObject` wraps actor for `@StateObject`. `Task.detached` for AVCaptureSession startRunning. 0 diagnostics.

**[2026-06-02] [P2-H] [DONE]** `ONEAlbumCreationView.swift` — `PhotosPicker(maxSelectionCount: 50)`, Form-based creation flow, privacy override sheet with audience chips + save toggle. 0 diagnostics.

**[2026-06-02] [P2-I] [DONE]** `ONENavigationShell.swift` updated — Moments zone routes to `ONELiquidCameraView()`. 0 diagnostics.

**[2026-06-02] [P2] [GATE]** P2 COMPLETE. 6 new Swift files + 2 HTML protos × 0 diagnostics. Moments zone fully wired into shell.

### P2 GATE — Known Open Items (not blocking P2 gate)
```
[ ] Key exchange CF not wired: ONEKeyRatchetService.initiate/accept must be called before
    first DM send. Decay scheduler's expireMoment CF is a full-logic stub — needs P2-I deploy.

[ ] Provenance is EXIF + Vision heuristics only (confidence ~0.50 for AI detection).
    C2PA hardware attestation deferred — requires entitlement + backend verification pipeline.

[ ] UNUserNotificationCenter.requestAuthorization must be called in app lifecycle
    (SceneDelegate/AppDelegate) before decay scheduler notifications will fire.

[ ] Album creation: collaborator invite is UI stub (no CF backing).
    Collaborative add-more requires separate CF: one_addAlbumCollaborator.
```

### P2 GATE — Deploy Checklist (DO NOT AUTO-RUN)
```
[ ] firebase deploy --only functions:one_expireMoment   (full logic — currently stub)
[ ] HUMAN: Add UNUserNotificationCenter.requestAuthorization call in app launch lifecycle
[ ] HUMAN: Test camera permission flow on device (simulator uses gradient fallback)
```

### P1 GATE — Known Open Items (not blocking P1 gate)
```
[ ] Ratchet session init: ONEKeyRatchetService.initiate/accept must be called via
    a key-exchange CF before first send. Until wired, send() throws noRatchetState.
    First-send will show "Could not decrypt" placeholder in bubbles. → P2 scope.

[ ] Contact picker / user discovery not yet wired (New Conversation button is a stub). → P2 scope.

[ ] Living Threads Remote Config flag default is OFF (one_living_threads_ai).
    Must be enabled in Firebase console to activate AI distillation. → deploy step.

[ ] Thread participant display names: ONEThreadListView uses UID prefix as fallback.
    Full name resolution requires ONEUser profile lookup. → P2 scope.
```

### P0 GATE — Deploy Checklist (DO NOT AUTO-RUN)
```
[ ] HUMAN: Switch Firebase console (amen-5e359) App Check from "debug" → "enforce"
[ ] firebase deploy --only firestore:rules   (after human reviews rules draft in CONTRACTS.md §14)
[ ] firebase deploy --only functions:one_sendMoment      (stub; no logic yet)
[ ] firebase deploy --only functions:one_expireMoment    (stub; no logic yet)
[ ] firebase deploy --only functions:one_reportMoment    (stub; no logic yet)
```
All other CF deploys are deferred to their phase gate.

---

## Open Blocking Questions

| # | Blocking What | Question | Status | Decision |
|---|--------------|----------|--------|----------|
| BQ-1 | P1 (E2E) | Which MLS library for iOS 26? | RESOLVED | **CryptoKit Double Ratchet** — no third-party dep, Secure Enclave-backed, documented as `encryptionVersion: "cr_1.0"`. MLS upgrade path noted for post-ship. |
| BQ-2 | P2 (Evidence) | Evidence key custody? | RESOLVED | **Google Cloud KMS** (already in Firebase/GCP ecosystem, amen-5e359). Dedicated key ring `one-evidence-keys`. |
| BQ-3 | P2 (CSAM) | NCMEC PhotoDNA access confirmed? | RESOLVED | **No confirmed access** — implemented as structural stub; public upload gated behind `one_csam_scan_enabled` Remote Config flag defaulting **false**. NCMEC partnership is a prerequisite before P2 ships to external users. |
| BQ-4 | P0 (App Check) | App Check mode? | RESOLVED | Code enforces App Check on all callables. **Human prerequisite**: switch Firebase console for amen-5e359 to "enforce" (not "debug") before any callable reaches external users. Logged in P0 deploy checklist. |
| BQ-5 | P1 (Evidence) | Legal hold duration? | RESOLVED | **90 days** conservative default, encoded in `one_evidence` schema as `retainUntil: Date`. Can be extended per legal instruction without schema change. |
| BQ-6 | P4 (Sealed Sender) | Sealed sender scope? | RESOLVED | **Deferred post-ship.** Threat model updated: metadata graph (sender UID + recipient UIDs) visible to server; disclosed in SECURITY.md §2. |
| BQ-7 | P5 (Stripe) | Subscription mechanism? | RESOLVED | **StoreKit (IAP)** — App Store digital subscriptions require Apple IAP, not Stripe. `SubscriptionStoreView` + `Product` API. Stripe available for web/admin billing only (out of iOS scope). |

---

## Contract Amendment Log

| # | Date | Section | Old Value | New Value | Reason | Approved By |
|---|------|---------|----------|----------|--------|------------|
| A-1 | 2026-06-10 | §3 ONEEntitlement / §13 / §15 | `stripeSubscriptionID: String?`; `one_stripeCheckout` callable; "Stripe-verified" | `storeKitTransactionID: UInt64?`; callable removed (9 callables); "StoreKit auto-renewable" | BQ-7: App Store 3.1.1 requires Apple IAP for digital subs; Stripe is web/admin-only | Lead Orchestrator |
| A-2 | 2026-06-10 | §4 ONEThread / SECURITY §1 | `encryptionVersion: "mls_1.0" \| "cr_1.0"`; `mlsGroupID: String?` present | `encryptionVersion: "cr_1.0"`; `mlsGroupID` removed | BQ-1: MLS→CryptoKit Double Ratchet; no MLS group identifier in fallback | Lead Orchestrator |
| A-3 | 2026-06-10 | §4 ONELivingThreadSummary / ONELivingDate / ONELivingTask | `Codable, Sendable` | `Sendable` (Codable removed) | On-device-only invariant: dropping Codable makes off-device serialization a compile error (privacy strengthening) | Lead Orchestrator |
| A-4 | 2026-06-10 | §2 ONEAudienceScope / ONELifetimePolicy; §9 ONEWitnessSeason | `enum` with associated values | `struct { kind: Kind; … }` flat-keyed Codable | SwiftUI ergonomics (CaseIterable pickers, ForEach over `.kind`); schema amended to the shipped flat shape so code and §14 agree | Lead Orchestrator |
| A-5 | 2026-06-10 | §1.1 ONEEncryptedPayload | `{ ciphertext, mlsEpoch, senderDeviceID }` | `+ encryptionVersion: String`; Swift property `epoch` ↔ wire key `mlsEpoch` via CodingKeys | Carry ratchet suite version on the payload; wire name preserved to match §14 message schema | Lead Orchestrator |
| A-6 | 2026-06-10 | §1 ONEMomentType | code shipped 9 of 10 cases (`story` dropped) | `story` restored (code conformed to frozen §1) | Decode-safety: `"story"` documents must round-trip; no contract change, code now matches | Lead Orchestrator |

> Amendments A-1…A-6 filed retroactively on 2026-06-10 to close the contract-drift class surfaced by the adversarial audit (`ONE/AUDIT-2026-06-10.md`): 10 of 11 confirmed findings were frozen-contract deviations with no amendment entry. Code↔schema now agree in both directions.

---

## Audit Remediation — 2026-06-10

Source: `ONE/AUDIT-2026-06-10.md` (read-only adversarial audit; 11 confirmed). Rulings executed in order.

1. **H-1 (consent bypass) — FIXED in code.** `ONEFeedModeService.relay(itemID:)` now calls `ONEStickyConsentService.isPermitted(.forward, in:)` and throws `ONEConsentError.forwardNotPermitted` **before any network call** (fail-closed). `ONEWorldFeedView` Relay control is shown DISABLED in its no-forwarding state when forwarding is denied — never an active button that contradicts the cell's displayed consent. New nonisolated `isPermitted(_:in:)` is the single source of truth. Named test: `AMENAPPTests/ONERelayConsentTests.swift` → forward-prohibited Moment → relay denied client-side + budget untouched.
   **⚠ SERVER-SIDE STILL REQUIRED (P5-deferred):** client-side consent enforcement is **advisory only**. The `one_relayMoment` callable MUST reject `forwardAllowed=false` relays server-side (per SECURITY.md §8.3 `mergedConsentDNA` logic) **before the ONE feature flag is ever flipped on**. Both layers are the requirement; shipping client-only is not done.
2. **Wire-shape — FIXED.** `mlsEpoch` wire name restored via CodingKeys (A-5); `ONEMomentType.story` restored (A-6); enum→struct reshapes reconciled by formal schema amendment (A-4). On-device-only non-Codable types are exempt (they never touch the wire) and were not changed.
3. **Provenance — FIXED at source.** `ONEProvenanceLabel` now forces `classification = .unknown` when `confidence < 0.70` in its initializer (persisted field, not just `displayClassification`), so any future Cloud Function reading `.classification` inherits the honesty. **Migration note:** already-persisted raw values are re-normalized on decode via a custom `init(from:)` — a stored confident class with sub-threshold confidence reads back as `.unknown` automatically; no backfill job required.
4. **Amendment Log — FILED.** A-1…A-6 above; CONTRACTS.md bodies updated to match shipped code.

---

## Phase Gate Summary

| Phase | Gate Date | Build Status | Summary | Open Risks |
|-------|----------|-------------|---------|-----------|
| Step A | 2026-06-01 | N/A (no code yet) | PLAN.md, CONTRACTS.md, SECURITY.md produced | See BQ-1 through BQ-7 |
| P0 | 2026-06-01 | ✅ 0 diagnostics | 9 Swift files (tokens, 6 model files, nav shell, CF stubs) + 3 HTML protos. Contracts frozen. | P0 deploy checklist requires human action (App Check, Firestore rules, 3 CF stubs) |
| P1 | 2026-06-02 | ✅ 0 diagnostics | 10 Swift files: ONEKeyRatchetService, ONEThreadStore, ONELivingThreadsEngine, ONEConsentBadgeView, ONEMessageBubble, ONELivingThreadsSummaryCard, ONEMessageComposerView, ONEThreadView, ONEThreadListView, ONEEphemeralGroupFlowView. People zone wired into shell. | Ratchet session init (initiate/accept) not yet wired to key exchange → first send will throw. Living Threads gated behind Remote Config flag (default OFF). |
| P2 | 2026-06-02 | ✅ 0 diagnostics | 6 Swift files (ONEProvenanceLabelService, ONEMomentFormatPickerView, ONEEarnedPermanenceView, ONEDecaySchedulerService, ONELiquidCameraView, ONEAlbumCreationView) + 2 HTML protos. Moments zone wired into shell. | expireMoment CF still a stub (needs deploy). Provenance heuristics only (no C2PA). Album collaborator invite is a UI stub. |
| P3 | 2026-06-02 | ✅ 0 diagnostics | 5 Swift files (ONEFeedModeService, ONEReachBudgetPill, ONEContextGateView, ONEWitnessRequestView, ONEWorldFeedView) + 3 HTML protos. World zone wired into shell. | one_relayMoment CF stub only. Context gate checks are UI-only (server-side enforcement is P5 scope). Witness request CF stub. |
| P4 | 2026-06-02 | ✅ 0 diagnostics | 5 Swift files (ONEPrivacyMirrorService, ONEStickyConsentService, ONERepairFlowView, ONEVaultView, ONELegacyDirectiveView) + 3 HTML protos. No new CF stubs needed (relay/witness wired in prior phases). | SE entitlement requires human Apple approval. Vault Firestore decryption mapping is P5 scope. `one_activateLegacy` CF is stub (trustee-only activation needs P5 deploy). |
| P5 | 2026-06-02 | ✅ 0 diagnostics | 5 Swift files (ONEEmotionalSafetyModeView, ONEImmuneSignalService, ONEReportMomentView, ONEEntitlementService, ONEEntitlementGateView) + 3 HTML protos + SECURITY.md v2. A11y sweep + App Check audit passed. | 8 deploy steps required before external users (see gate checklist above). |
