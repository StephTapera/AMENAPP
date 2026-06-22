# Rules Reconciliation Worksheet (READ-ONLY — no merge, no push, no PR, no deploy)

Compares `origin/main:firestore.rules` vs the **deployed** ruleset (`deployed-rules-snapshot`).
Input to a human three-way merge. Job: ensure NO safety rule is dropped.

**Counts:** both=17 · deployed-only=85 · main-only=78 · safety-flagged=35

> Generated read-only. Bodies shown verbatim so `allow` rules can be compared side by side.


---
## ⚠️ SAFETY / CRISIS / AUDIT / MEDIA-SCAN — REVIEW FIRST


### `/actionIntelligenceAudit` — **DEPLOYED-ONLY**

**main:**
```
(absent)
```

**deployed:**
```
match /actionIntelligenceAudit/{auditId} {
      allow read, write: if isAdminSDK();
    }
```

### `/aiReports` — **DEPLOYED-ONLY**

**main:**
```
(absent)
```

**deployed:**
```
match /aiReports/{reportId} {
      allow read: if isAdminSDK();
      allow create: if isSignedIn();
      allow update, delete: if isAdminSDK();
    }
```

### `/auditLog` — **DEPLOYED-ONLY**

**main:**
```
(absent)
```

**deployed:**
```
match /auditLog/{eventId} {
      // Read: owner or executive admin only.
      allow read: if hasAnyClaimRole(['owner', 'executive_admin']);

      // Create: CF Admin SDK only — no client writes ever.
      allow create: if false;

      // Audit log is append-only — no updates ever.
      allow update: if false;

      // Audit log is permanent — no deletes ever.
      allow delete: if false;
    }
```

### `/auditTrail` — **DEPLOYED-ONLY**

**main:**
```
(absent)
```

**deployed:**
```
match /auditTrail/{uid}/events/{eventId} {
      allow read: if isOwner(uid) || isAdminSDK();
      allow create: if isOwner(uid);
      allow update, delete: if false;  // INVARIANT: append-only
    }
```

### `/banAppeals` — **DEPLOYED-ONLY**

**main:**
```
(absent)
```

**deployed:**
```
match /banAppeals/{uid} {
      allow read: if isOwner(uid) || isAdminSDK();
      allow create, update: if isOwner(uid);
      allow delete: if isAdminSDK();
    }
```

### `/bereanAuditLog` — **MAIN-ONLY**

**main:**
```
match /bereanAuditLog/{logId} {
      // Users can read their own AI interaction log (transparency).
      allow read: if isAuthenticated()
        && resource.data.get('userId', '') == request.auth.uid;

      // Clients append their own entries only.
      allow create: if isAuthenticated()
        && request.resource.data.get('userId', '') == request.auth.uid;

      // Immutable once written — no updates or deletes from client.
      allow update, delete: if false;
    }
```

**deployed:**
```
(absent)
```

### `/childSafetyEscalations` — **DEPLOYED-ONLY**

**main:**
```
(absent)
```

**deployed:**
```
match /childSafetyEscalations/{escalationId} {
      allow read: if isSafetyLead() || isLegalReviewer();
      allow create, update, delete: if false; // CF Admin SDK / NCMEC pipeline only
    }
```

### `/contentAppeals` — **DEPLOYED-ONLY**

**main:**
```
(absent)
```

**deployed:**
```
match /contentAppeals/{appealId} {
      // APPEAL-C3: owner reads their own appeal
      // APPEAL-C4: moderators read all appeals
      allow read: if
        (isSignedIn() && resource.data.get('contentOwnerUid', '') == request.auth.uid) ||
        isModerator();

      // APPEAL-C1 + APPEAL-C2: create own appeal with status == "submitted" only
      allow create: if
        isSignedIn() &&
        request.resource.data.get('contentOwnerUid', '') == request.auth.uid &&
        request.resource.data.get('status', '') == 'submitted' &&
        // Prevent client from setting moderator-controlled fields
        !request.resource.data.keys().hasAny([
          'moderatorUid', 'moderatorDecision', 'moderatorNotes',
          'resolvedAt', 'escalatedAt'
        ]);

      // APPEAL-C5: no client updates or deletes
      allow update, delete: if false; // CF moderatorResolveAppeal callable only
    }
```

### `/crisisDetectionLogs` — **MAIN-ONLY**

