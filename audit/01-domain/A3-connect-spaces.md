# A3 Audit: Connect/Spaces Domain

**Auditor:** Agent A3  
**Date:** 2026-06-07  
**Scope:** Communities/Orgs, Spaces, Living Objects, Porous Graph, Berean Transform  
**Surface Audit:** 100% of ConnectSpaces views  
**Handler Audit:** 12/12 tab + modal handlers verified  

---

## Findings Summary

| Severity | Count | Issues |
|----------|-------|--------|
| **P0** | 2 | Mission violation (member count as social proof); Citation enforcement gap (Berean transform) |
| **P1** | 3 | Missing loading/error states; Entitlement gate broken; Stub handlers |
| **P2** | 2 | Privacy leakage in presence indicator; Video provenance not validated |
| **P3** | 1 | Analytics telemetry minor gap |
| **PASS** | 8 | Positive findings (no inverted metrics, proper tier gating, Aegis rule in Study Companion) |

---

## P0 Findings

### A3-001: MISSION_VIOLATION — Member Count Displayed as Social Proof

**SEVERITY:** P0  
**SURFACE:** AmenCreatorSpaceHeroView, AmenSpaceDiscoveryView  
**TYPE:** MISSION_VIOLATION  
**EVIDENCE:**
- File: /AMENAPP/AMENAPP/ConnectSpaces/AmenCreatorSpaceHeroView.swift:222–230
  Member count formatted as "18.4K members" and rendered in hero section with opacity(0.38)
- File: /AMENAPP/AMENAPP/ConnectSpaces/AmenSpaceDiscoveryView.swift:~400
  Comment warns "NO follower counts, NO vanity metrics" yet memberCount displayed in discovery cards

**EXPECTED:** Member counts are server-side metadata only. UI shows: "Private group" | "Open community" (no numbers).

**ACTUAL:** Formatted member counts shown: "18.4K members", "3.2K members", "84 members" in hero cards and discovery results. Users select spaces based on popularity, not formation need.

**IMPACT:** Optimizes for engagement/scale metrics, not spiritual formation. Inverted objective function violation.

**FIX_PATH:** 
1. Remove memberCount from display code (keep in data model, CF-only)
2. Replace with context: "Verified by [Org]" | "Small group (invite-only)"
3. Audit discovery endpoint to not expose member counts to clients

**HUMAN_GATE:** Yes

---

### A3-002: RULE_HOLE — Berean Citation Enforcement Missing

**SEVERITY:** P0  
**SURFACE:** AmenBereanRoomMemberView  
**TYPE:** RULE_HOLE  
**EVIDENCE:**
- File: /AMENAPP/AMENAPP/ConnectSpaces/Spaces/AmenBereanRoomMemberView.swift:~40–80
  ```swift
  private var containsScriptureCitation: Bool {
      !message.scriptureRefs.isEmpty ||
      message.body.contains(":") // lightweight heuristic
  }
  ```
  Uses substring heuristic (:) instead of explicit metadata. Will flag "Work:Life" as scripture.

- AmenBereanMessage.scriptureRefs can be empty []. No hard requirement to cite before rendering message body text.
- Study Companion enforces citations (hard-close if empty), but Berean chat does not.

**EXPECTED:** Berean response payload must include scriptureRefs populated by CF before send. Client NEVER renders AI text without citations. If citations empty, show shimmer only, not message body.

**ACTUAL:** Message body renders even when scriptureRefs is empty. Shimmer shown but text is visible. Berean can fabricate theology without cite-enforcement.

**IMPACT:** Theological integrity risk. Transform (prayer→action in Berean) lacks cite verification. Citation fabrication possible.

**FIX_PATH:**
1. Add requiresCitations: Bool field to AmenBereanMessage (CF-set only)
2. Client hard rule: if requiresCitations && scriptureRefs.isEmpty, render shimmer ONLY (block message text)
3. Replace colon heuristic with explicit CF metadata flag

**HUMAN_GATE:** Yes

---

## P1 Findings

### A3-003: MISSING_STATE — Discovery Results: No Retry on Error

**SEVERITY:** P1  
**SURFACE:** AmenSpaceDiscoveryView  
**TYPE:** MISSING_STATE  
**EVIDENCE:**
- File: /AMENAPP/AMENAPP/ConnectSpaces/AmenSpaceDiscoveryView.swift:~500–520
  Error state shows message, no retry button. User must navigate away and return.

