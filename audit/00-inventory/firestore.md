# AMEN iOS App — Firestore Collections & Security Rules

**Rules File:** firestore.rules (2,000+ lines)  
**Total Collections:** 50+ unique paths  
**Audit Status:** ✅ All collections found in rules  

## Collections by Category

### Social Content (Posts, Prayers, Discussions)

| Collection | Read Rule | Write Rule | Rule Ref | Notes |
|-----------|-----------|-----------|----------|-------|
| posts/{postId} | privacy-gated (public/church/space/private) | owner or soft-delete by moderator | C5 §2b | Hard delete denied (I-1) |
| posts/{postId}/comments/* | signed-in | signed-in + not under_minimum | C5 §2e | Hard delete denied |
| posts/{postId}/actionThreads/* | signed-in | CF-only | C5 §2e ext | Post-to-action conversion |
| prayers/{prayerId} | privacy-gated + [MINOR] logic | owner | C5 §2c | ownerUidEncrypted never readable (I-6) |
| discussions/{discussionId} | privacy-gated | owner or soft-delete by moderator | C5 §2d | Hard delete denied |
| discussions/{discussionId}/messages/* | privacy-gated | signed-in | C5 §2d ext | Discussion messages |
| discussions/{discussionId}/comments/* | signed-in | signed-in | C5 §2d ext | Discussion comments |

### User Data & Preferences

| Collection | Read Rule | Write Rule | Rule Ref | Notes |
|-----------|-----------|-----------|----------|-------|
| users/{uid} | signed-in | owner (protected fields CF-only) | C5 §2a | premiumTier/ageTier immutable by client (I-8) |
| users/{uid}/private/age_assurance | owner | owner (updates CF-only) | C5 §2a | IMMUTABLE by clients (I-8) |
| users/{uid}/safety/* | owner or admin | CF-only | C5 §2a | Safety signals, notifications, reports |
| users/{uid}/trust/* | owner | CF-only | C5 §2a | Trust profile, signals, ledger |
| users/{uid}/drafts/* | owner | CF-only | C5 §2a | Draft posts, moderation |
| users/{uid}/media/* | owner | CF-only | C5 §2a | Media metadata, transcripts, captions |
| users/{uid}/notifications/* | owner | CF-only (create), owner (delete) | C5 §2a | Push notification records |
| users/{uid}/actions/* | owner | owner | C5 §2a | Action reminders from posts |

### Messaging & Communication

| Collection | Read Rule | Write Rule | Rule Ref | Notes |
|-----------|-----------|-----------|----------|-------|
| conversations/{cid} | participant only | participant | C5 §2r | [MINOR-DM] mutual-follow required |
| conversations/{cid}/messages/* | participant only | sender (not under_minimum) | C5 §2r | Soft-delete only |
| churchNotes/{noteId} | owner/collaborator/admin | owner/collaborator | C5 §2s | Collaborative sermon notes |

### Community (Organizations, Churches, Spaces, Teams)

| Collection | Read Rule | Write Rule | Rule Ref | Notes |
|-----------|-----------|-----------|----------|-------|
| organizations/{orgId} | public profiles or same-org | same-org admin | C5 §2f | Soft-delete only (I-1) |
| organizations/{orgId}/members/* | same-org or admin | admin roles | C5 §2f | isActive: false for deactivation |
| churches/{churchId} | public profiles or member | member admin | C5 §2g | Soft-delete only |
| churches/{churchId}/members/* | member or admin | admin roles | C5 §2g | churchVerified blocks minors in spaces |
| spaces/{spaceId} | signed-in + [MINOR] verification | leader/admin | C5 §2i | churchVerified required for minors |
| spaces/{spaceId}/members/* | member or admin | leader/admin/self-join | C5 §2i | Soft-delete only |
| teams/{teamId} | signed-in | leader/admin | C5 §2h | Soft-delete only |

### Opportunities & Events

| Collection | Read Rule | Write Rule | Rule Ref | Notes |
|-----------|-----------|-----------|----------|-------|
| events/{eventId} | signed-in | admin roles | C5 §2j | [MINOR] minors can read; no blocking |
| jobs/{jobId} | signed-in & !minor | admin roles | C5 §2l | [MINOR-BLOCK] minors completely blocked (read denied) |
| volunteerOpportunities/* | signed-in & !raw-pii-check | admin roles | C5 §2k | I-5: no contactPhone/email/homeAddress |
| mentorshipRequests/{rid} | requestor/mentor/admin | requestor/mentor | C5 §2m | [MINOR] minors can request |

### Moderation & Admin

| Collection | Read Rule | Write Rule | Rule Ref | Notes |
|-----------|-----------|-----------|----------|-------|
| moderationQueue/{itemId} | moderator+ | moderator+ | C5 §2o | Admin SDK writes, client reads |
| auditLog/{eventId} | owner/executive_admin | CF Admin SDK only | C5 §7 | I-2: append-only (no updates/deletes) |
| age_verification_events/* | executive_admin only | CF Admin SDK only | C5 age gate | Not readable by owner |
| moderationDecisions/{did} | author/moderator | CF-only | C5 ext | Enforcement decision records |
| userReports/{rid} | reporter/moderator | CF-only (submitReport) | C5 ext | User-submitted reports |
| crisisEscalations/{uid}/{ts} | owner/executive_admin | CF-only | C5 ext | Self-harm/CSAM escalations |
| humanReviewQueue/{itemId} | moderator+/admin | CF-only | C5 ext | Manual review queue |
| mediaModeration/{docId} | author/moderator | CF-only | C5 ext | Media-specific moderation results |

### Messaging & Notifications

| Collection | Read Rule | Write Rule | Rule Ref | Notes |
|-----------|-----------|-----------|----------|-------|
| broadcastMessages/* | signed-in + privacy-gated | pastor/admin | C5 §2q | Soft-delete only |
| notificationCounts/{uid} | owner | CF-only | C5 ext | Notification badge counters |

### Intelligence & Living Formation

| Collection | Read Rule | Write Rule | Rule Ref | Notes |
|-----------|-----------|-----------|----------|-------|
| intelligence_cards/{cid} | owner only | CF Admin SDK only | New 2026-06-05 | Living Intelligence cards |
| intelligence_briefs/{uid} | owner only | CF Admin SDK only | New 2026-06-05 | Per-user brief |
| intelligence_actions/{uid} | owner only | CF Admin SDK only | New 2026-06-05 | Actionable recommendations |
| opportunity_graph/{nid} | CF internal only | CF internal only | New 2026-06-06 | ML ranking graph (no client access) |
| church_pulse/{cid} | signed-in (member/pastor/admin) | CF Admin SDK only | New 2026-06-06 | Church health metrics |
| amen_live_sessions/* | signed-in | CF Admin SDK only | New 2026-06-06 | Live session records |
| world_response_queue/* | CF internal only | CF internal only | New 2026-06-06 | Global card event queue |
| worldResponseSources/* | signed-in | CF Admin SDK only | New 2026-06-06 | Trusted source registry |
| needs/{needId} | signed-in | CF callable only (classifyPostNeed) | New 2026-06-06 | Community needs classification |

### Catalog & Knowledge Network

| Collection | Read Rule | Write Rule | Rule Ref | Notes |
|-----------|-----------|-----------|----------|-------|
| works/{workId} | signed-in + visibility-gated | creator (no self-publish) | New 2026-06-06 | Catalog media items |
| knowledgeNodes/{nid} | creator only | creator (immutable creatorId) | New 2026-06-06 | Knowledge graph nodes |
| ingestionJobs/{jid} | creator only | creator (status CF-only) | New 2026-06-06 | Provider ingestion tracking |
| verificationClaims/{cid} | creator/admin | creator (status CF-only) | New 2026-06-06 | Ownership verification (no self-approval) |
| users/{uid}/followedTopics/* | owner | owner (can unfollow) | New 2026-06-06 | Subscription list |

### Formation & Berean OS

| Collection | Read Rule | Write Rule | Rule Ref | Notes |
|-----------|-----------|-----------|----------|-------|
| berean/{uid}/memory/* | owner | owner (CF-only updates) | New 2026-06-07 | B-1: Per-user isolation |
| berean/{uid}/threads/* | owner | owner | New 2026-06-07 | B-4: Soft-delete only |
| berean/{uid}/messages/* | owner | owner (user role only) | New 2026-06-07 | B-5: Assistant role CF-only |
| berean/{uid}/usage/* | owner | CF Admin SDK only | New 2026-06-07 | B-6: Read-only for clients |
| berean/{uid}/capabilities | owner | owner or CF | New 2026-06-07 | B-7: Capability tier access |
| berean/{uid}/connectors/* | owner (no minors) | owner (no minors) or CF | New 2026-06-07 | B-3: Minors cannot access |
| config/credits | signed-in | CF Admin SDK only | New 2026-06-07 | Voice credits (read-only) |
| config/voice | signed-in | CF Admin SDK only | New 2026-06-07 | Voice config (read-only) |

### Sabbath Mode

| Collection | Read Rule | Write Rule | Rule Ref | Notes |
|-----------|-----------|-----------|----------|-------|
| users/{uid}/sabbath/config | owner | owner | New 2026-06-07 | S-1: Sabbath configuration |
| users/{uid}/sabbathSessions/* | owner | owner | New 2026-06-07 | S-1: Session records |
| users/{uid}/sabbathReflections/* | owner ONLY | owner ONLY | New 2026-06-07 | S-2: NEVER readable by admin/CF |
| users/{uid}/sabbath/heldNotifications/* | owner | owner (CF writes) | New 2026-06-07 | S-3: Held notification digest |
| users/{uid}/sabbath/presence | any signed-in | owner | New 2026-06-07 | S-4: Boolean only (text display) |

### Selah & Spiritual

| Collection | Read Rule | Write Rule | Rule Ref | Notes |
|-----------|-----------|-----------|----------|-------|
| users/{uid}/selahNotes/* | owner | owner (soft-delete only) | New 2026-06-07 | SE-1: Private spiritual notes |
| discernmentChecks/{cid} | creator/shared thread | creator (visibility CF-only) | New 2026-06-07 | SE-2: Visibility default private |
| spiritualOS/{did} | owner | CF Admin SDK only | C5 ext | Spiritual OS documents |
| unsentThoughts/{did} | owner | CF Admin SDK only | C5 ext | Risk detection (self-harm signals) |
| repairFlows/{fid} | initiator/target | CF-only | C5 ext | Repair flow records (ONE) |

### Social Graph & Relationships

| Collection | Read Rule | Write Rule | Rule Ref | Notes |
|-----------|-----------|-----------|----------|-------|
| edges/{eid} | own edges or moderator+ | creator (soft-delete only) | C5 §2n | Follow/block/mutual edges |
| follows/{fid} | signed-in | CF-only (createFollow) | C5 ext | Follow edges |
| follows_index/{idx} | signed-in | CF-only | C5 ext | Follow index (query optimization) |
| blockedUsers/{bid} | blocker or admin | CF-only | C5 ext | Block edges |
| mentorships/{mid}/signals/* | owner/mentor | owner/mentor (append-only) | C5 ext | Mentorship signals (written by iOS SDK) |
| user_activity_summary/{uid} | signed-in | CF-only | C5 ext | Activity summarization |
| relationship_activity_state/* | self-reference only | CF-only | C5 ext | Social graph state |

### Other Collections

| Collection | Read Rule | Write Rule | Rule Ref | Notes |
|-----------|-----------|-----------|----------|-------|
| communityHubs/{hid} | signed-in | CF-only | C5 ext | Community object hubs |
| communityHubs/{hid}/posts/* | signed-in | CF-only | C5 ext | Hub-indexed posts |
| communityHubs/{hid}/members/* | signed-in | CF-only | C5 ext | Hub membership |
| canonicalObjects/{oid} | signed-in | CF-only | C5 ext | Canonical object resolution |
| user_trust/{uid} | owner/moderator | CF-only | C5 ext | Trust OS scoring |
| userSafetyRecords/{uid} | owner/moderator | CF-only | C5 ext | Safety evaluation records |
| banAppeals/{uid} | owner/admin | owner/admin | New 2026-06-07 | Ban appeal records |
| auditTrail/{uid}/events/* | owner/admin | owner (append-only) | New 2026-06-07 | GDPR audit trail |
| aiReports/{rid} | admin SDK only | signed-in (create), admin (update) | New 2026-06-07 | AI safety reports |
| systemStatus/{did} | signed-in | CF Admin SDK only | C5 ext | Kill-switch flags |
| one_moments/{mid} | sender/recipient | CF-only | C5 ext | ONE: ephemeral messages |
| one_repair_flows/{fid} | initiator/target | CF-only | C5 ext | ONE: repair flows |
| bereanProjects/{pid} | owner/admin | CF-only | C5 ext | Berean project management |

---

## Security Invariants Enforced

| Code | Description | Collections | Status |
|------|-------------|-----------|--------|
| I-1 | Soft-delete only (isDeleted: false→true) | All content | ✅ Enforced |
| I-2 | Audit mutations CF-batch-enforced | auditLog/* | ✅ Enforced |
| I-3 | [MINOR] Minors public posts need confirmation | posts, prayers | ✅ Enforced |
| I-4 | MFA/passkeys opt-in | users/{uid} | ✅ Enforced |
| I-5 | No raw PII in opportunities | jobs, volunteerOpportunities | ✅ Enforced |
| I-6 | ownerUidEncrypted never readable | prayers (anonymous) | ✅ Enforced |
| I-7 | BereanInsights CF-write-only | bereanInsights/{iid} | ✅ Enforced |
| I-8 | Age profile immutable by clients | users/{uid}/private/age_assurance | ✅ Enforced |

---

## Coverage Summary

- **Total Collections:** 50+ unique paths
- **All In Rules:** ✅ YES
- **No Orphan Collections:** ✅ YES (no collection found in code without matching rule)
- **No Allow true Rules:** ✅ YES (all rules have explicit access gates)
- **CF-Only Collections:** 20+ (writing CF-enforced, no client create/update)
- **Soft-Delete Pattern:** 100% (no hard deletes for user-generated content)