**main:**
```
match /crisisDetectionLogs/{logId} {
      // P0 FIX: Crisis logs contain sensitive self-harm signals — deny ALL client reads.
      // Only Cloud Functions (admin SDK) can read or create these. Admin UI reads via backend.
      allow create: if false;
      allow read: if false;
      allow update, delete: if false;
    }
```

**deployed:**
```
(absent)
```

### `/crisisDetectionRequests` — **MAIN-ONLY**

**main:**
```
match /crisisDetectionRequests/{requestId} {
      // Users can create crisis detection requests for their own prayers
      allow create: if isAuthenticated()
        && request.resource.data.userId == request.auth.uid
        && hasRequiredFields(['prayerText', 'userId', 'timestamp']);

      // No read/update/delete - only Cloud Functions process these
      allow read, update, delete: if false;
    }
```

**deployed:**
```
(absent)
```

### `/crisisDetectionResults` — **MAIN-ONLY**

**main:**
```
match /crisisDetectionResults/{resultId} {
      // Users can only read results for their own crisis detection requests
      allow read: if isAuthenticated()
        && resource.data.get('userId', '') == request.auth.uid;

      // Only Cloud Functions can write results
      allow create, update, delete: if false;
    }
```

**deployed:**
```
(absent)
```

### `/crisisEscalations` — **DEPLOYED-ONLY**

**main:**
```
(absent)
```

**deployed:**
```
match /crisisEscalations/{uid}/{ts} {
      allow read: if isOwner(uid) || hasAnyClaimRole(['executive_admin']);
      allow create, update, delete: if false; // CF only
    }
```

### `/criticalSafetyAlerts` — **DEPLOYED-ONLY**

**main:**
```
(absent)
```

**deployed:**
```
match /criticalSafetyAlerts/{alertId} {
      allow create: if isSignedIn()
        && request.resource.data.keys().hasOnly([
          'type', 'contentRef', 'authorId', 'detectionSource', 'failedStep',
          'errorDescription', 'createdAt', 'requiresImmediateHumanReview',
          'reporterUid'
        ])
        && request.resource.data.type == 'csam_escalation_write_failure'
        && request.resource.data.reporterUid == request.auth.uid
        && request.resource.data.requiresImmediateHumanReview == true;
      allow read, update, delete: if false;
    }
```

### `/deletionAuditLog` — **MAIN-ONLY**

**main:**
```
match /deletionAuditLog/{logId} {
      // Admin only reads for compliance
      allow read: if isAuthenticated()
        && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.isAdmin == true;
      allow write: if false; // Server-side only
    }
```

**deployed:**
```
(absent)
```

### `/enforcementHistory` — **MAIN-ONLY**

**main:**
```
match /enforcementHistory/{actionId} {
      // Users can read enforcement actions taken against them or by them (transparency).
      allow read: if isAuthenticated()
        && (resource.data.get('userId', '') == request.auth.uid
          || resource.data.get('targetUserId', '') == request.auth.uid);

      // P0 FIX: All writes must come from Cloud Functions (admin SDK) only.
      // Any authenticated client write would allow audit log poisoning.
      allow create: if false;
      allow update, delete: if false;
    }
```

**deployed:**
```
(absent)
```

### `/enforcement_actions` — **MAIN-ONLY**

**main:**
```
match /enforcement_actions/{actionId} {
      // Targets can read enforcement actions taken against them.
      allow get: if isAuthenticated()
        && resource.data.get('target_user_id', '') == request.auth.uid;
      // Allow users to list their own enforcement history by filtering on target_user_id.
      allow list: if isAuthenticated();
      // Append-only by Cloud Functions — no client writes.
      allow create, update, delete: if false;
    }
```

**deployed:**
```
(absent)
```

### `/evidencePreservation` — **MAIN-ONLY**

**main:**
```
match /evidencePreservation/{docId} {
      allow create: if isAuthenticated();
      allow read, update, delete: if false;
    }
```

**deployed:**
```
(absent)
```

### `/mandatory_reports` — **DEPLOYED-ONLY**

**main:**
```
(absent)
```

**deployed:**
```
match /mandatory_reports/{reportId} {
      allow read, create, update, delete: if false;
    }
```

### `/mediaModeration` — **DEPLOYED-ONLY**

**main:**
```
(absent)
```

**deployed:**
```
match /mediaModeration/{docId} {
      allow read: if
        isOwner(resource.data.get('authorId', '')) ||
        hasAnyClaimRole(['moderator', 'executive_admin']);
      allow create, update, delete: if false; // CF mediaModerationPipeline
    }
```

