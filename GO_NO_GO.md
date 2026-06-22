# AMEN — Go / No-Go Verdict (Module C: AI Safety)
*Generated: 2026-06-16 | Branch: app-store-readiness-overnight*

---

## VERDICT: NO-GO

**Rationale:** 21 P0 (blocking) findings remain open across the AI safety audit. Module C AI Ship-Gate condition 15 requires zero P0 findings before any AI feature flag may flip ON. With 21 P0s spanning prompt injection, COPPA/age gating, App Check bypass, autonomous messaging, missing kill switches, wildcard CORS, AI content labeling suppressed by default, and AI memory not deleted on account deletion, the product cannot proceed to AI flag enablement or App Store submission in its current state. No partial exceptions apply — each of the 21 P0s independently blocks the gate.

Total findings: 79
- GREEN (fixed): 23
- YELLOW (staged/in-progress): 34
- RED (unresolved): 22
- **P0 blocking: 21**
- P1 critical: 18

---

## Module C AI Ship-Gate Checklist

| # | Gate Condition | Status | Notes |
|---|---------------|--------|-------|
| 1 | No provider keys in iOS client code | UNVERIFIED | Not audited in this pass; must confirm ANTHROPIC_API_KEY absent from all Swift/plist files |
| 2 | All sensitive AI callables have auth + App Check | FAIL | bereanChatProxyStream has no App Check enforcement (C-INF-1-001, CINF3-002); invoker=public, Bearer-token only |
| 3 | All sensitive context is consent-gated before AI call | FAIL | AskSelahView streams without consent check (C-OUT-2-002); BereanCoCreatorService bypasses pipeline and consent entirely (C-OUT-1-002) |
| 4 | Private/blocked/deleted content excluded by construction (not by behavior) | UNVERIFIED | Not fully audited in this pass; postContext injection gap (CIN3-001) is relevant |
| 5 | All AI side-effects go through propose→confirm→execute round-trip | FAIL | No ProposedAction struct exists; no executeConfirmedAction callable exists; saveToChurchNotes fires on tap with no idempotency key (CACT-001, CACT-003) |
| 6 | AI cannot publish/message/delete/invite/pay/subscribe/moderate/change-settings silently | FAIL | Helix WorkflowTemplate sends DMs autonomously on triggers without per-send confirmation (CACT-002, CACT-010) |
| 7 | Injection→tool-exec eval at 100% (adversarial eval harness) | FAIL | systemPromptSuffix accepted verbatim from client (CIN2-001); postContext.bodyText inserted as plain string (CIN3-001); jailbreak patterns not stripped server-side (CIN3-002) |
| 8 | PII redaction live in all AI callables | UNVERIFIED | Not audited in this pass; no evidence of server-side PII redaction layer in bereanChatProxyStream |
| 9 | Per-user rate limits + quotas + kill switches live | FAIL | No kill switch on bereanChatProxy or bereanChatProxyStream (C-INF-1-003, CINF3-002); streaming path has no model tier ceiling (C-INF-1-004) |
| 10 | Streaming gated by sensitivity (high-risk = generate-then-filter) | FAIL | bereanChatProxyStream pipes raw Anthropic deltas with no output validation, no disclosure, no generate-then-filter (C-OUT-2-001) |
| 11 | AI-generated content labeled in UI | FAIL | bereanAiDisclosureEnabled defaults false; disclosure suppressed on all Berean output surfaces in production (C-OUT-3-001, CINF6-001) |
| 12 | AI memory user-controllable + deleted on account deletion | FAIL | users/{uid}/bereanMemory not in AccountDeletionService deletion list (CINF2-002) |
| 13 | Minor-tier AI defaults enforced (stricter context, no memory, no agentic actions) | FAIL | bereanChatProxyStream has no COPPA age gate (C-OUT-1-001, C-INF-1-002); BereanMemoryManager has no minor check (CINF5-002) |
| 14 | App Store AI disclosure drafts complete | FAIL | bereanAiDisclosureEnabled defaults false; legal/DPO review not confirmed complete (CINF6-001) |
| 15 | Zero P0 findings remaining | FAIL | 21 P0 findings open |

