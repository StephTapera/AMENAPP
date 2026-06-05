# C2 — Intent Taxonomy Contract
**AMEN App — Phase 0 Contracts**
Status: FROZEN — Do not edit without Lead Orchestrator authorization.
Authored: 2026-06-05

---

## 1. Purpose

This document is the single source of truth for how an **AmenObject** can be
transformed by user intent into a new derived object. It defines:

- The canonical 11-intent set and their semantics
- The 13 source object types eligible for transformation
- A complete transform matrix mapping (sourceType × intent) → target
- The `transform()` operation contract, provenance rules, and error cases

No intent-routing logic may be written in feature code before this contract is
approved and broadcast to all agents.

---

## 2. Canonical Intent Set

An **Intent** expresses the social or spiritual purpose a user wishes to apply
to a source object. Intents are not free-form; only the 11 below are supported.

> OPEN: Should a 12th intent `Challenge` (scholarly rebuttal / doctrinal
> question) be added, or is `Ask` sufficient for that use case?

### 2.1 Intent Definitions

| Intent | Raw value | Description |
|---|---|---|
| **Share** | `share` | Relay the object — or a quoted/summarized form of it — to an audience. Preserves source attribution. |
| **Discuss** | `discuss` | Open or join a structured conversation room anchored on the source object. |
| **Pray** | `pray` | Spawn a private or group prayer workflow tied to the content; fires ActionThread of type `.prayerCircle`. |
| **Study** | `study` | Create a Bible-study derived object (study guide, reflection sheet, or discussion group) from the source. |
| **Teach** | `teach` | Produce a teaching artefact (sermon outline, devotional, lesson plan) drawn from the source. |
| **Ask** | `ask` | Route a specific question about the source to a mentor, pastor, or AI Berean. |
| **Invite** | `invite` | Generate an invitation artefact (event RSVP, space join-link, or ministry call-to-join). |
| **Volunteer** | `volunteer` | Express or solicit a serve commitment tied to an event or organization. |
| **Hire** | `hire` | Post or respond to a job or paid ministry-role linked to an organization object. |
| **Mentor** | `mentor` | Initiate a structured mentorship request thread anchored on the source. |
| **Announce** | `announce` | Broadcast derived content to a wider audience (space, church feed, or public). |

### 2.2 Who Can Trigger Each Intent

| Intent | Minimum Role Required | Notes |
|---|---|---|
| Share | Any authenticated user | Audience inherits source permissions at most |
| Discuss | Any authenticated user | |
| Pray | Any authenticated user | Private by default |
| Study | Any authenticated user | |
| Teach | Creator role or Space admin | Produces Creator OS artefacts |
| Ask | Any authenticated user | |
| Invite | Space/Org admin, or event host | Members can invite if space setting allows |
| Volunteer | Any authenticated user | Serve slot must exist first |
| Hire | Org admin / employer role | Requires verified organization |
| Mentor | Any authenticated user | Mentor must consent before thread activates |
| Announce | Space admin, church admin, or Creator OS subscriber | |

### 2.3 Privacy Defaults per Intent

| Intent | Default Audience | Can Actor Widen? | Can Actor Narrow? |
|---|---|---|---|
| Share | Same as source (capped, never widened automatically) | No | Yes |
| Discuss | spaceMembers or smallGroup (context-dependent) | Yes, up to publicFeed | Yes |
| Pray | private (ownerOnly) | Yes, to trustedCircle | — |
| Study | private | Yes, to smallGroup or spaceMembers | — |
| Teach | spaceMembers | Yes, to publicFeed | Yes |
| Ask | private (owner + recipient) | No | — |
| Invite | spaceMembers | Yes | Yes |
| Volunteer | spaceMembers | Yes | Yes |
| Hire | publicFeed | Yes (org page) | Yes |
| Mentor | private (owner + mentor) | No — immutable | — |
| Announce | churchOnly | Yes, to publicFeed | Yes |

### 2.4 Moderation Tier per Intent

Moderation tier drives the pipeline review level (NeMo Guard / Vision LLM /
human review) applied to the **output** object.

