# ONE — Frozen Contracts
# Generated: 2026-06-01 | Status: FROZEN — amendment requires RUNLOG entry + orchestrator approval
# Version: 1.0.0

---

## Amendment Log
| # | Date | Field Changed | Reason | Approved By |
|---|------|--------------|--------|------------|
| — | — | — | Initial freeze | Lead Orchestrator |

---

## 1. Core Object — ONEMoment

The single universal content primitive. Format is downstream of privacy scope.

```swift
struct ONEMoment: Codable, Identifiable, Sendable {
    let id: String                         // Firestore document ID
    let authorUID: String
    let type: ONEMomentType
    var privacy: ONEPrivacyContract        // mutable until sent; frozen on send
    let content: ONEMomentContent          // tagged union; see §1.2
    let provenance: ONEProvenanceLabel
    let createdAt: Date
    var expiresAt: Date?                   // nil = no scheduled decay
    var permanentAt: Date?                 // set when user explicitly remembers
    var reachBudget: ONEReachBudget?       // nil for private/DM moments
    let consentDNA: ONEConsentDNA          // per-message permissions; travels with the moment
    let isE2E: Bool                        // true = Firestore stores only ciphertext
    var reportedAt: Date?                  // set server-side on report; evidence locked
}

enum ONEMomentType: String, Codable, Sendable {
    case directMessage       // DM, E2E
    case snap                // disappearing
    case post                // public/semi-public post
    case story               // 24h story ring
    case voice               // voice note
    case reflection          // prayer / journal entry
    case locationShare       // live or static location
    case memory              // vault-eligible personal memory
    case album               // collaborative album
    case creatorDrop         // gated creator content
}
```

### 1.1 ONEMomentContent (tagged union)

```swift
enum ONEMomentContent: Codable, Sendable {
    case text(ONETextPayload)
    case image(ONEImagePayload)
    case video(ONEVideoPayload)
    case audio(ONEAudioPayload)
    case location(ONELocationPayload)
    case album(ONEAlbumPayload)
    case encrypted(ONEEncryptedPayload)    // E2E; server stores only this case for DMs
}

struct ONETextPayload: Codable, Sendable {
    let body: String                       // max 10,000 chars
    let mentionedUIDs: [String]
    let linkedScriptureRefs: [String]      // optional Berean cross-ref
}

struct ONEImagePayload: Codable, Sendable {
    let storageURL: String
    let provenanceLabel: ONEProvenanceLabel
    let altText: String?
    let facesBlurred: Bool
    let locationStripped: Bool
    let width: Int
    let height: Int
}

struct ONEVideoPayload: Codable, Sendable {
    let storageURL: String
    let thumbnailURL: String?
    let durationSeconds: Double
    let captionsURL: String?               // WebVTT
    let provenanceLabel: ONEProvenanceLabel
    let autoplayEnabled: Bool              // default false
}

struct ONEAudioPayload: Codable, Sendable {
    let storageURL: String
    let durationSeconds: Double
    let transcriptText: String?
}

struct ONELocationPayload: Codable, Sendable {
    let precisionLevel: ONELocationPrecision
    let expiresAt: Date?
    // Note: lat/lng stored ONLY on device; server receives only precision bucket
}

enum ONELocationPrecision: String, Codable, Sendable {
    case exact       // only for explicit live-share consent
    case neighborhood
    case city
    case region
    case hidden
}

struct ONEAlbumPayload: Codable, Sendable {
    let title: String
    let contributorUIDs: [String]
    let itemIDs: [String]                  // references to child ONEMoment IDs
    let isCollaborative: Bool
}

struct ONEEncryptedPayload: Codable, Sendable {
    let ciphertext: Data                   // MLS/HPKE encrypted; server cannot decrypt
    let mlsEpoch: UInt64
    let senderDeviceID: String
}
```

---

## 2. Privacy Contract — ONEPrivacyContract

First-class object attached to every Moment. Displayed as a Liquid Glass pill before send.

