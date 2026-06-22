# C5 — Security Rules & RBAC Contract

**Contract ID:** C5  
**Phase:** 0 (Stubs & Contracts — no production logic)  
**Owner:** Trust & Safety Lead (ONE OWNER — no other party may unilaterally edit this document)  
**Status:** FROZEN FOR PHASE 0  
**Last updated:** 2026-06-05  
**Review gate:** Phase 4 implementation must match every cell in this matrix exactly  
**Change process:** Any edit requires written sign-off from the T&S Lead AND a pull-request review  

---

## 0. Ownership Notice

This contract has **exactly one owner** across the entire program: the **Trust & Safety Lead**.

- Product managers may request changes via the T&S Lead.
- Engineers implementing Phase 4 rules must open a PR that references this document.
- No cell in this matrix may be changed without a signed Decision Register entry below.
- If the T&S Lead is unavailable, the Head of Engineering acts as temporary owner with written notice.

---

## 1. Role Definitions

| Role | Description | Firestore `role` field value |
|------|-------------|------------------------------|
| **Owner** | Organization founder / account owner (church or space creator) | `owner` |
| **ExecutiveAdmin** | Platform-level admin with cross-org access — Amen staff only | `executive_admin` |
| **Pastor** | Ordained ministry lead inside a church org | `pastor` |
| **Leader** | Ministry team leader / small group leader inside a church or space | `leader` |
| **Moderator** | Content and comment moderator — can action moderation queue but not manage org settings | `moderator` |
| **VolunteerLead** | Coordinates volunteer opportunities; no moderation power | `volunteer_lead` |
| **ContentManager** | Manages media, sermons, Church Notes; no member management | `content_manager` |
| **EventManager** | Creates and edits events only | `event_manager` |
| **Member** | Verified, age-compliant member of a church or space | `member` |
| **Visitor** | Authenticated user with no org membership | `visitor` |
| **Minor** | Authenticated user whose `ageTier` is `teen` (13–17) — see Section 4 for restrictions | `minor` |

> **OPEN-1 (T&S Lead must resolve before Phase 4):** The age threshold for `minor` status needs a definitive legal ruling. Current implementation treats 13–17 as `teen` (Minor) and under-13 as `under_minimum` (blocked entirely). Does the app have COPPA obligations in the US context that require treating 13 as the hard floor? Does EU GDPR-K require 16 as the floor for some regions? The rules skeleton uses 13 as the placeholder. T&S Lead must confirm or override.

> **NOTE — `under_minimum` tier:** Users who declare an age below the minimum (under-13 per AppConfig.Legal.minimumAge) are blocked at onboarding and assigned `under_minimum` tier. They are NOT a role in the RBAC matrix; their accounts are suspended pending parental verification or age correction. If they somehow reach a Firestore read, every rule treats them as Visitor with no write access.

---

## 2. Role × Resource × Action Matrix

**Legend:** ✓ Allow | ✗ Deny | C = Conditional (see condition key below table)

### Condition Key

| Code | Condition |
|------|-----------|
| C-OWN | Allowed only if `request.auth.uid == resource.data.authorId` (content owner) |
| C-ORG | Allowed only if actor is a verified member of the same organization as the resource |
| C-CHURCH | Allowed only if actor is a verified member of the same church |
| C-SPACE | Allowed only if actor is a verified member of the same space |
| C-MOD | Allowed for Moderator+ within the same org scope |
| C-AUDIT | Action is allowed but MUST write an audit log entry before returning |
| C-PRIV | Allowed only if resource.privacyLevel == 'public' or actor is explicitly invited |
| C-MINOR-DM | Minors may only exchange DMs with mutual follows who pass the minor-safe contact check |
| C-AGE | Blocked entirely for Minor role |
| C-PAID | Allowed only if actor has an active paid membership in the covenant |

---

### 2a. User Resource

| Role | create (own profile) | read (own) | read (other public) | read (other private) | update (own) | update (other) | delete (own) | delete (other) | view_analytics (own) | view_analytics (other) |
|------|--------------------|------------|---------------------|----------------------|--------------|----------------|--------------|----------------|----------------------|------------------------|
| Owner | ✓ | ✓ | ✓ | C-ORG | ✓ | C-AUDIT | C-AUDIT | ✗ | ✓ | C-ORG |
| ExecutiveAdmin | ✓ | ✓ | ✓ | ✓ | ✓ | C-AUDIT | C-AUDIT | C-AUDIT | ✓ | ✓ |
| Pastor | ✓ | ✓ | ✓ | C-CHURCH | ✓ | ✗ | C-AUDIT | ✗ | ✓ | C-CHURCH |
| Leader | ✓ | ✓ | ✓ | C-SPACE | ✓ | ✗ | C-AUDIT | ✗ | ✓ | C-SPACE |
| Moderator | ✓ | ✓ | ✓ | ✗ | ✓ | ✗ | C-AUDIT | ✗ | ✓ | ✗ |
| VolunteerLead | ✓ | ✓ | ✓ | ✗ | ✓ | ✗ | C-AUDIT | ✗ | ✓ | ✗ |
| ContentManager | ✓ | ✓ | ✓ | ✗ | ✓ | ✗ | C-AUDIT | ✗ | ✓ | ✗ |
| EventManager | ✓ | ✓ | ✓ | ✗ | ✓ | ✗ | C-AUDIT | ✗ | ✓ | ✗ |
| Member | ✓ | ✓ | ✓ | ✗ | ✓ | ✗ | C-AUDIT | ✗ | ✓ | ✗ |
| Visitor | ✓ | ✓ | C-PRIV | ✗ | ✓ | ✗ | C-AUDIT | ✗ | ✓ | ✗ |
| **Minor** | ✓ | ✓ | **C-PRIV (profile defaults private)** | ✗ | ✓ | ✗ | C-AUDIT | ✗ | ✓ | ✗ |

