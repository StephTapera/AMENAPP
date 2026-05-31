# SPACES_CONNECT_V1 — Gate −1 Summary
**Phase −1 complete. Date: 2026-05-31.**

---

## 1. What Already Exists in the Codebase

### Spaces module (most relevant)
**`AMENAPP/AMENAPP/Spaces/SpacesModels.swift`**
Complete, production-ready Spaces data layer. Defines:
- `SpacesCommunity` (name, handle, avatarURL, ownerUserId, stripeConnectAccountId)
- `CommunityMember`, `CommunityRole` (owner | admin | member)
- `CommunityLink` (pending | active | revoked cross-community sharing)
- `AmenSpace` (type: chat | bibleStudy | group | announcement; accessPolicy: free | oneTime | recurring)
- `SpaceMemberRole` (owner | admin | member)
- `SpaceAccess` (granted | none)
- `SpaceThread`, `SpaceMessage`, `SpaceMessageAttachment`
- `SpaceStudy`, `StudyBlock` (reuses Church Notes block model)
- `SpaceEntitlement` (flat top-level collection: active | grace | expired)

**`AMENAPP/AMENAPP/Spaces/ChatCore/`** — SpacesChatCoreModels, SpacesChatView, SpacesChatViewModel, SpacesFilterService, SpacesTypingService

**`AMENAPP/AMENAPP/Spaces/Wizard/`** — SpaceCreationWizard, WizardIntentStep, WizardScaffoldStep, WizardAccessStep, WizardConfirmStep

**`AMENAPP/AMENAPP/Spaces/Monetization/`** — SpacesEntitlementService, SpaceEntitlementViewModel, SpaceLockedView, SpaceRevenueCard, CommunityStripeOnboardingView

The existing Spaces system maps to a `communities/amenCommunities` top-level collection (NOT the legacy `/communities` ark). The schema authority is `spaces-spec/00_MASTER_CONTRACT.md`.

---

### OrgWorkspace module
**`AMENAPP/AMENAPP/OrgWorkspace/AmenOrgOnboardingFlow.swift`**
Defines `OrgSpaceType` enum (church | school | ministry | smallGroup | enterprise) — **UI-only, NOT Firestore**. Drives the 5-step org creation wizard. Contains `OrgPlan` (free | ministry | enterprise). No backing Firestore model.

**`AMENAPP/AMENAPP/OrgWorkspace/AmenOrgWorkspaceHomeView.swift`** — workspace home shell

**`AMENAPP/AMENAPP/OrgWorkspace/AmenYouPanelView.swift`** — user panel within workspace

---

### Organization/org type definitions (multiple, fragmented)
Three separate "org type" enums exist in the codebase — none are the Firestore authority:

1. **`OrgSpaceType`** in `OrgWorkspace/AmenOrgOnboardingFlow.swift`
   Cases: church, school, ministry, smallGroup, enterprise
   Purpose: onboarding wizard UI only

2. **`OrganizationType`** in `ContextualExperiences/Models/ContextualExperienceModels.swift`
   Cases: church, school, university, ministry, business, enterprise, nonprofit, prayerGroup, creatorCommunity, campus
   Purpose: contextual experiences feature

3. **`ConversationOSOrgType`** in `AMENAPP/ConversationOS/AmenConversationOSModels.swift`
   Cases: church, school, business, enterprise, ministry, creatorCommunity, prayerGroup, studyGroup, leadershipTeam, event, operationalTeam
   Purpose: ConversationOS AI feature

None of these is the canonical SpacesConnect org type. **`OrgType`** (defined in OrgSpaceHierarchyContract.swift) is the new Firestore-authoritative type.

---

### SocialGraph module
**`AMENAPP/AMENAPP/SocialGraph/Services/SocialGraphService.swift`**
Reads from the flat `follows` collection (followerId/followingId). Implements followers, following, mutuals. No edge-type model, no privacy model — purely binary follow/unfollow.

**`AMENAPP/AMENAPP/SocialGraph/Models/SmartActivityModels.swift`**
`UserActivitySummary` and `RelationshipActivityState` — precomputed activity aggregations for follower list display. No graph edge model.

No existing `PeopleGraph`, `GraphEdge`, or typed relationship edge type found anywhere in the codebase. **PeopleGraphContract.swift** introduces this concept from scratch.