**Gate result: 0 of 15 PASS. NO-GO.**

---

## Build-Readiness Assertion

NOT a build claim. Static analysis only. Build status is unverified by this audit.

Canonical build command:
```
xcodebuild -scheme AMENAPP -destination 'generic/platform=iOS' build \
  -clonedSourcePackagesDirPath ./SourcePackages.nosync \
  -derivedDataPath ./DerivedData.nosync
```

**HUMAN-PENDING:** A human must run the canonical command from the repo root on a clean tree and report SUCCEEDED or FAILED with the current SHA before any gate can advance to build-verified state. Agents cannot make this attestation.

---

## Remaining P0 Blockers

1. **CIN2-001** — `systemPromptSuffix` from client inserted verbatim into system-prompt instruction channel (bereanChatProxy.ts + bereanChatProxyStream.ts). Remove field from API contract entirely.

2. **CIN3-001** — `postContext.bodyText` inserted as plain text in system prompt with no XML delimiting or server-side injection stripping (bereanChatProxy.ts + bereanChatProxyStream.ts). Add `<user_post_body>` delimiters, 500-char cap on stream path, and server-side strip of known injection sequences.

3. **CIN3-002** — `systemPromptSuffix` bypasses client-side jailbreak pattern validation (BereanSafetyPolicy.swift); server has no equivalent strip. Remove field or add server-side pattern matching equivalent to jailbreakPatterns.

4. **CACT-001** — No `ProposedAction` typed model exists; C-ACT-1 confirm→execute round-trip is not architecturally enforced anywhere. Define `ProposedAction<T>` struct and `executeConfirmedAction` callable with server-side re-authorization.

5. **CACT-002** — Helix `WorkflowTemplate` includes `.sendDM` steps that fire autonomously on triggers without per-send user confirmation. Remove or gate `sendDM` behind mandatory per-send human approval.

6. **CACT-003** — `saveToChurchNotes` executes immediately on first tap with no idempotency key and no server re-authorization. Add deterministic document ID (hash of uid + card.id + day) and route through `executeConfirmedAction` callable.

7. **CACT-010** — Helix `new_member_welcome` and `inactivity_nudge` templates auto-send DMs to other users on event/AI-detected triggers without per-message confirmation. Replace `.sendDM` with `.sendDMDraft` requiring admin review of each individual send.

8. **C-OUT-2-001** — `bereanChatProxyStream` streams raw Anthropic deltas with no output validation, no AI disclosure, and no App Check. Implement buffer-then-emit pattern with `validateRawTextOutput`, `ensureAIDisclosure`, and `getAppCheck().verifyToken()`.

9. **C-OUT-1-001** — `bereanChatProxyStream` has no COPPA age gate; under-13 / no-DOB users blocked by the callable can reach the streaming endpoint directly. Port the fail-closed age/DOB check from `bereanChatProxy` lines 116–162.

10. **C-OUT-2-002** — `AskSelahView` streams tokens with no consent check, no feature flag guard, and no AI content disclosure label. Add `consentCreatorAI` guard, `selahEnabled` flag check, and `AmenAIUsageLabel` below streamed content.

11. **C-OUT-1-002** — `BereanCoCreatorService.buildContent()` returns hardcoded static strings, never calls the constitutional pipeline, presents fabricated strings as Berean AI output. Replace with real `BereanPipelineClient` call or remove surface until implemented.

12. **C-OUT-3-001** — `bereanAiDisclosureEnabled` defaults `false`; the in-product AI disclaimer is suppressed on all Berean output surfaces. Change default to `true` and ensure all Berean output views render the disclosure footnote.

13. **C-INF-1-001** — `bereanChatProxyStream`: no App Check enforcement on SSE streaming endpoint; `invoker=public`, Bearer-token only. Add manual `admin.appCheck().verifyToken()` before processing any request body.