---

### 2b. Post Resource

| Role | create | read (public) | read (private/church/space) | update (own) | update (other) | delete (own) | delete (other) | moderate | escalate | view_analytics |
|------|--------|--------------|----------------------------|--------------|----------------|--------------|----------------|----------|----------|----------------|
| Owner | ✓ | ✓ | C-ORG | ✓ | C-AUDIT | C-AUDIT | C-AUDIT | ✓ | ✓ | ✓ |
| ExecutiveAdmin | ✓ | ✓ | ✓ | ✓ | C-AUDIT | C-AUDIT | C-AUDIT | ✓ | ✓ | ✓ |
| Pastor | ✓ | ✓ | C-CHURCH | ✓ | ✗ | C-AUDIT | C-AUDIT | ✓ | ✓ | ✓ |
| Leader | ✓ | ✓ | C-SPACE | ✓ | ✗ | C-AUDIT | ✗ | C-MOD | ✓ | C-SPACE |
| Moderator | ✓ | ✓ | ✗ | ✓ | ✗ | C-AUDIT | C-AUDIT | ✓ | ✓ | ✗ |
| VolunteerLead | ✓ | ✓ | ✗ | ✓ | ✗ | C-AUDIT | ✗ | ✗ | ✓ | ✗ |
| ContentManager | ✓ | ✓ | C-ORG | ✓ | C-AUDIT | C-AUDIT | ✗ | ✗ | ✓ | C-ORG |
| EventManager | ✓ | ✓ | ✗ | ✓ | ✗ | C-AUDIT | ✗ | ✗ | ✓ | ✗ |
| Member | ✓ | ✓ | C-ORG | ✓ | ✗ | C-AUDIT | ✗ | ✗ | ✓ | ✗ |
| Visitor | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ |
| **Minor** | **C-AGE (defaults private; must confirm before public posting)** | ✓ | C-ORG | ✓ | ✗ | C-AUDIT | ✗ | ✗ | ✗ | ✗ |

---

### 2c. Prayer Resource

| Role | create | read (own) | read (public) | read (church/trusted) | update (own) | delete (own) | moderate | escalate | send_dm |
|------|--------|------------|--------------|----------------------|--------------|--------------|----------|----------|---------|
| Owner | ✓ | ✓ | ✓ | ✓ | ✓ | C-AUDIT | ✓ | ✓ | ✓ |
| ExecutiveAdmin | ✓ | ✓ | ✓ | ✓ | ✓ | C-AUDIT | ✓ | ✓ | ✓ |
| Pastor | ✓ | ✓ | ✓ | C-CHURCH | ✓ | C-AUDIT | ✓ | ✓ | C-CHURCH |
| Leader | ✓ | ✓ | ✓ | C-SPACE | ✓ | C-AUDIT | C-MOD | ✓ | C-SPACE |
| Moderator | ✓ | ✓ | ✓ | ✗ | ✓ | C-AUDIT | ✓ | ✓ | ✗ |
| VolunteerLead | ✓ | ✓ | ✓ | ✗ | ✓ | C-AUDIT | ✗ | ✓ | ✗ |
| ContentManager | ✓ | ✓ | ✓ | ✗ | ✓ | C-AUDIT | ✗ | ✓ | ✗ |
| EventManager | ✓ | ✓ | ✓ | ✗ | ✓ | C-AUDIT | ✗ | ✓ | ✗ |
| Member | ✓ | ✓ | ✓ | C-ORG | ✓ | C-AUDIT | ✗ | ✓ | ✗ |
| Visitor | ✓ | ✓ | C-PRIV | ✗ | ✓ | C-AUDIT | ✗ | ✗ | ✗ |
| **Minor** | ✓ | ✓ | **C-PRIV (prayer defaults private for Minors)** | C-ORG | ✓ | C-AUDIT | ✗ | ✗ | **C-MINOR-DM** |

> Private prayer requests are never visible to any role other than the owner and explicitly invited members. This is a non-negotiable safety invariant.

---

### 2d. Discussion Resource