---

### Knowledge / sermon notes
**`AMENAPP/AMENAPP/ChurchNotes/Models/ChurchNoteSemanticModels.swift`**
`ChurchNoteV2` + `ChurchNoteBlockV2` — personal, per-user sermon notes with rich semantic blocks. Private to one user. NOT indexed to Pinecone.

**`AMENAPP/AMENAPP/Spaces/SpacesModels.swift`** — `SpaceStudy` + `StudyBlock`
Study curriculum blocks inside a Space. Structural, not independently indexable.

No `KnowledgeUnit`, no Pinecone namespace model, no `EmbeddingStatus` exists anywhere. **KnowledgeContract.swift** introduces this concept from scratch.

---

### Berean AI modes
**`AMENAPP/BereanAIAssistantView.swift`** defines `BereanPersonalityMode`:
Cases: shepherd, scholar, coach, builder, strategist, creator, debater, askBerean, scriptureStudy, prayerCompanion, deepStudy, discernment, mediaInsight, workLifeWisdom, safetyReview

This is a conversational persona type. **`BereanMode`** in SelectionIntentContract.swift is a **distinct and separate** 2I routing mode (ask | discern | build | guard | reflect). These must never be conflated.

---

### Selection / highlight primitives
No `SelectionIntent`, `TextSelection`, or `highlight→Ask` payload type found anywhere in the codebase. **SelectionIntentContract.swift** introduces this concept entirely from scratch.

---

### Phase 0 contracts (frozen predecessor)
**`AMENAPP/AMENAPP/MasterRunContracts/Phase0Contracts.swift`**
Covers ChurchRecord (Find a Church), PostProvenance (feed provenance), SelahStory (multimedia stories), LiturgicalSeasonKind. None of these overlap with the four SpacesConnect contracts.

---

## 2. What the Four Contracts Define

| Contract | New Types | Key Purpose |
|---|---|---|
| PeopleGraphContract | EdgeType, EdgePrivacy, PeopleGraphEdge, PeopleGraphEdgePage, PeopleGraphFilter, PeopleGraphServiceProtocol | Typed, private-by-default relationship edges beyond binary follow |
| OrgSpaceHierarchyContract | OrgType, OrgSpaceKind, SpaceVisibility, SpaceRole, OrgDocument, OrgSpace, OrgSpaceMembership, OrgHierarchyServiceProtocol | Firestore-authoritative org + org space management layer |
| SelectionIntentContract | BereanMode, HumanRouteAction, SelectionSource, AlwaysPresentAction, SelectionIntent, SelectionIntentMenuActions, orgActionMap(), SelectionIntentServiceProtocol | Highlight→Ask payload + action resolution for every text selection in the app |
| KnowledgeContract | KnowledgeSource, EmbeddingStatus, KnowledgeRefType, KnowledgeRef, KnowledgeUnit, KnowledgeUnitVersion, KnowledgeQuery, KnowledgeSearchResult, KnowledgeServiceProtocol | Org-level indexable knowledge artifacts + Pinecone namespace model |

---

## 3. Conflicts and Tensions

### Naming conflicts (documented in each contract, no blocking issues)

**OrgType vs OrganizationType (HIGH PRIORITY)**
`OrganizationType` in `ContextualExperiences/Models/ContextualExperienceModels.swift` and `ConversationOSOrgType` in `ConversationOS/AmenConversationOSModels.swift` have overlapping but non-identical case sets. SpacesConnect agents MUST use `OrgType` from OrgSpaceHierarchyContract. The onboarding wizard (`OrgSpaceType`) must be updated to map to `OrgType` when writing to Firestore.

**SpaceRole vs SpaceMemberRole**
`SpaceMemberRole` (owner | admin | member) exists in `Spaces/SpacesModels.swift`.
`SpaceRole` (this contract) adds moderator and guest. They are for different collections: `SpaceMemberRole` governs `spaces/{spaceId}/members` in the Slack-like Spaces module; `SpaceRole` governs `/orgs/{orgId}/spaces/{spaceId}/members` in the org hierarchy layer.

