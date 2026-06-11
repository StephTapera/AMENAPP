# Platform OS Design

This is the first additive design pass. It defines the integration direction and explicit gates; it does not enable behavior.

## Rollout Contract

All Platform OS layers must be behind a reviewed rollout gate. The initial implementation in `AMENAPP/AMENAPP/PlatformOS/PlatformOSContracts.swift` defaults every layer off:

```swift
let rollout = PlatformOSRollout.allOff
rollout.isEnabled(.identity) == false
```

## Foundational Dependency Order

| Order | Layer | Reason |
|---|---|---|
| 1 | Identity OS | Every decision needs a stable actor, session, device, recovery, deletion, and export model. |
| 2 | Role & Permission OS | Screens and backend operations need one action matrix before adding more lifecycle behavior. |
| 3 | Entitlement OS | Features must check entitlements, not raw subscription/provider state. |
| 4 | Subscription OS | Billing states map into entitlements only after a subscription state machine is canonical. |
| 5 | Recovery OS | All destructive workflows must land on tombstone + retention + restore before permanent deletion. |
| 6 | Audit OS | Consequential actions must be append-only and server-authored before high-risk systems are enabled. |

## Core Protocols

```swift
protocol PlatformOSEntitlementChecking {
    func can(_ userId: String, perform feature: String) async -> Bool
}

protocol PlatformOSPermissionChecking {
    func can(_ actorId: String, perform action: String, on resourceId: String) async -> Bool
}

protocol PlatformOSRecoveryRecording {
    func markRecoverableDeletion(objectId: String, objectType: String, actorId: String, retentionDays: Int) async throws
}

protocol PlatformOSAuditRecording {
    func record(action: String, actorId: String, resourceId: String, metadata: [String: String]) async throws
}
```

## Data Model Direction

| Model | Required Fields |
|---|---|
| IdentityPrincipal | `userId`, `accountState`, `sessionIds`, `deviceIds`, `recoveryState`, `deletionState`, `exportState` |
| PermissionDecision | `actorId`, `action`, `resourceId`, `allowed`, `reason`, `policyVersion`, `evaluatedAt` |
| EntitlementDecision | `holderId`, `feature`, `allowed`, `source`, `subscriptionState`, `expiresAt`, `policyVersion` |
| RecoverableTombstone | `objectId`, `objectType`, `actorId`, `deletedAt`, `restoreUntil`, `state`, `reason` |
| AuditEvent | `eventId`, `actorId`, `action`, `resourceId`, `resourceType`, `createdAt`, `requestId`, `policyVersion`, `metadata` |

## Implementation Rules

| Rule | Requirement |
|---|---|
| Fail closed | Disabled or unresolved Platform OS gates deny privileged behavior. |
| Server authority | Role mutation, moderation enforcement, billing, audit, recovery, and lifecycle transitions must be callable/server-authored before production use. |
| Soft delete first | All deletes create a tombstone with retention and restore metadata. |
| One resolver | Entitlements, roles, devices, and audit events must converge behind canonical resolver protocols before feature surfaces consume them. |
| Emulator tests first | Backend/rules fixes need emulator tests before deployment. |

## First Safe Implementation Scope

The current branch adds only:

| Artifact | Purpose |
|---|---|
| `PlatformOSContracts.swift` | Shared enums/protocols/dependency order and disabled fail-closed gate. |
| `PlatformOSContractTests.swift` | Regression guard that all layers exist and rollout defaults off. |
| Audit/design/log markdown | Human-reviewable map of risk and next branches. |

## Next Feature Branches

| Branch | Scope |
|---|---|
| `os/role-permission` | Replace client role mutation with server-authoritative command contracts and emulator tests. |
| `os/audit` | Unify audit schema and define server-authored append-only event writer. |
| `os/recovery` | Universal tombstone + retention + restore model for posts, notes, events, spaces, orgs, churches, and media. |
| `os/entitlement-subscription` | Canonical entitlement resolver and full subscription edge state matrix. |
| `os/device-notification` | One device/session/token registry plus channel/cadence/quiet-hours model. |

## Human Approval Gates

| Gate | Required Before |
|---|---|
| Backend deploy approval | Any Cloud Functions export/import fix, callable implementation, or App Check enforcement change. |
| Firestore rules approval | Any permission, audit, recovery, entitlement, or lifecycle rule changes. |
| Data migration approval | Any schema consolidation or backfill. |
| Billing approval | Any StoreKit/Stripe/RevenueCat live behavior. |
| Permanent deletion approval | Any non-recoverable delete or orphan cleanup. |
