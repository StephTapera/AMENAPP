# AMEN Spaces — Phase 0 Frozen Contracts

**Status: FROZEN**  
Date frozen: 2026-05-25  
Branch: audit/2026-05-21

> **Orchestrator law:** Any change to a public interface in this document requires an explicit orchestrator decision, an update to this file, and a notification to all affected agents (A–G). Do not modify these contracts unilaterally.

---

## Files Produced by Phase 0

| File | Owner | Status |
|------|-------|--------|
| `AMENAPP/Spaces/SpacesCore.swift` | Phase 0 (Lead) | FROZEN |
| `AMENAPP/Spaces/ScopedIdentityService.swift` | Phase 0 (Lead) | FROZEN |
| `AMENAPP/Spaces/BereanSpaceMemberContract.swift` | Phase 0 (Lead) | FROZEN |
| `AMENAPP/Spaces/SpacesFeatureFlags.swift` | Phase 0 (Lead) | FROZEN |
| `firestore.rules` (amended) | Phase 0 (Lead) | FROZEN |
| `AMENAPP/Docs/SPACES_INVENTORY.md` | Phase 0 (Lead) | FROZEN |

> **Xcode note:** The four `.swift` files must be added to the AMENAPP target in `project.pbxproj` before they will compile. Add them under a new `Spaces` group.

---

## 1. Core Data Types (SpacesCore.swift)

All agents build against these types. Import `SpacesCore.swift` — do not duplicate definitions.

### AmenSpaceV2
The forward Space contract. Backward-compat bridge: `AmenSpaceV2.from(_ legacy: AMENSpace)`.

| Field | Type | Writable by | Notes |
|-------|------|-------------|-------|
| `id` | `String?` | Server | Firestore document ID |
| `name` | `String` | Client (callable) | Via `createSpace` / `updateSpaceSettings` |
| `description` | `String` | Client (callable) | |
| `type` | `AmenSpaceType` | Client (callable) | Set at creation |
| `visibility` | `AmenSpaceVisibility` | Client (callable) | |
| `parentSpaceId` | `String?` | Client (callable) | Composition feature-flagged |
| `orgId` | `String?` | Client (callable) | |
| `churchId` | `String?` | Client (callable) | |
| `memoryNamespace` | `String?` | **SERVER-OWNED** | Pinecone namespace |
| `dna` | `AmenSpaceDNA?` | **SERVER-OWNED** | Via `generateSpaceDNA` callable |
| `covenant` | `AmenSpaceCovenant?` | Client (callable, values/level only) | `guardianThresholds` SERVER-OWNED |
| `rhythm` | `AmenSpaceRhythm?` | **SERVER-OWNED** | Computed by Agent F pipeline |
| `safetyStatus` | `String?` | **SERVER-OWNED** | GUARDIAN enforced |
| `guardianCovenantId` | `String?` | **SERVER-OWNED** | |
| `aiDetectedTopics` | `[String]` | **SERVER-OWNED** | |
| `createdBy` | `String` | Client (callable) | Set at creation; immutable after |

### AmenRoom
| Field | Writable by | Notes |
|-------|-------------|-------|
| `id` | Server | |
| `spaceId`, `name`, `kind`, `description` | Server (createRoom callable) | |
| `requiredRole` | Server (createRoom callable) | |
| `isPinned`, `isArchived` | Server (admin callable) | |
| `summaryArtifactId` | **SERVER-OWNED** | Ephemeral room dissolution |
| `safetyStatus` | **SERVER-OWNED** | |

### AmenRoomPost
Client may CREATE with these fields ONLY: `roomId`, `spaceId`, `authorId`, `body`, `mediaRefs`, `mentionedUserIds`, `replyToId`, `createdAt`.

Fields that are **SERVER-OWNED** (blocked by Firestore rules if sent by client):
`guardianStatus`, `embeddingRef`, `aiTopics`, `scriptureRefs`, `deletedAt`.

Updates and deletes go through `deleteRoomPost` callable.

### AmenSpaceMembershipV2
| Field | Writable by | Notes |
|-------|-------------|-------|
| `status` | **SERVER-OWNED** | Set by joinSpace/leaveSpace/suspendMember callables |
| `roles` | **SERVER-OWNED** | Set by updateMemberRole callable (admin only) |
| `gifts` | Client (callable: updateScopedProfile) | User self-declares |
| `scopedProfile` | Client (callable: updateScopedProfile) | Owner only |
| `contributionScore` | **SERVER-OWNED** | Private reputation signal |
| `trustLevel` | **SERVER-OWNED** | Private reputation signal |

### AmenScopedProfile
Client may write (own profile, via `updateScopedProfile` callable):
`displayName`, `bio`, `visibleGifts`, `isAnonymous`, `showsPrayerActivity`, `showsStudyActivity`.

### AmenSpacePresence
Client may write own presence (direct Firestore, field-restricted by rules):
`userId`, `spaceId`, `state`, `updatedAt`. All other fields are server-owned or blocked.

---

## 2. Privacy Boundary (ScopedIdentityService.swift)