### `/mediaScanQueue` — **MAIN-ONLY**

**main:**
```
match /mediaScanQueue/{scanId} {
      allow create: if isAuthenticated()
        && request.resource.data.senderId == request.auth.uid;
      allow read, update, delete: if false;
    }
```

**deployed:**
```
(absent)
```

### `/moderationAppeals` — **MAIN-ONLY**

**main:**
```
match /moderationAppeals/{appealId} {
      allow read: if isAuthenticated() && resource.data.userId == request.auth.uid;
      allow create: if isAuthenticated() && request.resource.data.userId == request.auth.uid;
      allow update, delete: if false; // Only admins via backend
    }
```

**deployed:**
```
(absent)
```

### `/moderationDecisions` — **DEPLOYED-ONLY**

**main:**
```
(absent)
```

**deployed:**
```
match /moderationDecisions/{decisionId} {
      allow read: if
        isSignedIn() &&
        (isOwner(resource.data.get('targetUid', '')) ||
         hasAnyClaimRole(['moderator', 'executive_admin']));
      allow create, update, delete: if false; // CF only
    }
```

### `/moderationLogs` — **MAIN-ONLY**

**main:**
```
match /moderationLogs/{logId} {
      // Users can create logs for their own content
      allow create: if isAuthenticated()
        && request.resource.data.userId == request.auth.uid;

      // Only admins can read moderation logs
      allow read: if isAuthenticated()
        && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.isAdmin == true;

      allow update, delete: if false;
    }
```

**deployed:**
```
(absent)
```

### `/moderationQueue` — **BOTH**  ⚠️ ALLOW-RULES DIFFER

**main:**
```
match /moderationQueue/{queueId} {
      // Only admins can read moderation queue
      allow read: if isAuthenticated()
        && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.isAdmin == true;
      
      // Anyone can create moderation flags
      allow create: if isAuthenticated()
        && request.resource.data.reporterId == request.auth.uid;
      
      // Only admins can update/delete (in production, add admin role check)
      allow update: if false;
      allow delete: if false;
    }
/* +dup */
match /moderationQueue/{messageId} {
      // Clients can create (gateway writes on flagged message)
      allow create: if isAuthenticated()
        && request.resource.data.senderId == request.auth.uid
        && request.resource.data.keys().hasAll(['messageId', 'conversationId', 'senderId', 'decision', 'createdAt']);
      // Clients cannot read, update, or delete moderation records
      allow read, update, delete: if false;
    }
```

**deployed:**
```
match /moderationQueue/{itemId} {
      // Read: moderators, pastors, owners, executive admins; leaders for their space only.
      allow read: if
        hasAnyClaimRole(['moderator', 'pastor', 'owner', 'executive_admin']) ||
        (hasClaimRole('leader') &&
         sameOrg(resource.data.get('orgId', '')) &&
         isSpaceMember(resource.data.get('spaceId', '')));

      // Create: Admin SDK only (CF-generated reports; clients escalate via CF callable).
      allow create: if isAdminSDK();

      // Update: moderators and above can action items.
      allow update: if
        hasAnyClaimRole(['moderator', 'pastor', 'owner', 'executive_admin']);

      // Delete: owner/executive admin only (via CF + audit log). No client deletes.
      allow delete: if false;
    }
```

### `/moderationRequests` — **MAIN-ONLY**

**main:**
```
match /moderationRequests/{requestId} {
      // Users can create moderation requests for their own content
      allow create: if isAuthenticated()
        && request.resource.data.userId == request.auth.uid
        && hasRequiredFields(['content', 'contentType', 'userId', 'timestamp']);

      // No read/update/delete - only Cloud Functions process these
      allow read, update, delete: if false;
    }
```

**deployed:**
```
(absent)
```

### `/moderationResults` — **MAIN-ONLY**

**main:**
```
match /moderationResults/{resultId} {
      // P0 FIX: Confirmed — scoped to requesting user only (no world-readable access).
      allow read: if isAuthenticated()
        && resource.data.get('userId', '') == request.auth.uid;

      // Only Cloud Functions can write results
      allow create, update, delete: if false;
    }
```

**deployed:**
```
(absent)
```

### `/moderation_ingest_events` — **MAIN-ONLY**

