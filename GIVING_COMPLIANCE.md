# AMEN Giving — Compliance & Legal Gate Register

Last updated: 2026-06-15
Branch: feature/berean-island-w0
Auditor: Claude Code (automated audit + PAY-001 auto-fix)

---

## Status summary

| ID     | Severity | Status            | Owner        |
|--------|----------|-------------------|--------------|
| PAY-001 | Critical | FIXED (auto)     | Engineering  |
| PAY-002 | Critical | HUMAN+LEGAL GATE | Legal + Eng  |
| PAY-004 | High     | HUMAN+LEGAL GATE | Legal + Eng  |
| PAY-005 | High     | AUDIT COMMENT     | Engineering  |
| PAY-007 | Medium   | HUMAN+LEGAL GATE | Legal + CPA  |
| MISSING | Critical | HUMAN GATE        | Engineering  |

---

## PAY-001 — Donor Customer bug (FIXED)

**Finding:** `processGivingCharge.ts` was creating Stripe Subscriptions with
`customer_email: nonprofit.contactEmail` — the receiving organization's address
— instead of the donor's email. This routed receipts, payment failure notices,
and subscription management emails to the nonprofit's contact instead of the
person who donated.

**Root cause:** Line 104 in the original file used `nonprofit.contactEmail` in
the `customer_email` field of the Subscriptions API call, which is the
deprecated way to associate a Customer with a Subscription. A Stripe Subscription
must be attached to a `customer` (Customer object) owned by the donor.

**Fix applied (auto):**
- Added `getAuth` import from `firebase-admin/auth`.
- Resolved donor email from Firebase Auth (`getAuth().getUser(uid).email`).
- Added a Stripe Customer lookup-or-create block keyed by `metadata.uid = donorUid`
  so the same Customer is reused across multiple donations (avoids orphaned objects).
- Replaced `customer_email: nonprofit.contactEmail` with `customer: donorCustomerId`
  on the Subscription creation call.
- Removed the duplicate `stripeSecretKey.value()` call (moved to shared scope above).

**File changed:** `Backend/functions/src/giving/processGivingCharge.ts`

**Deploy required:** Yes — redeploy `processGivingCharge` to `us-central1`:
```
firebase deploy --only functions:creator:processGivingCharge
```

---

## PAY-002 — givingEnabled must gate on Stripe charges_enabled (HUMAN+LEGAL GATE)

**Finding:** The `nonprofits/{id}.givingEnabled` flag is set manually in
Firestore (or by the org admin). There is no check that the nonprofit's
Stripe Connected Account has `charges_enabled == true` before allowing
donations to flow. If a Stripe account is under review, restricted, or
misconfigured, charges will fail at runtime after the donor has already
committed to a payment — a poor UX and a potential compliance gap.

**Required controls (not yet implemented):**
1. A Cloud Function (or webhook handler) that listens to
   `account.updated` Stripe Connect webhooks and syncs
   `charges_enabled` / `payouts_enabled` to
   `nonprofits/{id}.stripeChargesEnabled`.
2. `processGivingCharge.ts` must reject the call with a friendly
   `failed-precondition` error if `stripeChargesEnabled !== true`,
   regardless of the `givingEnabled` flag.
3. The admin panel / onboarding flow must only allow setting
   `givingEnabled = true` after Stripe confirms `charges_enabled`.

**Why HUMAN+LEGAL:** Enabling giving for an account without Stripe KYC
verification complete may violate Stripe's Connect platform agreement and
potentially money-transmission regulations. Legal must confirm whether AMEN
qualifies as a Payment Facilitator under state MSB rules before toggling
this for all nonprofits.

**Action required:**
- [ ] Legal: confirm MSB / PayFac classification
- [ ] Engineering: implement `account.updated` webhook sync
- [ ] Engineering: add `stripeChargesEnabled` guard in `processGivingCharge.ts`
- [ ] Ops: audit existing nonprofits with `givingEnabled=true` that may lack `charges_enabled`

**DO NOT** flip `givingEnabled` for any new nonprofit until this gate is closed.

---

## PAY-004 — Payout bank account changes must require re-auth + Stripe webhook verification (HUMAN+LEGAL GATE)

**Finding:** There is no evidence of a control requiring re-authentication or
Stripe webhook verification when a nonprofit admin changes their payout bank
account destination. An undetected account takeover could silently redirect
giving funds to a fraudulent account.

**Required controls (not yet implemented):**
1. Any write to `nonprofits/{id}.stripeConnectedAccountId` or any Stripe
   Connected Account external bank account change must trigger a re-auth
   challenge (step-up MFA or Firebase custom token challenge).
2. After a bank account change, a Stripe `account.external_account.created`
   webhook must be received and verified before the new account is treated
   as active for payouts.
3. All bank account change events must be logged to
   `nonprofits/{id}/adminAuditLog` with timestamp, admin uid, and old/new
   last-4 digits.
4. Notify the org's registered contact email of any payout destination change
   with a 24-hour reversal window.

**Why HUMAN+LEGAL:** Undetected fraudulent payout redirection is a financial
crime exposure. Legal must confirm incident response obligations and disclosure
requirements if a fraudulent redirect is discovered after funds have been paid out.

