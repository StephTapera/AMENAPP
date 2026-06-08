# C1 — Object Model & Graph Schema

**Version:** v2.0.0  
**Status:** COMPLETE — Phase 0 Contract  
**Owner:** Phase 0 / C1 — Core Object Model  
**Last Updated:** 2026-06-05  
**Synthesized from:** 20+ existing model files in AMENAPP/AMENAPP/  

---

## 1. Universal Object Types

Every object is a Firestore document. The type is encoded in the document path and in a `_type` field for cross-collection queries.

| Type | ObjectType string | Collection | Description |
|------|---|-----------|-------------|
| `User` | `user` | `/users/{uid}` | Authenticated account |
| `Organization` | `organization` | `/organizations/{orgId}` | Church, school, business, ministry, nonprofit, team, creator |
| `Church` | `church` | `/churches/{churchId}` | Verified church entity (distinct from Organization for trust/discovery) |
| `Team` | `team` | `/teams/{teamId}` | Internal team within a Church or Space |
| `Space` | `space` | `/covenants/{spaceId}` | Amen Space / Covenant (community hub, ≈ Slack workspace + Patreon) |
| `Post` | `post` | `/posts/{postId}` | Public/semi-public feed item |
| `Prayer` | `prayer` | `/prayers/{prayerId}` | Prayer request or room |
| `Discussion` | `discussion` | `/objectDiscussionRooms/{parentId}/rooms/{roomId}` | Threaded discussion spawned from any canonical object |
| `Study` | `study` | `/studies/{studyId}` | Bible study plan or room |
| `Event` | `event` | `/events/{eventId}` | Calendar event |
| `VolunteerOpportunity` | `volunteerOpportunity` | `/volunteerOpportunities/{id}` | Volunteer position |
| `Mentorship` | `mentorship` | `/mentorships/{id}` | Mentorship pairing/request |
| `Job` | `job` | `/jobs/{jobId}` | Job or internship posting |
| `ChurchNote` | `churchNote` | `/users/{uid}/churchNotes/{noteId}` | Sermon/service notes (user-owned) |
| `BereanInsight` | `bereanInsight` | `/users/{uid}/bereanInsights/{insightId}` | AI-generated scripture study output (user-owned) |
| `MediaObject` | `mediaObject` | `/mediaObjects/{mediaId}` | Audio, video, image, document |
| `Moment` | `moment` | `/moments/{momentId}` | ONE private social moment (E2E capable) |
| `ActionThread` | `actionThread` | `/actionThreads/{threadId}` | Care workflow (already built — do not replace) |

> OPEN: Should `Moment` and `Post` be unified under a single `/content/{id}` collection with a `contentType` discriminator, or remain separate paths? Current code treats them as separate systems with different privacy contracts.

> OPEN: `Church` vs `Organization` — the codebase has both `GivingOrganization` (with `trustBadges`, `transparency`) and `Church` (with `ChurchModels`). They are currently distinct. Confirm whether Church is a sub-type of Organization or a parallel type.

---

## 2. Shared Capability Set

Every object exposes zero or more of these capabilities. The resolved capability set is computed per `(objectType, viewerRole, audienceLevel)` — see C5 for the RBAC matrix.

```
View | Discuss | Pray | Study | Share | Save | Invite | FollowUp
```

No object exposes capabilities beyond this set. New verbs require a C1 contract change.

The table below shows which capabilities each object type exposes. A checkmark means the object type surfaces this affordance in the UI and has a backend handler.

| Object Type | View | Discuss | Pray | Study | Share | Save | Invite | FollowUp |
|---|---|---|---|---|---|---|---|---|
| User | Y | | Y | | Y | | Y | |
| Organization | Y | Y | Y | | Y | Y | Y | |
| Church | Y | Y | Y | Y | Y | Y | Y | Y |
| Team | Y | Y | Y | | Y | | Y | Y |
| Space | Y | Y | Y | Y | Y | | Y | Y |
| Post | Y | Y | Y | | Y | Y | | |
| Prayer | Y | Y | Y | | Y | Y | | Y |
| Discussion | Y | Y | Y | | Y | | Y | |
| Study | Y | Y | Y | Y | Y | Y | Y | Y |
| Event | Y | Y | Y | | Y | Y | Y | Y |
| VolunteerOpportunity | Y | Y | Y | | Y | Y | Y | Y |
| Mentorship | Y | Y | Y | Y | | | Y | Y |
| Job | Y | Y | | | Y | Y | | Y |
| ChurchNote | Y | | Y | Y | Y | Y | | Y |
| BereanInsight | Y | Y | Y | Y | Y | Y | | |
| MediaObject | Y | Y | Y | | Y | Y | | |
| Moment | Y | | Y | | Y | | | |
| ActionThread | Y | Y | Y | | | | Y | Y |

