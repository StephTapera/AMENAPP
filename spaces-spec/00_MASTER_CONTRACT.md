# AMEN Spaces — Master Contract (READ FIRST)

**Every agent reads this file before writing a line of code.** It is the single source of
truth for the data model, naming, design tokens, and the hard boundaries between agents.
If your task seems to contradict this file, STOP and flag it — do not improvise a second
schema.

---

## 0. What we are building

AMEN Spaces is the hub layer of AMEN: an accumulation of Slack (channels, threads, DMs,
external collaboration), Outlook/Teams (organization + collaboration), and Patreon
(creator monetization) — rendered in AMEN's **Liquid Glass** design language and made
**smarter** with Berean AI scaffolding.

The product is **faith-oriented but NOT church-specific**. The collaborating unit is a
generic **Community**: it can be a church, a Bible study, a family, a small group, a
ministry, or one person. No data field, enum, string, or UI label may hardcode "church."
Use **Community** everywhere.

---

## 1. Core hierarchy

```
Community  ─┬─ owns branding, member roster, billing identity (Stripe Connect account)
            │
            └─ Space ─┬─ a room inside a community; carries a TYPE
                      │   type ∈ { chat, bibleStudy, group, announcement }
                      │   type drives render mode (protocol-driven, like Smart Church Notes)
                      │   access gate lives HERE (per-Space, whole-Space entitlement)
                      │
                      ├─ Thread   (for chat/group types)  → messages
                      └─ Study    (for bibleStudy type)   → blocks (reuse SCN block editor)
```

- **Community** = Slack workspace + Patreon creator page.
- **Space** = Slack channel, but typed. Render mode is selected by `type`.
- **Thread/Study** = the conversation/content unit inside a Space.

---

## 2. Firestore schema (authoritative)

Reuse existing AMEN conventions (Firestore primary, RTDB for presence, Cloud Functions,
Storage, Auth). Backend AI calls route through Firebase callable proxies. Vector search =
Pinecone, text search = Algolia.

```
communities/{communityId}
  name, handle, avatarURL, ownerUserId, stripeConnectAccountId, createdAt
  members/{userId}        → role: owner|admin|member, joinedAt
  links/{linkId}          → otherCommunityId, status: pending|active|revoked, scope, createdBy

spaces/{spaceId}
  communityId             → parent community (denormalized)
  type                    → chat | bibleStudy | group | announcement
  title, description, avatarURL, createdBy, createdAt
  accessPolicy            → free | oneTime | recurring
  priceConfig             → { amountCents, currency, interval? }   (null when free)
  sharedWith: [communityId]   // denormalized for fast badge/banner render
  members/{userId}        → role, homeCommunityId, access: granted|none, joinedAt
  threads/{threadId}
    title, createdBy, createdAt, lastMessageAt
    messages/{messageId}  → authorId, body, createdAt, editedAt, reactions{}, attachments[], status
  studies/{studyId}
    title, passageRefs[], cadence, createdBy, createdAt
    blocks/{blockId}      → reuse Smart Church Notes block model + render modes

entitlements/{userId}_{spaceId}   // FLAT, top-level — the paywall source of truth
  userId, spaceId, status: active|grace|expired, source: purchase|grant,
  stripeSubId?, expiresAt (null = lifetime), updatedAt
```

### Why entitlements is a flat top-level collection
Security rules must gate every message/study read with **one `get()`**, never a tree walk.
`get(/databases/$(db)/documents/entitlements/$(uid + "_" + spaceId))` → check status.
Do not nest entitlements under spaces; do not require a join.

---

## 3. Hard boundaries (do not cross)

1. **Money does not cross a community Link (v1).** A shared Space's revenue is collected
   ONLY by the owning community's Stripe Connect account. The other community gets
   *access and conversation*, not revenue. Multi-party Connect transfers / tax splitting
   are explicitly OUT OF SCOPE for v1.
2. **Never hard-delete data a view may be rendering.** Lapsed subscription → flip
   `entitlement.status`, drop the Space to locked-preview. Revoked link → mark
   `status: revoked`, keep the row. Hard deletes mid-render are the source of the known
   EXC_BAD_ACCESS / CALayerGetSuperlayer crashes.
3. **Entitlement is Space-scoped, never artifact-scoped (v1).** Buying a study grants the
   whole Space (chat + study + future content). One `{user, space}` row.
4. **No "church" anywhere.** Generic Community language only.
5. **Cross-community is create-first / link-second (v1).** Simultaneous co-creation is a
   fast-follow, not v1. The creation wizard does NOT have a "co-create with another
   community" step yet.
