# AMEN PLATFORM OS AUDIT — 2026-06-01
**25 OS Layers | Branch: feature/spiritual-os**

---

## SUMMARY

Three OS layers are completely missing and block launch:
- **OS-02 Entitlement OS** — no single source of truth for what a user can access
- **OS-20 Recovery OS** — no account recovery workflow beyond Firebase default
- **OS-21 Audit OS** — no append-only audit trail (required for App Store COPPA + GDPR)

---

## LAYER ANALYSIS

### OS-01: Identity OS
**Status:** COMPLETE
Firebase Auth + Firestore profile. Email verification enforced at registration. Display name + avatar in UserProfile. Minor: verification gate at compose missing (C-2).

### OS-02: Entitlement OS
**Status:** MISSING — P0 BLOCKER
EntitlementService.shared exists but has no typed protocol. Multiple features call it without contracts. Need EntitlementServiceProtocol with typed capabilities.

### OS-03: Subscription OS
**Status:** PARTIAL
AmenCovenantCheckoutService + StoreKit integration exists. Gap: IAP terms not shown before SKPayment.add() — App Store guideline 3.1.1 violation (C-7).

### OS-04: Role & Permission OS
**Status:** COMPLETE
AmenRoleService with admin/mod/member/pastor roles. Firestore rules enforce server-side. RBAC consistent across Church, Spaces, Orgs.

### OS-05: Notification OS
**Status:** PARTIAL
FirebaseMessagingService handles FCM + local. CalmNotificationPolicyEngine (7 categories, 4 intensity modes, Sabbath mode). Gap: bulk send has no rate limit (C-10).

### OS-06: AI Credit OS
**Status:** COMPLETE
Berean credit system with monthly allocation, usage tracking, entitlement gates. Unentitled access blocked.

### OS-07: Reputation OS
**Status:** PARTIAL
Aegis trust scores. Shadow-ban lacks audit trail for GDPR Article 22.

### OS-08: Legal/Compliance OS
**Status:** PARTIAL
Privacy manifest present. COPPA DM (C-5) and data rights CFs (I-1) not yet deployed.

### OS-09: Creator Economy OS
**Status:** PARTIAL
SpacesFeeCalculator present. Account delete does not resolve creator revenue stream.

### OS-10: Organization Lifecycle OS
**Status:** PARTIAL
Organization CRUD exists. No secondary admin designation; org orphans if primary admin deletes account.

### OS-11: Church Lifecycle OS
**Status:** PARTIAL
Church CRUD with pastor role. C-14: no designateSuccessor() before pastor account delete. Church becomes permanently uneditable.

### OS-12: Community Lifecycle OS
**Status:** COMPLETE
Spaces v2 (49 Swift files). Admin chain auto-promotes next admin on owner delete.

### OS-13: Event OS
**Status:** PARTIAL
EventService with RSVP. C-13: creator deletion strands RSVPs. Need soft-delete + system reminder to attendees.

### OS-14: Search OS
**Status:** COMPLETE
Firestore full-text + churchSearchProxy CF. Denomination + location filters. VoiceOver labels present.

### OS-15: Media Rights OS
**Status:** PARTIAL
AegisVisionDetector (C1-C13) built. C-11: grooming on child photo not auto-removed + T&S not escalated.

### OS-16: Moderation OS
**Status:** PARTIAL
Aegis 58 caps built, all flagged OFF. C-1: AegisPrePostReviewSheet not wired into CreatePostView compose flow.

### OS-17: Device OS
**Status:** COMPLETE
Siri, Spotlight, Widgets, Haptics, Translation, Media session all wired (23 Swift files). Reduce Motion + Dynamic Type respected.

### OS-18: Membership OS
**Status:** COMPLETE
Subscription tiers (free/premium/creator). Entitlement gates on Berean AI, Spaces, Creator tools.

### OS-19: Relationship Graph OS
**Status:** COMPLETE
Follow graph, prayer network, church membership. Cross-community relationships via SpaceV2 link system.

### OS-20: Recovery OS
**Status:** MISSING — P0 BLOCKER
No AccountRecoveryService. Firebase default password reset only. No recovery flow for banned accounts, no appeal UX, no data export before delete.