> OPEN: `ChurchNote` currently has no `Discuss` capability in the UI. The `ObjectDiscussionRoom` system can spawn a room from any canonical object. Should ChurchNotes become first-class discussion surfaces?

> OPEN: `Mentorship` Share capability — mentorship relationships are intentionally private in current code (`ONEWitness`). Should Share be blocked at the capability layer rather than just UI-hidden?

---

## 3. Provenance — Inline on Every Spawnable Object

Every object that can be created *from* another object carries an immutable `provenance` block written at creation time. It is **never updated after creation.**

**Spawnable objects** (must carry `provenance`): Post, Prayer, Discussion, Study, ChurchNote, BereanInsight, VolunteerOpportunity, Job, Mentorship, Event, Moment, ActionThread.

**Non-spawnable** (no provenance): User, Organization, Church, Team, Space, MediaObject.

> OPEN: Should `MediaObject` become spawnable when AI-generated (e.g., from a church note audio upload)? The AI audit flagged this as a traceability gap.

### 3a. Swift struct

```swift
// Defined in stubs/AmenCoreModels.swift
// NOTE: Named "Provenance" in Swift stubs; keep distinct from ONEProvenanceLabel
// (which tracks media authenticity, not spawn chain).
struct Provenance: Codable, Equatable, Sendable {
    let sourceType: String       // ObjectType raw value, e.g. "post", "bereanInsight"; nil="direct"
    let sourceRef: String?       // Firestore document path, e.g. "/posts/abc123"; nil for root objects
    let sourceOwnerId: String?   // uid of the original object's owner
    let intent: String           // C2 Intent raw value, e.g. "discuss", "pray", "direct"
    let createdAt: Date          // server-side FieldValue.serverTimestamp(); never client-set
}
```

### 3b. Firestore shape

```json
"provenance": {
  "sourceType": "post",
  "sourceRef": "/posts/abc123",
  "sourceOwnerId": "uid_XYZ",
  "intent": "discuss",
  "createdAt": "<Timestamp>"
}
```

### 3c. Rules

- Root-originated objects (no parent) set `provenance.sourceRef = null` and `sourceType = "direct"`.
- Resharing a reshared object sets `sourceRef` to the **original** (hop 1), not the intermediate.
- `TrueSourceMetadata.repostLineage` records the full chain for provenance UI; `Provenance.sourceRef` is the canonical single link used for access/permission resolution.
- `createdAt` on `Provenance` is always set server-side via Cloud Function or Firestore trigger. The iOS client never writes this field.

> OPEN: Rename `Provenance` to `SpawnProvenance` in all stubs and schemas to avoid collision with `ONEProvenanceLabel` (the media-authenticity struct in ONE/Core/). Decision needed before stubs are consumed by feature agents.

---

## 4. Edges Collection — Many-to-Many Relationships

The `edges` collection enables many-to-many relationships between any two objects without embedding arrays on parent documents. This prevents unbounded array growth and enables bidirectional reads.

### 4a. Firestore shape

Collection: `/edges/{edgeId}`

```json
{
  "_type": "edge",
  "fromRef": "/posts/abc",
  "fromType": "post",
  "toRef": "/organizations/xyz",
  "toType": "organization",
  "edgeType": "belongsTo",
  "createdBy": "uid_ABC",
  "visibility": "members",
  "createdAt": "<Timestamp>"
}
```

### 4b. EdgeType enum

