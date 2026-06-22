# Stripe vs Apple IAP — Policy Decision Memo

**For:** CEO / CPO / Legal Counsel / Engineering Lead
**Prepared:** 2026-06-16
**Required decision by:** Before App Store submission
**Classification:** CONFIDENTIAL

---

## The Decision Required

AMEN processes payments through Stripe across multiple product surfaces (creator subscriptions, church giving, studio subscriptions, mentorship plans). Apple App Store Review Guideline 3.1.1 requires that digital goods and services sold or unlocked within an iOS app must use Apple's In-App Purchase system. AMEN cannot submit to the App Store while Stripe is the active payment processor for any in-app purchase of a digital good. A subset of AMEN's payment flows — specifically charitable giving to registered 501(c)(3) nonprofits — may qualify for a Guideline exemption, but that determination requires legal confirmation before engineering proceeds. The consequence of delay is continued inability to submit to the App Store; every week of indecision is a week the product cannot ship.

---

## What AMEN Currently Does (monetization inventory)

The following payment surfaces were identified through code audit of the iOS codebase and Firebase backend as of 2026-06-16.

### 1. Creator Subscriptions (Community / Partner / Covenant tiers)
- **What it is:** Fan/follower subscriptions to individual creators at $4.99–$29.99/mo. Unlocks exclusive content, Space access, mentoring, study guides.
- **Current processor:** Stripe (via `processGivingCharge.ts` and `createCatalogCheckoutSession` CF; also referenced in `CreatorMonetizationView.swift` and `CreatorViewModel.swift`).
- **Status:** Partially wired; `CreatorViewModel.swift` contains the comment "In production this would go through Stripe/IAP." — indicating this is not fully live.
- **IAP required:** YES. These are digital goods unlocked within the app.

### 2. Platform Subscription Tiers (Amen+ / AmenPro / CreatorPro / ChurchPro)
- **What it is:** Platform-level subscription tiers granting access to AI features, Spaces, advanced tools, and premium content.
- **Current processor:** StoreKit partially wired. `AmenStoreKitManager.shared` is initialized in `AMENAPPApp.swift` with `startTransactionListener()`. `AmenSubscriptionPaywall.swift` wraps `AmenStoreKitManager`. Product IDs defined (e.g., `amenapp.studio.creator.monthly`) but App Store Connect products not yet created.
- **Status:** StoreKit code scaffolded but App Store Connect IAP products are placeholders — not live.
- **IAP required:** YES.

### 3. Studio Subscriptions (Creator / Pro / Team tiers — $7.99–$24.99/mo)
- **What it is:** Creator Studio subscriptions for unlimited creates, AI Muse, export, collaboration, and vault features.
- **Current processor:** RevenueCat SDK (`StudioSubscriptionService.swift`) wrapping StoreKit. Product IDs defined (`amenapp.studio.creator.monthly`, etc.). `REVENUECAT_API_KEY` required but not confirmed set in production.
- **Status:** Best-wired subscription surface in the codebase. StoreKit path exists but RC webhook CF for server-side entitlement sync is still marked as a deploy-pending TODO.
- **IAP required:** YES (already using StoreKit via RevenueCat — this surface is architecturally compliant, pending full wiring).

### 4. Faith Giving / Charitable Donations to Churches and Nonprofits
- **What it is:** One-time and recurring donations to registered Christian nonprofits and churches. Amounts $1–$1,000. Apple Pay and card tokenization supported.
- **Current processor:** Stripe directly (`processGivingCharge.ts`; `GivingInAppSheet.swift` shows Stripe card path). The CF routes payments to the nonprofit's `stripeConnectedAccountId` via Stripe Connect.
- **Platform fee:** A 2% platform fee is charged (`GivingInAppSheet.swift` line 57: `platformFee = effectiveAmount * 0.02`). The backend CF also calculates `platformFeeCents = Math.round(amountCents * 0.029 + 30)` unless the user opts to cover the fee.
- **Status:** Functionally complete on the server side. iOS sheet is complete. This is the most legally sensitive surface.
- **IAP required:** DISPUTED — see Policy section below. The platform fee complicates the charitable exemption.

### 5. 242 Hub Tiers (Grow / Lead — in-app subscription)
- **What it is:** Subscription tiers for the 242 Resources hub: sermon library, mentorship matching, intercessors network, pastoral tools.
- **Current processor:** StoreKit 2 directly (`TwoFourTwoSubscriptionView.swift`). Product IDs defined (e.g., `com.amen.twofourtwohub.grow.monthly`).
- **Status:** StoreKit code written; product IDs are placeholders ("Replace these with real IDs before App Store submission").
- **IAP required:** YES (already using StoreKit — architecturally correct).