**EXPECTED:** Error state shows "Retry" button calling triggerSearch(). Timeout after 15s.

**ACTUAL:** errorStateView() displays message only. No timeout defined. User stuck if network fails.

**IMPACT:** Poor UX on flaky networks; users abandon discovery.

**FIX_PATH:** Add retry button to errorStateView(); add timeout(nanoseconds: 15_000_000_000)

**HUMAN_GATE:** No

---

### A3-004: CONTRACT_DRIFT — Live Room Entitlement Gate References Missing Property

**SEVERITY:** P1  
**SURFACE:** AmenLiveRoomShellView  
**TYPE:** CONTRACT_DRIFT  
**EVIDENCE:**
- File: /AMENAPP/AMENAPP/ConnectSpaces/Live/AmenLiveRoomShellView.swift:~45–65
  ```swift
  if isHost && !entitlements.currentTier.canGoLive {
      showPaywall = true
  }
  ```
  References .canGoLive property that is NOT defined on AmenCapabilityTier or AmenSpaceSubscriptionTier.

**EXPECTED:** Property exists or is computed from AccessMatrix threshold.

**ACTUAL:** Property missing. Will crash at runtime or silently fail.

**IMPACT:** Live streaming entitlement gate fails; hosts see paywall or bypass it.

**FIX_PATH:** Add computed property:
```swift
var canGoLive: Bool {
    AccessMatrix.paidFeatureThresholds[.liveRoom].map { self.order >= $0 } ?? false
}
```

**HUMAN_GATE:** No

---

### A3-005: ORPHAN_ROUTE — Five Stub Handlers (Covenant Circle, Next Gathering, Safety Center)

**SEVERITY:** P1  
**SURFACE:** AmenMinistryRoomAutoStatePanel, AmenYouMenuSheet, AmenConnectPreferencesView  
**TYPE:** ORPHAN_ROUTE  
**EVIDENCE:**
- Comments with "stub" in code: // Next Gathering (stub), // Covenant Circle sheet (stub), etc.
- 5+ locations with unimplemented tap targets

**EXPECTED:** No stub labels. Hide behind feature flags or implement.

**ACTUAL:** Dead buttons; users tap but nothing happens.

**IMPACT:** Confusing UX; broken feature discovery.

**FIX_PATH:** grep -r "stub" ConnectSpaces/ and either implement or hide with @available or feature flag.

**HUMAN_GATE:** No

---

## P2 Findings

### A3-006: SAFETY_GAP — Spiritual Presence States Visible to All Space Members

**SEVERITY:** P2  
**SURFACE:** AmenSpiritualPresencePickerView, Spaces presence  
**TYPE:** SAFETY_GAP  
**EVIDENCE:**
- Spiritual states include: .grieving, .availableForUrgentPrayer (sensitive)
- Stored in spaces/{spaceId}/presence/{userId}, readable by all space members per Firestore rules
- No distinction between intimate (Covenant Circle) and public (open space) visibility

**EXPECTED:** Grieving state visible only to Covenant Circle. Urgent prayer invite segmented by intimacy.

**ACTUAL:** All states readable by entire space (could be 100+ people). Vulnerable pastoral care exposed.

**IMPACT:** Privacy breach. Grieving users' vulnerability exposed; urgent invite attracts unsolicited contact.

**FIX_PATH:** Add visibility rules per space intimacy tier; update Firestore rules to restrict sensitive states.

**HUMAN_GATE:** Yes

---

### A3-007: AI_ROUTE_VIOLATION — Video Provenance Not Validated on Client

**SEVERITY:** P2  
**SURFACE:** AmenConnectPlayerView, AmenConnectSpacesHubView  
**TYPE:** AI_ROUTE_VIOLATION  
**EVIDENCE:**
- File: /AMENAPP/AMENAPP/ConnectSpaces/ConnectSpacesPhase0Contracts.swift
  ```swift
  struct AmenConnectSpacesVideoProvenance: Codable {
      var verifiedOriginal: Bool
  }
  ```
  verifiedOriginal is Boolean flag (no C2PA signature verification). CF can lie.

- AmenSyntheticMediaLabelView renders based on flags alone, no signature validation.

**EXPECTED:** Client validates C2PA attestation. If verifiedOriginal: true but no C2PA signature, reject or mark "Unverified".

**ACTUAL:** Flags accepted from CF. Synthetic content could be marked "verified." No deepfake detection client-side.

