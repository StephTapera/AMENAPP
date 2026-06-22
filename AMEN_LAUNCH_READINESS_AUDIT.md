# AMEN LAUNCH-READINESS AUDIT — 2026-06-01
**Branch:** feature/spiritual-os | **Items audited:** 713+ | **Agents:** 7 parallel

---

## P0 BLOCKER REPORT

### Infra Deploys (block all users)

| # | Blocker | Command |
|---|---|---|
| I-1 | Aegis 5 CFs | firebase deploy --only functions:aegisAnalyzeMedia,aegisReviewText,aegisAccountTrust,aegisPrivacyAction,aegisEscalate |
| I-2 | Spaces 8 CFs | firebase deploy --only functions:createCommunity,linkCommunity,acceptCommunityLink,revokeCommunityLink,grantAccess,revokeAccess,stripeWebhookEntitlementHandler,purchaseSpaceAccess |
| I-3 | Calm/Rhythm 10 CFs | firebase deploy --only functions:calmControl,spiritualRhythm |
| I-4 | Firestore rules | firebase deploy --only firestore:rules |
| I-5 | RemoteConfig (58 aegis keys) | Firebase Console: all aegis.C1-C58 = false |
| I-6 | churchSearch/postProvenance/selahStory CFs | firebase deploy --only functions:churchSearchProxy,postProvenanceProxy,selahStoryProxy |

### App Code P0s

| # | Blocker | File | Fix |
|---|---|---|---|
| C-1 | AegisPrePostReviewSheet NOT wired | CreatePostView.swift | Add preflight sheet before publish |
| C-2 | Email verification NOT enforced at compose | CreatePostView.swift | Auth.auth().currentUser?.isEmailVerified gate |
| C-3 | No AccountStatusGate on launch | AMENAPPApp.swift | AccountStatusGate before ContentView |
| C-4 | NotificationDeepLinkRouter: no auth guard | NotificationDeepLinkRouter.swift | guard currentUser != nil |
| C-5 | COPPA DM not enforced | MessagingService | Minor flag before DM |
| C-6 | Delete account not in Settings (App Store) | AccountSettingsView.swift | Button in <=3 taps |
| C-7 | IAP terms not shown (App Store) | AmenCovenantCheckoutService | Show before SKPayment.add() |
| C-8 | Berean: medical guardrail missing | BereanSafetyPolicy | Medical -> refuse + disclaimer |
| C-9 | Berean: injection guard missing | BereanCoreService | Injection detect -> refuse + log |
| C-10 | Bulk notif rate limit missing | FirebaseMessagingService | 100/min; batch 100/call |
| C-11 | Grooming on child photo not removed | AIContentDetectionService | Auto-remove + T&S escalate |
| C-12 | VoiceOver: CreatePostView no labels | CreatePostView.swift | .accessibilityLabel everywhere |
| C-13 | Event creator deletion strands RSVPs | EventService | Soft-delete; system sends reminders |
| C-14 | Church pastor deletion orphans church | ChurchOwnershipService | designateSuccessor() on deletion |

---

## GO / NO-GO SUMMARY

| Gate | Status | Blocking Items |
|------|--------|----------------|
| TestFlight Internal | 🟡 GO w/ mitigations | Deploy I-1..I-6; wire C-1, C-3 |
| Beta External | 🔴 NO-GO | All C-1..C-14 must resolve |
| App Store Submission | 🔴 NO-GO | C-6, C-7 violate App Store rules |
| Public Launch | 🔴 NO-GO | All P0s clear + all CFs deployed |

---

## LAUNCH GATE STATUS

| # | System | Status | Blocker |
|---|--------|--------|---------|
| L-01 | Aegis 58 caps | Built NOT deployed | Deploy I-1; seed I-5 |
| L-02 | AegisPrePostReviewSheet | Built NOT wired | Fix C-1 |
| L-03 | Spaces 8 CFs | Built NOT deployed | Deploy I-2 |
| L-04 | Calm/Rhythm 10 CFs | Built NOT deployed | Deploy I-3 |
| L-05 | Firestore security rules | NOT deployed | Deploy I-4 |
| L-06 | AccountStatusGate | MISSING | Fix C-3 |
| L-07 | Email verification gate | MISSING | Fix C-2 |
| L-08 | COPPA DM enforcement | MISSING | Fix C-5 |
| L-09 | Delete-account UI | MISSING | Fix C-6 |
| L-10 | IAP terms display | MISSING | Fix C-7 |
| L-11 | Berean medical guardrail | MISSING | Fix C-8 |
| L-12 | Berean injection guard | MISSING | Fix C-9 |
| L-13 | Bulk notif rate limit | MISSING | Fix C-10 |
| L-14 | Child photo auto-remove | MISSING | Fix C-11 |
| L-15 | CreatePostView VoiceOver | MISSING | Fix C-12 |
| L-16 | Event creator deletion | MISSING | Fix C-13 |
| L-17 | Church pastor succession | MISSING | Fix C-14 |
| L-18 | DeepLinkRouter auth guard | MISSING | Fix C-4 |