| Role | create | read (public) | read (space/church) | update (own) | delete (own) | moderate | escalate | view_analytics |
|------|--------|--------------|---------------------|--------------|--------------|----------|----------|----------------|
| Owner | ✓ | ✓ | ✓ | ✓ | C-AUDIT | ✓ | ✓ | ✓ |
| ExecutiveAdmin | ✓ | ✓ | ✓ | ✓ | C-AUDIT | ✓ | ✓ | ✓ |
| Pastor | ✓ | ✓ | C-CHURCH | ✓ | C-AUDIT | ✓ | ✓ | C-CHURCH |
| Leader | ✓ | ✓ | C-SPACE | ✓ | C-AUDIT | C-MOD | ✓ | C-SPACE |
| Moderator | ✓ | ✓ | ✗ | ✓ | C-AUDIT | ✓ | ✓ | ✗ |
| VolunteerLead | ✓ | ✓ | ✗ | ✓ | C-AUDIT | ✗ | ✓ | ✗ |
| ContentManager | ✓ | ✓ | C-ORG | ✓ | C-AUDIT | ✗ | ✓ | C-ORG |
| EventManager | ✓ | ✓ | ✗ | ✓ | C-AUDIT | ✗ | ✓ | ✗ |
| Member | ✓ | ✓ | C-ORG | ✓ | C-AUDIT | ✗ | ✓ | ✗ |
| Visitor | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **Minor** | ✓ | ✓ | C-ORG | ✓ | C-AUDIT | ✗ | ✓ | ✗ |

---

### 2e. Comment Resource

| Role | create | read | update (own) | delete (own) | delete (other) | moderate | escalate |
|------|--------|------|--------------|--------------|----------------|----------|----------|
| Owner | ✓ | ✓ | ✓ | C-AUDIT | C-AUDIT | ✓ | ✓ |
| ExecutiveAdmin | ✓ | ✓ | ✓ | C-AUDIT | C-AUDIT | ✓ | ✓ |
| Pastor | ✓ | ✓ | ✓ | C-AUDIT | C-AUDIT | ✓ | ✓ |
| Leader | ✓ | ✓ | ✓ | C-AUDIT | C-AUDIT (within space) | C-MOD | ✓ |
| Moderator | ✓ | ✓ | ✓ | C-AUDIT | C-AUDIT | ✓ | ✓ |
| VolunteerLead | ✓ | ✓ | ✓ | C-AUDIT | ✗ | ✗ | ✓ |
| ContentManager | ✓ | ✓ | ✓ | C-AUDIT | ✗ | ✗ | ✓ |
| EventManager | ✓ | ✓ | ✓ | C-AUDIT | ✗ | ✗ | ✓ |
| Member | ✓ | ✓ | ✓ | C-AUDIT | ✗ | ✗ | ✓ |
| Visitor | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ |
| **Minor** | ✓ | ✓ | ✓ | C-AUDIT | ✗ | ✗ | ✓ |

---

### 2f. Organization Resource

| Role | create | read | update | delete | view_analytics | moderate | escalate |
|------|--------|------|--------|--------|----------------|----------|----------|
| Owner | ✓ | ✓ | C-AUDIT | C-AUDIT | ✓ | ✓ | ✓ |
| ExecutiveAdmin | ✓ | ✓ | C-AUDIT | C-AUDIT | ✓ | ✓ | ✓ |
| Pastor | ✓ | ✓ | C-AUDIT (same org) | ✗ | ✓ | ✓ | ✓ |
| Leader | ✗ | ✓ | ✗ | ✗ | C-SPACE | ✗ | ✓ |
| Moderator | ✗ | ✓ | ✗ | ✗ | ✗ | C-MOD | ✓ |
| VolunteerLead | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ |
| ContentManager | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ |
| EventManager | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ |
| Member | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ |
| Visitor | ✗ | C-PRIV | ✗ | ✗ | ✗ | ✗ | ✗ |
| **Minor** | ✗ | C-PRIV | ✗ | ✗ | ✗ | ✗ | ✓ |

---

### 2g. Church Resource

| Role | create | read | update | delete | view_analytics | moderate | escalate |
|------|--------|------|--------|--------|----------------|----------|----------|
| Owner | ✓ | ✓ | C-AUDIT | C-AUDIT | ✓ | ✓ | ✓ |
| ExecutiveAdmin | ✓ | ✓ | C-AUDIT | C-AUDIT | ✓ | ✓ | ✓ |
| Pastor | ✓ | ✓ | C-AUDIT (own church) | ✗ | ✓ | ✓ | ✓ |
| Leader | ✗ | ✓ | ✗ | ✗ | C-CHURCH | ✗ | ✓ |
| Moderator | ✗ | ✓ | ✗ | ✗ | ✗ | C-MOD | ✓ |
| VolunteerLead | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ |
| ContentManager | ✗ | ✓ | C-AUDIT (media fields only) | ✗ | ✗ | ✗ | ✓ |
| EventManager | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ |
| Member | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ |
| Visitor | ✗ | C-PRIV | ✗ | ✗ | ✗ | ✗ | ✗ |
| **Minor** | ✗ | C-PRIV | ✗ | ✗ | ✗ | ✗ | ✓ |

---

### 2h. Team Resource