```swift
struct ONEPrivacyContract: Codable, Sendable {
    let audience: ONEAudienceScope
    let lifetime: ONELifetimePolicy
    let permissions: ONEMomentPermissions
    let safety: ONESafetySettings
    let metricsPrivate: Bool               // default true; no public likes/views
    let reshareAllowed: Bool               // default false for DMs/snaps
}

enum ONEAudienceScope: Codable, Sendable {
    case selfOnly
    case closeFriends                      // user-curated list
    case witnesses                         // season-scoped followers
    case world                             // fully public
    case custom(Set<String>)               // explicit UID set
    case group(String)                     // ephemeral group ID
}

enum ONELifetimePolicy: Codable, Sendable {
    case afterView                         // snap: decays after first view
    case hours(Int)                        // e.g. 24 for story
    case days(Int)
    case permanent                         // only if user explicitly chooses
    case decayUnlessRemembered(days: Int)  // default for posts; remembered = permanent
}

struct ONEMomentPermissions: Codable, Sendable {
    var forwardAllowed: Bool       = false
    var saveAllowed: Bool          = false
    var quoteAllowed: Bool         = false
    var reactAllowed: Bool         = true
    var translateAllowed: Bool     = true  // on-device translation OK
    var summarizeAllowed: Bool     = false // AI summary requires explicit consent
    var aiTrainingAllowed: Bool    = false // always off by default
}

struct ONESafetySettings: Codable, Sendable {
    var locationStripped: Bool        = true   // default strip EXIF
    var faceBlurEnabled: Bool         = false
    var childDetectionEnabled: Bool   = true   // always on for public content
    var screenshotBehavior: ONEScreenshotBehavior = .notify
}

enum ONEScreenshotBehavior: String, Codable, Sendable {
    case notify      // detect + notify sender — best effort, labeled as such
    case bestEffort  // attempt obscure; label as best-effort
    case none        // user accepts no protection
    // NOTE: "block" is intentionally absent — iOS does not support it without Apple entitlement
}
```

---

## 3. User Identity — ONEUser

```swift
struct ONEUser: Codable, Identifiable, Sendable {
    let id: String                         // == Firebase Auth uid
    let uid: String
    var displayName: String
    var avatarURL: String?
    var bio: String?
    var privacyMirror: ONEPrivacyMirrorLevel
    var presenceState: ONEPresenceState
    var entitlement: ONEEntitlement
    var reachBudgetRemaining: Int          // replenishes weekly; default 20
    var isMemorialized: Bool               // set on verified death
    var legacyDirectiveID: String?
}

enum ONEPrivacyMirrorLevel: String, Codable, Sendable {
    case sealed        // fully private; anonymous browsing renders you anonymous
    case opaque        // profile exists; no detail visible to strangers
    case translucent   // name + bio visible; posts require follow
    case open          // public profile
}

enum ONEPresenceState: String, Codable, Sendable {
    case available
    case focused       // do-not-disturb
    case driving       // no auto-notifications
    case sleeping
    case worship       // silences non-urgent pings
    case traveling
    case withFamily
    case unknown       // default; no inference
}

struct ONEEntitlement: Codable, Sendable {
    let tier: ONEEntitlementTier
    var stripeSubscriptionID: String?
    var validUntil: Date?
    var trialUsed: Bool
}

enum ONEEntitlementTier: String, Codable, Sendable {
    case free
    case subscriber      // full feature set; Stripe-verified
}
```

---

## 4. E2E Thread — ONEThread

```swift
struct ONEThread: Codable, Identifiable, Sendable {
    let id: String                         // Firestore doc ID
    let participantUIDs: [String]          // max 150 for groups
    let mlsGroupID: String?               // MLS group identifier; nil = key-ratchet fallback
    let encryptionVersion: String          // "mls_1.0" | "cr_1.0" (key-ratchet fallback)
    let isEphemeral: Bool
    var expiresAt: Date?
    var livingThreadSummary: ONELivingThreadSummary?   // on-device AI; never uploaded
    var consentOverrides: [String: ONEMomentPermissions] // per-participant overrides
    let createdAt: Date
    var lastActivityAt: Date
    var isArchived: Bool
}

struct ONELivingThreadSummary: Codable, Sendable {
    // Computed ON DEVICE only. Never sent to server. User curates before sharing.
    var decisions: [String]
    var promises: [String]
    var importantDates: [ONELivingDate]
    var sharedLinks: [String]
    var tasks: [ONELivingTask]
    var prayerRequests: [String]
    var lastDistilledAt: Date
}

struct ONELivingDate: Codable, Sendable {
    let label: String
    let date: Date
}

struct ONELivingTask: Codable, Sendable, Identifiable {
    let id: String
    let description: String
    var assignedUID: String?
    var completedAt: Date?
}
```

