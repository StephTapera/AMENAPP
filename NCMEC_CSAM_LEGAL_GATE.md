# NCMEC / CSAM Legal Gate

**Generated:** 2026-06-27  
**Status:** LEGAL BLOCKED / FAIL-CLOSED

## Current Implementation Evidence

- `ModerationMeshContracts.swift` defines `CSAMComplianceGate.closed` with legal/credential prerequisites defaulting to `false`.
- `AmenSafetyModerationProvider.swift` marks CSAM media scanning as a human/legal gate and warns not to enable it without PhotoDNA/equivalent, CyberTipline, legal sign-off, and deployment verification.
- `ChildSafetyController.swift` routes CSAM escalation to the internal safety queue only and explicitly does not file NCMEC reports.
- `ChildSafetyControlsView.swift` tells users formal NCMEC reporting requires legal registration handled by the safety team.
- `CameraChildSafetyService.swift` treats missing CSAM screening infrastructure as fail-closed for publish decisions.

## Credentials

No verified production credentials were present in this pass:

- `NCMEC_API_KEY`: not verified
- `NCMEC_ENDPOINT`: not verified
- PhotoDNA / equivalent hash provider credentials: not verified

## Legal Sign-Off

Not present in this workspace.

Required before any live reporting or provider-backed hash lookup:

- NCMEC ESP registration.
- Written 18 USC 2258A legal sign-off.
- PhotoDNA/NCMEC HashConnect/equivalent provider agreement.
- NCMEC endpoint/key approval.
- Non-engineering deploy reviewer.

## Runtime Status

Live NCMEC/CSAM reporting must remain disabled/quarantined until all gates above are satisfied. Internal safety escalation may remain available if it does not claim to file external reports.

## Release Impact

This is a legal release blocker. Do not deploy or enable CyberTipline/NCMEC/CSAM enforcement paths without written legal/credential proof.

## Final Release-Closeout Gate Table

| Gate | Status | Evidence | Owner | Exact next action |
| --- | --- | --- | --- | --- |
| Legal approval | BLOCKED | No written legal approval artifact is present in this workspace. | Legal | Approve the CSAM/NCMEC operating procedure in writing before any live external reporting or hash-provider enforcement is enabled. |
| NCMEC/CSAM credentials | BLOCKED | `NCMEC_API_KEY`, `NCMEC_ENDPOINT`, PhotoDNA/equivalent hash credentials, `CSAM_HASH_LOOKUP_URL`, and `CSAM_HASH_LOOKUP_TOKEN` were not verified. | Trust & Safety | Complete provider onboarding and set approved credentials through Firebase Secret Manager or the approved production runtime injection path. |
| Provider endpoint | BLOCKED | `Docs/Readiness/MODERATION_PROVIDER_CONFIG.md` records missing provider endpoint/token values. | Firebase production owner | Set `CSAM_HASH_LOOKUP_URL` and `CSAM_HASH_LOOKUP_TOKEN` with approved values; do not commit them. |
| Runtime fail-closed | CLOSED | `mediaModerationPipeline.ts` requires provider config when `REQUIRE_MEDIA_MODERATION_PROVIDERS=true`; missing config keeps readiness blocked. | Engineering | Keep fail-closed behavior intact and rerun the App Store readiness wrapper after real provider config is present. |
| User-facing claim accuracy | BLOCKED | No product/legal approval artifact confirms external NCMEC/CSAM reporting claims are accurate. | Product/Legal | Review all user-facing moderation language and remove or qualify claims until legal reporting is actually registered, configured, and verified. |
