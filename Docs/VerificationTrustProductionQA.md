# Verification & Trust Production QA

This runbook closes the non-code release gates for Amen Verification & Trust.

## 1. Live Provider Smoke Test

Run against staging first.

Persona:

```bash
KYC_PROVIDER=persona \
KYC_PERSONA_API_KEY=... \
KYC_PERSONA_TEMPLATE_ID=... \
AMEN_KYC_WEBHOOK_URL=https://.../handleIdentityVerificationWebhook \
node Backend/scripts/verification-provider-smoke.mjs
```

Stripe:

```bash
KYC_PROVIDER=stripe \
KYC_STRIPE_SECRET_KEY=... \
AMEN_KYC_WEBHOOK_URL=https://.../handleIdentityVerificationWebhook \
node Backend/scripts/verification-provider-smoke.mjs
```

Pass criteria:

- Provider returns an HTTPS hosted session URL.
- Deployed webhook rejects unsigned payloads with `401`.
- Sandbox approval updates `users/{uid}/privateVerification/main`.
- Sandbox rejection leaves public badges unchanged.
- Replaying the same webhook does not duplicate approval state or audit logs.
- No raw ID/selfie/document data appears in Firestore.

## 2. Admin Reviewer E2E

Use a staging admin account and a staging applicant account.

Steps:

1. Applicant starts identity verification.
2. Applicant requests organization verification.
3. Applicant requests role verification.
4. Reviewer opens admin review UI.
5. Reviewer marks one request `needs_more_info`.
6. Reviewer rejects one request with safe user reason.
7. Reviewer approves role verification with required reason.
8. Reviewer revokes that role with required reason.
9. Confirm `verificationAuditLogs` has every decision.
10. Confirm public badges appear/disappear from profile surfaces after summary refresh.

Pass criteria:

- Reviewer notes are not visible to normal users.
- Required reason cannot be bypassed.
- Revoked roles disappear from scoped public surfaces.
- User-facing copy is safe and non-accusatory.

## 3. Broad Surface QA

Check badges only where contextually useful:

- User profile header.
- Organization profile header.
- Spaces/member-style cards.
- Discussion host cards.
- Creator profile cards.
- Direct message profile sheet.
- Comments/replies only when the badge clarifies identity or role.

Do not add badges to normal feed cards or dense comment streams by default.

Pass criteria:

- No generic blue check appears.
- Badges are scoped and explainable on tap.
- Hidden metrics philosophy is preserved.
- Surfaces without `publicVerificationSummary` fail closed by showing no badge.

## 4. Remote Config Rollout

Validate template:

```bash
node Backend/scripts/verify-verification-remote-config.mjs
```

Rollout order:

1. `verification_center_enabled`
2. `organization_verification_enabled`
3. `role_verification_enabled`
4. `impersonation_reports_enabled`
5. `public_trust_badges_enabled`
6. `creator_verification_enabled`
7. `identity_verification_enabled` only after live provider smoke passes

Rollback:

- Set the affected flag to `false`.
- Confirm app hides the flow or badge.
- Confirm existing Firestore truth records remain unchanged.

## 5. Data Backfill

Dry-run:

```bash
GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
node Backend/scripts/backfill-verification-summaries.mjs --limit=100
```

Write:

```bash
GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
node Backend/scripts/backfill-verification-summaries.mjs --limit=100 --write
```

Pass criteria:

- Dry-run reviewed before writes.
- Existing verified users get `publicVerificationSummary`.
- Unverified users remain badge-free.
- Organization summaries are written to `organizations/{orgId}/publicVerificationSummary/main`.

## 6. Accessibility Device Pass

Test these surfaces on iPhone SE, standard iPhone, Pro Max, and iPad:

- Verification Center.
- User profile header badges.
- Mini profile/member cards.
- Admin review UI.

Settings:

- VoiceOver.
- Larger Dynamic Type.
- Increase Contrast.
- Reduce Transparency.
- Reduce Motion.
- Dark Mode.

Pass criteria:

- Every badge has a VoiceOver label.
- Badge tap target is at least 44pt.
- Badge meaning is not conveyed by color alone.
- Explanation sheet is reachable and dismissible.
- Layout does not clip at large text sizes.

## Final Gate

After the checks above are completed, copy:

```bash
cp Docs/VerificationTrustQAResults.template.json Docs/VerificationTrustQAResults.staging.json
```

Fill every `status` with `pass` and provide evidence for each check, then run:

```bash
node Backend/scripts/verification-release-gate.mjs \
  --results Docs/VerificationTrustQAResults.staging.json
```

Production is **NO-GO** unless this script prints:

```text
GO: Verification & Trust production release gate passed.
```