---

## 5. Consent DNA — ONEConsentDNA

Permissions bound to a Moment; travel with it when reshared.

```swift
struct ONEConsentDNA: Codable, Sendable {
    let momentID: String                   // back-reference
    let authorUID: String
    var permissions: ONEMomentPermissions
    let issuedAt: Date
    let consentVersion: String             // "1.0" — bump on schema change
    // NOTE: cryptographic binding to C2PA payload is P4 scope
}
```

---

## 6. Provenance Label — ONEProvenanceLabel

Every photo/video carries this. Degrades to `.unknown`, never fakes certainty.

```swift
struct ONEProvenanceLabel: Codable, Sendable {
    let classification: ONEProvenanceClass
    let confidence: Float                  // 0.0–1.0; < 0.7 forces .unknown
    let c2paPayload: Data?                 // nil when C2PA unavailable
    let attestedAt: Date?
    let processorNote: String?             // human-readable e.g. "Adobe Firefly"
}

enum ONEProvenanceClass: String, Codable, Sendable {
    case captured                          // direct camera capture, no edits
    case edited                            // filters, crops, color grading
    case aiAssisted                        // generative inpainting, upscale, etc.
    case synthetic                         // fully AI-generated
    case unknown                           // insufficient signal; always safe default
}
```

---

## 7. Feed Modes — ONEFeedMode

No infinite scroll. No autoplay by default.

```swift
enum ONEFeedModeKind: String, Codable, Sendable, CaseIterable {
    case close    // close friends + witnesses only
    case create   // creator drops + collaborative content
    case learn    // long-form, articles, scripture study
    case local    // geo-adjacent community
    case quiet    // curated slow feed; no video; low-motion
}

struct ONEFeedSession: Codable, Sendable {
    let mode: ONEFeedModeKind
    let sessionBudget: Int               // max items; default varies by mode
    let autoplayEnabled: Bool            // always false on init
    var itemsSeen: Int
    var startedAt: Date
}
```

---

## 8. Reach Budget — ONEReachBudget

Anti-virality. Each human relay costs real social capital.

```swift
struct ONEReachBudget: Codable, Sendable {
    let momentID: String
    let originalAuthorUID: String
    var sharesRemaining: Int             // decrements per relay; not replenished per-moment
    var totalRelays: Int
    var chainDepth: Int                  // hops from origin
    let maxChainDepth: Int               // hard cap; default 5
}
```

---

## 9. Witness Relationship — ONEWitness

Replaces the follower model. Time/season-scoped, mutual exposure tracked.

```swift
struct ONEWitness: Codable, Identifiable, Sendable {
    let id: String
    let witnessUID: String               // the watcher
    let subjectUID: String               // the watched
    let season: ONEWitnessSeason
    var expiresAt: Date?                 // nil = indefinite
    var mutualExposureLevel: ONEPrivacyMirrorLevel  // what subject sees back
    let createdAt: Date
    var renewedAt: Date?
}

enum ONEWitnessSeason: String, Codable, Sendable {
    case indefinite
    case liturgical(String)              // e.g. "Advent 2026"
    case academic(String)                // e.g. "Spring 2027"
    case event(String)                   // e.g. "Retreat 2026"
    case custom(days: Int)
}
```

---

## 10. Memory Vault — ONEVaultItem

Encrypted on-device + in Firestore. Server cannot read content.

```swift
struct ONEVaultItem: Codable, Identifiable, Sendable {
    let id: String
    let ownerUID: String
    let encryptedPayload: Data           // CryptoKit AES-GCM; key stored in Secure Enclave
    let iv: Data
    let contentType: ONEVaultContentType
    var timeReleaseAt: Date?             // nil = available now
    var timeReleaseRecipientUIDs: [String]  // empty = self only
    let accessRule: ONEVaultAccessRule
    let createdAt: Date
    var label: String                    // encrypted client-side; hint only
}

enum ONEVaultContentType: String, Codable, Sendable {
    case reflection
    case media
    case document
    case moment                          // archived ONEMoment
}

enum ONEVaultAccessRule: String, Codable, Sendable {
    case selfOnly
    case trustees                        // see ONELegacyDirective
    case timeRelease                     // unlocks at timeReleaseAt
}
```