6. **One shared style file.** Design tokens live in a single source. Only the design pass
   edits it. No agent redefines colors or materials locally.

---

## 4. Design language: Liquid Glass

- Materials: `ultraThinMaterial`, glassmorphic cards, soft inner highlights.
- Motion: spring animations on present/dismiss and card insertion.
- Palette: white/black primary + tokens `amenGold`, `amenPurple`, `amenBlue`, `amenBlack`.
- Components are simple and smart: minimum chrome, AI assist where it removes a step.
- **Hero profile header** style is reused for: Space detail header, the creation wizard
  confirm step, and the shared-community banner card.

### The "evident" cross-community signal (generic, faith-neutral)
- **Linked glyph**: small interlocking-rings / chain mark in `amenPurple` over
  `ultraThinMaterial`, placed on shared Spaces and on external members' avatars. Tappable.
  (This is AMEN's equivalent of Slack's rotated-arrow external badge.)
- **Banner pill**: glass pill at top of a shared Space and in the composer —
  *"This study is shared with [Community B]"* / *"3 members are from the Henderson Family."*
  Uses the hero-profile header style.
- **Roster sectioning**: in the member sheet, external members are grouped UNDER their
  home community, never blended. Drives off `member.homeCommunityId` (one field, no join).

---

## 5. The smart Liquid Glass creation wizard (the differentiator)

Entry: `+ → Start something`. Glass-card flow, spring-in:

1. **Intent** — "What are you starting?" → Discussion / Study / Group. (No co-create step in v1.)
2. **Smart scaffold** — Berean reads intent + title and proposes structure. e.g. *Study of
   Romans* → suggested passage range, a multi-week cadence, discussion prompts. This is the
   step nobody else has — AI-scaffolded community creation.
3. **Access & pricing** — free / one-time / recurring. Glass segmented control + live
   "you'll receive ~$X after fees" using the EXISTING Stripe fee math.
4. **Confirm** — single glass sheet, hero-profile-style header showing the creator.

---

## 6. Agent map & dependency order

| Agent | Owns (disjoint files) | Depends on |
|---|---|---|
| **A — Data/Rules** | Firestore schema, security rules, entitlements, access-grant Cloud Functions, Stripe webhook → entitlement status | nothing — **merges first** |
| **B — Chat Core** | Message/thread models, SSE streaming reuse, reactions, @MainActor-safe view models | A |
| **C — Spaces Shell + Shared Components** | Community/Space navigation, list + tabs (All/VIP/Unreads/External), Space detail, **the linked-glyph + banner + roster components** | A, B |
| **D — Creation Wizard** | Smart Liquid Glass start flow + Berean scaffolding callable | A; consumes B/C contracts |
| **E — Monetization** | Stripe Connect per-Space, entitlement purchase, paywall/locked-preview UI | A (entitlements) |
| **F — Cross-Community Links** | Link create/accept/revoke flow, `sharedWith` maintenance, attach UX | A, C |

### Coordination rules (these prevent the merge/crash chaos)
- **A merges to main before B–F begin wiring.** B–F build against A's committed schema,
  never against each other's in-flight code.
- Each agent edits a **disjoint file set**. If two agents need the same file, that file
  belongs to the shared style/contract layer and neither edits it ad hoc — raise it.
- Shared design components (glyph, banner, roster) are **Agent C's** so they stay
  consistent everywhere; B/D/E/F import them, never re-implement.
- Every agent ends its task with: (1) what it changed, (2) the public contract it exposes
  for downstream agents, (3) any assumption it had to make.

---

## 7. Definition of done (applies to every agent)

- Builds clean in `AMENAPP.xcworkspace`, no new warnings.
- No `@MainActor` violations; all UI mutation on main.
- No hard-deletes of in-render data (see boundary #2).
- Security-rule changes covered by a rules test where applicable.
- New surfaces use only shared design tokens — no local color/material literals.
- Reuses existing infra (Firebase callables for AI, Stripe fee math, SCN block model,
  Berean SSE) rather than re-building it.

---

## 8. v1 scope vs. fast-follow

**In v1:**
- Community → Space → Thread/Study hierarchy
- Chat core (messages, threads, reactions, DMs)
- The smart Liquid Glass creation wizard with Berean scaffolding
- Per-Space monetization (free / one-time / recurring via Stripe Connect)
- Generic cross-community linking with the evident signal (glyph + banner + roster)

**Fast-follow (explicitly NOT v1):**
- Simultaneous co-creation of a shared Space
- Revenue-sharing across linked communities (multi-party Connect + tax)
- Artifact-scoped entitlements
- Co-creation wizard step
