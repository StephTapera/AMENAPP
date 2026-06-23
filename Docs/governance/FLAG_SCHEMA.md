# Safety-Critical Flag Schema (Wave 5, Invariant 6)

Generalizes the existing four-part CSAM gate to **all** safety-critical flags: any flag
tagged `safety_critical` is **default-OFF** and **cannot be enabled without a recorded
human sign-off** (who / when / on what basis). Enabling requires **two** independent acts:
a sign-off in a reviewed commit **and** a Remote Config flip. Neither alone turns the
capability on.

## Source of truth

| Side | File | Role |
|------|------|------|
| Server | `Backend/functions/src/governance/flagRegistry.ts` | Canonical `SAFETY_CRITICAL_FLAGS` + `auditFlagRegistry()` (CI) + `effectiveFlagEnabled()` (runtime fail-closed). |
| Client | `AMENAPP/AMENFeatureFlags.swift` → `AMENFeatureFlagGovernance` | Mirror: `canEnable()` / `effectiveEnabled()` force OFF unless a sign-off exists. |

## Current registry (all default-OFF, no sign-off ⇒ all un-enableable)

| Key | CSAM-class | Why safety-critical |
|-----|-----------|---------------------|
| `csam_hash_scan_enabled` | ✓ | Four-part federal gate; never DIY. |
| `connect_kids_facial_verification` | ✓ | Biometric of minors — a lock, not a switch. |
| `connect_live_rooms_enabled` | | Live A/V; needs recording-consent + CSAM hooks first. |
| `connect_family_dashboard_enabled` | | Minor oversight; counsel-gated. |
| `berean_crisis_followup_sync_enabled` | | Crisis data; needs verified field-level encryption. |
| `moderation_auto_enforcement_enabled` | | Must route through the HITL boundary (inv. 5). |

CSAM-class flags require the sign-off's `nonEngineerReviewer` to be true.

## CI enforcement (Wave 6)

`auditFlagRegistry()` fails the build if any safety-critical flag:
- ships default-ON (`INV6_DEFAULT_OFF`),
- is enable-able without a complete sign-off,
- has an engagement-driven purpose (`INV1_PURPOSE_FIREWALL`), or
- attempts to override a red line (`INV4_RED_LINE_DENY`).

## How to enable one (the only path)

1. In a reviewed PR, replace the flag's `nil` with a complete `FlagSignOff` (TS) /
   `AMENFlagSignOff` (Swift): approver, ISO timestamp, basis; `nonEngineerReviewer: true`
   for CSAM-class.
2. Flip the corresponding Remote Config key.

`effectiveFlagEnabled` / `effectiveEnabled` then return `true`; until both are done they
return `false` even if Remote Config says ON.