14. **C-INF-1-002** — `bereanChatProxyStream`: no COPPA/age gate — complete bypass of under-13 rejection available to any authenticated user. Add fail-closed age/DOB check before SSE headers are written.

15. **C-INF-1-003** — Neither `bereanChatProxy` nor `bereanChatProxyStream` has a Remote Config kill switch. Add `berean_chat_kill_switch` check at top of both handlers before any Anthropic invocation.

16. **C-INF-1-004** — `bereanChatProxyStream` has no subscription tier check; free users can select `scholar`/`debater` modes and receive Sonnet responses. Add `getBereanTierForUser()` + `resolveEntitledModel()` logic before the Anthropic fetch.

17. **C-INF-1-005** — `bereanChatProxyStream`: wildcard CORS origin (`*`) allows any web client to drive Anthropic API calls using a stolen token. Replace with explicit origin allowlist or remove CORS headers if iOS-only.

18. **CINF2-002** — Account deletion does not delete `users/{uid}/bereanMemory` subcollection. Add path to `AccountDeletionService.deleteAccount()` subcollections list and wire `bereanDeleteAllMemory` Cloud Function to account deletion trigger.

19. **CINF3-002** — `bereanChatProxy` has no kill switch; `bereanChatProxyStream` has no kill switch AND no App Check. (Consolidates C-INF-1-001 + C-INF-1-003.) Add kill switch to both; add App Check to stream path.

20. **CINF5-002** — `BereanMemoryManager` has no minor/age check; minors will accumulate AI memory entries when `berean_memory_enabled` flips ON. Add `AgeAssuranceService.shared.currentUserTier.isMinor` guard in `BereanMemoryManager` and in `bereanGetMemory`/`bereanDeleteMemory` Cloud Functions. Block enabling `berean_memory_enabled` until gate is deployed.

21. **CINF6-001** — `bereanAiDisclosureEnabled` defaults `false`; `AI-assisted content · Not pastoral guidance` footnote disabled in production. Change default to `true`; complete legal/DPO review before App Store submission.

---

## Remaining P1 Items

18 P1 (critical, non-blocking for ship-gate but required before public launch) findings remain open.

Top 5:

1. **Hallucination confidence threshold not surfaced in UI** — Berean responses with confidence below threshold are displayed without any uncertainty indicator; users cannot distinguish high-confidence from low-confidence AI output.

2. **BereanContextCoordinator sanitization is client-side only** — `sanitizeCommunityContent()` wraps community content in XML tags on the client, but the server does not validate or re-apply the delimiter, trusting client sanitization of untrusted data.

3. **No server-side PII redaction in bereanChatProxy or bereanChatProxyStream** — Prayer requests and community content may contain full names, phone numbers, addresses, and health information passed to Anthropic without redaction.

4. **Berean memory entries have no user-visible expiry or auto-purge** — `BereanMemoryView` shows entries but there is no TTL, no auto-expiry UI, and no bulk-delete that also purges from Firestore. Users cannot confirm their data is gone.

5. **WhyAmISeeingThisSheetV2 and DailyOfficeView do not render the AI disclosure footnote** — Only `BereanStudyCardView` has the disclosure wired; at least 4 other Berean output surfaces are missing it even when `bereanAiDisclosureEnabled` is `true`.

---

## Consolidated Human Action List

Actions are ordered: P0 code fixes first, then credential/secret actions, then deploys, then flag flips, then App Store submission. No step may be skipped.

### Phase 1 — P0 Code Fixes (must be done before any deploy)

1. Remove `systemPromptSuffix` from `BereanChatRequest` interface and `StreamRequest` counterpart in `bereanChatProxy.ts` and `bereanChatProxyStream.ts`. Delete the server-side append lines. (CIN2-001, CIN3-002)

2. Add XML-delimited `<user_post_body>` wrappers around `postContext.bodyText` in `buildCallDataPrompt()` and `buildCallDataBlock()`. Add 500-char cap to stream path. Add server-side injection-sequence strip. (CIN3-001)