| Value | Meaning |
|-------|---------|
| `belongsTo` | Object is owned/hosted by another (Post→Church, User→Space, Event→Org) |
| `spawnedFrom` | Object was created via a transform (Discussion←Post via Discuss intent) |
| `links` | Contextual association (ChurchNote↔Sermon, BereanInsight↔Scripture) |
| `follows` | User follows User/Org/Space/Church/Creator |
| `praysFor` | User is actively praying for a Prayer or Person |

> OPEN: Is `follows` needed given the existing SocialGraph service has its own follow data at `/socialGraph/{uid}/following`? These may be redundant — confirm whether edges replace or overlay that structure before writing to both paths.

> OPEN: Should `praysFor` edges be written by the client or strictly by a Cloud Function after a prayer reaction? Client-side writes open surface area for spam / fake prayer counts.

### 4c. EdgeVisibility

```
"public"   — visible to anyone who can read both endpoint objects
"members"  — visible only to members of a shared Space or Church
"private"  — visible only to the createdBy user
```

### 4d. Indexes required (Firestore composite)

```
Index 1 — forward traversal:
  fromRef ASC, edgeType ASC, createdAt DESC
  Purpose: "All edges FROM object X of type Y, sorted by recency"

Index 2 — reverse traversal:
  toRef ASC, edgeType ASC, createdAt DESC
  Purpose: "All edges TO object X — e.g., who follows this church"

Index 3 — type-scoped traversal:
  fromType ASC, toType ASC, edgeType ASC, createdAt DESC
  Purpose: "All edges between two object types"
```

### 4e. Fan-out rule (pending D1 decision)

Default ceiling: **≤ 50 edge writes per mutation** before switching to async queue. Objects with predicted fan-out > 50 (broadcast announcements, large-org events) use `async/batch` path; UI shows eventual-consistency indicator.

---

## 5. Per-Object Schema Sketches

Fields synthesized from existing codebase model files. Existing field names are preserved exactly. New fields added for C1 completeness are noted with `[C1-new]`.

### User

```
/users/{uid}
  uid: string                         // = Firebase Auth uid
  displayName: string
  avatarURL: string?
  bio: string?
  ageTier: "tierD"|"tierC"|"tierB"|"blocked"  // [C1-new] set by server, never client
  privacyMirror: ONEPrivacyMirrorLevel        // "sealed"|"opaque"|"translucent"|"open"
  presenceState: ONEPresenceState
  entitlement: ONEEntitlement
  reachBudgetRemaining: int           // replenishes weekly; default 20
  isMemorialized: bool
  legacyDirectiveID: string?
  persona: UserPersona?               // "believer"|"pastor"|"creator"|etc.
  faithJourneyStage: FaithJourneyStage?
  denomination: Denomination?
  profileIdentity: UserProfileIdentity
  verificationState: "none"|"pending"|"verified"   // [C1-new]
  roles: { [orgId]: SpaceMemberRole }              // [C1-new]
  createdAt: Timestamp
  updatedAt: Timestamp
  isDeleted: bool                     // [C1-new] soft delete
```

### Organization

```
/organizations/{orgId}
  _type: "organization"
  orgType: "church"|"school"|"university"|"business"|"ministry"|"team"|"creator"|"nonprofit"
  name: string
  slug: string
  description: string?
  logoURL: string?
  coverURL: string?
  verificationState: "none"|"pending"|"verified"
  entitlementPlan: "free"|"communityPro"|"churchPro"|"orgPro"|"enterprise"  // [C1-new]
  adminIds: string[]                  // uids
  privacyLevel: "public"|"members"|"private"
  causeCategories: [GivingCause]?
  trustBadges: [TrustBadge]
  trustScore: double                  // 0.0-1.0
  transparency: OrgTransparency?
  websiteUrl: string?
  donationUrl: string?
  isActive: bool
  createdAt: Timestamp
  updatedAt: Timestamp
  isDeleted: bool
```

### Church

```
/churches/{churchId}
  _type: "church"
  name: string
  address: string?
  city: string?
  state: string?
  zipCode: string?
  denomination: Denomination?
  website: string?
  logoURL: string?
  trustBadges: [TrustBadgeType]
  memberCount: int                    // denormalized
  isVerified: bool
  isActive: bool
  createdBy: string?                  // uid of claiming pastor/admin
  verificationState: "none"|"pending"|"verified"
  createdAt: Timestamp
  updatedAt: Timestamp
  isDeleted: bool
```