---

## 11. Legacy Directive — ONELegacyDirective

```swift
struct ONELegacyDirective: Codable, Identifiable, Sendable {
    let id: String
    let ownerUID: String
    var trustees: [ONETrustee]
    var bequests: [ONEMemoryBequest]
    var memorialization: ONEMemorialization
    var activatedAt: Date?               // nil = not yet activated
    let createdAt: Date
    var updatedAt: Date
}

struct ONETrustee: Codable, Sendable {
    let uid: String
    let displayName: String
    var canActivate: Bool                // can trigger memorialization
    var canAccessVault: Bool
}

struct ONEMemoryBequest: Codable, Identifiable, Sendable {
    let id: String
    let vaultItemID: String
    let recipientUID: String
    var deliverAt: Date                  // can be "at activation" or specific date
    var message: String?
}

enum ONEMemorialization: String, Codable, Sendable {
    case archiveProfile                  // freeze; no new interactions
    case quietMemorial                   // minimal presence; no engagement prompts
    case memorialPage                    // explicit memorial with tribute space
    case deleteAll                       // per user choice; trustees verify
}
```

---

## 12. Repair Flow — ONERepairFlow

Structured, opt-in reconciliation. Both parties must accept. Block/sever always instant.

```swift
struct ONERepairFlow: Codable, Identifiable, Sendable {
    let id: String
    let initiatorUID: String
    let otherUID: String
    var phase: ONERepairPhase
    var initiatorAccepted: Bool
    var otherAccepted: Bool
    var toneChecks: [ONEToneCheck]
    var resolvedAt: Date?
    var exitedAt: Date?                  // either party can exit at any time
    let createdAt: Date
}

enum ONERepairPhase: String, Codable, Sendable {
    case invited        // initiator sent; other has not responded
    case active         // both accepted
    case toneCheck      // AI tone preview shown before each message
    case resolved       // both marked resolved
    case exited         // one or both exited
}

struct ONEToneCheck: Codable, Sendable {
    let messagePreview: String           // first 280 chars
    let toneWarning: String?             // nil = tone OK
    let sentAt: Date?                    // nil = not yet sent; user may edit
}
```

---

## 13. Entitlement — ONEEntitlement (see §3)

Defined inline in ONEUser. No separate top-level struct needed.

---

## 14. Firestore Schema

```
/one_moments/{momentID}
  Fields: ONEMoment (minus E2E content; for E2E moments content = encrypted stub)
  Rules: read = participantUIDs or audience-scoped; write = authorUID only after auth check

/one_moments/{momentID}/reactions/{reactionID}
  Rules: read = audience-scoped; write = authenticated user, reactAllowed == true

/one_moments/{momentID}/comments/{commentID}
  Rules: read = audience-scoped + context gate passed; write = auth + context gate server-verified

/one_threads/{threadID}
  Fields: ONEThread metadata (no plaintext message content ever)
  Rules: read/write = request.auth.uid in participantUIDs

/one_threads/{threadID}/messages/{messageID}
  Fields: id, senderUID, ciphertext (Data), mlsEpoch, sentAt, expiresAt
  Rules: read/write = participantUIDs only; server cannot decrypt

/one_users/{uid}
  Fields: ONEUser (minus sensitive presence details)
  Rules: read = privacy-mirror-scoped (see rules draft); write = self only

/one_users/{uid}/witnesses/{witnessID}
  Fields: ONEWitness
  Rules: read = witnessUID or subjectUID; write = witnessUID (accept/renew) or subjectUID (grant)

/one_vaults/{uid}/items/{itemID}
  Fields: ONEVaultItem (encrypted payload; server cannot decrypt)
  Rules: read/write = request.auth.uid == uid ONLY — no exceptions

/one_reach/{momentID}
  Fields: ONEReachBudget
  Rules: read = originalAuthorUID; write = CF service account only (not client-writable)

/one_repair_flows/{flowID}
  Fields: ONERepairFlow
  Rules: read/write = initiatorUID or otherUID; write requires both-party acceptance in phase transitions

/one_legacy/{uid}
  Fields: ONELegacyDirective
  Rules: read = ownerUID or trustees (after activation); write = ownerUID only

/one_evidence/{evidenceID}
  Fields: { momentID, reporterUID, snapshotData (encrypted), lockedAt }
  Rules: read = CF service account + law enforcement CF only; write = CF only (one_reportMoment)
```