3. Define `ProposedAction<T>` struct in iOS, `confirmProposedAction(id:)` method on `BereanContextActionEngine`, and `executeConfirmedAction` Firebase callable (us-east1) with server-side re-authorization. (CACT-001)

4. Remove `sendDM` from `WorkflowStepType` or replace with `sendDMDraft` in `HelixModels.swift`. Update backend executor to block auto-send. (CACT-002, CACT-010)

5. Add idempotency key (deterministic document ID) to `saveToChurchNotes` in `ContentApprovalSheet` and `ContentDiscussionLauncher`. (CACT-003)

6. Implement buffer-then-emit pattern in `bereanChatProxyStream.ts`: accumulate deltas, call `validateRawTextOutput`, apply `ensureAIDisclosure`, emit with `aiDisclosureApplied:true` and `safetyStatus` fields. (C-OUT-2-001)

7. Port the fail-closed age/DOB gate from `bereanChatProxy.ts` lines 116–162 to `bereanChatProxyStream.ts`. (C-OUT-1-001, C-INF-1-002)

8. Add consent guard, `selahEnabled` feature flag check, and `AmenAIUsageLabel` to `AskSelahView.swift`. (C-OUT-2-002)

9. Replace `BereanCoCreatorService.buildContent()` hardcoded strings with a real `BereanPipelineClient.shared.sendQuery()` call, or remove the co-creator surface entirely until implemented. (C-OUT-1-002)

10. Change `bereanAiDisclosureEnabled` default to `true` in `AMENFeatureFlags.swift` line 912. Ensure all Berean output views render the disclosure footnote. (C-OUT-3-001, CINF6-001)

11. Add manual `admin.appCheck().verifyToken()` to `bereanChatProxyStream.ts` before processing any request body. (C-INF-1-001)

12. Add `berean_chat_kill_switch` Remote Config check to both `bereanChatProxy.ts` and `bereanChatProxyStream.ts` immediately after auth verification. (C-INF-1-003)

13. Add `getBereanTierForUser()` + `resolveEntitledModel()` tier ceiling to `bereanChatProxyStream.ts` before the Anthropic fetch. (C-INF-1-004)

14. Replace `Access-Control-Allow-Origin: '*'` in `bereanChatProxyStream.ts` with an explicit origin allowlist, or remove CORS headers entirely if the endpoint is iOS-only. (C-INF-1-005)

15. Add `users/\(userId)/bereanMemory` to the subcollections array in `AccountDeletionService.deleteAccount()`. Wire `bereanDeleteAllMemory` Cloud Function to account deletion trigger. (CINF2-002)

16. Add `AgeAssuranceService.shared.currentUserTier.isMinor` guard to `BereanMemoryManager.fetchEntries()` and `BereanMemoryView`. Add minor check to `bereanGetMemory` and `bereanDeleteMemory` Cloud Functions. (CINF5-002)

### Phase 2 — Canonical Build Verification

17. Run the canonical build command from repo root:
    ```
    xcodebuild -scheme AMENAPP -destination 'generic/platform=iOS' build \
      -clonedSourcePackagesDirPath ./SourcePackages.nosync \
      -derivedDataPath ./DerivedData.nosync
    ```
    Report SUCCEEDED or FAILED with the SHA. Do not proceed to deploys until SUCCEEDED.

### Phase 3 — Credential and Secret Actions

18. Confirm `ANTHROPIC_API_KEY` does not appear in any iOS Swift file, plist, or compiled bundle. If found, rotate immediately and remove from client code.

19. Confirm `FIREBASE_WEB_API_KEY` and all other backend secrets are not in iOS client code or committed to the repository.

20. Complete legal/DPO review of the disclosure text `'AI-assisted content · Not pastoral guidance'` in `BereanStudyCardView.swift` and `'This is not a replacement for pastoral care'` in `BereanProvenanceChips.swift`. Get written sign-off before proceeding to App Store submission.