| Role | create | read | update | delete | view_analytics | moderate | escalate |
|------|--------|------|--------|--------|----------------|----------|----------|
| Owner | ✓ | ✓ | C-AUDIT | C-AUDIT | ✓ | ✓ | ✓ |
| ExecutiveAdmin | ✓ | ✓ | C-AUDIT | C-AUDIT | ✓ | ✓ | ✓ |
| Pastor | ✓ | ✓ | C-AUDIT | ✗ | ✓ | ✓ | ✓ |
| Leader | ✓ | ✓ | C-AUDIT (own team) | ✗ | C-SPACE | ✗ | ✓ |
| Moderator | ✗ | ✓ | ✗ | ✗ | ✗ | C-MOD | ✓ |
| VolunteerLead | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ |
| ContentManager | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ |
| EventManager | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ |
| Member | ✗ | C-ORG | ✗ | ✗ | ✗ | ✗ | ✓ |
| Visitor | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **Minor** | ✗ | C-ORG | ✗ | ✗ | ✗ | ✗ | ✓ |

---

### 2i. Space Resource

| Role | create | read | update | delete | view_analytics | moderate | escalate |
|------|--------|------|--------|--------|----------------|----------|----------|
| Owner | ✓ | ✓ | C-AUDIT | C-AUDIT | ✓ | ✓ | ✓ |
| ExecutiveAdmin | ✓ | ✓ | C-AUDIT | C-AUDIT | ✓ | ✓ | ✓ |
| Pastor | ✓ | ✓ | C-AUDIT (own church space) | ✗ | ✓ | ✓ | ✓ |
| Leader | ✓ | ✓ | C-AUDIT (spaces they lead) | ✗ | C-SPACE | C-MOD | ✓ |
| Moderator | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✓ |
| VolunteerLead | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ |
| ContentManager | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ |
| EventManager | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ |
| Member | ✗ | C-PRIV | ✗ | ✗ | ✗ | ✗ | ✓ |
| Visitor | ✗ | C-PRIV | ✗ | ✗ | ✗ | ✗ | ✗ |
| **Minor** | ✗ | **C-PRIV (Minors can only join age-appropriate, church-verified spaces)** | ✗ | ✗ | ✗ | ✗ | ✓ |

---

### 2j. Event Resource

| Role | create | read | update | delete | view_analytics | moderate | escalate |
|------|--------|------|--------|--------|----------------|----------|----------|
| Owner | ✓ | ✓ | C-AUDIT | C-AUDIT | ✓ | ✓ | ✓ |
| ExecutiveAdmin | ✓ | ✓ | C-AUDIT | C-AUDIT | ✓ | ✓ | ✓ |
| Pastor | ✓ | ✓ | C-AUDIT | ✗ | ✓ | ✓ | ✓ |
| Leader | ✓ | ✓ | C-AUDIT (own events) | ✗ | C-SPACE | ✗ | ✓ |
| Moderator | ✗ | ✓ | ✗ | ✗ | ✗ | C-MOD | ✓ |
| VolunteerLead | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ |
| ContentManager | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ |
| EventManager | ✓ | ✓ | C-AUDIT | C-AUDIT | ✓ | ✗ | ✓ |
| Member | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ |
| Visitor | ✗ | C-PRIV | ✗ | ✗ | ✗ | ✗ | ✗ |
| **Minor** | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ |

---

### 2k. VolunteerOpportunity Resource

| Role | create | read | update | delete | moderate | escalate |
|------|--------|------|--------|--------|----------|----------|
| Owner | ✓ | ✓ | C-AUDIT | C-AUDIT | ✓ | ✓ |
| ExecutiveAdmin | ✓ | ✓ | C-AUDIT | C-AUDIT | ✓ | ✓ |
| Pastor | ✓ | ✓ | C-AUDIT | ✗ | ✓ | ✓ |
| Leader | ✓ | ✓ | C-AUDIT (own listings) | ✗ | ✗ | ✓ |
| Moderator | ✗ | ✓ | ✗ | ✗ | C-MOD | ✓ |
| VolunteerLead | ✓ | ✓ | C-AUDIT | C-AUDIT | ✗ | ✓ |
| ContentManager | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ |
| EventManager | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ |
| Member | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ |
| Visitor | ✗ | C-PRIV | ✗ | ✗ | ✗ | ✗ |
| **Minor** | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ |

> **Invariant — no raw PII in listings:** VolunteerOpportunity documents must NEVER expose coordinator phone numbers, home addresses, or financial compensation details. Contact is mediated through the in-app channel only. This is enforced by the ContentPermissionEngine `safetyVeto`.

---

### 2l. Job Resource

| Role | create | read | update | delete | moderate | escalate |
|------|--------|------|--------|--------|----------|----------|
| Owner | ✓ | ✓ | C-AUDIT | C-AUDIT | ✓ | ✓ |
| ExecutiveAdmin | ✓ | ✓ | C-AUDIT | C-AUDIT | ✓ | ✓ |
| Pastor | ✓ | ✓ | C-AUDIT | ✗ | ✓ | ✓ |
| Leader | ✓ | ✓ | C-AUDIT (own listings) | ✗ | ✗ | ✓ |
| Moderator | ✗ | ✓ | ✗ | ✗ | C-MOD | ✓ |
| VolunteerLead | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ |
| ContentManager | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ |
| EventManager | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ |
| Member | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ |
| Visitor | ✗ | C-PRIV | ✗ | ✗ | ✗ | ✗ |
| **Minor** | **✗ (blocked — no employment listings for minors)** | **C-AGE (minors cannot read job listings — employment context requires adult status)** | ✗ | ✗ | ✗ | ✗ |