**BereanMode vs BereanPersonalityMode (CRITICAL)**
`BereanPersonalityMode` (15 cases) in `AMENAPP/BereanAIAssistantView.swift` is a conversational persona.
`BereanMode` (5 cases) in SelectionIntentContract is a 2I inference routing mode.
These must never be merged or conflated. Any agent that imports both must use fully qualified names in comments.

**AmenSpace (Spaces module) vs OrgSpace (this contract)**
`AmenSpace` in `Spaces/SpacesModels.swift` is the Slack-like room with chat/study/group render modes.
`OrgSpace` in OrgSpaceHierarchyContract is the org management layer Space (team/department/ministry).
They are intentionally separate. Linking them is done via `settings["amenSpaceId"]` on OrgSpace.

### Schema tensions (require Steph decision — see Section 5)

**Community vs Org naming**
`spaces-spec/00_MASTER_CONTRACT.md` calls the top billing unit a "Community" (collection: `amenCommunities`). SpacesConnect contracts call the org-management unit an "Org" (collection: `/orgs`). These may need to be unified or explicitly separated as two distinct concepts in the product. See Decision #1 below.

**Knowledge path nesting depth**
`/orgs/{orgId}/spaces/{spaceId}/knowledge/{unitId}` is 4 levels deep. Firestore security rules require a `get()` on the parent org and space for every knowledge read, which increases rule complexity. An alternative flat `knowledge/{unitId}` collection with `orgId`/`spaceId` fields may be preferable for rules performance.

---

## 4. Agents That Can Unblock Now

| Agent | Unblocked by | What they can start |
|---|---|---|
| **Spaces Agent** | OrgSpaceHierarchyContract | OrgDocument/OrgSpace CRUD, Firestore schema creation, rules for `/orgs` collection |
| **Connect Agent** | PeopleGraphContract | PeopleGraphEdge CRUD service, reverse-lookup indexes, privacy filter logic |
| **Selection Agent** | SelectionIntentContract | SelectionIntentMenu view, orgActionMap wiring, 2I callable stub |
| **Knowledge Agent** | KnowledgeContract + OrgSpaceHierarchyContract | KnowledgeUnit CRUD, Algolia index setup, Pinecone namespace provisioning CF |
| **Berean AI Agent** | SelectionIntentContract (BereanMode enum) | 2I routing Cloud Function, resolveMode server implementation |
| **Firestore Rules Agent** | All four contracts | Rules for `/orgs`, `/users/{uid}/graph`, and knowledge subcollection |
| **A9 Feature Flags Agent** | OrgSpaceHierarchyContract | New feature flags: `spacesConnectOrg`, `peopleGraph`, `selectionIntent`, `knowledgeIndex` |

---

## 5. Outstanding Decisions Needed from Steph Before Phase 0

**Decision 1 (BLOCKING for data model):**
Should the product have two separate top-level concepts — **Community** (social/billing, from spaces-spec) and **Org** (management/knowledge, from these contracts) — or should they be unified into one collection? Currently `SpacesCommunity` lives in `amenCommunities/{communityId}` and `OrgDocument` is proposed at `/orgs/{orgId}`. If unified, the `SpacesCommunity` model needs org fields added; if separate, the relationship between them must be defined (1:1? 1:many?).

**Decision 2 (BLOCKING for Firestore rules):**
Knowledge collection path: nested `/orgs/{orgId}/spaces/{spaceId}/knowledge/{unitId}` (current contract) vs. flat `/knowledge/{unitId}` with denormalized `orgId`/`spaceId` fields. Flat is simpler for security rules; nested is cleaner for subcollection listeners.

**Decision 3 (UX — SelectionIntent):**
Should `saveToNotes` in SelectionIntentMenuActions save to Church Notes (ChurchNoteV2) or to a new KnowledgeUnit, or let the user choose? This drives which service the Selection Agent calls.

**Decision 4 (Privacy — PeopleGraph):**
Should PeopleGraph edges be visible to users being pointed-to (i.e., can I see who has a "prayedFor" edge pointing at me)? The reverse-lookup in `fetchInboundEdges` exists in the protocol but privacy semantics of inbound reads need product sign-off.

**Decision 5 (AI consent — SelectionIntent logging):**
The `selectionIntentLog` path is opt-in per `analyticsConsent`. Confirm this maps to an existing privacy preference key in the app's `CalmControl` / privacy settings, or a new one needs to be added.
