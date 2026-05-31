# SPACES_CONNECT_V1 — Changelog

## Phase −1 — Contracts frozen (2026-05-31)

- **PeopleGraphContract.swift** — edges, privacy model
  - `EdgeType` (11 cases: org, space, family, mentor, mentee, serves, prayedFor, authoredNote, attendedEvent, hasSkill, milestone)
  - `EdgePrivacy` (private | org | space | public, default private)
  - `PeopleGraphEdge` Firestore model at `/users/{uid}/graph/edges/{edgeId}`
  - `PeopleGraphServiceProtocol` (fetchEdges, upsertEdge, deleteEdge, fetchInboundEdges)

- **OrgSpaceHierarchyContract.swift** — org/space/group hierarchy, orgType enum
  - `OrgType` (8 cases: church, business, school, family, ministry, nonprofit, sports, network)
  - `OrgSpaceKind` (Group | Team | Department | Ministry | Project | Event)
  - `SpaceRole` (owner | admin | moderator | member | guest)
  - `OrgDocument`, `OrgSpace`, `OrgSpaceMembership` Firestore models
  - `OrgHierarchyServiceProtocol`

- **SelectionIntentContract.swift** — highlight→Ask payload, action resolution
  - `BereanMode` (ask | discern | build | guard | reflect) — 2I routing mode, DISTINCT from `BereanPersonalityMode`
  - `HumanRouteAction` (askChurch | askTeam | askTeacher | askFamily | askLeader | askCoach)
  - `SelectionSource` (sermonNote | message | sop | testimony | lesson | general)
  - `SelectionIntent` struct with all required fields
  - `orgActionMap()` pure-function OrgType→HumanRouteAction resolver
  - `SelectionIntentServiceProtocol`

- **KnowledgeContract.swift** — KnowledgeUnit, Pinecone namespace model
  - `KnowledgeUnit` at `/orgs/{orgId}/spaces/{spaceId}/knowledge/{unitId}`
  - `KnowledgeSource` (SermonNote | SOP | Testimony | Lesson | Meeting)
  - `EmbeddingStatus` (pending | indexed | failed) — CF-managed lifecycle
  - Pinecone namespace convention: `"{orgId}_{spaceId}"` — one per Space
  - `KnowledgeRef`, `KnowledgeQuery`, `KnowledgeSearchResult`
  - `KnowledgeServiceProtocol` (all Pinecone calls server-side only)

**Gate −1:** types compile, schemas documented, naming conflicts documented.

**Next:** Phase 0 — Spaces hierarchy + membership (blocked on human approval).