---

### 2m. MentorshipRequest Resource

| Role | create | read (own) | read (other) | update | delete | moderate | escalate | send_dm |
|------|--------|------------|-------------|--------|--------|----------|----------|---------|
| Owner | ✓ | ✓ | ✓ | C-AUDIT | C-AUDIT | ✓ | ✓ | ✓ |
| ExecutiveAdmin | ✓ | ✓ | ✓ | C-AUDIT | C-AUDIT | ✓ | ✓ | ✓ |
| Pastor | ✓ | ✓ | C-CHURCH | C-AUDIT | ✗ | ✓ | ✓ | C-CHURCH |
| Leader | ✓ | ✓ | C-SPACE | C-AUDIT | ✗ | ✗ | ✓ | C-SPACE |
| Moderator | ✗ | ✓ | ✗ | ✗ | ✗ | C-MOD | ✓ | ✗ |
| VolunteerLead | ✓ | ✓ | ✗ | C-AUDIT (own) | C-AUDIT (own) | ✗ | ✓ | ✗ |
| ContentManager | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ |
| EventManager | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ |
| Member | ✓ | ✓ | ✗ | C-AUDIT (own) | C-AUDIT (own) | ✗ | ✓ | ✗ |
| Visitor | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **Minor** | **✓ (minors may request mentorship — see DM restrictions in §4)** | ✓ | ✗ | C-AUDIT (own) | C-AUDIT (own) | ✗ | ✓ | **C-MINOR-DM** |

---

### 2n. Edge (Social Graph) Resource