**main:**
```
match /moderation_ingest_events/{eventId} {
      // Authors can create their own ingest events (pre-submit signal).
      allow create: if isAuthenticated()
        && request.resource.data.get('author_id', '') == request.auth.uid
        && request.resource.data.keys().hasAll(['content_id', 'content_type', 'author_id', 'created_at']);
      // No client reads — server-only processing.
      allow read, update, delete: if false;
    }
```

**deployed:**
```
(absent)
```

### `/moderation_jobs` — **MAIN-ONLY**

**main:**
```
match /moderation_jobs/{jobId} {
      // Authors can read their own job results (transparency centre).
      allow get: if isAuthenticated()
        && resource.data.get('author_id', '') == request.auth.uid;
      // No client list — prevents fishing for other users' job IDs.
      allow list: if false;
      // Cloud Functions write via admin SDK (bypasses rules).
      allow create, update, delete: if false;
    }
```

**deployed:**
```
(absent)
```

### `/ncmecReports` — **DEPLOYED-ONLY**

**main:**
```
(absent)
```

**deployed:**
```
match /ncmecReports/{reportId} {
      allow read, create, update, delete: if false;
    }
```

### `/ncmecSubmissionQueue` — **DEPLOYED-ONLY**

**main:**
```
(absent)
```

**deployed:**
```
match /ncmecSubmissionQueue/{entryId} {
      allow read, create, update, delete: if false;
    }
```

### `/one_evidence` — **DEPLOYED-ONLY**

**main:**
```
(absent)
```

**deployed:**
```
match /one_evidence/{evidenceId} {
      allow read, write: if false;
    }
```

### `/reports` — **MAIN-ONLY**

**main:**
```
match /reports/{reportId} {
      // Reporter can read only their own report submissions
      allow read: if isAuthenticated()
        && resource.data.reporterId == request.auth.uid;

      // Create: reporter must identify themselves + schema must be valid
      allow create: if isAuthenticated()
        && request.resource.data.reporterId == request.auth.uid
        && hasRequiredFields(['reporterId', 'reportedUserId', 'reason', 'submittedAt'])
        && validLength(request.resource.data.get('additionalContext', ''), 500)
        && request.resource.data.reason in [
          // SafetyReportingService.ReportReason raw values
          'grooming_or_trafficking', 'child_safety', 'threat_or_blackmail', 'sextortion',
          'solicitation', 'off_platform_pressure', 'financial_scam', 'violence_or_self_harm',
          'harassment', 'hate_speech', 'unwanted_contact', 'spam', 'impersonation', 'other',
          // Legacy / ModerationReportReason enum values (keep for backwards-compat)
          'Inappropriate content', 'Spam', 'Harassment', 'Hate speech',
          'False information', 'Violence', 'Self-harm', 'Adult content',
          'Privacy violation', 'Other', 'inappropriate', 'reported_content'
        ];

      // NO client updates or deletes — reports are immutable evidence
      allow update, delete: if false;
    }
```

**deployed:**
```
(absent)
```

### `/safetyEvents` — **MAIN-ONLY**

**main:**
```
match /safetyEvents/{eventId} {
      // Any authenticated user can create their own safety event.
      // Schema validation: required fields + senderId must be the caller.
      // No message text is stored — only signals and metadata.
      allow create: if isAuthenticated()
        && request.resource.data.senderId == request.auth.uid
        && request.resource.data.keys().hasAll(['senderId', 'recipientId', 'signals', 'conversationId', 'createdAt'])
        && request.resource.data.signals is list
        && request.resource.data.signals.size() <= 20;
      // Users can read only events they were party to
      allow read: if isAuthenticated()
        && (resource.data.senderId == request.auth.uid
            || resource.data.recipientId == request.auth.uid);
      allow update, delete: if false;
    }
```

**deployed:**
```
(absent)
```

### `/userReports` — **BOTH**  ⚠️ ALLOW-RULES DIFFER

**main:**
```
match /userReports/{reportId} {
      // Users can read reports where they are the reporter or the reported user
      allow read: if isAuthenticated()
        && (resource.data.get('reporterId', '') == request.auth.uid
          || resource.data.get('reportedUserId', '') == request.auth.uid);

      // Any authenticated user can file a report
      allow create: if isAuthenticated()
        && request.resource.data.get('reporterId', '') == request.auth.uid;

      // No updates or deletes from client
      allow update, delete: if false;
    }
```

**deployed:**
```
match /userReports/{reportId} {
      allow read: if
        isOwner(resource.data.get('reporterUid', '')) ||
        hasAnyClaimRole(['moderator', 'executive_admin']);
      allow create, update, delete: if false; // CF submitReport only
    }
```