> OPEN: Who owns the claim of a Church record — the platform admin or a verified church leader? The `CreatorVerificationRequest` model in CovenantModels.swift covers `.church` verification type — link this to the Church claim flow.

### Team

```
/teams/{teamId}
  _type: "team"
  name: string
  description: string?
  churchId: string?                   // denormalized FK; edge also exists
  spaceId: string?                    // denormalized FK
  creatorId: string
  memberCount: int                    // denormalized
  isPrivate: bool
  createdAt: Timestamp
  updatedAt: Timestamp
  isDeleted: bool
```

### Space (Covenant)

```
/covenants/{spaceId}
  _type: "space"
  name: string
  tagline: string
  description: string
  creatorId: string
  coverImageURL: string?
  avatarURL: string?
  tiers: [CovenantTier]
  operatingMode: CovenantOperatingMode   // "teaching"|"prayer"|"event"|"quiet"|"launch"
  trustBadges: [TrustBadgeType]
  memberCount: int                       // denormalized
  paidMemberCount: int                   // denormalized
  isPublic: bool
  isPaused: bool
  createdAt: Timestamp
  updatedAt: Timestamp
  isDeleted: bool
```

### Post

```
/posts/{postId}
  _type: "post"
  authorId: string
  authorDisplayName: string            // denormalized
  authorAvatarURL: string?             // denormalized
  body: string
  mediaAttachments: string[]           // mediaObject IDs or Storage URLs
  scriptureRefs: string[]
  tags: string[]
  audience: ContentAudience
  visibility: "public"|"followers"|"church"|"space"|"private"
  spaceId: string?
  churchId: string?
  likeCount: int                       // denormalized
  commentCount: int                    // denormalized
  prayerCount: int                     // denormalized
  moderationStatus: ContentModerationStatus
  trueSource: TrueSourceMetadata?
  provenance: Provenance?
  capabilities: string[]               // resolved capability set for display
  createdAt: Timestamp
  updatedAt: Timestamp
  isDeleted: bool
  deletedAt: Timestamp?
```

### Prayer

```
/prayers/{prayerId}
  _type: "prayer"
  authorUserId: string
  authorDisplayName: string            // denormalized
  body: string
  visibility: "public"|"membersOnly"|"anonymous"
  prayedCount: int                     // denormalized
  followUpRequested: bool
  status: "open"|"updated"|"answered"|"closed"
  covenantId: string?
  roomId: string?
  sourceMessageId: string?
  lastUpdateAt: Timestamp?
  provenance: Provenance?
  createdAt: Timestamp
  updatedAt: Timestamp
  isDeleted: bool
```

### Discussion (ObjectDiscussionRoom)

```
/objectDiscussionRooms/{canonicalObjectId}/rooms/{roomId}
  _type: "discussion"
  canonicalObjectId: string
  canonicalObjectTitle: string         // denormalized
  canonicalObjectType: ObjectType      // [C1-new] type discriminator on parent
  roomType: "discussion"|"prayer"|"study_group"
  participantCount: int                // denormalized
  messageCount: int                    // denormalized
  lastMessage: string?                 // denormalized
  lastMessageAt: Timestamp?            // denormalized
  createdBy: string
  provenance: Provenance?
  createdAt: Timestamp
  updatedAt: Timestamp
  isDeleted: bool
```

> OPEN: `objectDiscussionRooms` uses `canonicalObjectId` as the parent doc — but this is not namespaced by object type. Two objects of different types with the same ID will collide. Recommended path: `/objectDiscussionRooms/{objectType}_{canonicalObjectId}/rooms/{roomId}`.

> OPEN: Discussion messages currently have no pagination contract. All messages load from sub-collection. Add pagination limit (default 50/page) before Discussion goes live.

### Study

```
/studies/{studyId}
  _type: "study"
  title: string
  description: string
  authorUid: string
  studyType: "plan"|"room"
  passages: string[]                   // scripture references
  weekCount: int
  audience: ContentAudience
  isPublic: bool
  spaceId: string?
  churchId: string?
  provenance: Provenance?
  createdAt: Timestamp
  updatedAt: Timestamp
  isDeleted: bool
```