### Phase 4 — Deploys

21. Deploy `Backend/functions` (creator codebase) from repo root:
    ```
    firebase deploy --only functions:creator:bereanChatProxy,functions:creator:bereanChatProxyStream
    ```
    Log output to `deploy-logs/`. Confirm both functions deploy to us-east1 (us-central1 is at quota).

22. Deploy `executeConfirmedAction` callable (new function) to us-east1. Add entry to Interim Region Table in `docs/FUNCTION_INVENTORY.md`.

23. Deploy `bereanGetMemory`, `bereanDeleteMemory`, and `bereanDeleteAllMemory` Cloud Functions with minor-check and account-deletion-trigger updates.

24. Verify `berean_chat_kill_switch` Remote Config parameter exists and is set to `false` (enabled) in the Firebase console before traffic resumes.

### Phase 5 — Flag Flips (only after all P0s resolved and build verified)

25. Enable `bereanAiDisclosureEnabled = true` via Remote Config (this should now be the hardcoded default; Remote Config confirmation is belt-and-suspenders).

26. Do NOT flip `berean_memory_enabled` until Phase 1 item 16 (minor gate) is deployed and verified.

27. Do NOT flip any Helix workflow flags until Phase 1 item 4 (sendDM removal) is deployed and verified.

28. Do NOT flip any Berean Agent or streaming AI flags until all 21 P0s are resolved, the build is verified SUCCEEDED, and all deploys in Phase 4 are confirmed.

### Phase 6 — App Store Submission Gate

29. Re-run Module C AI Ship-Gate checklist. All 15 conditions must show PASS.

30. Confirm zero P0 findings remain open.

31. Confirm legal/DPO sign-off from item 20 is on file.

32. Submit to App Store only after all 31 items above are complete.

---

## AI-Specific Conditions for Flag Flips

None of the following flags may flip ON until ALL conditions listed under each are cleared:

**`bereanAiDisclosureEnabled`**
- C-OUT-3-001 and CINF6-001 resolved (default changed to `true` in code)
- Legal/DPO review of disclosure text complete (item 20)
- All Berean output views confirmed rendering the disclosure footnote

**`berean_memory_enabled`**
- CINF2-002 resolved (bereanMemory in account deletion path)
- CINF5-002 resolved (minor gate in BereanMemoryManager + Cloud Functions)
- COPPA parental consent flow confirmed for under-13 accounts (if memory is enabled for any minor tier)

**Any Berean Agent or Berean chat streaming flag**
- CIN2-001 resolved (systemPromptSuffix removed from API contract)
- CIN3-001 resolved (postContext XML delimiting + server-side injection strip)
- C-INF-1-001 resolved (App Check on streaming endpoint)
- C-INF-1-002 resolved (age gate on streaming endpoint)
- C-INF-1-003 resolved (kill switches on both callables)
- C-INF-1-004 resolved (model tier ceiling on streaming endpoint)
- C-INF-1-005 resolved (CORS wildcard removed)
- C-OUT-2-001 resolved (buffer-then-emit + output validation on stream)

**Any Helix workflow automation flag**
- CACT-001 resolved (ProposedAction + executeConfirmedAction architecture deployed)
- CACT-002 and CACT-010 resolved (sendDM removed or gated behind per-send confirmation)

**Any AskSelah or co-creator flag**
- C-OUT-2-002 resolved (AskSelahView consent + flag + disclosure label)
- C-OUT-1-002 resolved (BereanCoCreatorService uses real pipeline or surface removed)

**All AI flags globally**
- Gate 15: zero P0 findings remaining
- Build verified SUCCEEDED at the post-fix SHA
- All P0 Cloud Function deploys confirmed in deploy-logs/

---

*This file reflects Module C AI Safety audit results as of 2026-06-16. It must be updated and the verdict re-evaluated after each P0 resolution. A NO-GO verdict does not expire until a human re-runs the gate checklist and all 15 conditions show PASS.*