### `/userSafetyRecords` — **BOTH**  ⚠️ ALLOW-RULES DIFFER

**main:**
```
match /userSafetyRecords/{userId} {
      // Users can only read their OWN safety record (to check freeze/accountStatus).
      // Previously any authenticated user could read any record — this exposed strike
      // counts and freeze reasons to other users.
      // The ConversationRiskEngine fetches reportCount via a Cloud Function, not
      // a direct Firestore read, so this restriction does not break that pipeline.
      allow read: if isOwner(userId);
      // ALL writes blocked from client — Cloud Functions write via admin SDK which
      // bypasses Firestore security rules entirely, so this 'false' only affects clients.
      allow create, update, delete: if false;
    }
```

**deployed:**
```
match /userSafetyRecords/{userId} {
      allow read: if isOwner(userId) || hasAnyClaimRole(['moderator', 'executive_admin']);
      allow create, update, delete: if false; // CF evaluateTrustOSPolicy
    }
```

---
## 🔒 DO-NOT-DROP LIST (safety rules that MUST survive the merge)

- `/actionIntelligenceAudit` — present on: deployed
- `/aiReports` — present on: deployed
- `/auditLog` — present on: deployed
- `/auditTrail` — present on: deployed
- `/banAppeals` — present on: deployed
- `/bereanAuditLog` — present on: main
- `/childSafetyEscalations` — present on: deployed
- `/contentAppeals` — present on: deployed
- `/crisisDetectionLogs` — present on: main
- `/crisisDetectionRequests` — present on: main
- `/crisisDetectionResults` — present on: main
- `/crisisEscalations` — present on: deployed
- `/criticalSafetyAlerts` — present on: deployed
- `/deletionAuditLog` — present on: main
- `/enforcementHistory` — present on: main
- `/enforcement_actions` — present on: main
- `/evidencePreservation` — present on: main
- `/mandatory_reports` — present on: deployed
- `/mediaModeration` — present on: deployed
- `/mediaScanQueue` — present on: main
- `/moderationAppeals` — present on: main
- `/moderationDecisions` — present on: deployed
- `/moderationLogs` — present on: main
- `/moderationQueue` — present on: main, deployed
- `/moderationRequests` — present on: main
- `/moderationResults` — present on: main
- `/moderation_ingest_events` — present on: main
- `/moderation_jobs` — present on: main
- `/ncmecReports` — present on: deployed
- `/ncmecSubmissionQueue` — present on: deployed
- `/one_evidence` — present on: deployed
- `/reports` — present on: main
- `/safetyEvents` — present on: main
- `/userReports` — present on: main, deployed
- `/userSafetyRecords` — present on: main, deployed

---
## Bucket 1 — BOTH (⚠️ = allow-rules differ)

- `/blockedUsers` ⚠️ DIFFERS
- `/churchNotes` ⚠️ DIFFERS
- `/churches` ⚠️ DIFFERS
- `/conversations` ⚠️ DIFFERS
- `/events` ⚠️ DIFFERS
- `/follows` ⚠️ DIFFERS
- `/moderationQueue` ⚠️ DIFFERS 🔒
- `/notificationBatches` ⚠️ DIFFERS
- `/posts` ⚠️ DIFFERS
- `/prayerRequests` ⚠️ DIFFERS
- `/prayers` ⚠️ DIFFERS
- `/scheduledBatches` ⚠️ DIFFERS
- `/userNotificationPreferences` ⚠️ DIFFERS
- `/userReports` ⚠️ DIFFERS 🔒
- `/userSafetyRecords` ⚠️ DIFFERS 🔒
- `/user_trust` ⚠️ DIFFERS
- `/users` ⚠️ DIFFERS

---
## Bucket 2 — DEPLOYED-ONLY (live; absent from main)