> OPEN: No standalone `Study` document model exists in the main source tree. Only `CovenantScheduledContent` references `studyDrop` target type. Author `StudyModels.swift` before study features ship.

### Event

```
/events/{eventId}
  _type: "event"
  title: string
  description: string
  organizerId: string                  // uid or Church/Space ID
  organizerType: ObjectType            // "user"|"church"|"space"
  startAt: Timestamp
  endAt: Timestamp?
  locationText: string?
  locationCoords: GeoPoint?            // [C1-new] redacted before public publication
  isVirtual: bool
  streamURL: string?
  rsvpCount: int                       // denormalized
  audience: ContentAudience
  spaceId: string?
  churchId: string?
  provenance: Provenance?
  createdAt: Timestamp
  updatedAt: Timestamp
  isDeleted: bool
```

> OPEN: No standalone `Event` model exists in the main source tree. Only `CovenantActivity.ActivityType.eventReminder` and `CovenantScheduledContent.TargetType.event` reference events. Author `EventModels.swift`.

### VolunteerOpportunity

```
/volunteerOpportunities/{id}
  _type: "volunteerOpportunity"
  title: string
  description: string
  organizationId: string
  churchId: string?
  location: string?
  isRemote: bool
  causeCategory: GivingCause
  requiredSkills: string[]
  applicationUrl: string?
  contactMethod: "amenInbox"           // always Amen inbox — never raw PII
  audience: ContentAudience
  expiresAt: Timestamp?
  provenance: Provenance?
  createdAt: Timestamp
  updatedAt: Timestamp
  isDeleted: bool
```

> OPEN: No `VolunteerOpportunity` model exists in the main source tree. Referenced in `AmenHubItemType.volunteerRequest` and `OpenToSignal.serving`. Author model before volunteer features ship.

### Mentorship

```
/mentorships/{id}
  _type: "mentorship"
  mentorUid: string
  menteeUid: string
  status: "requested"|"active"|"paused"|"completed"
  focus: string?
  scriptureTheme: string?
  sessionCount: int
  nextSessionAt: Timestamp?
  provenance: Provenance?
  createdAt: Timestamp
  updatedAt: Timestamp
  isDeleted: bool
```

> OPEN: `Mentorship` model implied by `OpenToSignal.mentorship` and `RelationshipType.mentor/mentee` but no document schema exists. Author `MentorshipModels.swift`.

### Job

```
/jobs/{jobId}
  _type: "job"
  title: string
  description: string
  organizationId: string
  organizationType: ObjectType         // "church"|"organization"
  location: string?
  isRemote: bool
  jobType: JobType                     // OPEN: JobType enum not defined
  salaryRange: string?
  applicationUrl: string?
  contactMethod: "amenInbox"           // always Amen inbox — never raw PII
  expiresAt: Timestamp?
  provenance: Provenance?
  createdAt: Timestamp
  updatedAt: Timestamp
  isDeleted: bool
```

> OPEN: `JobModels.swift` was found in git worktrees but not in the main source tree. Locate or re-author.

### ChurchNote

```
/users/{uid}/churchNotes/{noteId}
  _type: "churchNote"
  userId: string
  type: LivingEntryType                // "churchNote"|"sermonInsight"
  title: string
  body: string
  churchId: string?
  churchName: string?                  // denormalized
  sermonTitle: string?
  scriptureRefs: string[]
  tags: string[]
  anchors: [CNAnchorType]
  posture: CNPostureSignal?
  sermonBridge: CNSermonBridge?
  state: LivingEntryState
  reflectionPrompt: string?
  reflectionAnswer: string?
  aiSummary: string?
  provenance: Provenance?
  createdAt: Timestamp
  updatedAt: Timestamp
  isDeleted: bool
```

### BereanInsight

```
/users/{uid}/bereanInsights/{insightId}
  _type: "bereanInsight"
  userId: string
  requestText: string
  responseText: string
  intent: BereanRequestIntent          // "scripture"|"doctrine"|"personal"|"pastoral"|etc.
  risk: BereanRequestRisk              // "low"|"elevated"|"high"|"pastoral"|"crisis"
  scriptureRefs: string[]
  studyOutline: BereanStudyOutline?
  provenanceRecord: BereanProvenanceRecord
  provenance: Provenance?
  createdAt: Timestamp
  updatedAt: Timestamp
  isDeleted: bool
```