### 6. Mentorship Paid Relationships
- **What it is:** Paid mentor-mentee relationships with a `stripePriceId` on the MentorModel. Subscription created via Stripe via a backend CF.
- **Current processor:** Stripe (`MentorshipService.swift` calls `createPaidRelationship` which takes a `stripePriceId`; `MentorModel.swift` stores `stripePriceId`).
- **Status:** Wired to Stripe backend CF. This is an unlockable digital service (access to a human mentor via the app platform).
- **IAP required:** YES. Paid access to in-app digital services (mentor matching, messaging, content) is a digital good under 3.1.1. Note: if the underlying transaction is framed as a person-to-person payment (user pays mentor directly), a narrow exemption may exist — but this requires legal review.

### 7. Catalog Subscription Tiers (Creator Pro / Creator Studio — $19–$49/mo)
- **What it is:** Knowledge catalog subscription tiers for catalog management, knowledge maps, team members, transcript search.
- **Current processor:** Stripe (`createCatalogCheckoutSession` CF in `catalogEntitlements.ts`). Checkout redirects to a Stripe-hosted URL.
- **Status:** Fully wired to Stripe checkout. This is the clearest IAP violation — Stripe Checkout URLs opened in-app for digital subscriptions are explicitly prohibited.
- **IAP required:** YES, unambiguously.

### 8. Creator Tips / Tokens
- **What it is:** Direct tips to creators. Referenced in `CreatorViewModel.swift` ("tipsEnabled: true") and `PlatformOSContracts.swift` (`.subscription` case).
- **Current processor:** Unclear — `CreatorViewModel.swift` comment says "In production this would go through Stripe/IAP. For now, record the tip."
- **Status:** Not live. Must use IAP when implemented if the tip unlocks in-app content or is a digital good. If it is a true person-to-person payment with no platform benefit, an exemption may apply — requires legal review.

---

## The Policy (Guideline 3.1.1 — what it actually says)

### Exact text of Guideline 3.1.1 (App Store Review Guidelines, current)

> "If you want to unlock features or functionality within your app, you must use in-app purchase. Apps and their metadata may not include buttons, external links, or other calls to action that direct customers to purchasing mechanisms other than In-App Purchase... Apps may not use their own mechanisms to unlock content or functionality, such as license keys, augmented reality markers, QR codes, cryptocurrencies and cryptocurrency wallets, and so on."

### What qualifies as a "digital good or service" requiring IAP

The following trigger Guideline 3.1.1 without exception:
- Subscription tiers that unlock features, content, or capabilities within the app
- Access to premium AI features gated by tier
- Exclusive Spaces, rooms, or content gated by subscription
- Digital tips that grant recognition, badges, or featured placement within the app
- Any digital currency, token, or credit redeemable within the app

### Key exemptions relevant to AMEN

**Charitable giving exemption:** Apple explicitly permits apps to facilitate donations to registered 501(c)(3) organizations. The App Store Review Guidelines (Section 3.2.1(viii)) state that apps "collecting charitable donations on behalf of non-profit organizations" are permitted and do not require IAP — provided: (a) the organization is a registered nonprofit, (b) the app clearly identifies the organization, and (c) Apple Pay or other approved payment methods are used appropriately.

**Critical caveat — platform fees:** The exemption is premised on 100% of the donation going to the charity (minus standard payment processing fees charged by the payment network, not by the platform). A platform fee retained by AMEN (currently 2%) changes the legal character of the transaction. Apple's reviewers may treat a platform-fee-bearing giving flow as a commercial transaction, not a charitable donation, removing the exemption.

**Person-to-person payment exemption (Section 3.1.3(e)):** Apps facilitating person-to-person payments between individuals using approved payment processors are exempt. This may apply to direct creator tips if structured as P2P and if AMEN takes no cut. Requires legal analysis.

**Reader / Remote Purchase rule (Section 3.1.3(a)):** Apps that sell digital content for consumption outside the app (e.g., a church website subscription managed externally) may link to a website for that purchase. This does not apply to in-app subscriptions that unlock in-app features.

### Key precedent

- **Charitable apps (e.g., Tithe.ly, Pushpay):** Faith-giving apps on the App Store use a combination of Apple Pay and ACH without StoreKit for 501(c)(3) giving. They do not take a platform percentage. Apple has historically approved these under the charitable exemption.
- **Stripe Checkout URLs:** Opening a Stripe Checkout session URL in-app (even in SFSafariViewController) for digital subscription upgrades has resulted in rejections and takedowns. This is the pattern in `createCatalogCheckoutSession` and is a clear violation.

