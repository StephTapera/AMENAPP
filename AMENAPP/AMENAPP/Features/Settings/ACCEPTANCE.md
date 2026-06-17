# Settings Safety Acceptance Matrix

Status values: `blocked`, `stubbed`, `wired`, `human-verified`.

| Gate | Requirement | Current Status | Evidence / Next Step |
|---|---|---|---|
| R0 | Wave 0 contracts compile | blocked | `BuildProject` timed out after prior duplicate-output failures; human canonical build still required. |
| R1 | Shell route reachable | wired | `SettingsSafetyReleaseTrainView` is routed from `AMENSettingsView` once AMENSettingsSystem switch is patched. |
| R1 | Flag-off disabled states render safely | wired | Each release-train surface renders a reviewable flag-off detail state with disabled status reporting. |
| R1 | Reduce transparency fallback | stubbed | Needs Lane A implementation in `DesignSystem/Settings/**`. |
| R2 | Security surface | stubbed | Visible in release hub; live actions wait on Lane B and Lane G callables. |
| R2 | Trusted Contact surface | stubbed | Visible in release hub; notification remains server-only and GUARDIAN/Aegis-gated. |
| R2 | Family/Parental surface | stubbed | Visible in release hub; guardian-wall rules/tests are not implemented here. |
| R2 | Notifications/General surfaces | stubbed | Visible in release hub; persistence and notification floors remain Lane D. |
| R2 | Storage/Data/About/Report surfaces | stubbed | Visible in release hub; deletion/export/report callables remain Lane E/G. |
| R2 | Berean AI controls | stubbed | Visible in release hub; S5/S9 enforcement remains Lane F. |
| R3 | Settings callables deployed to us-east1 | blocked | Human-run per-function deploy required after Lane G implementation. |
| R3 | Firestore settings rules deny-by-default | blocked | Lane G rules and rules tests not present in this patch. |
| R4 | No dependency TODOs on shipping surfaces | blocked | `TODO(dependency:)` comments intentionally remain while callables are not deployed. |
| R5 | Child-safety launch gate | blocked | Human/legal verification required for COPPA, NCMEC, CSAM, age gates, and guardian wall. |
| R5 | Security/credentials launch gate | blocked | Human credential rotation/history purge verification required. |
| R5 | Privacy launch gate | blocked | App Privacy labels and E2EE export behavior require human verification. |
| R5 | Berean AI safety launch gate | blocked | S5/S9 enforcement must be verified across Berean surfaces. |
| R5 | App Store mechanics | blocked | Account deletion, UGC, permissions, login parity, encryption, payment, and age rating require human verification. |
| R5 | Accessibility | stubbed | Needs Lane A and per-surface Dynamic Type/VoiceOver/contrast validation. |