### OS-21: Audit OS
**Status:** MISSING — P0 BLOCKER
No AuditTrailService. T&S actions (bans, removals, escalations) are not logged to an append-only store. Required for COPPA + GDPR compliance audit.

### OS-22: Revenue OS
**Status:** PARTIAL
Stripe webhook handler exists. No revenue reconciliation dashboard or discrepancy alerting. Stripe -> Firestore sync unverified for edge cases.

### OS-23: Automation OS
**Status:** COMPLETE
CalmNotificationPolicyEngine, Spiritual Rhythm OS (40 features), Berean automation triggers all flag-gated.

### OS-24: Smart Context OS
**Status:** PARTIAL
Berean context engine, scripture auto-detect, TrendingTopicService. AmenJourneyContinuityEngine relationship path still open — not wired to onboarding state.

### OS-25: Memory & Continuity OS
**Status:** PARTIAL
Berean conversation history persisted. Journey state (liturgical season, growth phase) not linked to Berean context window. Cross-session continuity incomplete.


---

## SWIFT PROTOCOL STUBS FOR MISSING OS LAYERS

### EntitlementServiceProtocol (OS-02)

protocol EntitlementServiceProtocol: AnyObject {
    var currentTier: AmenSubscriptionTier { get }
    func canAccess(_ capability: AmenCapability) async -> Bool
    func grantCapability(_ capability: AmenCapability, to uid: String) async throws
    func revokeCapability(_ capability: AmenCapability, from uid: String) async throws
    func refreshEntitlements() async throws
}

enum AmenCapability: String, CaseIterable {
    case bereanAI, spacesCreate, creatorOS, selahStories
    case aegisModeration, bulkNotifications, analyticsExport
}

### RecoveryServiceProtocol (OS-20)

protocol RecoveryServiceProtocol: AnyObject {
    func submitBanAppeal(uid: String, reason: String) async throws -> AppealID
    func getAppealStatus(appealID: AppealID) async throws -> AppealStatus
    func initiateDataExport(uid: String) async throws -> ExportToken
    func checkDataExportStatus(token: ExportToken) async throws -> DataExportStatus
    func softDeleteAccount(uid: String, graceDays: Int) async throws
    func cancelAccountDeletion(uid: String) async throws
}

enum AppealStatus: String { case pending, underReview, approved, denied }
enum DataExportStatus: String { case requested, processing, ready, expired }

### AuditServiceProtocol (OS-21)

protocol AuditServiceProtocol: AnyObject {
    func logEvent(_ event: AuditEvent) async
    func queryEvents(filter: AuditFilter) async throws -> [AuditEvent]
}

struct AuditEvent: Codable {
    let id: String
    let timestamp: Date
    let actorUID: String
    let targetUID: String?
    let action: AuditAction
    let metadata: [String: String]
}

enum AuditAction: String, Codable {
    case accountBan, accountUnban, contentRemoval, contentRestore
    case shadowBan, appealApproved, appealDenied
    case dataExportRequested, dataExportDelivered, accountDeleted
    case moderatorAction, adminAction
}

struct AuditFilter {
    var actorUID: String?
    var targetUID: String?
    var action: AuditAction?
    var from: Date?
    var to: Date?
}

---

## BUILD ORDER

**Phase 1 (before any beta):**
1. OS-21: AuditTrailService — append-only Firestore collection auditEvents/{id}, backed by AuditServiceProtocol
2. OS-20: AccountRecoveryService — ban appeal UI, data export flow, soft-delete with 30-day grace
3. OS-02: EntitlementService v2 — typed protocol, all capability gates migrate to it

**Phase 2 (before App Store submission):**
4. OS-03: IAP terms sheet shown before every SKPayment.add() call
5. OS-08: COPPA DM gate + AegisDataRights CFs deployed
6. OS-11: Church succession prompt on pastor account delete
7. OS-13: Event soft-delete + system reminder to RSVPs

**Phase 3 (post-launch hardening):**
8. OS-07: Reputation audit trail + GDPR Article 22 shadow-ban notification
9. OS-22: Stripe reconciliation view + discrepancy alert
10. OS-24+25: AmenJourneyContinuityEngine wired to Berean context window

---

*Platform OS Audit generated 2026-06-01 | Branch: feature/spiritual-os*
