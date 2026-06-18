# Moment System Contract

Wave 0 freezes the Moment primitive only. Implementation agents must treat these contracts as read-only until the human approves a new contract wave.

## Core Model

- `Moment.type` decides which verb families are relevant.
- `Moment.temporalState` decides which surface can render the Moment.
- `availableActions(moment, flags)` is pure and deterministic.
- TypeScript in `contracts/moment/momentContracts.ts` is the source of truth.
- Swift in `Sources/Contracts/Moment/MomentContracts.swift` is a mirror for app-side compile-time alignment.

## Feature Flags

All Moment flags default off:

- `moment_system_enabled = false`
- `deepen_actions_enabled = false`
- `gather_live_enabled = false`

No build agent may flip these flags. A flag flip requires a completed verification ledger and explicit human approval.

## Deepen V1

Deepen is the only verb family approved for v1 implementation. Deepen actions are:

- `summarize`
- `crossReference`
- `generatePrayer`
- `generateStudyGuide`
- `generateDiscussion`
- `generateDevotional`
- `saveTo`

Every Deepen result must be routed through Berean mode selection, Constitutional Intelligence, and a GUARDIAN/Aegis guard pass before output is returned or saved.

Save targets are:

- `prayerJournal`
- `studyJournal`
- `churchNotes`
- `sermonCollection`
- `savedTeachings`

## Gather V1

Gather is contract-only in v1. The actions are:

- `prayLive`
- `joinAudio`
- `joinDiscussion`

Gather functions must remain gated stubs returning `gated` or `notImplemented`. Gather cannot be built or wired until all four compliance gates clear:

- ESP/NCMEC registration
- Hash-provider contract
- Written legal sign-off
- Non-engineer review

## Region And Deploy Contract

Moment Cloud Functions must use `us-east1`.

Agents declare readiness only. Humans run deploys per function, for example:

```sh
firebase deploy --only functions:momentSummarize
```

Bare `firebase deploy` is outside contract.

## Firestore Data Shape

Moments live as finite documents keyed by Moment id:

```text
moments/{momentId}
```

Saved Deepen outputs live under the owning user:

```text
users/{ownerId}/momentSaves/{saveId}
```

Rules must be two-sided: they must prove both allow and deny paths in emulator evidence before any PASS claim.

## CalmCap Governance

Every surfaced Moment must pass this question: does this deepen formation, or just capture attention?

Encoded constraints:

- Pull, not push: no urgency push notifications for Moment surfacing in v1.
- No live-count theater: no rolling or animated participant counts, no per-event reward pulses or haptics.
- Bounded, not infinite: no infinite event feed; Moment surfaces are finite and dismissible.
- Deepen-first: Deepen is the only verb family wired in v1.

## Target Ownership Boundaries

- A1 owns endpoint files under `functions/src/moment/deepen/*` and stub-only gather files under `functions/src/moment/gather/*`.
- A2 owns Firestore rules, indexes, and save-collection data layer.
- A3 owns `functions/src/berean/momentAdapter/*`.
- A4 owns `Sources/Features/Moment/*` and `demos/moment/*.html`, with HTML demo approval before SwiftUI.
- A5 owns Deepen-only integration wiring.
- A6 owns `contracts/moment/VERIFICATION_LEDGER.md`.

No agent may edit `project.pbxproj`.