---

## Three Options

### Option A — Pure StoreKit (full IAP migration)

**Description:** Replace Stripe with StoreKit 2 for all in-app purchases of digital goods. Giving flows are also migrated to StoreKit (treating donation amounts as consumable IAP products) or directed to a web checkout.

**What it covers:** Creator subscriptions, platform tiers, Studio subscriptions, 242 Hub, catalog tiers, mentorship plans, future tips/tokens.

**What it does NOT require (debated):** Charitable giving may still qualify for the Stripe-on-server path if legal confirms the exemption and the platform fee is eliminated. See Option B.

**Apple's cut:** 15% for apps earning under $1M/year (Small Business Program). 30% standard rate above $1M/year. Applies to all subscription revenue processed via StoreKit.

**Engineering effort:** Medium — 3 to 4 weeks. StoreKit 2 is mature. The largest effort is creating App Store Connect IAP products for every tier, implementing server-side receipt validation via the App Store Server API, and migrating the entitlement sync away from Stripe webhooks.

**App Store outcome:** FULLY COMPLIANT. Zero policy risk.

**Financial impact:** Apple commission on all digital subscription revenue. At current pricing ($4.99–$49/mo tiers), the commission reduces net revenue by 15–30%.

**Recommendation note:** Most straightforward path to App Store submission. Eliminates all policy risk in a single engineering pass.

---

### Option B — Hybrid (StoreKit for digital + Stripe for giving)

**Description:** StoreKit 2 for all digital subscriptions and access products. Stripe retained exclusively for faith giving to registered 501(c)(3) nonprofits, with the platform fee eliminated (or disclosed as a voluntary processing fee covered by the donor).

**Basis for Stripe exemption:** Apple permits charitable giving to registered nonprofits without requiring IAP. The `processGivingCharge.ts` CF already validates nonprofit status against a Firestore allowlist. If all churches/nonprofits in that allowlist are registered 501(c)(3) entities and AMEN retains zero net platform fee (i.e., the 2% covers only actual Stripe processing costs passed through transparently), the exemption may hold.

**Risk:** Two risks. First, Apple interprets "charitable giving" narrowly and reviewers exercise discretion. Apps have been rejected even for charitable flows if the UX looks transactional. Second, the current 2% "platform fee" in `GivingInAppSheet.swift` is described as a platform fee in the UI ("AMEN takes 0% platform fee" is stated in `CreatorMonetizationView.swift` — but the code charges 2%). This inconsistency must be resolved before submission; it currently reads as AMEN taking a cut, which defeats the exemption.

**Engineering effort:** Medium — maintain both payment stacks. Stripe remains for giving; StoreKit 2 replaces everything else. Requires auditing every payment entry point to ensure no digital-good purchase routes through Stripe.

**Requires before proceeding:** (1) Legal confirmation that all nonprofits in the allowlist are registered 501(c)(3) entities; (2) resolution of the platform fee disclosure inconsistency; (3) legal opinion on whether the exemption applies.