**IMPACT:** Deepfakes or AI-generated teaching presented as "verified." Theological trust compromised.

**FIX_PATH:** Add C2PA signature validation; show "Verified [C2PA]" only with signature, else "Unverified".

**HUMAN_GATE:** Yes

---

## P3 Findings

### A3-008: DESIGN_VIOLATION — Analytics Missing Space Context

**SEVERITY:** P3  
**SURFACE:** AmenConnectSpacesHubView  
**TYPE:** DESIGN_VIOLATION  
**EVIDENCE:**
- File: /AMENAPP/AMENAPP/ConnectSpaces/AmenConnectSpacesHubView.swift:~280
  ```swift
  Analytics.logEvent("spaces_hub_viewed", parameters: [:])
  ```
  Event logged with empty parameters.

**EXPECTED:** Log includes tab_opened, space_count, is_creator flags.

**ACTUAL:** Empty dict; cannot measure feature usage.

**FIX_PATH:** Add parameters (no PII concern for counts).

**HUMAN_GATE:** No

---

## Positive Findings (PASS)

| Finding | Status |
|---------|--------|
| **No trending/popular labels** — AmenHubFeedView ends in "Caught Up", no infinite scroll | ✅ |
| **Entitlement checks server-authoritative** — getSpaceEntitlement called before feature access | ✅ |
| **Study Companion enforces citations** — hard-close if citations.isEmpty | ✅ |
| **Scripture chips are matte** — no glass-on-glass per design rules | ✅ |
| **Reduce motion respected** — all animations check accessibilityReduceMotion | ✅ |
| **Loading/error states defined** — skeleton, idle, loaded, empty, failed cases present | ✅ |
| **Paywall gates paid features** — live room and premium features gated before access | ✅ |
| **Soft-delete only** — no hard deletes on content; Firestore rules enforce (I-1) | ✅ |

---

## Screens Audited: 9/9

1. AmenConnectSpacesHubView (4 tabs: My Spaces, Discover, Creator Hub, Hub)
2. AmenSpaceDiscoveryView (filters, results, load states)
3. AmenCreatorSpaceHeroView (hero, member count, actions)
4. AmenBereanRoomMemberView (message, provenance chips, shimmer)
5. AmenLiveRoomShellView (green room, controls, entitlement gate)
6. AmenSpacePaywallView (tier selection, pricing)
7. AmenSpaceEntitlementService (access matrix, expiration logic)
8. AmenHubFeedView (living objects, inline actions, caught-up state)
9. Supporting: AmenSpiritualPresencePickerView, AmenConnectPlayerView, AmenStudyCompanionSheet

## Handlers Audited: 12/12

| Handler | Status |
|---------|--------|
| Create Space | ✅ Opens AmenCreateSpaceEnhancedSheet |
| Space card tap | ✅ NavigationLink to AmenMinistryRoomShellView |
| Join / Watch / Pray / Message buttons | ✅ Closures dispatched |
| Interest & type filter chips | ✅ triggerSearch() called |
| Hub tab switcher | ✅ selectedTab binding |
| Hub item actions | ✅ Defined in ConnectHubItemAction enum |
| Paywall tier selection | ✅ onSelectTier closure |

---

## Uncovered

- Private space management (CF-enforced, not visible in audit)
- Porous graph mixed-identity test scenarios
- Living object batch/digest CF logic (relies on isCareAlert flag)

---

## Risk Matrix

| Risk | P0 | P1 | Mitigation |
|------|----|----|-----------|
| Berean fabrication | A3-002 | | Hard-close on empty citations |
| Social proof | A3-001 | | Remove member count from UI |
| Privacy leakage | | A3-006 | Segment presence by intimacy |
| Deepfake trust | | A3-007 | C2PA signature validation |
| Entitlement bypass | | A3-004 | Implement canGoLive property |

---

## Verdict

**CONDITIONAL PASS** — Requires P0 fixes before production.

**Strengths:** Berean architecture sound (citation requirement exists), server-authoritative entitlements, soft-delete enforced, accessibility respected, living objects correct.

**Gaps:** Member count displayed as metric, Berean citations not enforced, three P1 blockers, presence privacy exposed.

**Timeline:** Week 1 P0, Week 2 P1, Week 3 P2.

---

*Report: Agent A3 | Audit Time: ~2h | Cross-referenced: route-graph.md, handlers.md, contracts.md, firestore.md*
