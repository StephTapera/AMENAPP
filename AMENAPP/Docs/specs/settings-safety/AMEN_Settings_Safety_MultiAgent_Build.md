# AMEN / Berean Settings, Safety, Privacy, Storage, Notifications & Account-Control System

Contracts-first, wave-based build spec for the AMEN settings and safety release train.

## Mission
Build a complete Liquid Glass settings, safety, privacy, storage, notification, feedback, family, and account-control system for AMEN / Berean. AMEN identity, theological humility, user dignity, child safety, privacy, and anti-addiction defaults lead the system.

## Frozen Safety Invariants
- S1 - Safe defaults: new toggles default protective; rollout flags default off.
- S2 - Sensitive operations are server-authoritative and audited.
- S3 - Users read/write only their own `users/{uid}/...` subtree; server queues deny client writes.
- S4 - Guardian wall: parents see safety flags and account controls only, never private journals, prayers, DMs, or Living Memory content unless explicitly shared.
- S5 - Berean AI is never framed as pastor, prophet, priest, therapist, counselor, or emergency responder.
- S6 - Analytics carries categorical metadata only, never sensitive free text.
- S7 - Child-safety pipelines, age gates, COPPA VPC, CSAM matching, and NCMEC reporting cannot be weakened by settings.
- S8 - Destructive operations confirm; irreversible operations double-confirm.
- S9 - Sources, scripture cross-checking, AI labels, uncertainty labels, and alternatives are system-enforced for doctrinal claims.
- S10 - E2EE exports/deletion respect client-side keys; the server never sees plaintext.

## Wave 0 Artifacts
- `SettingsContracts/SettingsContractModels.swift`: Codable model contracts and safe defaults.
- `SettingsContracts/SettingsFoundationContracts.swift`: Firestore paths, feature flags, Cloud Function registry, analytics, audit schemas, invariants.
- `SettingsContracts/SettingsComponentContracts.swift`: placeholder SwiftUI component API contracts.
- `SettingsContracts/BUILD_REQUEST.md`: human build-broker request.

## Feature Flags
All flags in `SettingsFeatureFlag` default to `false`: `ff_settings_v2`, `ff_appearance_v2`, `ff_general_v2`, `ff_passkeys`, `ff_mfa_totp`, `ff_mfa_sms`, `ff_lockdown_mode`, `ff_face_id_gate`, `ff_sessions`, `ff_trusted_contact`, `ff_parental_controls`, `ff_family_linking`, `ff_notification_prefs_v2`, `ff_storage_management`, `ff_data_export`, `ff_account_deletion`, `ff_ai_memory_delete`, `ff_berean_ai_controls`, `ff_amen_safety_controls`, `ff_issue_reporting`.

Flag-off surfaces must render safe disabled states with clear copy and a `TODO(dependency):` comment naming the missing backend.

## Backend Contracts
New settings functions use `SettingsFunctionContract.region == "us-east1"`. Sensitive operations require authenticated callable Cloud Functions with App Check, re-auth where appropriate, and audit logging.

Callable names are frozen in `SettingsFunctionContract.Callable`. Internal-only functions are `writeAuditLog`, `stripSensitiveFields`, and GUARDIAN/Aegis-gated `notifyTrustedContact`.

## File Ownership
- `SettingsContracts/**` - Wave 0, frozen after ratification.
- `DesignSystem/Settings/**`, `Features/Settings/Shell/**` - Lane A.
- `Features/Settings/Security/**` - Lane B.
- `Features/Settings/SafetyFamily/**` - Lane C.
- `Features/Settings/Notifications/**`, `Features/Settings/General/**` - Lane D.
- `Features/Settings/Storage/**`, `Features/Settings/DataControls/**`, `Features/Settings/About/**`, `Features/Settings/ReportIssue/**` - Lane E.
- `Features/Settings/BereanAI/**` - Lane F.
- `functions/src/settings/**` and settings block of `firestore.rules` - Lane G.

## Operating Protocol
Agents write code and produce build requests. The human runs the canonical build and per-function deploys. No lane claims completion until artifacts exist, the human build report is green, and the lane definition of done is met. Broad Firebase deploys are forbidden; deploy named functions only.

## Human-Gated Decisions
- HTML demo gate per settings surface.
- E2EE export approach and key-loss copy.
- Reuse path for GUARDIAN/Aegis moderation queue.
- Confirmation of `us-east1` for new functions.
- Safety/account notification floors.
- COPPA VPC first method.

## Acceptance Matrix
Lane G owns the living `ACCEPTANCE.md`. Wave 6 requires all rows pass, including wired actions, dismissible sheets, destructive confirmations, audit logging, guardian-wall denials, crisis routing, no sensitive analytics text, clean flag-off states, and reduce-transparency fallbacks.