| Intent | Moderation Tier | Rationale |
|---|---|---|
| Share | Medium | Relay can expose originally-private context |
| Discuss | Medium | Open threads can amplify |
| Pray | Low | Stays private; no broadcast risk |
| Study | Low | Study artefacts are typically self-contained |
| Teach | High | Doctrinal claims reach wide audiences |
| Ask | Low | Routed to specific recipient |
| Invite | Low | Targeted; no mass broadcast |
| Volunteer | Low | |
| Hire | Medium | Public job posts carry PII risk |
| Mentor | Low | Private dyadic thread |
| Announce | High | Designed to reach broadest possible audience |

> OPEN: Should `Hire` be elevated to High given potential fraud / non-verified
> organization risk? See Trust OS Audit 2026-05-28 critical: nonprofit KYC.

---

## 3. Source Object Types

These are the 13 canonical types that can appear as the `source` in a transform
operation. Each maps to an existing Amen domain model.

| Type | Raw value | Description | Existing model reference |
|---|---|---|---|
| **ChurchNote** | `church_note` | Audio/OCR-captured sermon note | `ContentSourceType.churchNote` |
| **BereanInsight** | `berean_insight` | AI-generated reflection / study output | `BereanContextActionResult` |
| **Sermon** | `sermon` | Full sermon or clip from Connect video | `ContentSourceType.sermonClip` |
| **MediaObject** | `media_object` | Photo, video, or audio post attachment | `BereanContextContentType.media` |
| **Post** | `post` | Standard feed post | `ContentSourceType.post` |
| **PrayerRequest** | `prayer_request` | Prayer request post | `ContentSourceType.prayerRequest` |
| **Event** | `event` | Space or org event | `ContentSourceType.event` |
| **Job** | `job` | Ministry job/role posting | (not yet modelled — synthesized) |
| **MentorshipRequest** | `mentorship_request` | Mentorship connection request | (not yet modelled — synthesized) |
| **Message** | `message` | Direct message or Space message | `ContentSourceType.message` |
| **SpaceObject** | `space_object` | An AMEN Space entity | `AmenConnectSpacesSpace` |
| **OrganizationObject** | `organization_object` | Church or ministry org | (maps to church/org concept) |
| **ScriptureReference** | `scripture_reference` | A canonical Bible verse/passage | `BereanContextContentType.scripture` |

> OPEN: `Job` and `MentorshipRequest` have no canonical Firestore model yet.
> These must be modelled in a Phase 1 task before Hire and Mentor transforms
> can be wired end-to-end.

---

## 4. Transform Matrix

Each cell contains: **Target type · Default audience · Room type (if any) ·
Available actions · Moderation tier · Provenance fields copied**.

Abbreviations used in the table:
- Audience: `priv` = private, `tc` = trustedCircle, `sg` = smallGroup, `co` = churchOnly, `sm` = spaceMembers, `pf` = publicFeed
- Mod: `L` = Low, `M` = Medium, `H` = High, `S` = Severe
- `–` = not applicable or blocked (unsupported combination)

> OPEN: Unsupported cells marked `–` must return `TransformError.unsupportedCombination`
> in all engine implementations. A future iteration may unlock additional cells.

### 4.1 Matrix