### MediaObject

```
/mediaObjects/{mediaId}
  _type: "mediaObject"
  ownerUid: string
  storageURL: string
  thumbnailURL: string?
  mimeType: string
  durationSeconds: double?
  widthPx: int?
  heightPx: int?
  altText: string?
  captionsURL: string?
  sourceType: MediaSourceType          // "device_camera"|"ai_generated"|etc.
  syntheticStatus: SyntheticMediaStatus
  contentCredentials: ContentCredentialsStatus
  aiEvents: [ProvenanceAIEvent]
  editEvents: [ProvenanceEditEvent]
  disclosureRequired: bool
  disclosureSatisfied: bool
  moderationStatus: string
  createdAt: Timestamp
  updatedAt: Timestamp
  isDeleted: bool
```

### Moment (ONE)

```
/moments/{momentId}
  _type: "moment"
  authorUID: string
  type: ONEMomentType                  // "directMessage"|"snap"|"post"|"story"|"voice"|etc.
  privacy: ONEPrivacyContract
  content: ONEMomentContent            // encrypted payload for E2E; plaintext content otherwise
  provenanceLabel: ONEProvenanceLabel  // media authenticity (distinct from spawn Provenance)
  consentDNA: ONEConsentDNA
  reachBudget: ONEReachBudget?
  isE2E: bool
  expiresAt: Timestamp?
  permanentAt: Timestamp?
  reportedAt: Timestamp?
  provenance: Provenance?              // spawn chain (nil for root moments)
  createdAt: Timestamp
  updatedAt: Timestamp
  isDeleted: bool                      // [C1-new] currently absent from ONEMoment
```

> OPEN: `ONEMoment` uses `ONEProvenanceLabel` (media authenticity) rather than the universal `Provenance` struct (spawn chain). Both are needed but naming is ambiguous. Recommend keeping `ONEProvenanceLabel` as `provenanceLabel` and using `Provenance` as `provenance` on all spawnable objects including Moment.

### ActionThread (existing — do not replace)

```
/actionThreads/{threadId}
  // Existing schema — see ActionThreadModels.swift
  // C1 treatment: ActionThread is a spawnable object and may carry provenance.
  // No schema changes to this type in Phase 0.
```

---

## 6. Denormalization Rules

### 6.1 What Is Always Denormalized (copied onto the object)

| Field | Copied Onto | Rationale |
|-------|-------------|-----------|
| `authorDisplayName`, `authorAvatarURL` | Post, Prayer, Discussion msg, CovenantMessage | Feed rendering without second read |
| `participantCount`, `messageCount` | Discussion, CovenantRoom | Card-level UI without subcollection query |
| `memberCount`, `paidMemberCount` | Space (Covenant) | Hub card rendering |
| `canonicalObjectTitle` | ObjectDiscussionRoom | Room header without parent-object fetch |
| `trustBadges[]` | Organization, Church | Discovery feed card render |
| `churchName` | LivingEntry, ChurchNote | Avoids Church document read when surfacing entries |
| `lastActivityAt`, `lastMessage` | Thread, CovenantRoom | Inbox sorting |
| `rsvpCount` | Event | Updated by CF `counts` trigger on RSVP edge |
| `threadCount` | Discussion | Updated by CF `counts` trigger on message create/delete |

### 6.2 What Is Always Edge-Resolved (never denormalized)

| Relationship | Rationale |
|---|---|
| User → Church membership | User can belong to many churches; embedding creates unbounded arrays |
| User → Space membership | Same — `CovenantMembership` lives in `/covenants/{id}/members` |
| Post → Discussion rooms | Rooms are spawned lazily; the edge is created on spawn |
| Prayer ← praysFor ← Users | Aggregate counts are denormalized, but individual prayors are edge-only |
| Study ← belongsTo ← Space | A study can belong to multiple spaces |

### 6.3 Denormalization Update Strategy (Display Name Fan-Out)