**Recommendation note:** Defensible if legal clears it. Preserves lower payment processing costs for giving flows (Stripe is typically 2.9% + $0.30 vs Apple's 15–30% commission). This option is the industry standard for faith-giving apps.

---

### Option C — External Link for Giving (SFSafariViewController)

**Description:** StoreKit for all digital subscription products. For faith giving, display a "Complete on Website" button that opens the giving flow in SFSafariViewController, directing users to a web checkout powered by Stripe.

**Basis:** Apple's charitable organization and reader carve-outs allow directing users to a website for certain purchases. An entitlement program exists (the External Purchase Entitlement) that permits linking to external purchase flows for some app categories.

**Risk:** (1) Apple's External Purchase Entitlement program has limited availability and requires pre-approval. It currently applies primarily to "reader" apps and select categories — it is not a general exemption. (2) The UX degradation of breaking out of the app to a web giving flow is significant and may reduce giving conversion. (3) Apple may still reject the giving flow if it does not meet the charitable exemption criteria.

**Engineering effort:** Low for giving (add a "Give on Website" button); still requires full StoreKit migration for all digital subscriptions. The digital subscription Stripe paths must be replaced regardless.

**Recommendation note:** Technically possible for giving but creates a worse user experience than Option B and introduces additional pre-approval risk. Not recommended as the primary strategy. Acceptable as a temporary fallback while legal clears the Option B charitable exemption.

---

## Legal Clarification Required Before Deciding

The following questions must be answered by legal counsel before engineering selects Option B or C for the giving flows. Option A requires no legal input and can proceed immediately.

1. **Are all organizations in AMEN's `nonprofits` Firestore collection registered 501(c)(3) entities?** If any are not (e.g., unincorporated ministries, international churches), the charitable exemption does not apply and StoreKit or web checkout is required for those organizations.

2. **Does AMEN retain any net revenue from giving transactions, or does the platform fee solely cover actual Stripe processing costs?** The current code charges a 2% platform fee in addition to Stripe fees. If AMEN retains any margin on giving, the exemption is at risk. The `CreatorMonetizationView.swift` UI states "AMEN takes 0% platform fee" — but the code does not reflect this. This discrepancy must be resolved before submission regardless of which option is chosen, because it constitutes a material inconsistency in disclosures.

3. **Is AMEN enrolled in Apple's Small Business Program?** This determines whether the applicable StoreKit commission rate is 15% or 30%, which is material to the financial impact of Option A.

4. **Are the mentorship paid relationships structured as platform-to-mentor payouts, or as direct person-to-person payments?** If AMEN is the merchant of record and the mentor receives a payout (Stripe Connect model), this is a platform service and requires IAP. If it is truly P2P, an exemption may apply.

5. **Has AMEN received any prior App Review communications or rejections on payment-related grounds?** Prior Apple correspondence may constrain the options.

---

## Recommendation

**Proceed immediately with Option A (full StoreKit migration) for all digital goods, and hold the giving flow decision for legal review while engineering begins.**

The codebase already has StoreKit 2 wired in several places (`AmenStoreKitManager`, `TwoFourTwoSubscriptionView`, `AmenSubscriptionPaywall`, `StudioSubscriptionService` via RevenueCat). The architecture is not starting from zero. The blocking work is: creating App Store Connect IAP products, implementing server-side receipt validation, and replacing the Stripe checkout CF call paths with StoreKit purchase flows.

Option A minimizes legal risk, unblocks App Store submission fastest, and aligns with what the codebase already partially implements. Option B is financially preferable for giving flows but requires legal sign-off that could delay submission by weeks. Option C is not recommended as a primary strategy.

**Engineering should begin StoreKit implementation for digital subscriptions immediately regardless of the outcome of the giving-flow legal review.** The giving flow can remain in a feature-flagged or web-redirect state for the initial submission while legal clears the charitable exemption question. This parallelizes the work and does not block the submission timeline.

The single most important immediate action is **eliminating the `createCatalogCheckoutSession` Stripe Checkout URL pattern** — this is an unambiguous violation that will result in rejection on first review.

---

## Engineering Implications (by option)

### If Option A or B (required for digital subscriptions in either case)

**Immediate actions — required regardless of final giving-flow decision:**

- **Create App Store Connect IAP products** matching all current subscription tiers. Product IDs already exist in code (e.g., `amenapp.studio.creator.monthly`, `com.amen.twofourtwohub.grow.monthly`) — these need to be created in App Store Connect before StoreKit can fetch prices. This is a human/App Store Connect task that does not require code changes.
- **Remove or gate `createCatalogCheckoutSession`** — the Stripe Checkout session URL for catalog tier upgrades is an immediate rejection risk. Replace with StoreKit purchase for `creator_pro` and `creator_studio` tiers.
- **Implement StoreKit 2 product fetch** in `CatalogEntitlementService.swift` and `AmenSubscriptionPaywall.swift` — use `Product.products(for:)` to load prices from App Store Connect.
- **Implement server-side receipt validation** via App Store Server Notifications v2 (or App Store Server API) for entitlement writes. The RevenueCat webhook CF for Studio (`StudioSubscriptionService.swift`) is marked TODO — this must be deployed before launch.
- **Implement `Transaction.updates` listener** — already scaffolded in `AMENAPPApp.swift` via `AmenStoreKitManager.shared.startTransactionListener()`. Verify this handles renewals, billing-retry recoveries, and refunds.
- **Add Restore Purchases UI** — mandatory per Guideline 3.1.1. Must be surfaced in Settings or on the paywall. `StudioSubscriptionService.swift` has `restore()` implemented; verify it is wired to a visible UI control.
- **Migrate `MentorshipService.createPaidRelationship`** — replace `stripePriceId` path with StoreKit product purchase. `MentorModel.stripePriceId` can be retained as a metadata field but must not be the payment mechanism.

**Engineering timeline:** 3 to 4 weeks for full digital subscription migration.

### Giving flows (Option B)

If legal confirms the charitable exemption:
- Eliminate the platform fee or reclassify it transparently as a donor-elected processing fee (update both code and UI disclosure copy).
- Verify all `nonprofits` collection documents have confirmed 501(c)(3) status (`einNumber` field or equivalent).
- Add App Review metadata note explaining the giving flow is charitable in nature and directed to registered 501(c)(3) nonprofits.
- Keep `processGivingCharge.ts` as-is architecturally; update the fee logic and nonprofit validation.

If legal cannot confirm the exemption within the submission timeline:
- Implement Option C fallback: replace the in-app Stripe giving flow with a "Give on [Organization Name]'s Website" button opening `SFSafariViewController` with the nonprofit's own giving URL (the `givingURL` field already exists on church profiles in `ChurchEditProfileView.swift`).

### If Option C (giving only — digital subscriptions still require StoreKit)

- Option C does not change the digital subscription engineering scope. All work above is still required.
- For giving: replace `GivingInAppSheet` presentation with a web handoff that opens `church.givingURL` in `SFSafariViewController`. This is a 1–2 day engineering task.

---

## Files to Change (whichever option is chosen)

The following files require changes for Option A/B digital subscription migration:

| File | Change Required |
|------|----------------|
| `Backend/functions/src/billing/catalogEntitlements.ts` | Replace `createCatalogCheckoutSession` (Stripe Checkout URL) with an App Store Server validation CF or remove; add server-side receipt validation endpoint |
| `AMENAPP/AMENAPP/Monetization/AmenSubscriptionPaywall.swift` | Wire `AmenStoreKitManager` product fetch to real App Store Connect product IDs |
| `AMENAPP/AMENAPP/Monetization/CatalogEntitlementService.swift` | Replace Stripe entitlement path with StoreKit receipt-backed entitlement check |
| `AMENAPP/StudioSubscriptionService.swift` | Deploy RevenueCat webhook CF (`syncEntitlementToFirestore` TODO); confirm `REVENUECAT_API_KEY` in production |
| `AMENAPP/TwoFourTwoSubscriptionView.swift` | Replace placeholder product IDs with real App Store Connect IDs |
| `AMENAPP/MentorshipService.swift` | Replace `stripePriceId` payment path with StoreKit product purchase |
| `AMENAPP/MentorModel.swift` | `stripePriceId` field: retain as metadata but remove from payment path |
| `AMENAPP/CreatorViewModel.swift` | Implement actual IAP purchase where comment says "In production this would go through Stripe/IAP" |
| `AMENAPP/CreatorOS/CreatorMonetizationView.swift` | Update subscription creation/management to use StoreKit; resolve "0% platform fee" disclosure inconsistency |

For the giving flow (Option B conditional, or Option C fallback):

| File | Change Required |
|------|----------------|
| `AMENAPP/GivingInAppSheet.swift` | Resolve platform fee inconsistency (code vs. UI disclosure); if Option C, replace with web handoff |
| `Backend/functions/src/giving/processGivingCharge.ts` | Clarify/eliminate platform fee logic; add 501(c)(3) status validation field check |

---

## Decision Timeline

| Step | Owner | By When |
|------|-------|---------|
| Legal answers 5 clarification questions above | Legal Counsel | ASAP — this is the critical path item |
| Engineering removes `createCatalogCheckoutSession` Stripe Checkout URL | Engineering | Immediately — no legal dependency, clear violation |
| App Store Connect IAP products created for all subscription tiers | Human (App Store Connect access required) | Day 1 of engineering sprint |
| Product + Legal select Option A, B, or C for giving flows | CEO / CPO / Legal | Within 1 week of legal answers |
| Engineering begins StoreKit migration for all digital subscriptions | Engineering | Immediately — no legal dependency |
| RevenueCat webhook CF for Studio entitlement sync deployed | Engineering | During sprint — prerequisite for launch |
| Stripe migration / removal from digital subscription paths | Engineering | End of implementation sprint |
| Legal review of giving disclosure copy (fee language, receipt language) | Legal | During engineering sprint |
| Restore Purchases UI verified in Settings | Engineering | Before TestFlight submission |
| Full payment regression test on device | Engineering / QA | Before App Store submission |

**Minimum to unblock App Store submission:** 3 to 5 weeks from decision date, assuming App Store Connect IAP products are created in week 1 and legal answers the clarification questions within 1 week.

---

*Prepared by Claude Code automated audit — 2026-06-16. This memo is based on static code analysis and does not constitute legal advice. All legal conclusions require review by qualified counsel familiar with Apple's App Store Review Guidelines and applicable payment regulations.*