| Source \ Intent | Share | Discuss | Pray | Study | Teach | Ask | Invite | Volunteer | Hire | Mentor | Announce |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **ChurchNote** | DerivedPost · source audience · – · quote/save/pray · M · sourceId, creatorId, createdAt | DiscussionRoom · sm · BibleStudy · reply/react/save · M · sourceId | ActionThread.prayerCircle · priv · – · complete/add-participant · L · sourceId, sourceType | StudyObject · priv · – · save/share/discuss · L · sourceId, creatorId | TeachingArtefact · sm · – · share/discuss · H · sourceId, creatorId | AskThread · priv · – · reply/resolve · L · sourceId | – | – | – | – | AnnouncementPost · co · – · react/share · H · sourceId, creatorId |
| **BereanInsight** | DerivedPost · source audience · – · quote/save · M · sourceId, bereanActionId | DiscussionRoom · sm · BibleStudy · reply/react · M · sourceId | ActionThread.prayerCircle · priv · – · complete · L · sourceId | StudyObject · priv · – · save/share · L · sourceId, bereanActionId | TeachingArtefact · sm · – · share/discuss · H · sourceId | AskThread · priv · – · reply/resolve · L · sourceId | – | – | – | MentorshipThread · priv · – · reply/accept/decline · L · sourceId | AnnouncementPost · co · – · react/share · H · sourceId |
| **Sermon** | DerivedPost · source audience · – · quote/save/pray · M · sourceId, creatorId, sermonTimestamp | DiscussionRoom · sm · BibleStudy or General · reply/react/save · M · sourceId, creatorId | ActionThread.prayerCircle · priv · – · complete · L · sourceId | StudyObject · priv · – · save/share/discuss · L · sourceId, creatorId | TeachingArtefact · sm · – · share/discuss · H · sourceId, creatorId | AskThread · priv · – · reply/resolve · L · sourceId | InviteArtefact · sm · – · RSVP/share · L · sourceId | – | – | MentorshipThread · priv · – · reply/accept · L · sourceId | AnnouncementPost · co → pf · – · react/share · H · sourceId, creatorId |
| **MediaObject** | DerivedPost · source audience · – · react/save · M · sourceId, creatorId, mediaType | DiscussionRoom · sm · General · reply/react · M · sourceId | ActionThread.prayerCircle · priv · – · complete · L · sourceId | – | TeachingArtefact · sm · – · share · H · sourceId, creatorId | AskThread · priv · – · reply · L · sourceId | – | – | – | – | AnnouncementPost · co · – · react/share · H · sourceId, creatorId |
| **Post** | DerivedPost · source audience · – · quote/react/save · M · sourceId, creatorId, originalAudience | DiscussionRoom · sm · General · reply/react/save · M · sourceId, creatorId | ActionThread.prayerCircle · priv · – · complete/add-participant · L · sourceId | StudyObject · priv · – · save/share · L · sourceId | TeachingArtefact · sm · – · share · H · sourceId, creatorId | AskThread · priv · – · reply/resolve · L · sourceId | InviteArtefact · sm · – · RSVP/share · L · sourceId | – | – | MentorshipThread · priv · – · reply/accept · L · sourceId | AnnouncementPost · co · – · react/share · H · sourceId, creatorId |
| **PrayerRequest** | – (blocked: prayer content cannot be shared without creator approval) | DiscussionRoom · priv or tc · PrayerOnly · reply/pray · L · sourceId, creatorId | ActionThread.prayerCircle · priv → tc · – · complete/add-participant · L · sourceId, creatorId | – | – | AskThread · priv · – · reply/resolve · L · sourceId | – | – | – | MentorshipThread · priv · – · reply/accept · L · sourceId | – (blocked: prayer requests may not be announced) |
| **Event** | DerivedPost · sm → pf · – · RSVP/save/share · M · sourceId, creatorId, eventDate | DiscussionRoom · sm · EventFollowUp · reply/react · M · sourceId | ActionThread.prayerCircle · priv · – · complete · L · sourceId | – | TeachingArtefact · sm · – · share · H · sourceId | AskThread · priv · – · reply · L · sourceId | InviteArtefact · sm → pf · – · RSVP/share · L · sourceId, eventDate | VolunteerSlot · sm · – · sign-up/cancel · L · sourceId | – | – | AnnouncementPost · co → pf · – · react/share/RSVP · H · sourceId, creatorId, eventDate |
| **Job** | DerivedPost · pf · – · save/apply · M · sourceId, orgId, creatorId | DiscussionRoom · sm · General · reply/react · M · sourceId | – | – | – | AskThread · priv · – · reply · L · sourceId | InviteArtefact · pf · – · apply/share · L · sourceId, orgId | – | JobPosting · pf · – · apply/save/share · M · sourceId, orgId | – | AnnouncementPost · co → pf · – · apply/share · H · sourceId, orgId |
| **MentorshipRequest** | – (blocked: mentorship requests are private by contract) | – | ActionThread.prayerCircle · priv · – · complete · L · sourceId | StudyObject · priv · – · save · L · sourceId | – | AskThread · priv · – · reply/resolve · L · sourceId | – | – | – | MentorshipThread · priv · – · reply/accept/decline · L · sourceId, actorId | – |
| **Message** | – (blocked: DM content blocked from Share; see AI Audit 2026-06-02 COPPA/conversation enumeration findings) | DiscussionRoom · tc · General · reply/react · M · sourceId | ActionThread.prayerCircle · priv · – · complete · L · sourceId | – | – | AskThread · priv · – · reply · L · sourceId | – | – | – | MentorshipThread · priv · – · reply · L · sourceId | – |
| **SpaceObject** | DerivedPost · sm · – · join/save/share · M · sourceId, spaceId | DiscussionRoom · sm · General · reply/react · M · sourceId, spaceId | ActionThread.prayerCircle · sm · – · complete · L · sourceId, spaceId | StudyObject · sm · – · save/share · L · sourceId, spaceId | TeachingArtefact · sm · – · share · H · sourceId | AskThread · priv · – · reply · L · sourceId | InviteArtefact · sm → pf · – · join/RSVP/share · L · sourceId, spaceId | VolunteerSlot · sm · – · sign-up/cancel · L · sourceId, spaceId | – | – | AnnouncementPost · co → pf · – · react/join/share · H · sourceId, spaceId |
| **OrganizationObject** | DerivedPost · co → pf · – · save/follow/share · M · sourceId, orgId | DiscussionRoom · co · General · reply/react · M · sourceId, orgId | ActionThread.prayerCircle · co · – · complete · L · sourceId, orgId | StudyObject · co · – · save/share · L · sourceId, orgId | TeachingArtefact · co · – · share · H · sourceId, orgId | AskThread · priv · – · reply/resolve · L · sourceId | InviteArtefact · co → pf · – · join/RSVP · L · sourceId, orgId | VolunteerSlot · co · – · sign-up/cancel · L · sourceId | JobPosting · pf · – · apply/save · M · sourceId, orgId | – | AnnouncementPost · co → pf · – · react/share/join · H · sourceId, orgId |
| **ScriptureReference** | DerivedPost · source audience · – · quote/react/save · M · sourceId, reference, translation | DiscussionRoom · sm · BibleStudy · reply/react/save · M · sourceId, reference | ActionThread.prayerCircle · priv → tc · – · complete/add-participant · L · sourceId, reference | StudyObject · priv · – · save/share/discuss · L · sourceId, reference, translation | TeachingArtefact · sm → pf · – · share/discuss · H · sourceId, reference | AskThread · priv · – · reply/resolve · L · sourceId | – | – | – | MentorshipThread · priv · – · reply/accept · L · sourceId | AnnouncementPost · co → pf · – · react/share · H · sourceId, reference |

