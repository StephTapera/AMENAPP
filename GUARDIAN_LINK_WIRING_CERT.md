# Guardian Link — Total Control Wiring Certificate
**Finding:** #44 (DEPLOY_PACKAGE_SAFETY_CONSOLIDATED.md) | **Commit:** `35a09617` | **Date:** 2026-06-20
**Flag:** `guardian_link_enabled` (Remote Config, default **OFF**) | **Build:** BuildProject green

The guardian email-verification pipeline: a minor invites a parent/guardian by email;
the guardian receives a 6-digit code; entering it links the accounts and writes the
`guardianApprovedContacts` document that `isGuardianApprovedContact()` reads.

---

## Surface → Control → Destination → Disposition

| Surface | Control | Destination | Disposition |
|---|---|---|---|
| `GuardianLinkInvitationView` (minor) | "Send invite" button | `GuardianLinkService.requestGuardianLink(guardianEmail:)` → `guardianLinkRequests/{id}` write | **WIRED** |
| `GuardianLinkInvitationView` | Email text field | local `@State`, validated by `isValidEmail` before send | **WIRED** |
| `GuardianLinkInvitationView` | Flag OFF | returns `EmptyView()` | **fail-closed** |
| `GuardianLinkVerificationView` (guardian) | 6-digit code field | digit-filtered `@State`, capped at 6 | **WIRED** |
| `GuardianLinkVerificationView` | "Confirm link" button | `GuardianLinkService.verifyGuardianLink(requestId:otp:)` → `verifyGuardianLink` CF | **WIRED** |
| `GuardianLinkVerificationView` | Flag OFF | returns `EmptyView()` | **fail-closed** |
| `GuardianSupervisionSettingsView` | "Link a Guardian" row | presents `GuardianLinkInvitationView` (flag ON) | **WIRED** |
| `GuardianSupervisionSettingsView` | Flag OFF | legacy email `@AppStorage` field (prior behavior) | **honestly-disabled** |
| `onGuardianLinkCreated` CF | Firestore trigger | sends OTP email, stamps `otpHash`+`expiresAt`, rate-limit 3/24h | **WIRED** |
| `verifyGuardianLink` CF | callable (Auth + App Check) | constant-time OTP check → `guardianApprovedContacts/{minorId}/contacts/{guardianUid}` | **WIRED** |
| `verifyGuardianLink` CF | flag OFF | throws `failed-precondition` | **fail-closed** |

---

## Security Invariants (verified)

| ID | Invariant | Evidence |
|---|---|---|
| I-GUARDIAN-1 | Only the minor reads their own request | `firestore.rules` guardianLinkRequests `read: minorId == auth.uid` |
| I-GUARDIAN-2 | OTP hash stored, never raw | `guardianLink.js` stores `sha256(otp)`; test "never returns the raw OTP" passes |
| I-GUARDIAN-3 | 24h token expiry | `expiresAt` checked in `verifyGuardianLink`; `deadline-exceeded` on expiry |
| I-GUARDIAN-4 | Max 3 verify attempts | `attemptCount` incremented pre-validation; `resource-exhausted` at 3 |
| I-GUARDIAN-5 | Max 3 requests / minor / 24h | `count()` query in `onGuardianLinkCreated` |
| I-GUARDIAN-6 | Approved-contacts writes are CF-only | `firestore.rules` `contacts/{contactId}` + `guardianLinks/**` `create,update,delete: if false` |
| I-GUARDIAN-7 | No CSAM/NCMEC coupling | grep clean — guardianLink.js has no NCMEC path |
| OTP email privacy | `mail/{mailId}` denies all client access | `firestore.rules` `mail/{mailId}` `read, write: if false` |

---

## Tests

| Test | Result |
|---|---|
| `functions/test/guardianLink.test.js` — generateOTP 6-digit format (200 runs) | ✅ |
| sha256 stability + raw-OTP-never-leaked | ✅ |
| isValidEmail fail-closed on null/non-string | ✅ |
| **Total** | **8/8 pass** |
| iOS BuildProject | ✅ green |
| firestore.rules brace balance | ✅ 787/787 |

---

## Human Deploy Steps (HUMAN-ONLY)

1. `firebase deploy --only functions:onGuardianLinkCreated,functions:verifyGuardianLink --project amen-5e359`
2. Install the **Trigger Email** Firebase Extension (or wire SendGrid) so `mail/` queue sends real email. Until then, the CF logs the OTP to admin-only Cloud Logging as a dev fallback.
3. Deploy rules: `firebase deploy --only firestore:rules --project amen-5e359` (guardianApprovedContacts subcollection, guardianLinks, mail).
4. Add Remote Config key `guardian_link_enabled` (default false).
5. **Flag flip gated on A-03 policy decision** (guardian consent model) — do not flip before that decision is recorded in `DECISION_BRIEFS/A-03_*`.