**Action required:**
- [ ] Legal: review liability exposure and disclosure obligations
- [ ] Engineering: step-up auth for bank account mutations
- [ ] Engineering: `account.external_account.created` webhook verification
- [ ] Engineering: admin audit log + donor notification

---

## PAY-005 — Donor success event must wait for payment_intent.succeeded webhook

**Finding:** `GivingInAppSheet.swift` (line 425) fires `onSuccess()` immediately
after the `processGiving` Cloud Function callable returns. The callable only
confirms that Stripe accepted the PaymentIntent creation — it does not confirm
that funds were captured. For Apple Pay payments, the authorization and capture
are separate steps and can fail between them (e.g. insufficient funds after
Apple Pay authorization).

**Audit comment added** to `AMENAPP/GivingInAppSheet.swift` at the call site.

**Required fix (not yet implemented):**
1. `processGivingCharge` webhook handler must listen for
   `payment_intent.succeeded` and update
   `users/{uid}/givingHistory/{chargeId}.status = "succeeded"`.
2. iOS client must observe that Firestore document with a timeout (e.g. 15s)
   before showing the success screen.
3. For subscriptions: listen for `invoice.payment_succeeded` instead.
4. On timeout: show a "Your gift is being processed" pending state, not
   the full success screen.

**File annotated:** `AMENAPP/GivingInAppSheet.swift`

---

## PAY-007 — Tax receipts: Stripe Standard and 1099-K obligations (HUMAN+LEGAL GATE)

**Finding:** The app shows in-UI copy: "You'll receive a tax receipt at your
verified email address." The mechanism for generating and sending tax receipts
is not implemented in the codebase. This is a HUMAN+LEGAL gate because:

1. **Stripe Standard Connected Accounts** (the current model) receive 1099-K
   forms directly from Stripe when they exceed the IRS threshold ($600/year
   as of 2024). AMEN as the platform does NOT generate 1099-K for the nonprofits
   — Stripe does. Legal must confirm this is understood and communicated to
   nonprofit onboarding.
2. **Donor-side receipts:** Donations to 501(c)(3) organizations qualify for
   deduction. The nonprofit (not the platform) is responsible for issuing the
   charitable contribution acknowledgment letter. AMEN's role as platform is
   not to issue these — but the in-app copy implies AMEN will send one.
3. **Correction needed:** Remove or qualify the "tax receipt" UI copy until a
   receipting mechanism is confirmed and reviewed by legal.

**Action required:**
- [ ] Legal: confirm Stripe Standard 1099-K responsibility chain
- [ ] Legal: determine whether AMEN must issue contribution acknowledgments or
      whether this is delegated entirely to each nonprofit
- [ ] Engineering: update in-app copy to accurately describe what the donor
      will receive and from whom
- [ ] Engineering: if AMEN is to generate receipts, implement the receipt
      generation pipeline and confirm IRS acknowledgment letter format with legal

---

## MISSING — Critical unimplemented Cloud Functions

The following backend services are referenced in iOS code or contracts but do
not have corresponding deployed Cloud Functions. All are HUMAN GATE items
before their respective features can go live.

### processGivingCharge.ts — exists but needs re-deploy after PAY-001 fix

See PAY-001 above.

### covenant/* Cloud Functions — not found

Referenced in architecture docs / contracts. No source found in
`Backend/functions/src/`. If covenant/vow features involve financial
commitments or recurring pledges, they share the same PAY-002/PAY-004
compliance requirements.

**Action required:**
- [ ] Engineering: implement or confirm removal from roadmap
- [ ] Legal: if covenant involves financial pledge, route through same
      Stripe compliance gates as givingEnabled

### Spaces Connect Cloud Functions — not fully deployed

The `ConnectSpaces/` iOS module references backend callables that are
confirmed not deployed (see `project_spaces_connect_full_build_2026_06_02.md`
memory entry: "23 CF deploys pending").

**Action required:**
- [ ] Engineering: audit which Spaces CFs are live vs. stub
- [ ] Engineering: deploy missing CFs before enabling Spaces features

---

## Deployment checklist (giving feature)

Before any giving feature flag is enabled in production:

- [ ] PAY-001 fix deployed: `firebase deploy --only functions:creator:processGivingCharge`
- [ ] PAY-002 `stripeChargesEnabled` guard implemented and deployed
- [ ] `account.updated` webhook registered in Stripe Dashboard (Connect webhooks)
- [ ] PAY-004 step-up auth for bank account changes implemented
- [ ] PAY-005 webhook-confirmed success flow implemented (or success screen changed to "pending")
- [ ] PAY-007 legal sign-off on tax receipt copy and 1099-K responsibility chain
- [ ] Firestore rules updated to protect `nonprofits/{id}/stripeConnectedAccountId`
      from direct client writes

---

*This document is generated as part of the AMEN security audit process.*
*It is NOT a substitute for legal review. Items marked HUMAN+LEGAL GATE*
*must not be deployed without sign-off from both legal counsel and engineering leadership.*