**Contract:** All agents that need to display another user's Space-specific data MUST call `ScopedIdentityService.shared.projectionFor(userId:spaceId:)`. No agent may read `/users/{uid}` directly and compose it with Space data.

**What the projection returns:** `AmenScopedIdentityProjection` — a controlled view that:
- Respects the user's `isAnonymous` flag (hides name/photo for non-self viewers)
- Includes only `visibleGifts` (user-selected)
- Never exposes `privateInsights` or `safety` subcollections
- Is scoped to one Space — cannot be composed cross-Space without a new explicit grant

**Membership gate:** `projectionFor` throws `ScopedIdentityError.notAMember` if the requester is not in the Space. Agents must handle this error gracefully (show "Member not found" state).

**Cache:** Results are cached in-memory per session. Invalidate with `ScopedIdentityService.shared.invalidateCache(spaceId:)` on leave/suspend/block events.

---

## 3. Berean-as-Member (BereanSpaceMemberContract.swift)

**Contract:** Berean is invoked via `BereanSpaceMemberService.shared.invoke(...)`. Agents never call `Functions.httpsCallable("bereanSpaceInvoke")` directly — always through the service.

**Key rules (non-negotiable):**
1. `BereanSpacePersonality.allowsAIInference(for:)` must return `true` before any invocation.
2. `BereanSpacePersonality.allowsProactiveSurfacing(for:)` must return `true` before Agent F schedules proactive Berean messages.
3. Berean NEVER writes its own response to Firestore — the callable does it server-side. Agents observe the room's snapshot listener for the new post.
4. `guardianStatus` on Berean's posts is set server-side. If it is `"flagged"`, the post is hidden from members until reviewed.
5. Cited recall (`citedRecall(query:spaceId:)`) only returns real `sourceIds`. If confidence < 0.70, the `humbleCaveat` string must be shown.
6. Berean's `BereanResponseProvenance` must be stored with every AI output.

**Default lens by SpaceType:**

| SpaceType | Default Lens |
|-----------|-------------|
| `churchMinistry`, `sermonPrep`, `leadershipRoom` | `wisdom` |
| `prayerGroup`, `supportCommunity`, `discipleshipCohort` | `prayer` |
| `bibleStudy`, `schoolClassroom` | `discernment` |
| All others | `wisdom` |

**Proactive surfacing — blocked for:**
- `supportCommunity` (no proactive ever — explicit @mention only)
- `prayerGroup`, `familyGroup` (requires Space-level opt-in setting)

---

## 4. Feature Flags (SpacesFeatureFlags.swift)

**Contract:** Every Spaces surface must check the relevant flag before rendering. All flags default `false` in production.

```swift
// Required pattern at all Spaces-gated entry points:
guard SpacesFeatureFlags.shared.spacesIntelligenceEnabled else {
    // Show fallback / empty state
    return
}
```

**Master kill switch:** `spacesIntelligenceEnabled` — if `false`, NO Spaces intelligence features may render, regardless of sub-flags.

**Agent ownership of flags:**

| Flag | Agent |
|------|-------|
| `spacesIntelligenceEnabled` | All (master) |
| `spacesLiquidGlassEnabled` | Agent 2 (UI) |
| `spacesRelationshipGraphEnabled` | Agent E |
| `spacesChurchNotesOSEnabled` | Agent C |
| `spacesFindChurchIntelligenceEnabled` | Agent D |
| `spacesTrueSourceSafetyEnabled` | Agent G |
| `spacesEventsRSVPEnabled` | Agent 9 |
| `spacesEnterpriseSchoolModeEnabled` | Agent 8 |
| `spacesBereanMemberEnabled` | Agent B |
| `spacesSmartDiscoveryEnabled` | Agent 10 |
| `spacesAmbientPresenceEnabled` | Agent F |
| `spacesGroupFormationEnabled` | Agent E |
| `spacesMediaIntelligenceEnabled` | Agent 11 |
| `spacesLivingBannersEnabled` | Agent 2 (UI) |
| `spacesPrivateReputationEnabled` | Agent G |
| `spacesEphemeralRoomsEnabled` | Agent F |
| `spacesDNAGenerationEnabled` | Agent A |
| `spacesCompositionEnabled` | Agent E |
| `spacesReadingPlansEnabled` | Agent C |
| `spacesScopedIdentityEnabled` | Agent E |

---

## 5. Firestore Rules (firestore.rules amendments)

### New Helper Functions

```
isSpaceAdmin(spaceId)      — owner or admin role in Space
isSpaceModerator(spaceId)  — owner, admin, moderator, pastor, or elder
```

### New Subcollections (all within match /spaces/{spaceId})

