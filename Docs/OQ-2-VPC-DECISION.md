# OQ-2 — Verifiable Parental Consent (VPC) Decision Doc

**Purpose:** Resolve OQ-2 so the C-4 guardian-tooling build can start against a confirmed model.  
**Blocks:** C-4 (`requestGuardianLink()`, parent review/delete tooling, Firestore guardian-access rules). Do not build C-4 until this is decided — the consent model dictates the data model.  
**Status:** Draft for Steph + Legal/T&S review. Not legal advice. Every "counsel confirms" tag is a real gate.  
**Last updated:** 2026-06-15

---

## 0. Read this first — what actually changed

Two facts reshape this decision:

1. **The 2025 COPPA Rule amendment is already in effect.** Its compliance deadline was **April 22, 2026** — now past. AMEN must comply with the *amended* rule (updated VPC methods, separate consent for third-party disclosure / targeted ads, mandatory written data-retention policy, enhanced data-security program). Designing to the old 2013 rule is non-compliant.

2. **"Email plus" is disqualified the moment a child can post publicly or message anyone.** The FTC's low-friction "email plus" method is permitted **only** when children's data is used internally and is never disclosed to third parties or made public. A social platform — public posts, DMs, comments, profiles others can see — is "public disclosure" by definition. So for any social feature, you need a **rigorous** VPC method, full stop.

Together these mean OQ-2 is really two decisions stacked: **(0) do we support under-13 at all, and in what mode** → then **(1) which rigorous method** if the answer requires one.

---

## Decision 0 — Does AMEN support under-13 users? (decide this first)

COPPA applies only to children **under 13**. The cheapest compliance path is to not be subject to VPC at all. Three paths:

| Path | What it means | VPC burden | What you keep / lose |
|------|----------------|------------|----------------------|
| **A — 13+ only** | Prohibit under-13 accounts. Real age gate at signup; block + delete on detection. | **None** (no COPPA VPC) | Ships fastest. Loses the under-13 family/discipleship/youth-group audience. Still need 13–17 minor protections (adult→minor DM block, etc.) and state-law minor rules. |
| **B — Under-13, restricted "internal-only" mode** | Under-13 accounts exist but can't post publicly, can't DM, no third-party data sharing, no ads. Data used internally only. | **Light** — "email plus" may suffice for this tier | Keeps a kid tier but it's heavily limited; arguably not a real social experience. Complexity: you must enforce the walls technically, and prove no third-party SDK touches kids' data. |
| **C — Under-13, full social** | Under-13 kids get posting/DM/social. | **Heavy** — rigorous VPC required + ongoing compliance program | Full product for kids. Highest build + legal + operational cost; ongoing retention/security obligations. |

**The strategic read:** Path A is what most mainstream social apps chose (13+ only) precisely to sidestep COPPA. AMEN has a genuine mission reason to want under-13 (family discipleship, youth groups) — but that reason has to be worth a permanent compliance program, not just a one-time build. A common, defensible sequence: **ship v1 as Path A (13+ only), add a vetted under-13 tier later** once there's a Legal/T&S function to own it. If under-13 is mission-critical for launch, go to Decision 1.

> ⚠️ **Counsel confirms:** even Path A (13+ only) carries obligations — neutral age screening, handling 13–17 minors under FTC and various state minor-privacy laws, and Apple/Google age-rating rules. "13+" reduces COPPA exposure to near-zero; it does not zero out minor-safety obligations.

---

## Decision 1 — Which rigorous VPC method (only if Path B-social or Path C)

If under-13 users touch any social/public/third-party surface, pick from the FTC-recognized rigorous methods below. The Rule does **not** mandate a specific method — the standard is "reasonably calculated to ensure the person consenting is the child's parent." These are the methods the FTC has determined meet that bar (per 16 CFR § 312.5(b)(2), as amended).

