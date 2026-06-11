# Platform OS Audit

Branch: `audit/platform-os`
Date: 2026-06-10
Scope: additive audit only. No production deploys, rule changes, schema migrations, deletes, or secrets access.

## Executive Summary

The app has many real system fragments: auth lifecycle gates, feature flags, monetization/entitlement services, notification tests, moderation audit contracts, context intelligence, and recovery-style soft-delete fields in selected models. The platform risk is not total absence; it is fragmentation. High-risk systems are duplicated across feature folders, some backend callables referenced by clients appear missing or structurally incomplete, and several enforcement paths are client-authored or fail-open.

## P0 Blockers

| ID | Layer | Finding | Evidence | Status |
|---|---|---|---|---|
| POS-P0-001 | Role & Permission OS | Root role permission service is a scaffold and does not appear to persist/resolve roles. | `AMENAPP/AMENAPP/RolePermissionService.swift:17`, `:59`, `:134` | Open |
| POS-P0-002 | Role & Permission OS | Role mutation paths write directly from client without an in-method authorization gate before assign/revoke/transfer. | `AMENAPP/AMENAPP/AMENAPP/CommunityOS/Identity/AmenRoleManager.swift:88`, `:141`, `:248` | Open |
| POS-P0-003 | Community/Event/Membership Lifecycle OS | Covenant backend exports reference missing `./covenant/...` modules. Functions build/deploy is likely broken and lifecycle callables unresolved. | `AMENAPP/Backend/functions/src/index.ts:322` | Open |
| POS-P0-004 | Relationship Graph OS | Spiritual graph snapshot appears to aggregate first 300 global edges without filtering by caller uid, risking cross-user affinity contamination. | `AMENAPP/Backend/functions/src/spiritualGraph/services/SpiritualGraphService.ts:23`, `:35` | Open |
| POS-P0-005 | AI Credit & Usage OS | Backend functions tree appears incomplete: AI/backend imports and callable names referenced by client are missing or mismatched. | `AMENAPP/Backend/functions/src/smartAttachments.ts:3`, `AMENAPP/Backend/functions/src/bereanChatProxy.ts:11`, `AMENAPP/AMENAPP/AIIntelligence/AmenAIFeaturesService.swift:96` | Open |
| POS-P0-006 | Permission Revocation / Device OS | No automated mid-session OS permission revocation coverage for notification/camera/photo/mic or Firestore permission-denied listener recovery. | `AMENAPP/AMENAPPTests/NoteShareViewerTests.swift:44`, `AMENAPP/AMENAPPTests/WalkWithChristTests.swift:497` | Open |
| POS-P0-007 | Recovery OS | Deleted-reference fan-out is not emulator-verified across saved posts, notifications, feed refs, comments/replies, search indexes, and media URLs. | `AMENAPP/AMENAPPTests/ProductionAuditTests.swift:119`, `AMENAPP/AMENAPPTests/ServiceProtocolTests.swift:231` | Open |
| POS-P0-008 | Moderation OS | No automated report -> enforcement -> human review -> appeal -> restore/remove loop. | `AMENAPP/AMENAPPTests/AuditLogTests.swift:14`, `AMENAPP/AMENAPPTests/SocialSafetyOSTests.swift:103` | Open |
| POS-P0-009 | Subscription OS | StoreKit/subscription tests do not cover cancel, restore, refund, billing retry, grace, expired transaction, downgrade timing, or server/client mismatch. | `AMENAPP/AMENAPPTests/RemainingReleaseScopesTests.swift:58`, `AMENAPP/AMENAPPTests/AmenConnectTests.swift:46` | Open |
| POS-P0-010 | Ownership Lifecycle OS | No succession tests for owner deletion, last-admin leave, role transfer, paid/community takeover, or orphaned content. | `AMENAPP/AMENAPPTests/ContextStoreSecurityTests.swift:188`, `AMENAPP/AMENAPPTests/IntelligentSocialArchitectureTests.swift:115` | Open |

## Layer Status