| Path | Read | Write |
|------|------|-------|
| `/rooms/{roomId}` | isSpaceMember | false |
| `/rooms/{roomId}/messages/{messageId}` | isSpaceMember | CREATE by active member (field-restricted); update/delete = false |
| `/events/{eventId}` | isSpaceMember | false |
| `/events/{eventId}/rsvps/{uid}` | isSpaceMember | Owner create/update/delete (field-restricted) |
| `/presence/{uid}` | isSpaceMember | Owner create/update (field-restricted); delete by owner |
| `/roles/{roleId}` | Own doc or isSpaceAdmin | false |
| `/intelligence/{docId}` | isSpaceMember | false |
| `/safetyEvents/{eventId}` | isSpaceModerator or isAdmin | false |
| `/relationshipGraph/{edgeId}` | false (never client-readable) | false |
| `/banners/{bannerId}` | isSpaceMember | false |
| `/knowledgeNodes/{nodeId}` | isSpaceMember | false |
| `/theologyDoc/{docId}` | isSpaceMember | false |

### New User Subcollections

| Path | Read | Write |
|------|------|-------|
| `/users/{uid}/spacePreferences/{spaceId}` | isOwner | Owner (field-restricted) |
| `/users/{uid}/privateInsights/{insightId}` | isOwner | false (server-only) |

### Security Fix Applied

- `match /spaces/{docId}` at legacy block: tightened from `isSignedIn()` → `isSpaceMember(docId)`
- `match /spaceMemberships/{docId}`: read restricted to owner's own membership docs

---

## 6. Cloud Function Callable Contracts

All defined in `SpacesCallable` enum in `SpacesCore.swift`. Backend (Agent 3) must implement these. Client agents call them via `Functions.functions().httpsCallable(SpacesCallable.xyz.rawValue)`.

| Callable | Caller Permission | Action |
|----------|------------------|--------|
| `createSpace` | Any auth user | Creates AmenSpaceV2, generates memoryNamespace, auto-joins creator as owner |
| `joinSpace` | Any auth user | Joins or requests to join; enforces visibility rules |
| `leaveSpace` | Active member | Soft-removes membership |
| `updateSpaceSettings` | Admin/owner | Updates name, description, visibility |
| `generateSpaceDNA` | Admin/owner | AI generates DNA from description |
| `updateSpaceDNA` | Admin/owner | Applies updated DNA |
| `updateSpaceCovenant` | Admin/owner | Updates values, prohibitedTopics, moderationLevel |
| `postToRoom` | Active member | GUARDIAN-routed message create; sets guardianStatus, embeds |
| `deleteRoomPost` | Post author or moderator | Soft-deletes; sets deletedAt |
| `createRoom` | Admin/owner | Creates AmenRoom |
| `archiveRoom` | Admin/owner | Sets isArchived = true |
| `updateMemberRole` | Admin/owner | Role assignment with audit log |
| `updateScopedProfile` | Any member (own) | Updates AmenScopedProfile for self |
| `updatePresence` | Any member (own) | Presence state update with TTL |
| `bereanSpaceInvoke` | Any member | Invokes Berean; writes response server-side through GUARDIAN |
| `dissolveEphemeralRoom` | Admin/owner or server | Summarizes → writes Living Memory node → archives room |
| `bereanSpaceCitedRecall` | Any member | Cited memory search; returns grounded citations |

---

## 7. Per-Space Memory Namespace Contract

- Each Space gets an isolated Pinecone namespace: format `space_{spaceId}` (server-assigned in `createSpace` callable).
- `AmenSpaceV2.memoryNamespace` holds this value. Nil means the Space predates namespace seeding.
- All embedding reads/writes go through `SemanticEmbeddingService` callables.
- Client code NEVER calls Pinecone directly.
- Cross-Space namespace access is impossible — callables enforce `spaceId` scope.

---

## 8. Existing Systems — Do Not Break

| System | File | Agent constraint |
|--------|------|-----------------|
| Church Notes editor | `ChurchNotes/Editor/RichChurchNoteEditor.swift` | Agent C may extend, never replace |
| Berean modes | `BereanModeEngine.swift` | Agent B uses existing lenses; do not add new lenses |
| GUARDIAN | `ContentModerationService.swift` | Agent G extends with Space covenant params; does not replace |
| Find a Church | `FindChurchView.swift` | Agent D extends; does not replace Church model |
| AMENFeatureFlags | `AMENFeatureFlags.swift` | Do not modify; use SpacesFeatureFlags instead |
| Existing Spaces rules at line 621 | `firestore.rules` | Phase 0 extended them; do not weaken membership gate |

---

## 9. Integration Checkpoints

Phase 1 agents integrate in this order:

1. **Agent A** (Space DNA) + **Agent B** (Berean Member) + **Agent F** (Rhythm/Attention) — integrate first. These are the load-bearing agents.
2. Smoke test: Space creation → DNA generation → Berean @mention → rhythm-aware presence.
3. **Agent C** (Church Notes OS) + **Agent D** (Find a Church) + **Agent E** (Social Fabric) + **Agent G** (Trust/Economy) — integrate after spine passes.

**Security gate before every merge:**
- No client-side trust writes
- ScopedIdentity enforced (no raw `/users/{uid}` cross-space reads)
- GUARDIAN on all new UGC paths
- No secrets in client code
- No weakened Firestore rules

**Cohesion gate before every merge:**
- New screens use `AmenGlassSurface` or `AmenLiquidGlassComponents`
- New screens check `SpacesFeatureFlags.shared` before rendering
- All AI calls go through `BereanCoreService` or `BereanSpaceMemberService`