- `/actionIntelligenceAudit` 🔒
- `/actionIntelligenceObjects`
- `/adminDashboard`
- `/age_verification_events`
- `/aiReports` 🔒
- `/amenInitiatives`
- `/amenKnowledgeGraph`
- `/amenRelationshipSignals`
- `/amenVolunteerAssignments`
- `/amen_live_sessions`
- `/auditLog` 🔒
- `/auditTrail` 🔒
- `/banAppeals` 🔒
- `/berean`
- `/bereanInsights`
- `/bereanProjects`
- `/broadcastMessages`
- `/canonicalObjects`
- `/childSafetyEscalations` 🔒
- `/churchNotesJobs`
- `/church_pulse`
- `/communityHubs`
- `/communityTransforms`
- `/config`
- `/connectorTokens`
- `/contentAppeals` 🔒
- `/contextFacets`
- `/contextSnapshots`
- `/crisisEscalations` 🔒
- `/criticalSafetyAlerts` 🔒
- `/discernmentChecks`
- `/discussionContext`
- `/discussions`
- `/edges`
- `/entitlements`
- `/follows_index`
- `/helixNodes`
- `/humanReviewQueue`
- `/ingestionJobs`
- `/intelligence_actions`
- `/intelligence_briefs`
- `/intelligence_cards`
- `/jobs`
- `/knowledgeNodes`
- `/legalHolds`
- `/mandatory_reports` 🔒
- `/mediaModeration` 🔒
- `/mentorshipRequests`
- `/mentorships`
- `/moderationDecisions` 🔒
- `/moderator`
- `/ncmecReports` 🔒
- `/ncmecSubmissionQueue` 🔒
- `/needs`
- `/noteShares`
- `/notificationCounts`
- `/one_evidence` 🔒
- `/one_legacy`
- `/one_moments`
- `/one_reach`
- `/one_repair_flows`
- `/one_threads`
- `/one_users`
- `/one_vaults`
- `/opportunity_graph`
- `/organizations`
- `/relationship_activity_state`
- `/repairFlows`
- `/roles`
- `/scheduledActions`
- `/spaces`
- `/spiritualOS`
- `/stripeCustomers`
- `/systemStatus`
- `/teams`
- `/unsentThoughts`
- `/userSettings`
- `/user_activity_summary`
- `/verificationClaims`
- `/volunteerOpportunities`
- `/whatsNewStories`
- `/whisperUsage`
- `/works`
- `/worldResponseSources`
- `/world_response_queue`

---
## Bucket 3 — MAIN-ONLY (on main; absent from deployed — deploy may have dropped)

- `/admin`
- `/adultContentHashes`
- `/aiBibleStudyConversations`
- `/aiSearchRequests`
- `/aiSearchResults`
- `/analytics`
- `/analytics_performance`
- `/bereanAuditLog` 🔒
- `/bibleVerses`
- `/blocks`
- `/brigadingAlerts`
- `/churchRecommendationRequests`
- `/churchRecommendationResults`
- `/communities`
- `/crisisDetectionLogs` 🔒
- `/crisisDetectionRequests` 🔒
- `/crisisDetectionResults` 🔒
- `/dataExportRequests`
- `/datingProfiles`
- `/deletionAuditLog` 🔒
- `/deletionRequests`
- `/enforcementHistory` 🔒
- `/enforcement_actions` 🔒
- `/engagementEvents`
- `/evidencePreservation` 🔒
- `/fcmQueue`
- `/featureFlags`
- `/followRequests`
- `/mediaScanQueue` 🔒
- `/mediaSendEvents`
- `/mentorProfiles`
- `/mentorshipRelationships`
- `/moderationAppeals` 🔒
- `/moderationLogs` 🔒
- `/moderationRequests` 🔒
- `/moderationResults` 🔒
- `/moderation_ingest_events` 🔒
- `/moderation_jobs` 🔒
- `/moderatorAlerts`
- `/mutedUsers`
- `/noteSummaryRequests`
- `/noteSummaryResults`
- `/notificationDigests`
- `/notificationEngagement`
- `/notifications`
- `/onboardingFeedback`
- `/phoneAuthIPRateLimits`
- `/phoneAuthRateLimits`
- `/photoInsights`
- `/postEmbeddings`
- `/postInteractions`
- `/quarantinedContentHashes`
- `/quiet_blocks`
- `/rateLimits`
- `/repeated_contact_attempts`
- `/reports` 🔒
- `/reposts`
- `/safetyEvents` 🔒
- `/savedPosts`
- `/scheduled_posts`
- `/scriptureReferenceRequests`
- `/scriptureReferenceResults`
- `/searchIndex`
- `/securityEvents`
- `/suspiciousActivity`
- `/testimonies`
- `/toneAnalytics`
- `/trending`
- `/twoFactorOTP`
- `/twoFactorSessions`
- `/user`
- `/userChurchRelations`
- `/userFeedPrefs`
- `/userFeedSignals`
- `/user_backup_codes`
- `/user_privacy_settings`
- `/user_rate_limits`
- `/visit_plans`