---

## TEST MATRICES

### Matrix 1: State x Screen

| Screen | Loading | Empty | Error | Offline | Auth | Banned |
|--------|---------|-------|-------|---------|------|--------|
| HomeFeed | skeleton | EmptyFeedView | FeedErrorView | CachedFeedView | -> Login | BanBannerView |
| CreatePost | composer disabled | n/a | toast error | queue draft | -> Login | blocked |
| BereanChat | thinking dots | onboarding | LLM error toast | offline badge | -> Login | blocked |
| ChurchNotes | recording spinner | prompt to record | upload error | local queue | -> Login | n/a |
| SpaceHub | skeleton | EmptySpacesView | retry prompt | cached list | -> Login | removed |
| Messaging | skeleton | start convo prompt | connection error | cached msgs | -> Login | blocked |
| Events | skeleton | EmptyEventsView | retry | cached events | -> Login | n/a |
| Settings | skeleton | n/a | retry | cached prefs | -> Login | n/a |

### Matrix 2: Ownership Succession

| Entity | Owner Deletes | Owner Banned | Owner Inactivates | Grace Period | Auto-Successor |
|--------|---------------|--------------|-------------------|--------------|----------------|
| Church | P0 C-14: orphans | soft-ban pastor | archived | 30 days | designateSuccessor() MISSING |
| Space | soft-delete space | freeze space | archived | 14 days | next admin auto-promoted |
| Event | P0 C-13: strands RSVPs | cancel event | archived | 48 hours | system reminder MISSING |
| Organization | freeze org | freeze org | archived | 30 days | secondary admin MISSING |
| Community | next mod promoted | freeze | archived | 7 days | SpaceV2 admin chain |

### Matrix 3: Cross-Feature Chain (Note -> Berean -> Space -> Prayer)

| Step | Happy Path | Failure Mode | Recovery |
|------|-----------|--------------|----------|
| 1. Record Church Note | Audio captured, transcript generated | Mic permission denied | Fallback to manual text entry |
| 2. Berean enrichment | Scripture refs auto-detected | LLM timeout | Retry with cached context |
| 3. Share to Space | Post appears in SpaceHub feed | User not member | Prompt join Space |
| 4. Prayer request spawned | PrayerCardView shows + push notif | Notif permission off | In-app banner only |
| 5. Member prays | Prayer count increments, composer notified | Offline | Queue, sync on reconnect |

---

## DOMAIN AUDIT SUMMARY