### 4.2 Room Type Mapping (Discuss intent)

When the `Discuss` intent produces a `DiscussionRoom`, the room's type is
determined by the source object type:

| Source Type | DiscussionRoom.roomType |
|---|---|
| ChurchNote | `studyGroup` (BibleStudy mode) |
| BereanInsight | `studyGroup` (BibleStudy mode) |
| Sermon | `studyGroup` (BibleStudy mode) or `discussion` |
| MediaObject | `discussion` |
| Post | `discussion` |
| PrayerRequest | `prayer` (PrayerOnly mode) |
| Event | `discussion` (EventFollowUp mode) |
| Job | `discussion` |
| Message | `discussion` |
| SpaceObject | `discussion` |
| OrganizationObject | `discussion` |
| ScriptureReference | `studyGroup` (BibleStudy mode) |

Maps to `ObjectDiscussionRoom.ObjectDiscussionRoomType` in
`AmenObjectDiscussionModels.swift`.

---

## 5. Transform Operation Contract

### 5.1 Signature

```
transform(
    source:   AmenObject,
    intent:   Intent,
    actorId:  String,
    audience: AudienceConfig?
) async throws -> TransformResult
```

- `source` — any object whose `objectType` is in the canonical 13-type set.
- `intent` — one of the 11 canonical intents.
- `actorId` — the authenticated Firebase UID of the initiating user. Must not
  be empty; engine must verify a non-nil `Auth.auth().currentUser` before
  calling.
- `audience` — caller-supplied audience override; nil means use the matrix
  default. The engine **must clamp** to the matrix-defined ceiling (cannot
  automatically widen beyond the matrix default for the given combination).

### 5.2 TransformResult

```
struct TransformResult {
    let newObjectId:    String          // Firestore document ID of the derived object
    let newObjectType:  String          // raw type string of the derived object
    let provenance:     TransformProvenance  // immutable provenance written to Firestore
    let appliedAudience: AudienceConfig  // the audience actually applied (after clamping)
    let appliedPermissions: [String: Bool]  // permission set on the new object
    let moderationTier: ModerationTier
    let roomId:         String?         // non-nil for Discuss intent only
    let actionThreadId: String?         // non-nil for Pray intent only
    let warnings:       [TransformWarning]  // non-fatal advisory messages
}
```

### 5.3 Provenance Rules

Provenance is **always written** and **always immutable** after the transform
operation completes. No code path may produce a `TransformResult` without a
populated `TransformProvenance`.