When a User changes `displayName` or `avatarURL`:
1. A Firestore Cloud Function triggers on `users/{uid}` write.
2. It fans out updates to Post, Prayer, CovenantMessage, and ObjectDiscussionMessage documents written within the last 90 days (batch update, max 500 per CF invocation).
3. Documents older than 90 days retain the stale display name — acceptable per product spec.

> OPEN: The 90-day fan-out window is not currently enforced in any CF. Define the cutoff and add it to the CF deploy checklist.

---

## 7. Read Fan-Out Cost Analysis Per Object Type

| Object Type | Fan-Out Pattern | Max Reads Per Page Load |
|---|---|---|
| User | Single document | 1 |
| Post (feed card) | Post doc; author avatar denormalized | 1 |
| Post + Church affiliation | Post + Church doc | 2 |
| Discussion (room card) | Room doc only; counts denormalized | 1 |
| Discussion (messages) | Room + messages sub-collection paginated 50/page | 51 |
| Space (Covenant) hub | Space + rooms (paginated) | 1 + N rooms |
| Prayer | Prayer doc; author denormalized | 1 |
| ChurchNote | Note doc + optional Church doc | 1–2 |
| BereanInsight | Single user sub-collection read | 1 |
| MediaObject | Single doc + Firebase Storage URL | 1 |
| Event | Event doc + optional Org/Church doc | 1–2 |
| Study | Study doc + optional member list (edge query) | 1 + edge page |
| Job | Single document | 1 |
| Mentorship | Single document | 1 |
| VolunteerOpportunity | Opportunity doc + linked Church/Org | 1–2 |
| Organization | Single doc (all trust data denormalized) | 1 |
| Moment (ONE) | Single doc (private-by-design; no server aggregation) | 1 |
| Edges | Bidirectional edge query (indexed) | Paginated, 25/page |

---

## 8. Open Questions Summary

| # | Domain | Question |
|---|---|---|
| OQ-1 | Post vs Moment | Unify under `/content/{id}` or keep separate? |
| OQ-2 | Church vs Org | Is Church a sub-type of Organization or a parallel top-level type? |
| OQ-3 | MediaObject provenance | Should MediaObject become spawnable when AI-generated? |
| OQ-4 | Discussion path collision | Namespace `objectDiscussionRooms` by object type to prevent ID collision? |
| OQ-5 | ChurchNote discussion | Should ChurchNotes become first-class Discussion surfaces? |
| OQ-6 | Mentorship sharing | Block Share capability on Mentorship at capability layer? |
| OQ-7 | Fan-out window | Define and enforce 90-day display-name fan-out cutoff in CFs. |
| OQ-8 | Discussion pagination | Add pagination contract for Discussion messages before live launch. |
| OQ-9 | Church ownership | Who claims a Church record — platform admin or verified leader? |
| OQ-10 | Study model | Author `StudyModels.swift` (currently only referenced via schedule types). |
| OQ-11 | Event model | Author `EventModels.swift` (only referenced via CovenantActivity). |
| OQ-12 | VolunteerOpportunity model | Author `VolunteerOpportunityModels.swift`. |
| OQ-13 | Mentorship model | Author `MentorshipModels.swift`. |
| OQ-14 | Job model | Locate or re-author `JobModels.swift` (found in git worktrees, absent from main). |
| OQ-15 | Provenance naming | Rename generic `Provenance` → `SpawnProvenance` to avoid collision with `ONEProvenanceLabel`. |
| OQ-16 | praysFor edge ownership | Client-written or CF-only `praysFor` edges? |
| OQ-17 | follows edge vs socialGraph | Does `follows` EdgeType replace or overlay `/socialGraph/{uid}/following`? |
| OQ-18 | isDeleted on Moment | Add `isDeleted` flag to `ONEMoment` (currently absent). |

---

## Done Criteria

- [ ] Schema doc reviewed and signed off by human
- [ ] Swift stubs in `stubs/AmenCoreModels.swift` compile with zero diagnostics
- [ ] A sample round-trip test (create → fetch → transform) passes for Post, Prayer, Discussion
- [ ] Provenance chain verified: spawn a Discussion from a Post; `provenance.sourceRef` points to original Post
- [ ] OQ-1 through OQ-18 answered or deferred with an explicit decision log entry