| Domain | Items Audited | P0 | P1 | P2 | A11y | Glass | Analytics | Status |
|--------|---------------|----|----|----|----|-------|-----------|--------|
| D01 Foundation & Identity | 38 | 0 | 2 | 1 | 2 | PASS | 4 | PASS |
| D02 Onboarding | 42 | 0 | 3 | 2 | 1 | PASS | 6 | PASS |
| D03 Home Feed | 51 | 0 | 4 | 3 | 2 | PASS | 8 | PASS |
| D04 Post Composer | 47 | 4 | 2 | 1 | 3 | WARN | 5 | BLOCKED C-1,C-2,C-12 |
| D05 Messaging | 39 | 1 | 2 | 2 | 1 | PASS | 4 | BLOCKED C-5 |
| D06 Berean AI | 44 | 2 | 3 | 1 | 1 | PASS | 7 | BLOCKED C-8,C-9 |
| D07 Church Notes | 36 | 0 | 1 | 2 | 1 | PASS | 5 | PASS |
| D08 Spaces | 52 | 0 | 2 | 3 | 2 | PASS | 6 | CF deploy needed |
| D09 Organizations | 31 | 0 | 2 | 2 | 1 | PASS | 3 | PASS |
| D10 Creator OS | 28 | 1 | 1 | 1 | 1 | PASS | 4 | BLOCKED C-7 |
| D11 Media | 33 | 1 | 2 | 2 | 1 | PASS | 5 | BLOCKED C-11 |
| D12 Smart Communities | 29 | 0 | 2 | 1 | 1 | PASS | 3 | PASS |
| D13 Search | 24 | 0 | 1 | 2 | 1 | PASS | 4 | PASS |
| D14 Events | 35 | 1 | 2 | 1 | 1 | PASS | 4 | BLOCKED C-13 |
| D15 Notifications | 27 | 2 | 1 | 1 | 1 | n/a | 3 | BLOCKED C-4,C-10 |
| D16 Settings | 31 | 1 | 2 | 1 | 1 | PASS | 3 | BLOCKED C-6 |
| D17 Trust & Safety | 48 | 0 | 3 | 2 | 2 | PASS | 6 | CF deploy needed |
| D18 Security | 41 | 0 | 2 | 2 | 0 | n/a | 2 | PASS |
| D19 Screen Adaptability | 22 | 0 | 2 | 3 | 3 | PASS | 0 | PASS |
| D20 Liquid Glass | 38 | 0 | 1 | 2 | 2 | AUDIT | 0 | PASS |
| D21 Analytics | 19 | 0 | 1 | 1 | 0 | n/a | AUDIT | PASS |
| D22 Performance | 34 | 0 | 3 | 4 | 0 | n/a | 4 | PASS |
| D23 Offline Mode | 21 | 0 | 2 | 3 | 0 | n/a | 2 | PASS |
| D24 App Store Readiness | 26 | 2 | 1 | 0 | 1 | n/a | 1 | BLOCKED C-6,C-7 |
| D25 Launch Command Center | 18 | 6 | 0 | 0 | 0 | n/a | 0 | SEE P0 TABLE |
| **TOTAL** | **713+** | **20** | **45** | **42** | **30** | | **88** | |

---

## HIDDEN FAILURES P0 — TOP 14

| # | Failure Class | Trigger | Impact | Fix |
|---|---------------|---------|--------|-----|
| HF-01 | State leak on auth sign-out | Sign out mid-session | Private data visible to next user | AmenSessionManager.resetAll() on signOut |
| HF-02 | Timezone edge: DST gap | Event created at 2:30 AM DST gap | Event time invalid, no error | Store UTC + format in local tz |
| HF-03 | Church orphan on owner delete | Pastor deletes account | Church has no owner, uneditable | designateSuccessor() before delete |
| HF-04 | Note -> Berean chain breaks on LLM timeout | bereanChatProxy CF times out | Note loses enrichment silently | Retry queue + partial-save pattern |
| HF-05 | Infinite listener leak in SpaceHub | Space member count > 500 | Memory spike, potential OOM | Paginated listener with detach on exit |
| HF-06 | AVPlayer not released on tab switch | User switches tab during video | Audio continues, player leaked | .onDisappear { player.pause(); player = nil } |
| HF-07 | Feed snapshot accumulates without limit | App open > 6 hrs | Memory grows unbounded | Cap listener at 100 items, paginate |
| HF-08 | Concurrent compose + offline = duplicate post | Post queued offline, user resubmits | Duplicate post published | Idempotency key on all write paths |
| HF-09 | Selah Story viewer no reduce-motion fallback | Reduce Motion ON | Story still auto-advances with animation | prefersReducedMotion check on player |
| HF-10 | Prayer count desync across devices | Concurrent prayers from multiple users | Stale count shown | Firestore FieldValue.increment + snapshot |
| HF-11 | RSVP stranding on event creator delete | Event owner deletes account | RSVPs exist, no event owner | Soft-delete + system reminds attendees |
| HF-12 | Aegis C-flags all false = silent no-op | T&S flags never seeded | Aegis never activates in prod | Seed 58 Remote Config keys to false + verify |
| HF-13 | Berean injection via Unicode homoglyphs | Malicious prompt with lookalike chars | Prompt injection bypasses filter | Normalize Unicode before classify |
| HF-14 | Bulk notification storm on large church | Admin sends notif to 10k members | FCM rate limit hit, delivery fails | 100/min rate limit + exponential backoff |

---

## PLATFORM OS STATUS (25 LAYERS)

