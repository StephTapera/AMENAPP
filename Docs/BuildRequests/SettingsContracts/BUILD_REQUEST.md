# Wave 0 Build Request - Settings Safety Contracts

## Lane
Coordinator / Wave 0

## Changed files
- `AMENAPP/AMENAPP/SettingsContracts/SettingsContractModels.swift`
- `AMENAPP/AMENAPP/SettingsContracts/SettingsFoundationContracts.swift`
- `AMENAPP/AMENAPP/SettingsContracts/SettingsComponentContracts.swift`

## What landed
- Codable settings data contracts for appearance, general preferences, security mirror state, sessions, trusted contacts, family links, parental controls, notification preferences, Berean AI controls, AMEN safety preferences, storage breakdown, and issue reports.
- Frozen feature flag registry with all requested `ff_*` flags defaulting `false`.
- Firestore path contracts for owner-scoped settings documents and server-owned audit/report/moderation/family collections.
- Cloud Function contract registry with `region = "us-east1"`.
- Categorical-only analytics event and append-only audit event contracts.
- Placeholder SwiftUI component API contracts for the settings shell, rows, modals, toggles, pickers, storage, sessions, reporting, trusted contacts, parental controls, notifications, and data controls.

## Naming note
Existing app code already defines global `TrustedContact`, `NotificationCategory`, `PrayerVisibility`, and `AuditEventType`. The Wave 0 contract equivalents use project-safe names:
- `SettingsTrustedContact`
- `SettingsNotificationCategory`
- `SettingsPrayerVisibility`
- `SettingsAuditEventType`

## Verification performed by agent
- `XcodeRefreshCodeIssuesInFile` on `SettingsContractModels.swift`: no issues.
- `XcodeRefreshCodeIssuesInFile` on `SettingsFoundationContracts.swift`: no issues.
- `XcodeRefreshCodeIssuesInFile` on `SettingsComponentContracts.swift`: Xcode SourceEditor diagnostic retrieval failed with error 5, so this file still needs canonical build verification.

## Human verification requested
Run the canonical Xcode build for the active scheme and report pass/fail. If it fails, include the first compiler error touching `SettingsContracts/**`.

## No deploys
No Cloud Functions or Firestore rules were changed in Wave 0.