---

## 15. Cloud Functions — Callable Signatures

All callables require:
- Firebase Auth token (`context.auth` non-null)
- App Check token (`context.app` non-null)
- Rate limiting (per-UID, CF-side)

```typescript
// P0 stubs — logic added per phase
one_sendMoment(data: { moment: ONEMoment, recipientUIDs?: string[] }): { momentID: string }
one_expireMoment(data: { momentID: string }): { expired: boolean }  // also CF scheduled trigger
one_reportMoment(data: { momentID: string, reason: string }): { evidenceID: string }
one_requestWitness(data: { targetUID: string, season?: ONEWitnessSeason }): { requestID: string }
one_relayMoment(data: { momentID: string, toUIDs: string[] }): { sharesRemaining: number }
one_activateRepairFlow(data: { otherUID: string }): { flowID: string }
one_acceptRepairFlow(data: { flowID: string }): { phase: ONERepairPhase }
one_stripeCheckout(data: { plan: 'subscriber' }): { checkoutURL: string }
one_verifyEntitlement(data: {}): { entitlement: ONEEntitlement }
one_activateLegacy(data: { directiveID: string }): { activated: boolean }  // trustee-only
```

---

## 16. Design Tokens

Reuse from AMEN (never override):
```
amenGold      — primary accent
amenPurple    — secondary accent
amenBlue      — link / informational
amenBlack     — primary background
```

ONE-specific additions (additive only; never replace AMEN tokens):
```swift
// Colors
static let oneGlassWarm     = Color(red: 1.0,  green: 0.94, blue: 0.78, opacity: 0.15)  // candlelight glass
static let oneGlassCool     = Color(red: 0.78, green: 0.86, blue: 1.0,  opacity: 0.12)  // chrome glass
static let oneDecayAmber    = Color.amenGold.opacity(0.6)     // aging/expiring content indicator
static let oneWitnessGold   = Color(hex: "#D4A843")           // witness relationship badge
static let onePrivateIndigo = Color(hex: "#4B5EC6")           // E2E / private indicator
static let oneEphemeralRed  = Color(hex: "#D95B4A")           // countdown / ephemeral
static let oneSubscriberGold = Color(hex: "#C9A227")          // subscriber entitlement badge

// Radius
static let onePillRadius    : CGFloat = 24    // Privacy Contract pill
static let oneCardRadius    : CGFloat = 16    // content cards
static let oneSheetRadius   : CGFloat = 28    // bottom sheets

// Glass surfaces: use .glassEffect() iOS 26 API; wrap in availability guard
// Glass rule: ONLY on dock, capture button, headers, privacy selector, composer, media controls
// NEVER blur every feed cell
```

---

## 17. Architecture Rules (FROZEN)

1. **E2E content never leaves device in plaintext.** Firestore stores `ONEEncryptedPayload` only for DMs.
2. **Living Threads AI is on-device only.** No network call with message content.
3. **Screenshot protection is best-effort.** UX copy must say "We'll try to notify you" not "blocked."
4. **Provenance degrades to `.unknown`** — never to a more confident label without signal.
5. **Reach budget is CF-enforced only.** Client cannot write to `/one_reach/`.
6. **Evidence path is mandatory.** `one_reportMoment` locks evidence before any decay can run.
7. **Subscription funds the product.** No feature may be funded by advertising or engagement ranking.
8. **All new ONE callables require App Check + Auth.** No exceptions.
9. **All ONE types are prefixed `ONE`.** Zero modifications to existing AMEN types.
10. **glassEffect used only on designated chrome surfaces.** Not on feed cells.