| # | OS Layer | Status | P0 Gap | Required Before Launch |
|---|----------|--------|--------|------------------------|
| OS-01 | Identity OS | COMPLETE | none | none |
| OS-02 | Entitlement OS | MISSING | No EntitlementServiceProtocol | Build EntitlementService v2 |
| OS-03 | Subscription OS | PARTIAL | IAP terms not shown | Fix C-7 + show terms before SKPayment |
| OS-04 | Role & Permission OS | COMPLETE | none | none |
| OS-05 | Notification OS | PARTIAL | bulk rate limit missing | Fix C-10 |
| OS-06 | AI Credit OS | COMPLETE | none | none |
| OS-07 | Reputation OS | PARTIAL | shadow-ban lacks audit trail | Add audit log entry on shadow-ban |
| OS-08 | Legal/Compliance OS | PARTIAL | COPPA DM unenforced | Fix C-5 |
| OS-09 | Creator Economy OS | PARTIAL | delete-account keeps revenue | Fix C-6 + data rights flow |
| OS-10 | Organization Lifecycle OS | PARTIAL | no secondary admin | Add org secondary admin UX |
| OS-11 | Church Lifecycle OS | PARTIAL | pastor succession missing | Fix C-14 designateSuccessor() |
| OS-12 | Community Lifecycle OS | COMPLETE | none | none |
| OS-13 | Event OS | PARTIAL | creator deletion orphans RSVPs | Fix C-13 soft-delete |
| OS-14 | Search OS | COMPLETE | none | none |
| OS-15 | Media Rights OS | PARTIAL | grooming on child photo | Fix C-11 auto-remove + T&S escalate |
| OS-16 | Moderation OS | PARTIAL | Aegis not wired | Fix C-1; deploy I-1, I-5 |
| OS-17 | Device OS | COMPLETE | none | none |
| OS-18 | Membership OS | COMPLETE | none | none |
| OS-19 | Relationship Graph OS | COMPLETE | none | none |
| OS-20 | Recovery OS | MISSING | no RecoveryServiceProtocol | Build AccountRecoveryService |
| OS-21 | Audit OS | MISSING | no AuditServiceProtocol | Build AuditTrailService (append-only Firestore) |
| OS-22 | Revenue OS | PARTIAL | no revenue reconciliation | Add Stripe webhook reconciliation view |
| OS-23 | Automation OS | COMPLETE | none | none |
| OS-24 | Smart Context OS | PARTIAL | AmenJourneyContinuityEngine path open | Wire continuity engine to onboarding |
| OS-25 | Memory & Continuity OS | PARTIAL | journeyPath relationship open | Link journey state to Berean context |

---

## LAUNCH COMMAND CENTER

### Human Deploy Checklist (ordered)

- [ ] I-4: firebase deploy --only firestore:rules
- [ ] I-1: firebase deploy --only functions:aegisAnalyzeMedia,aegisReviewText,aegisAccountTrust,aegisPrivacyAction,aegisEscalate
- [ ] I-2: firebase deploy --only functions:createCommunity,linkCommunity,acceptCommunityLink,revokeCommunityLink,grantAccess,revokeAccess,stripeWebhookEntitlementHandler,purchaseSpaceAccess
- [ ] I-3: firebase deploy --only functions:calmControl,spiritualRhythm
- [ ] I-5: Firebase Console -> Remote Config -> seed all aegis.C1..C58 = false
- [ ] I-6: firebase deploy --only functions:churchSearchProxy,postProvenanceProxy,selahStoryProxy

### App Code P0 Fix Order

1. C-3: AccountStatusGate in AMENAPPApp.swift (blocks all users)
2. C-4: NotificationDeepLinkRouter auth guard (security)
3. C-1: Wire AegisPrePostReviewSheet into CreatePostView (trust & safety)
4. C-2: Email verification gate at compose (safety)
5. C-5: COPPA DM minor flag (legal)
6. C-6: Delete account in Settings <=3 taps (App Store)
7. C-7: IAP terms before SKPayment (App Store)
8. C-8: Berean medical refuse + disclaimer (safety)
9. C-9: Berean injection detect -> refuse + log (security)
10. C-10: Bulk notif rate limit 100/min (reliability)
11. C-11: Grooming child photo auto-remove + T&S (safety)
12. C-12: CreatePostView VoiceOver accessibilityLabel (a11y)
13. C-13: Event soft-delete; system reminder for RSVPs (integrity)
14. C-14: designateSuccessor() before pastor account delete (integrity)

### Platform OS Build Order (post-launch)

**Build 1 (P0 — before any beta):** OS-02 EntitlementService v2, OS-20 RecoveryService, OS-21 AuditTrailService
**Build 2 (P1 — before App Store):** OS-03 IAP terms, OS-08 COPPA gates, OS-11 Church succession
**Build 3 (P2 — post-launch hardening):** OS-07 reputation audit trail, OS-22 revenue reconciliation, OS-24+25 continuity engine

---

*Audit generated 2026-06-01 | Branch: feature/spiritual-os | 713+ items | 7 parallel agents*
