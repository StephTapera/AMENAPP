# Apple Age Rating Questionnaire
**App:** AMEN
**Bundle ID:** tapera.AMENAPP
**Version:** 1.0 (build 5)
**Prepared by:** Agent 5, Launch Readiness Swarm
**Date:** 2026-06-11

---

## Apple Age Rating Questionnaire — Recommended Answers

Answer each question exactly as shown in App Store Connect → App Information → Age Rating.

| Apple Question | Recommended Answer | Rationale |
|---|---|---|
| Unrestricted web access | **None** | App does not embed an unfiltered WebView or web browser. All web content is rendered through controlled in-app surfaces. |
| Gambling and contests | **None** | No gambling, wagering, sweepstakes, or contests. |
| Alcohol, tobacco, or drug use or references | **None** | Faith-focused app; no depiction or reference to alcohol, tobacco, or drugs. |
| Horror or fear-themed content | **None** | No horror, jump scares, or fear-themed content. |
| Mature or suggestive themes | **None** | Faith-community focus; content moderation (NeMo Guard + human review) enforced for all UGC. |
| Simulated gambling | **None** | No gambling simulation. |
| Sexual content or nudity | **None** | No sexual content; automated image moderation + human review for all uploaded media. |
| Graphic or prolonged violence | **None** | No violence. |
| Realistic violence | **None** | No realistic violence. |
| Animated or cartoon violence | **None** | No violence of any kind. |
| Profanity or crude humor | **None** | NeMo Guard text moderation active on all UGC; profanity filtered. |
| **User-generated content** | **Frequent/Intense** | Posts, comments, DMs, prayer requests, church notes, media uploads — all user-generated and publicly or community-visible. This is the primary app mode. |
| **Social/community features** | **Frequent/Intense** | Social feed, comments, DMs, prayer walls, Spaces, Creator rooms — core to the product. |
| Medical or treatment information | **None** | Synaptic Studio wellness features do not provide medical treatment advice; HealthKit data is used for reflective prompts only. |

---

## Recommended Age Rating

### 12+

**Justification:**
- UGC is present at high frequency (Social/community = Frequent)
- Content is faith-focused with no mature, violent, or sexual themes
- Minor safety controls are implemented (age-tier restrictions, adult→minor DM gate, minor search exclusion)
- No gambling, drugs, alcohol, or horror content
- Social Networking category standard is 12+

**Do not rate lower than 12+** because Apple requires any app with social/community features to be rated at minimum 12+.

---

## UGC Mitigation Evidence (Required by Apple Guideline 1.2)

Apple requires apps with UGC to demonstrate all four of the following. Check each before submission.

### 1. Mechanism to report objectionable content
- [x] **Implemented:** Three-dot (…) menu on PostCard → "Report" → category selector
- [x] **Implemented:** Report button on UserProfileView → Profile menu → "Report User"
- [x] **Implemented:** Comment-level report via long-press / swipe action
- [x] **Implemented:** DM report flow in UnifiedChatView
- [x] **Backend:** `submitSafetyReport` Cloud Function (auth + AppCheck + rate-limited) — `DEPLOY_PACKAGE_SAFETY_WAVE_3_2026-06-10.md`

### 2. Mechanism to block abusive users
- [x] **Implemented:** Block user from Profile menu → blocked users cannot see content or send DMs
- [x] **Implemented:** Mute user from feed (hides from feed without notification)
- [x] **Backend:** Block state enforced in Firestore security rules + backend callables

### 3. Developer filters objectionable material before it is published
- [x] **Pre-publication:** NeMo Guard text moderation — all posts/comments pass through CF before going live
- [x] **Pre-publication:** Google Vision API image moderation — all uploaded media scanned in quarantine path
- [x] **Post-publication:** `adminReviewPost` CF — human moderation queue for escalated reports
- [x] **Minor safety:** Age-tier vocabulary filter; minor search exclusion; adult-to-minor DM gate (fail-closed)
- [x] **CSAM detection:** Hash-matching pipeline present (NCMEC registration gate — see action item A-01)

### 4. Developer responds to UGC reports within 24 hours
- [ ] **HUMAN ACTION REQUIRED:** Establish and document the operational process:
  - Who monitors the moderation queue?
  - What is the response SLA commitment?
  - Moderation contact email (e.g., `moderation@amen.app`) must be published in the app and privacy policy

---

## Minor Safety Summary (for App Review awareness)

AMEN implements age-tier restrictions that change app behavior based on the user's declared age at onboarding:

| Control | Adult (18+) | Teen (13–17) | Child (<13) |
|---|---|---|---|
| Public feed | Full access | Full access | Read-only |
| DMs with non-contacts | Allowed | Restricted | Blocked |
| Adult-to-minor DM | Allowed (consented) | N/A | Blocked |
| Search discovery | Full | Reduced | Hidden |
| Creator content | Full | Age-appropriate | Gated |
| Community rooms | Full | Moderated | Gated |

Age verification is self-reported at onboarding (`AgeVerificationOnboardingView.swift`). Server-side age-tier enforcement is via `ageTier.js` Cloud Function.

**Note for App Review:** If a reviewer creates a test account with a birth date indicating a minor, certain DM and public-discovery features will be restricted. This is by design and is the correct behavior.

---

## App Store Category Recommendation

**Primary:** Social Networking
**Secondary:** Lifestyle

---

## Sign-off Checklist

- [ ] Age rating answers entered in App Store Connect → App Information → Age Rating
- [ ] UGC moderation SLA documented and moderation contact published
- [ ] NCMEC registration complete (A-01 — required before enabling CSAM reporting CF)
- [ ] Release owner and legal confirmed rating is appropriate for all enabled features at launch