| Role | create | read (own) | read (other's edges) | delete | moderate | escalate |
|------|--------|------------|---------------------|--------|----------|----------|
| Owner | ✓ | ✓ | C-AUDIT | C-AUDIT | ✓ | ✓ |
| ExecutiveAdmin | ✓ | ✓ | C-AUDIT | C-AUDIT | ✓ | ✓ |
| Pastor | ✓ | ✓ | C-CHURCH | ✗ | ✓ | ✓ |
| Leader | ✓ | ✓ | C-SPACE | ✗ | ✗ | ✓ |
| Moderator | ✓ | ✓ | ✗ | C-AUDIT (block edges) | C-MOD | ✓ |
| VolunteerLead | ✓ | ✓ | ✗ | C-AUDIT (own) | ✗ | ✓ |
| ContentManager | ✓ | ✓ | ✗ | C-AUDIT (own) | ✗ | ✓ |
| EventManager | ✓ | ✓ | ✗ | C-AUDIT (own) | ✗ | ✓ |
| Member | ✓ | ✓ | ✗ | C-AUDIT (own) | ✗ | ✓ |
| Visitor | ✓ | ✓ | ✗ | C-AUDIT (own) | ✗ | ✗ |
| **Minor** | **✓ (restricted — only follow/mutual; no discovery of external users)** | ✓ | ✗ | C-AUDIT (own) | ✗ | ✓ |

---

### 2o. ModeratorQueue Resource

| Role | create | read | update (action items) | delete | view_analytics | escalate |
|------|--------|------|-----------------------|--------|----------------|----------|
| Owner | ✓ | ✓ | C-AUDIT | C-AUDIT | ✓ | ✓ |
| ExecutiveAdmin | ✓ | ✓ | C-AUDIT | C-AUDIT | ✓ | ✓ |
| Pastor | ✗ | ✓ | C-AUDIT | ✗ | ✓ | ✓ |
| Leader | ✗ | C-SPACE | C-AUDIT (space items) | ✗ | C-SPACE | ✓ |
| Moderator | ✗ | ✓ | C-AUDIT | ✗ | ✓ | ✓ |
| VolunteerLead | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ |
| ContentManager | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ |
| EventManager | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ |
| Member | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ |
| Visitor | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **Minor** | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ |

---

### 2p. AdminDashboard Resource

| Role | read | update | view_analytics |
|------|------|--------|----------------|
| Owner | ✓ | C-AUDIT | ✓ |
| ExecutiveAdmin | ✓ | C-AUDIT | ✓ |
| Pastor | C-CHURCH | C-AUDIT (church scope) | C-CHURCH |
| Leader | ✗ | ✗ | ✗ |
| Moderator | C-MOD (queue view only) | ✗ | ✗ |
| VolunteerLead | ✗ | ✗ | ✗ |
| ContentManager | ✗ | ✗ | ✗ |
| EventManager | ✗ | ✗ | ✗ |
| Member | ✗ | ✗ | ✗ |
| Visitor | ✗ | ✗ | ✗ |
| **Minor** | ✗ | ✗ | ✗ |

---

### 2q. BroadcastMessage Resource

| Role | create | read | update | delete | moderate | escalate |
|------|--------|------|--------|--------|----------|----------|
| Owner | ✓ | ✓ | C-AUDIT | C-AUDIT | ✓ | ✓ |
| ExecutiveAdmin | ✓ | ✓ | C-AUDIT | C-AUDIT | ✓ | ✓ |
| Pastor | ✓ | ✓ | C-AUDIT | ✗ | ✓ | ✓ |
| Leader | C-SPACE | ✓ | C-AUDIT (own) | ✗ | ✗ | ✓ |
| Moderator | ✗ | ✓ | ✗ | ✗ | C-MOD | ✓ |
| VolunteerLead | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ |
| ContentManager | ✓ | ✓ | C-AUDIT | ✗ | ✗ | ✓ |
| EventManager | C-ORG (event-related only) | ✓ | C-AUDIT (own) | ✗ | ✗ | ✓ |
| Member | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ |
| Visitor | ✗ | C-PRIV | ✗ | ✗ | ✗ | ✗ |
| **Minor** | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ |

---

### 2r. PrivateMessage (DM) Resource

| Role | create | read (own) | read (other) | delete (own) | moderate | escalate | send_dm |
|------|--------|------------|-------------|--------------|----------|----------|---------|
| Owner | ✓ | ✓ | C-AUDIT | C-AUDIT | ✓ | ✓ | ✓ |
| ExecutiveAdmin | ✓ | ✓ | C-AUDIT | C-AUDIT | ✓ | ✓ | ✓ |
| Pastor | ✓ | ✓ | ✗ | C-AUDIT | C-CHURCH | ✓ | ✓ |
| Leader | ✓ | ✓ | ✗ | C-AUDIT | ✗ | ✓ | ✓ |
| Moderator | ✓ | ✓ | ✗ | C-AUDIT | ✗ | ✓ | ✓ |
| VolunteerLead | ✓ | ✓ | ✗ | C-AUDIT | ✗ | ✓ | ✓ |
| ContentManager | ✓ | ✓ | ✗ | C-AUDIT | ✗ | ✓ | ✓ |
| EventManager | ✓ | ✓ | ✗ | C-AUDIT | ✗ | ✓ | ✓ |
| Member | ✓ | ✓ | ✗ | C-AUDIT | ✗ | ✓ | ✓ |
| Visitor | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **Minor** | **C-MINOR-DM** | ✓ | ✗ | C-AUDIT | ✗ | ✓ | **C-MINOR-DM** |

---

### 2s. ChurchNote Resource

| Role | create | read | update (own) | delete | moderate | escalate |
|------|--------|------|--------------|--------|----------|----------|
| Owner | ✓ | ✓ | C-AUDIT | C-AUDIT | ✓ | ✓ |
| ExecutiveAdmin | ✓ | ✓ | C-AUDIT | C-AUDIT | ✓ | ✓ |
| Pastor | ✓ | ✓ | C-AUDIT | ✗ | ✓ | ✓ |
| Leader | ✓ | ✓ | C-AUDIT (own + shared) | ✗ | ✗ | ✓ |
| Moderator | ✓ | ✓ | C-AUDIT (own) | ✗ | C-MOD | ✓ |
| VolunteerLead | ✓ | ✓ | C-AUDIT (own) | ✗ | ✗ | ✓ |
| ContentManager | ✓ | ✓ | C-AUDIT | ✗ | ✗ | ✓ |
| EventManager | ✓ | ✓ | C-AUDIT (own) | ✗ | ✗ | ✓ |
| Member | ✓ | C-OWN (own notes only — shared notes per CollaboratorRole) | C-AUDIT (own) | ✗ | ✗ | ✓ |
| Visitor | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **Minor** | ✓ | C-OWN | C-AUDIT (own) | ✗ | ✗ | ✓ |

---

### 2t. BereanInsight Resource (AI-generated, read-only for most roles)

| Role | create | read | update | delete | escalate |
|------|--------|------|--------|--------|----------|
| Owner | ✗ (CF only) | ✓ | ✗ | C-AUDIT | ✓ |
| ExecutiveAdmin | ✗ (CF only) | ✓ | ✗ | C-AUDIT | ✓ |
| Pastor | ✗ (CF only) | ✓ | ✗ | ✗ | ✓ |
| Leader | ✗ (CF only) | ✓ | ✗ | ✗ | ✓ |
| Moderator | ✗ (CF only) | ✓ | ✗ | ✗ | ✓ |
| VolunteerLead | ✗ (CF only) | ✓ | ✗ | ✗ | ✓ |
| ContentManager | ✗ (CF only) | ✓ | ✗ | ✗ | ✓ |
| EventManager | ✗ (CF only) | ✓ | ✗ | ✗ | ✓ |
| Member | ✗ (CF only) | C-OWN (own insights only) | ✗ | ✗ | ✓ |
| Visitor | ✗ | ✗ | ✗ | ✗ | ✗ |
| **Minor** | ✗ (CF only) | **C-OWN (Berean AI available for Minors at basic tier — no crisis/sensitive topics without escalation)** | ✗ | ✗ | ✓ |

> BereanInsight documents are created exclusively by Cloud Functions using the Admin SDK. No client-side create/update is permitted.

---

## 3. Privacy Level Rules

### 3a. Defined Privacy Levels

| Privacy Level | Who Can Read | Who Can Write | Notes |
|---------------|-------------|---------------|-------|
| **Private** | Owner only + explicitly invited users (named in `allowedUids[]` field) | Owner only | Firestore rule: `request.auth.uid == resource.data.ownerId || request.auth.uid in resource.data.allowedUids` |
| **TrustedCircle** | Users who follow AND are followed by the owner (mutual follows) | Owner only | Firestore rule: edge document with `type == 'mutual'` must exist |
| **Church** | Verified members of the same `churchId` | Owner (member of that church) | `church` field on resource must match actor's `churchId` claim |
| **Space** | Verified members of the same `spaceId` | Owner (member of that space) | `spaceId` field on resource must match actor's `spaceId` membership |
| **Public** | Any authenticated user; unauthenticated visitors if `publicVisibility == true` | Any authenticated member or above | Standard `isSignedIn()` check for write; no auth required for read if `isPublic == true` |
| **Anonymous** | Public visibility — content is visible but identity is shielded | Owner only (identity fields stripped server-side) | Identity shielding: `displayName` is replaced with "A member", `authorId` is hashed one-way, `profileImageURL` is null, `churchId` is null. The owner's UID is stored in `ownerUidEncrypted` (encrypted server-side, never exposed via rules). |

### 3b. Anonymous Identity Shielding Details

When a post or prayer is submitted as Anonymous:
- `displayName` → `"A member"` (set by Cloud Function before write)
- `authorId` → HMAC-SHA256 hash of UID + serverSecret (set by CF)
- `profileImageURL` → `null`
- `churchId` → `null`
- `ownerUidEncrypted` → AES-256 encrypted UID (stored, never readable by clients)
- Client rules: no client may read the `ownerUidEncrypted` field

**OPEN-3 (T&S Lead must resolve before Phase 4):** What level of identity shielding applies to Anonymous prayer requests? Option A: Full hash (no admin can de-anonymize without a separate key held by T&S Lead). Option B: Admin-readable (ExecutiveAdmin can see original UID for safety investigations). Option C: Time-limited de-anonymization (anonymous for 30 days; then stored in audit-only subcollection accessible by NCMEC-designated safety staff). Current skeleton uses Option B. T&S Lead must choose.

---

## 4. Minor-Specific Rules

> These are the most critical rules in this contract. All minor rules are marked `[MINOR]` for grep/audit purposes.

### 4a. Default Privacy

`[MINOR]` All content created by a Minor defaults to **Private** privacy level regardless of the UI selection. The UI may offer the option to change to TrustedCircle or Church, but the default must be Private. A Minor cannot post to Public feed without:
1. An explicit confirmation step ("Are you sure you want to share this with everyone?")
2. The post passing the `checkContentSafety` Cloud Function gate
3. No CSAM/safety flags from the AI moderation layer

### 4b. DM Restrictions

`[MINOR]` Direct Messages for Minors:

| Scenario | Allowed? | Condition |
|----------|----------|-----------|
| Minor sends DM to mutual follow (both follow each other) | C-MINOR-DM | Both accounts must be mutual follows; message goes through `checkContentSafety` |
| Minor sends DM to non-mutual follow | ✗ | Hard blocked |
| Minor sends DM to church leader/pastor | C-MINOR-DM | Only if church leader is verified + parental consent is on record (see OPEN-2) |
| Minor receives DM from mutual follow | C-MINOR-DM | Sender must pass minor-safe contact check |
| Minor receives DM from non-mutual | ✗ | Hard blocked |
| Minor receives DM from adult they do NOT follow | ✗ | Hard blocked — no exceptions |
| Minor's DM conversation forwarded externally | ✗ | Hard blocked — ContentPermissionEngine veto |

### 4c. Capabilities Completely Blocked for Minors

`[MINOR]` The following features are completely inaccessible to users with `ageTier == 'teen'` or `ageTier == 'under_minimum'`:

- Direct Messages with any non-mutual-follow user
- Job listings (read and create)
- Live Streaming (create) — viewing is permitted if stream is church-verified
- Commerce / paid content purchase
- Creator OS / Covenant paid tier creation
- Age-sensitive content (sermons/resources tagged 18+)
- Contact information in VolunteerOpportunity listings
- `shareExternal` action (ContentPermissionEngine veto)
- Admin Dashboard access
- Moderation Queue access

### 4d. Capabilities Restricted (not blocked) for Minors

`[MINOR]` The following features are available but restricted:

- Posts: default Private, explicit confirmation required for Church or Public
- Spaces: only church-verified spaces; no unverified public spaces
- Prayer requests: default Private
- Mentorship requests: allowed; DM with mentor requires C-MINOR-DM gate
- Berean AI: available; crisis/sensitive topics escalate to church leader + guardian notification if parental supervision is active

### 4e. Guardian Tools

`[MINOR]` **OPEN-2 (T&S Lead must resolve before Phase 4):** Guardian tools scope for v1 is undefined. The `parentUserId` and `parentalSupervisionEnabled` fields exist in `UserAgeProfile`. The T&S Lead must define:
- Can a guardian see their Minor's post history? (read access to Minor's private posts)
- Can a guardian receive escalation notifications when a Minor triggers a crisis flag?
- Can a guardian revoke a Minor's DM permissions from the parent account?
- Is guardian verification required before supervision is active, or is it self-reported?