| Method | How it works | Build effort | Parent friction | Cost | Fit for AMEN |
|--------|--------------|--------------|-----------------|------|--------------|
| **Payment-card transaction** | A card transaction that notifies the account holder (small verification charge or tie to a real purchase). | **Low–Med** — Stripe Connect rails already exist. | Low–Med (parent enters a card). | Low (per-txn fees) | **Strong.** Leverages existing infra. Downside: assumes the parent has/will use a card; some parents balk at a charge even if refunded. |
| **Signed consent form** | Parent prints/signs and returns a form by mail, fax, or electronic scan/upload. | **Low** — upload + manual or OCR review. | High (print/sign/scan is the highest-effort UX). | Low | Workable as a fallback. High abandonment. Good as a secondary option, weak as the only one. |
| **Government-ID check** | Collect a gov ID, verify against databases (often via vendor), **then promptly delete** the ID. | **Med–High** | Med | Med (vendor) | Privacy-sensitive — handling parent gov-ID images. Cuts against AMEN's privacy-first ethos unless fully outsourced + immediate-delete. |
| **Face match to photo ID** | Parent submits a selfie matched to a verified photo ID (vendor-run). | **High** (vendor only) | Med | Med–High | Effective but heavyweight; only sensible via a vendor. |
| **Knowledge-based auth (KBA)** | Dynamic, sufficiently-hard identity questions from independent data sources (the kind a child couldn't answer). | **High** (vendor only) | Low–Med | Med | Good UX, but the data sourcing is hard to do yourself — vendor territory. |
| **Phone / video call** | Parent calls (or video-conferences) trained personnel who confirm consent. | Low to build, **unscalable to staff** | Med–High | High (human time) | **Not viable** for a solo/small team. Skip unless you have staffed support. |
| **Text-plus** *(2025 addition)* | Like email-plus via SMS — parent confirms by text plus a confirming step. | Low | Low | Low | **Internal-use-only**, same disqualifier as email-plus. Not valid for social features. |

### The option the table doesn't capture: outsource it (recommended if you go Path C)

Don't build VPC in-house. Use a **COPPA Safe Harbor / VPC vendor** (e.g., **PRIVO**, kidSAFE, or another FTC-approved program). Two compounding benefits:

- They run the rigorous VPC flow (KBA, ID, face-match, card) as a service — you integrate, you don't build identity verification.
- Membership in an FTC-approved **Safe Harbor program** gives **"deemed compliant"** status for the core COPPA provisions — a documented good-faith record that materially reduces enforcement risk. The FTC-approved programs are **CARU, ESRB, iKeepSafe, kidSAFE, PRIVO, and TRUSTe.**

For a small team taking on under-13, this is almost certainly the right call: it converts the hardest, riskiest part of OQ-2 (correct identity verification + audit trail) into a vendor integration and buys you regulatory cover.

---

## Recommendation framework (counsel makes the final call)

- **If shipping speed matters most for v1 →** Path A (13+ only). Defer under-13 until there's a Legal/T&S owner. Lowest cost, fastest, smallest risk surface.
- **If under-13 is mission-critical for launch →** Path C **via a Safe Harbor vendor** (PRIVO et al.), with **payment-card** (Stripe) as the in-house fallback method for parents who prefer it. Do **not** hand-roll VPC.
- **Path B (restricted internal-only kid tier) →** only if you genuinely want under-13 present but are willing to give them a non-social, walled experience, and you can *prove* no third-party SDK touches their data. In practice this is harder to enforce than it looks; treat it as a niche, not a default.

**Default suggestion:** Path A for v1, Path C-via-vendor when under-13 graduates from backlog to roadmap.

---

## What each path means for the C-4 build

Once Decision 0/1 lands, C-4 becomes mechanical. The pieces, regardless of method:

- **Guardian↔child link model** (Firestore): a verified `guardianLinks/{linkId}` collection binding a consenting parent identity to a child UID, with consent method + timestamp + evidence reference recorded.
- **Consent record + retention:** the 2025 amendment requires a **written data-retention policy** and prohibits keeping children's data longer than needed. C-4 must store *proof of consent* but must **not** retain raw verification artifacts (e.g., gov-ID images) beyond verification — delete-after-verify is both a privacy win and a compliance requirement.
- **Parent review/delete tooling** (the COPPA § 1303(c)(2) right): authenticated parent surface to review and delete the child's data, with Firestore rules granting parent read/delete scoped strictly to linked children.
- **Separate consent for any third-party disclosure / ads** (2025 amendment): if AMEN ever shares kid data or runs targeted ads (it shouldn't, per product philosophy), that needs its *own* consent — keep this structurally impossible by default.

The data model differs only at the "evidence reference" field per method (card txn ID vs. vendor verification token vs. signed-form scan ID). Decide the method, and the schema freezes.

---

## Open sub-questions for counsel before C-4 freezes

1. **Confirm the exact current enumerated VPC list and mechanics** against 16 CFR § 312.5(b)(2) *as amended (April 2026)* — especially whether the payment-card method still requires a monetary transaction or a notification suffices.
2. **Confirm the audit's "violation" framing** — is current state a live COPPA violation, or pre-launch exposure? Affects urgency vs. launch-gate sequencing.
3. **Decision 0 itself is partly a legal-risk question:** is a 13+ age gate with neutral screening sufficient to keep AMEN out of COPPA scope given its likely-attractive-to-kids content?
4. **Safe Harbor membership** — is it worth pursuing for the deemed-compliant cover, and which program fits a faith social platform?
5. **State-law overlay** for 13–17 minors (e.g., state age-appropriate-design and minor-privacy laws) — separate from COPPA, still applies on Path A.

---

## Sources (for counsel to verify)

- FTC, *Complying with COPPA: FAQs* (email-plus = internal-use only): https://www.ftc.gov/business-guidance/resources/complying-coppa-frequently-asked-questions
- FTC, *Children's Privacy* hub (approved VPC methods, Safe Harbor programs): https://www.ftc.gov/business-guidance/privacy-security/childrens-privacy
- FTC press release, *Finalizes Changes to Children's Privacy Rule* (Jan 2025 amendment): https://www.ftc.gov/news-events/news/press-releases/2025/01/ftc-finalizes-changes-childrens-privacy-rule-limiting-companies-ability-monetize-kids-data
- eCFR, 16 CFR Part 312 (current rule text): https://www.ecfr.gov/current/title-16/chapter-I/subchapter-C/part-312
- Securiti, *FTC's 2025 COPPA Final Rule Amendments* (April 22, 2026 compliance date): https://securiti.ai/ftc-coppa-final-rule-amendments/