| # | Layer | Status | Existing Evidence | Key Gap |
|---|---|---|---|---|
| 1 | Identity OS | Audited | `AuthenticationViewModel.swift`, `FirebaseManager.swift`, `AccountDeletionService.swift`, `AccountRecoveryService.swift` | No standalone identity boundary spanning sessions, devices, recovery, export, and deletion. |
| 2 | Entitlement OS | Audited | `Shared/Contracts/Entitlement.swift`, `CommunityOS/Monetization/AmenEntitlementService.swift`, `Monetization/AmenAccountEntitlementService.swift` | Multiple entitlement sources without one resolver/preference order. |
| 3 | Subscription OS | Audited | `AmenStoreKitManager.swift`, `AmenPlatformStoreKitService.swift`, `AmenPlanModels.swift` | Edge states are not fully modeled/tested. |
| 4 | Role & Permission OS | Audited | `RolePermissionService.swift`, `AmenRoleManager.swift`, ActionThread permission models | Central enforcement is incomplete; role mutation is not server-authoritative in inspected paths. |
| 5 | Notification OS | Audited | `NotificationSystemTests.swift`, `DeviceTokenManager.swift`, `PushNotificationHandler.swift` | Channels/cadence/quiet-hours are not unified; device-token stores are duplicated. |
| 6 | AI Credit & Usage OS | Audited | `AIUsageService.swift`, `AmenAIFeaturesService.swift` | Quotas are local/fail-open in inspected paths; backend callables appear missing. |
| 7 | Reputation & Trust OS | Partial | `trustScoringEnabled`, App Check service, moderation/trust hints | No central private trust ledger with explainable inputs and retention policy. |
| 8 | Legal & Compliance OS | Partial | Account deletion/recovery, consent surfaces | Consent/export/deletion/DMCA workflows are not one compliance contract. |
| 9 | Creator Economy OS | Partial | Creator/studio monetization files | Payout/tax/refund/revenue-share interfaces need server-authoritative stubs before money movement. |
| 10 | Organization Lifecycle OS | Partial | Org/community models, note-share membership probes | Org schemas drift between collections; merge/archive/transfer not canonical. |
| 11 | Church Lifecycle OS | Partial | Church OS models and services | Legacy church lookup bypasses soft-delete filtering. |
| 12 | Community Lifecycle OS | Partial | Covenant/community models | Missing succession and survival contracts when founder/owner leaves. |
| 13 | Event OS | Partial | Covenant event view/model snippets | Event status/canceled/deleted/restored fields and lifecycle filtering are thin. |
| 14 | Search OS | Partial | RAG/search services, Algolia dependency | Search callables/index lifecycle and deleted-object filtering need verification. |
| 15 | Media Rights OS | Missing/Partial | `AMENMediaService.swift` | Rights/license/removal-request lifecycle is mostly implicit. |
| 16 | Moderation OS | Partial | `AmenSafetyModerationProvider.swift`, `AuditLogTests.swift` | Full moderation/appeal loop missing; some moderation paths fail open or are stubs. |
| 17 | Device OS | Partial | `DeviceTokenManager.swift`, `PushNotificationHandler.swift`, App Check | No single session/device trust registry. |
| 18 | Membership OS | Partial | Covenant membership statuses/roles | No transition audit or succession rules. |
| 19 | Relationship Graph OS | Partial | Spiritual graph backend | P0 cross-user aggregation risk found. |
| 20 | Recovery OS | Partial | `isDeleted`, `deletedAt`, archive fields in selected models | No universal tombstone/retention/restore contract. |
| 21 | Audit OS | Partial | `AuditTrailService`, `AmenAuditLogService`, `AuditLogService`, `ContentAuditLogger` | Audit schemas are fragmented and often client-authored. |
| 22 | Revenue OS | Partial | StoreKit, Stripe/covenant monetization, creator monetization | No single revenue lifecycle model; live billing remains approval-gated. |
| 23 | Automation OS | Partial | Action suggestions, daily digest, reminders | No central rule engine with ownership, audit, retries, and idempotency. |
| 24 | Smart Context OS | Partial | ContextStore, smart context engine, Berean context actions | Strong client UX, but consent/receipt/backend broker are incomplete. |
| 25 | Memory & Continuity OS | Partial | ContextStore, conversation memory UI, journey continuity tests | No authoritative consent/audit/retention contract for long-term memory. |
| 26 | Governance OS | Missing/Partial | Moderation/trust systems | No moderator hierarchy, appeals board, safety escalation, or transparency-reporting contract. |

## Hidden-Failure Test Matrix Gaps

| Matrix | Severity | Current Coverage | Missing Coverage |
|---|---|---|---|
| State x Screen | P1 | `AuthAccountLifecycle10GoTests.swift`, `AppReadyStateManagerTests.swift`, `AuthResolutionRaceTests.swift` | Exhaustive production route/UI matrix for logged out, partial onboarding, banned, deleted, offline, revoked permissions, role-switched. |
| Timezone | P1 | Holiday/journey tests with simple offsets | DST forward/back, travel, leap year, birthdays, reminders across local midnight. |
| Permission Revocation | P0 | Consent and note/share tests | Automated OS revocation while app is active and listener permission-denied recovery. |
| Ownership Succession | P0 | Owner-scoped access model tests | Last admin/owner deletion, transfer, successor selection, orphaned objects. |
| Cross-feature Chains | P1 | Bridge/unit contracts | Church Note -> Berean -> Notes -> Space -> Discussion -> Prayer end-to-end with auth/persistence/notification routing. |
| Deleted References | P0 | Model/documentation tests | Emulator fan-out verification for all dependent references. |
| Moderation Loop | P0 | Audit/safety model tests | Report -> action -> appeal -> reinstate/remove -> notify. |
| Subscription Edges | P0 | Basic monetization tests | Cancel, restore, refund, grace, billing failed, family shared, downgrade, offline cached mismatch. |
| Accessibility Regression | P2 | String labels/hints | UI tests for VoiceOver traversal, focus order, hit targets, Dynamic Type clipping, Reduce Motion, contrast. |

## Deferred Approval-Gated Actions

| Action | Why Deferred |
|---|---|
| Firestore rules changes | Production/security-impacting and requires human review. |
| Cloud Functions fixes/deploys | Backend deploy/build changes are approval-gated; missing modules need focused backend branch. |
| Schema migrations for audit/recovery/entitlements | Data migration and retention policy require explicit approval. |
| Hard deletes or cleanup of orphaned assets | Safety contract requires soft-delete first and human approval for permanent deletes. |
| Billing/payout implementation | Live money movement and subscription state changes are human-gated. |