Current skeleton: guardian has zero read access to Minor's private data. All escalation goes to the Minor's account notification center. T&S Lead must confirm or expand.

### 4f. Age Gate Threshold

`[MINOR]` **OPEN-1 (repeated from §1):** Current threshold from `AMENAgeAssuranceTier`:
- under_minimum = under-13: account blocked
- teen (Minor) = 13–17: restricted features
- adult = 18+: full access

The rules skeleton enforces 13 as the minimum. COPPA (US) requires parental consent for under-13. GDPR-K (EU) may require 16 as floor for data processing without consent in some data categories. T&S Lead + Legal must confirm the definitive threshold for each major jurisdiction before Phase 4 deploy.

---

## 5. Key Security Invariants

These invariants are non-negotiable. They must appear in the Phase 4 Firestore rules as explicit deny conditions, not just default behavior.

| # | Invariant | Enforcement Point |
|---|-----------|-------------------|
| **I-1** | All destructive operations are soft-delete only — `deletedAt` timestamp is set, document is not removed | Firestore rules: `delete` operations on Post, Prayer, Discussion, Comment, User are denied at the rule level; updates setting `deletedAt` are allowed. CF handles physical delete after 30-day retention. |
| **I-2** | All admin mutations (update/delete on any resource by Owner+ roles) write an audit log entry atomically in the same batch | CF enforces via Admin SDK batch. Firestore rule: direct client-side admin mutations without a corresponding audit write are denied. |
| **I-3** | `[MINOR]` Minors are Private by default | Firestore rule: if `resource.data.ageTier in ['teen', 'under_minimum']` then `request.resource.data.privacyLevel` must not be `'public'` unless `publicConfirmed == true`. |
| **I-4** | Passkeys/MFA are opt-in — baseline phone auth always usable | Auth layer, not Firestore rules. Firestore rules must NOT gate on MFA status. The T&S Lead must ensure no rule accidentally locks out baseline-auth users. |
| **I-5** | No raw PII in opportunity listings | Firestore rule: create/update on VolunteerOpportunity and Job must not contain the fields `contactPhone`, `contactEmail`, `homeAddress`, `salaryAmount`. CF validates before write. |
| **I-6** | Anonymous content cannot be deanonymized by any client | Firestore rule: `ownerUidEncrypted` field is unreadable via rules — `request.auth != null && !('ownerUidEncrypted' in resource.data)` is always enforced on reads. |
| **I-7** | BereanInsight documents are CF-only writes | Firestore rule: `allow write: if false` on `/bereanInsights/{id}` for all client requests. |
| **I-8** | Age profile cannot be self-updated by client | Firestore rule: `allow update: if false` on `/users/{uid}/private/age_assurance`. Update only via Admin SDK. (Already present in `firestore_age_assurance.rules`.) |