Fields always copied from source:

| Field | Source location | Required? |
|---|---|---|
| `sourceObjectId` | `source.id` | Yes |
| `sourceObjectType` | `source.objectType.rawValue` | Yes |
| `sourceCreatorId` | `source.creatorId` | Yes |
| `sourceCreatedAt` | `source.createdAt` | Yes |
| `transformActorId` | `actorId` parameter | Yes |
| `transformedAt` | Server timestamp (never client clock) | Yes |
| `intentApplied` | `intent.rawValue` | Yes |
| `originalAudience` | `source.audience.rawValue` | Yes |

Additional fields copied based on source type:
- `sermonTimestamp` — Sermon only
- `scriptureReference`, `translation` — ScriptureReference only
- `bereanActionId` — BereanInsight only
- `orgId` — OrganizationObject, Job only
- `spaceId` — SpaceObject only
- `eventDate` — Event only

Provenance is written to Firestore as an **immutable sub-document** at
`transformedObjects/{newObjectId}/provenance` using a transaction that fails if
the document already exists.

### 5.4 Permission Inheritance Rules

1. The derived object's audience **never exceeds** the matrix-defined default
   for the (sourceType × intent) combination.
2. If `audience` param is supplied and is **narrower** than the matrix default,
   the supplied value is used.
3. If `audience` param is supplied and is **wider** than the matrix default,
   the engine clamps to the matrix default and appends a `TransformWarning`.
4. Permission sets (canEdit, canDelete, canShare, canAddParticipants) are set
   from the `ActionThreadPermissionSet` pattern: actor receives owner defaults,
   others receive role-appropriate defaults.
5. Privacy-restricted source objects (isAnonymous, isDM, hasPrayerContent with
   non-public audience) propagate an **at-most-as-restrictive** constraint to
   the output.

### 5.5 Error Cases

`TransformError` is thrown (not returned as an optional) for all hard failures:

| Error case | When thrown |
|---|---|
| `unsupportedCombination(sourceType:intent:)` | Cell in the matrix is `–` (blocked) |
| `actorNotAuthorized(requiredRole:)` | Actor lacks the minimum role for the intent |
| `sourceObjectNotFound` | `source.id` does not resolve in Firestore |
| `provenanceWriteFailed` | Firestore transaction to write provenance document failed |
| `audienceCapExceeded` | Caller attempted to set audience wider than matrix ceiling (hard block, not just warning) |
| `featureFlagDisabled(flagName:)` | Required Remote Config flag is false |
| `orgNotVerified` | Hire intent attempted without verified organization |
| `mentorConsentPending` | Mentor intent attempted; mentor has not yet consented |
| `missingRequiredProvenance(field:)` | A required provenance field could not be resolved |

---

## 6. Provenance Integrity Rule (Protocol Requirement)

Any concrete type conforming to `TransformEngine` **must** enforce the
following invariant at the protocol boundary — not delegated to callers:

> **Provenance must always be set. A `TransformResult` with a nil or empty
> `provenance` must never be returned. Implementations that cannot guarantee
> provenance must throw `TransformError.missingRequiredProvenance`.**

This maps to the existing pattern in `AmenConnectSpacesHardSafetyRule`:
`noScriptureWithoutProvenance` — extended here to all transform outputs.

---

## 7. Open Questions

> OPEN: Should `BereanInsight` produced by Berean be allowed as a transform
> source for `Teach`, or only for `Study`? Teaching from an AI insight carries
> doctrinal risk; current matrix allows it at `High` moderation tier as a
> compromise.

> OPEN: The `Job` source type has no Swift model. Hire/Job transforms should be
> gated behind `featureFlagDisabled` until a canonical `JobPosting` model is
> modelled and reviewed.

> OPEN: Should `Announce` from a `PrayerRequest` be permanently blocked, or
> should there be a "de-identified testimony" pathway that strips PII first?
> Current matrix permanently blocks it; an unlock would require a new
> `AnonymizedTestimony` target type.

> OPEN: `MentorshipRequest` has no canonical Swift model. The `Mentor` intent
> is spec'd here but cannot be wired until the model exists.

> OPEN: Moderation tier `Severe` is defined in the taxonomy but does not
> appear in the current matrix. Should it apply to any transform output, or is
> it reserved for the Aegis/safety pipeline inputs only?

---

*Contract version: C2-v1 · 2026-06-05*
