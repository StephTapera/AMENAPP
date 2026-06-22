# AMEN — UX Placement Audit · Table C Decision Record

**Date:** 2026-06-15 · **Branch context:** `feature/berean-island-w0` · **Status:** decisions made. Dependent code must wait on a green build and on the per-item unblock conditions below.

These four were the human-decision blockers from the UX Placement Audit (Table C). They are now decided. Each entry is the decision, why, what ships vs. defers, and the condition that unblocks the rest.

---

## D-1 · Giving link attachment model (§7.7) — DECIDED (HUMAN+LEGAL checkpoint remains)

**Decision:** At launch, giving is for **verified nonprofit / church recipients only.** Collect via **Stripe Connect Standard** with an **in-app Stripe payment sheet**; the **donor is the Stripe Customer.** Gate `givingEnabled` on `charges_enabled == true` **and** nonprofit-status verification. **Defer** personal fundraisers and creator tips.

**Why:** Apple exempts donations to registered nonprofits from In-App Purchase — no 30% cut, Stripe permitted. Payments to individuals / personal fundraisers fall outside that carve-out and risk IAP rules or App Review rejection. Donor-as-Customer fixes the prior wrong-email recurring-billing bug; the `charges_enabled` gate doubles as the KYC gate, since Stripe onboarding verifies the church.

**Ships:** nonprofit-gated in-app Stripe donation sheet. **Defers:** personal fundraisers, creator tips.

**Unblock condition (HUMAN+LEGAL):** counsel confirms the recipient structure qualifies for Apple's nonprofit donation exemption; consider a pre-submission App Review inquiry. Do not enable until verification + sign-off.

---

## D-2 · Server-side draft sync (§4.9) — DECIDED

**Decision:** **No server-side sync.** Drafts stay **local-only (Tier P / on-device).** Defer cross-device sync to W4, behind the E2EE recovery model.

**Why:** Drafts can hold private/unpublished/reflection content. Syncing now means either plaintext server storage (breaks the privacy/honesty posture) or shipping E2EE with a recovery model not yet chosen. Cross-device drafts are a convenience not worth forcing either.

**Ships:** local autosave (already built — `LocalPostDraft.swift`). **Defers:** cross-device sync.

**Unblock condition:** E2EE account-recovery model decided (see `docs/privacy-model.md`).

---

## D-3 · ActivityKit extension target (§9.4 / §9.5) — DECIDED (sequencing)

**Decision:** **Add the ActivityKit / Widget extension target — but only after the build is green, and added by a human in Xcode** (not an agent).

**Why:** Adding a target is a `project.pbxproj` change (human-only rule), and doing it on the current red build makes new failures impossible to attribute. Order: green build → human adds target in Xcode → §9.4/9.5 extension code proceeds.

**Unblock condition:** build green; human adds target in Xcode with steps:
1. File → New → Target → Widget Extension → name `AmenLiveActivities`
2. Signing & Capabilities → add **ActivityKit** + **Push Notifications**
3. Compile Sources: add existing files from `AmenLiveActivities/` directory
4. Extension `Info.plist`: `NSSupportsLiveActivities = YES`
5. Main target `Info.plist`: confirm `NSSupportsLiveActivities = YES`

---

## D-4 · §8 selection-menu AI actions — App Review (§8.1–8.6) — DECIDED

**Decision:** **Build behind a flag, default OFF, now.** Before enabling: update the **privacy nutrition label** to declare **server-side processing of user-selected text** (not "on-device inference" — §8 routes through `BereanConstitutionalIntelligence.swift` / `BereanConstitutionalPipeline.swift`, which are cloud-backed Firebase callables). Prepare an **App Review rationale** citing GUARDIAN / the constitutional pipeline / interpretation-vs-direct-scripture labeling as the moderation layer.

**Why:** The functionality (4.2) is sound — real Berean-mode routing through an existing safety pipeline. The risks are an inaccurate privacy label (5.1) and Apple's sensitivity to AI content on theological topics. The safety pipeline is the answer to the latter, but only if the label honestly reflects off-device text transmission. Labeling it "on-device inference" when it's server-side is itself the inaccuracy problem (5.1).

**Architectural fact (confirmed):** §8 AI actions dispatch as `BereanIntent` cases (`.guard_`, `.discern`, `.build`) through `BereanConstitutionalPipeline`, which calls Firebase cloud functions server-side. Foundation Models / on-device inference is NOT in this path and must NOT be substituted — server-side moderation via GUARDIAN is the safety rationale that makes inline AI theology defensible to App Review.

**Privacy label update required:** declare User Content data type — "selected text" — transmitted off-device to AMEN's AI service. Cross-reference: `docs/APP_STORE_PRIVACY_LABEL_MAPPING.md`.

**Ships now:** flagged-OFF code. **Unblock condition:** privacy label updated + App Review rationale submitted. See `docs/APP_REVIEW_NOTES.md`.

---

## Connects to standing decisions

- **Stripe:** Connect Standard (donations), Express (Spaces payouts), Checkout (Covenant); reject Custom. **D-1 sits inside this.**
- **E2EE:** iCloud Keychain default + High Privacy Mode opt-in; stop labeling Tier S/C "encrypted." **D-2 waits on the recovery half of this.** See `docs/privacy-model.md`.

## Net effect on the waves

| Wave | Status | Gate |
|---|---|---|
| W1 — extend existing surfaces | **Unblocked** once build is green | Green build |
| W2 — §8 UIEditMenu + Berean routing | **Build now (flag OFF)** | Label + rationale before enable |
| W4 — §7.7 giving attach | **Deferred** | D-1 legal sign-off |
| W4 — §4.9 draft sync | **Deferred** | E2EE recovery model |
| §9.4/9.5 ActivityKit extension | **Deferred** | D-3: green build + human Xcode step |