---

## 6. Decision Register

All open items below must be resolved by the T&S Lead before Phase 4 begins.

| ID | Question | Owner | Due | Status |
|----|----------|-------|-----|--------|
| **OPEN-1** | Minor age gate threshold — confirm 13 vs 16 per jurisdiction | T&S Lead + Legal | Phase 3 complete | OPEN |
| **OPEN-2** | Guardian tools scope in v1 — what can a guardian see/control? | T&S Lead | Phase 3 complete | OPEN |
| **OPEN-3** | Anonymous prayer identity shielding level — Option A/B/C (see §3b) | T&S Lead | Phase 3 complete | OPEN |
| **OPEN-4** | NCMEC pipeline timing — when does a CSAM detection trigger human authorization? What is the SLA? Who holds the escalation key? | T&S Lead + Legal | Phase 3 complete | OPEN |
| **OPEN-5** | Visitor unauthenticated access — can unauthenticated users read `public` posts, or must they authenticate first? Impacts SEO vs privacy tradeoff. | T&S Lead + Product | Phase 3 complete | OPEN |
| **OPEN-6** | Cross-church data access — can a Pastor from Church A read posts from Church B members who are also in a shared Space? Current matrix says no. Confirm. | T&S Lead + Product | Phase 3 complete | OPEN |

---

## 7. Audit Log Schema (Reference)

Every C-AUDIT action must write to `/auditLog/{eventId}` with this schema:

```
{
  actorUid: string,
  actorRole: string,
  action: string,           // e.g. "delete_post", "update_user_role"
  resourceType: string,     // e.g. "post", "user"
  resourceId: string,
  targetUid: string | null, // UID of the affected user, if applicable
  timestamp: Timestamp,
  orgId: string | null,
  churchId: string | null,
  spaceId: string | null,
  ipHash: string | null,    // HMAC hash of IP — never raw IP
  outcome: "success" | "denied" | "escalated"
}
```

AuditLog documents are append-only. Firestore rules: `allow read: if hasRole('executive_admin') || hasRole('owner')`. `allow create: if false` (CF Admin SDK only). `allow update, delete: if false`.

---

*End of C5 Security Rules Contract*
