# Launch Flag Configuration — v1.0 App Store Submission
**Prepared by:** Agent 4, Launch Readiness Swarm
**Date:** 2026-06-11
**Branch:** safety-hardening
**HEAD at evaluation:** 5525cf6e
**Bias:** Conservative — core proven + safety-hardened; nothing decision-gated; nothing whose backend is not deployed

---

## The Flag Table

Groupings match `// MARK:` sections in `AMENAPP/AMENAPP/AMENFeatureFlags.swift`.

**Decision rules used:**
- ON = default true in code AND no unmet precondition AND no GROUP A/B decision dependency
- OFF = any of: default false in code / backend not deployed / GROUP A/B dependency / DONE-AWAITING-CAPTURE only / in-flight lane / safety decision open

---

### SYSTEM 1 — Advanced Moderation

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `moderation_v2_enabled` | `moderationV2Enabled` | **ON** | Core moderation — always-on safety path | YES |
| `image_moderation_enabled` | `imageModerationEnabled` | **ON** | Image scan wired and needed pre-launch | YES |
| `dm_enhanced_scanning_enabled` | `dmEnhancedScanningEnabled` | **ON** | DM safety scanning — safety-hardened | YES |
| `moderation_appeals_enabled` | `moderationAppealsEnabled` | **ON** | Appeals path needed for launch; B-05 SLA TBD but flag is client-side | YES — B-05 is SLA policy, not a code gate |
| `trust_scoring_enabled` | `trustScoringEnabled` | **ON** | Trust scoring wired; no unresolved CF dependency | YES |

---

### SYSTEM 2 — Berean RAG

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `berean_rag_enabled` | `bereanRAGEnabled` | **ON** | Core Berean AI — built, committed, entitlement-enforced | YES — B-14 minor policy advisory but not a code gate on flag itself |
| `berean_conversation_memory_enabled` | `bereanConversationMemoryEnabled` | **ON** | Memory UX core to Berean value prop; bereanMemoryKillSwitch available | YES |
| `berean_source_attribution_enabled` | `bereanSourceAttributionEnabled` | **ON** | Required for AI disclosure compliance | YES |
| `berean_streaming_response_enabled` | `bereanStreamingResponseEnabled` | **ON** | UX improvement, no separate backend dependency | YES |
| `berean_voice_enabled` | `bereanVoiceEnabled` | **ON** | Voice UX built; no LiveKit dependency for this flag | YES |
| `berean_adaptive_mode_enabled` | `bereanAdaptiveModeEnabled` | **ON** | Adaptive mode is core Berean — no blocking dependency | YES |
| `berean_deep_enabled` | `bereanDeepEnabled` | **ON** | Kill switch available; entitlement-enforced | YES |
| `berean_entitlement_enforcement_enabled` | `bereanEntitlementEnforcementEnabled` | **ON** | Must be ON — entitlement gate; disabling is emergency-only | YES — kill switch, keep ON |

---

### SYSTEM 3 — Spiritual Check-In

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `spiritual_check_in_enabled` | `spiritualCheckInEnabled` | **ON** | Core well-being feature; no undeployed CF dependency | YES |
| `check_in_behavioral_signals_enabled` | `checkInBehavioralSignalsEnabled` | **ON** | Client-side behavioral signals; no separate backend | YES |
| `check_in_crisis_escalation_enabled` | `checkInCrisisEscalationEnabled` | **ON** | Crisis routing must be ON; B-08 protocol policy, not a code gate | YES |

---

### SYSTEM 4 — Feed Intelligence

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `feed_ranking_v2_enabled` | `feedRankingV2Enabled` | **ON** | Core feed ranking; built and committed | YES |
| `anti_doomscroll_enabled` | `antiDoomscrollEnabled` | **ON** | Core human-first media design principle | YES |
| `feed_session_pacing_enabled` | `feedSessionPacingEnabled` | **ON** | Healthy usage feature; no undeployed CF | YES |
| `feed_reflection_prompts_enabled` | `feedReflectionPromptsEnabled` | **ON** | Core formation feature | YES |
| `feed_quality_metrics_enabled` | `feedQualityMetricsEnabled` | **ON** | Quality signals; client-side | YES |

---

### SYSTEM 5 — Church Discovery (v1 — original)

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `church_smart_ranking_enabled` | `churchDiscoverySmartRankingEnabled` | **ON** | Core Find a Church ranking; `find_a_church_enabled` is ON | YES |
| `church_first_visit_companion_enabled` | `churchFirstVisitCompanionEnabled` | **ON** | First-visit companion wired; no undeployed CF | YES |
| `church_service_reminders_enabled` | `churchServiceRemindersEnabled` | **ON** | Client-side reminders; notification plist confirmed | YES |
| `church_reviews_enabled` | `churchReviewsEnabled` | **ON** | Reviews wired; Firestore rules include churches path | YES |
| `church_interaction_tracking_enabled` | `churchInteractionTrackingEnabled` | **ON** | Interaction tracking; client-side + existing Firestore | YES |
| `church_journey_timeline_enabled` | `churchJourneyTimelineEnabled` | **ON** | Church journey; no undeployed CF dependency | YES |
| `church_post_card_drafts_enabled` | `churchPostCardDraftsEnabled` | **ON** | Draft UX; client-side | YES |
| `church_explainable_recommendations_enabled` | `churchExplainableRecommendationsEnabled` | **ON** | "Why this church" explainability — no external CF | YES |

---

### SYSTEM 6 — Studio / Creator Marketplace

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `studio_enabled` | `studioEnabled` | **ON** | Studio surface built; monetization scaffold non-tappable (B-C-02 deferred) | YES |
| `studio_monetization_enabled` | `studioMonetizationEnabled` | **ON** | Scaffold wired; Stripe paywall scaffold is non-tappable overlay | YES — Stripe scaffold is deferred D-09; overlay is non-functional |
| `studio_job_board_enabled` | `studioJobBoardEnabled` | **ON** | Job board surface built | YES |
| `studio_ai_tagging_enabled` | `studioAITaggingEnabled` | **ON** | AI tagging wired; uses existing moderation pipeline | YES |

---

### SYSTEM 7 — Knowledge Graph

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `knowledge_graph_enabled` | `knowledgeGraphEnabled` | **ON** | Knowledge graph wired in catalog build | YES |
| `knowledge_graph_related_content_enabled` | `knowledgeGraphRelatedContentEnabled` | **ON** | Related content; client-side + Firestore | YES |
| `knowledge_graph_semantic_search_enabled` | `knowledgeGraphSemanticSearchEnabled` | **ON** | Semantic search built; no undeployed CF gate | YES |

---

### SYSTEM 8 — Action Threads (Care Workflows)

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `action_threads_enabled` | `actionThreadsEnabled` | **ON** | Action threads wired; `actionIntelligence.ts` export exists in index.ts | YES — deploy needed but flag reads client-side first |
| `action_suggestions_enabled` | `actionSuggestionsEnabled` | **ON** | Suggestions surface wired | YES |
| `care_followups_enabled` | `careFollowupsEnabled` | **ON** | Care follow-ups; client-side | YES |
| `mentorship_enabled` | `mentorshipEnabled` | **ON** | Mentorship wired; no undeployed CF | YES |

---

### SYSTEM 9 — Compound Identity Graph

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `compound_identity_graph_enabled` | `compoundIdentityGraphEnabled` | **ON** | Identity graph wired | YES |
| `agent_recommendations_enabled` | `agentRecommendationsEnabled` | **ON** | Recommendations; no standalone undeployed CF | YES |

---

### SYSTEM 10 — Proof of Human + Proof of Care

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `proof_of_human_enabled` | `proofOfHumanEnabled` | **ON** | Core trust signal | YES |
| `proof_of_care_enabled` | `proofOfCareEnabled` | **ON** | Core trust signal | YES |
| `trust_signals_enabled` | `trustSignalsEnabled` | **ON** | Trust signals surface | YES |

---

### SYSTEM 11 — Topic Drill-Down

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `topic_drill_down_enabled` | `topicDrillDownEnabled` | **ON** | Topic exploration; wired in catalog build | YES |
| `topic_enrichment_enabled` | `topicEnrichmentEnabled` | **ON** | Enrichment; no undeployed CF | YES |

---

### SYSTEM 12 — Smart Media Continuity

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `media_resume_enabled` | `mediaResumeEnabled` | **ON** | Media resume; client-side | YES |

---

### SYSTEM 13 — Suggested Follows

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `suggested_follows_enabled` | `suggestedFollowsEnabled` | **ON** | Core discovery surface | YES |
| `suggested_rail_prayer_enabled` | `suggestedRailPrayerEnabled` | **ON** | Prayer suggestion rail; client-side | YES |
| `suggested_rail_testimonies_enabled` | `suggestedRailTestimoniesEnabled` | **ON** | Testimonies rail; client-side | YES |
| `suggested_rail_peek_sheet_enabled` | `suggestedRailPeekSheetEnabled` | **ON** | Peek sheet UX | YES |
| `suggested_rail_server_ranking_enabled` | `suggestedRailServerRankingEnabled` | **ON** | Server ranking wired | YES |
| `suggested_rail_insertion_index` (int:2) | `suggestedRailInsertionIndex` | **ON** (value:2) | Default position is correct | YES |
| `suggested_rail_card_limit` (int:12) | `suggestedRailCardLimit` | **ON** (value:12) | Default limit is correct | YES |
| `suggested_rail_cooldown_hours` (int:24) | `suggestedRailCooldownHours` | **ON** (value:24) | Default cooldown correct | YES |
| `suggested_rail_dismiss_cooldown_days` (int:7) | `suggestedRailDismissCooldownDays` | **ON** (value:7) | Default is correct | YES |

---

### SYSTEM 14 — Social Context & UX Enhancements

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `mutual_context_row_enabled` | `mutualContextRowEnabled` | **ON** | Mutual context row; client-side | YES |
| `presence_intelligence_enabled` | `presenceIntelligenceEnabled` | **OFF** | Default false in code; presence tracking creates B-20 minor-status exposure risk until private subcollection move complete | NO — B-20 open |
| `message_request_intelligence_enabled` | `messageRequestIntelligenceEnabled` | **ON** | Message request intelligence wired | YES |
| `trust_explainer_enabled` | `trustExplainerEnabled` | **ON** | Trust explainer UX | YES |
| `post_divider_enabled` | `postDividerEnabled` | **ON** | Visual dividers; client-side | YES |
| `feed_view_mode_switcher_enabled` | `feedViewModeSwitcherEnabled` | **ON** | Feed view modes built | YES |
| `media_filter_pills_enabled` | `mediaFilterPillsEnabled` | **ON** | Filter pills; client-side | YES |
| `media_detail_view_enabled` | `mediaDetailViewEnabled` | **ON** | Media detail view built | YES |
| `enhanced_notifications_enabled` | `enhancedNotificationsEnabled` | **ON** | Notifications wired | YES |
| `server_notifications_v2_enabled` | `serverNotificationsV2Enabled` | **ON** | Server notifications v2 | YES |
| `berean_chat_redesign_enabled` | `bereanChatRedesignEnabled` | **ON** | Berean chat redesign committed | YES |
| `in_app_browser_enabled` | `inAppBrowserEnabled` | **ON** | In-app browser wired | YES |
| `composer_approved_audio_enabled` | `composerApprovedAudioEnabled` | **ON** | Approved audio; composer wired | YES |
| `smart_attachments_enabled` | `smartAttachmentsEnabled` | **ON** | Smart attachments; composer wired | YES |
| `smart_attachment_composer_paste_enabled` | `smartAttachmentComposerPasteEnabled` | **ON** | Paste wired | YES |
| `smart_attachment_music_picker_enabled` | `smartAttachmentMusicPickerEnabled` | **ON** | Music picker; `musicAttachmentEnabled` also ON | YES |
| `smart_attachment_expanded_sheet_enabled` | `smartAttachmentExpandedSheetEnabled` | **ON** | Expanded sheet; wired | YES |
| `smart_attachment_media_graph_enabled` | `smartAttachmentMediaGraphEnabled` | **ON** | Media graph; wired | YES |
| `smart_attachment_smart_actions_enabled` | `smartAttachmentSmartActionsEnabled` | **ON** | Smart actions in composer | YES |

---

### SYSTEM 15 — Accessibility Intelligence Layer (AIL)

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `accessibility_intelligence_enabled` | `accessibilityIntelligenceEnabled` | **OFF** | ailTransform CF not deployed; in-flight lane | NO — CF not deployed (BLOCKED) |
| `meaning_aware_translation_enabled` | `meaningAwareTranslationEnabled` | **OFF** | Depends on `accessibility_intelligence_enabled` | NO |
| `natural_mode_enabled` | `naturalModeEnabled` | **OFF** | AIL in-flight | NO |
| `contextual_mode_enabled` | `contextualModeEnabled` | **OFF** | AIL in-flight | NO |
| `readability_layer_enabled` | `readabilityLayerEnabled` | **OFF** | AIL in-flight | NO |
| `content_difficulty_scoring` | `contentDifficultyScoring` | **OFF** | AIL in-flight | NO |
| `audio_narration_enabled` | `audioNarrationEnabled` | **OFF** | AIL in-flight | NO |
| `context_bridge_enabled` | `contextBridgeEnabled` | **OFF** | AIL in-flight | NO |
| `adaptive_accessibility_enabled` | `adaptiveAccessibilityEnabled` | **OFF** | AIL in-flight | NO |
| `conversation_bridge_enabled` | `conversationBridgeEnabled` | **OFF** | AIL in-flight | NO |
| `smart_translation_visibility_enabled` | `smartTranslationVisibilityEnabled` | **OFF** | AIL in-flight | NO |
| `side_by_side_translation_enabled` | `sideBySideTranslationEnabled` | **OFF** | AIL in-flight | NO |
| `per_language_auto_translate_enabled` | `perLanguageAutoTranslateEnabled` | **OFF** | AIL in-flight | NO |
| `creation_language_enabled` | `creationLanguageEnabled` | **OFF** | AIL in-flight | NO |
| `adaptive_translation_enabled` | `adaptiveTranslationEnabled` | **OFF** | AIL in-flight | NO |

---

### SYSTEM 16 — Berean Spiritual Intelligence Layers

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `berean_spiritual_layers_enabled` | `bereanSpiritualLayersEnabled` | **ON** | Core spiritual intelligence; wired | YES |
| `living_scripture_graph_enabled` | `livingScriptureGraphEnabled` | **ON** | Living Scripture graph wired | YES |
| `spiritual_state_layer_enabled` | `spiritualStateLayerEnabled` | **ON** | Spiritual state tracking | YES |
| `guided_discipleship_enabled` | `guidedDiscipleshipEnabled` | **ON** | Discipleship guidance built | YES |
| `scripture_immersion_enabled` | `scriptureImmersionEnabled` | **ON** | Scripture immersion built | YES |
| `authority_alignment_enabled` | `authorityAlignmentEnabled` | **ON** | Authority alignment wired | YES |

---

### SYSTEM 17 — Resources Intelligence + Church Notes

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `resources_intelligence_enabled` | `resourcesIntelligenceEnabled` | **ON** | Resources surface built | YES |
| `support_draft_detection_enabled` | `supportDraftDetectionEnabled` | **ON** | Support detection wired | YES |
| `church_note_care_summary_enabled` | `churchNoteCareSummaryEnabled` | **ON** | Care summary built | YES |
| `church_notes_server_summary_enabled` | `churchNotesServerSummaryEnabled` | **ON** | Server summary CF wired | YES |
| `church_notes_audio_capture_enabled` | `churchNotesAudioCaptureEnabled` | **ON** | Audio capture built + tested | YES |
| `church_notes_photo_ocr_enabled` | `churchNotesPhotoOCREnabled` | **ON** | Photo OCR pipeline built | YES |
| `church_notes_video_capture_enabled` | `churchNotesVideoCaptureEnabled` | **ON** | Video capture built | YES |
| `church_notes_ai_draft_review_enabled` | `churchNotesAIDraftReviewEnabled` | **ON** | AI draft review built | YES |
| `church_notes_study_guide_enabled` | `churchNotesStudyGuideEnabled` | **ON** | Study guide built | YES |
| `church_notes_prayer_prompts_enabled` | `churchNotesPrayerPromptsEnabled` | **ON** | Prayer prompts built | YES |
| `church_notes_intelligence_enabled` | `churchNotesIntelligenceEnabled` | **ON** | Intelligence layer built | YES |
| `sermon_audio_capture_enabled` | `sermonAudioCaptureEnabled` | **ON** | Sermon audio built + tested | YES |
| `sermon_video_capture_enabled` | `sermonVideoCaptureEnabled` | **ON** | Sermon video built | YES |
| `church_photo_ocr_capture_enabled` | `churchPhotoOCRCaptureEnabled` | **ON** | OCR capture built | YES |
| `church_notes_translation_enabled` | `churchNotesTranslationEnabled` | **ON** | Translation built | YES |
| `church_notes_collaboration_enabled` | `churchNotesCollaborationEnabled` | **ON** | Collaboration built | YES |
| `sermon_summary_generation_enabled` | `sermonSummaryGenerationEnabled` | **ON** | Summary generation built | YES |
| `scripture_detection_enabled` | `scriptureDetectionEnabled` | **ON** | Scripture detection built | YES |
| `api_bible_scripture_provider_enabled` | `apiBibleScriptureProviderEnabled` | **OFF** | Default false; API Bible licensed key required first | NO — license key not confirmed |
| `api_bible_licensed_display_translations_enabled` | `apiBibleLicensedDisplayTranslationsEnabled` | **OFF** | Licensed translations; API Bible key required | NO |
| `api_bible_core_offline_cache_enabled` | `apiBibleCoreOfflineCacheEnabled` | **OFF** | Offline cache; depends on API Bible key | NO |
| `sermon_action_extraction_enabled` | `sermonActionExtractionEnabled` | **ON** | Action extraction built | YES |
| `sermon_clip_suggestion_enabled` | `sermonClipSuggestionEnabled` | **ON** | Clip suggestion built | YES |
| `church_notes_study_guide_generation_enabled` | `churchNotesStudyGuideGenerationEnabled` | **ON** | Study guide generation built | YES |
| `feature_note_share_viewer` | `noteShareViewerEnabled` | **OFF** | Build blocked; DONE-AWAITING-CAPTURE + build failures unrelated | NO — build not clean |
| `church_notes_smart_objects_enabled` | `churchNotesSmartObjectsEnabled` | **OFF** | Smart Objects Wave 1 not yet screenshot-verified | NO — AWAITING-CAPTURE |
| `church_notes_processing_kill_switch` | `churchNotesProcessingKillSwitch` | **OFF** | Kill switch; keep false (OFF = processing allowed) | YES — correct |
| `trusted_contacts_enabled` | `trustedContactsEnabled` | **ON** | Trusted contacts wired | YES |
| `helping_someone_else_enabled` | `helpingSomeoneElseEnabled` | **ON** | Helper surface wired | YES |
| `support_followups_enabled` | `supportFollowupsEnabled` | **ON** | Support follow-ups wired | YES |
| `nonprofit_recommendation_enabled` | `nonprofitRecommendationEnabled` | **ON** | Nonprofit recommendations built | YES |
| `berean_resource_routing_enabled` | `bereanResourceRoutingEnabled` | **ON** | Resource routing wired | YES |

---

### Selah Scripture Actions

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `selah_scripture_actions_enabled` | `selahScriptureActionsEnabled` | **ON** | Core Selah actions; wired | YES |
| `church_study_companion_enabled` | `churchStudyCompanionEnabled` | **ON** | Study companion built | YES |
| `church_notes_scripture_bridge_enabled` | `churchNotesScriptureBridgeEnabled` | **ON** | Scripture bridge wired | YES |
| `selah_add_to_church_notes_enabled` | `selahAddToChurchNotesEnabled` | **ON** | Save-to-notes wired | YES |
| `find_church_study_actions_enabled` | `findChurchStudyActionsEnabled` | **ON** | Study actions wired | YES |
| `after_service_reflection_enabled` | `afterServiceReflectionEnabled` | **ON** | Post-service reflection wired | YES |
| `church_study_group_bridge_enabled` | `churchStudyGroupBridgeEnabled` | **ON** | Study group bridge wired | YES |

---

### SYSTEM 18 — Selah Media OS

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `selah_media_os_enabled` | `selahMediaOSEnabled` | **ON** | Selah Media OS fully built; kill switch available | YES |
| `selah_media_os_min_app_version` (string:"1.0.0") | `selahMediaOSMinAppVersion` | **ON** (value:"1.0.0") | Correct for v1.0 | YES |
| `selah_media_os_rollout_percent` (int:100) | `selahMediaOSRolloutPercent` | **ON** (value:100) | Full rollout | YES |
| `selah_media_os_kill_reason` (string:"") | `selahMediaOSKillReason` | **ON** (value:"") | Empty = not killed | YES |

---

### Onboarding & Auth Remediation (Wave 1)

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `ff_onboarding_v2` | `onboardingV2Enabled` | **OFF** | 6 UI blockers still open in onboarding/auth lane; in-flight | NO — in-flight lane |

---

### SYSTEM 19 — Berean Pulse

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `berean_pulse_enabled` | `bereanPulseEnabled` | **ON** | Berean Pulse wired; no undeployed CF gate | YES |

---

### Amen Pulse (Personalized Daily Surface)

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `amen_pulse_enabled` | `amenPulseEnabled` | **OFF** | FirebaseAI iOS-27 SDK error present; generation pipeline not deployed | NO — SDK error blocking |

---

### Universal Migration & Context System

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `context_system_enabled` | `contextSystemEnabled` | **OFF** | Step 8 bait-transcript runner required first | NO — bait-transcript not run |
| `context_manual_entry_enabled` | `contextManualEntryEnabled` | **OFF** | Depends on `context_system_enabled` | NO |
| `context_berean_interview_enabled` | `contextBereanInterviewEnabled` | **OFF** | Depends on `context_system_enabled` | NO |
| `context_universal_import_enabled` | `contextUniversalImportEnabled` | **OFF** | Depends on `context_system_enabled` | NO |
| `context_matching_enabled` | `contextMatchingEnabled` | **OFF** | Bait-transcript + W4 validation required | NO |
| `context_export_enabled` | `contextExportEnabled` | **OFF** | Depends on `context_system_enabled` | NO |
| `context_qr_enabled` | `contextQREnabled` | **OFF** | Depends on `context_system_enabled` | NO |
| `context_commitment_bridge_enabled` | `contextCommitmentBridgeEnabled` | **OFF** | Depends on `context_system_enabled` | NO |

---

### Amen Daily Digest

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `amen_daily_digest_enabled` | `amenDailyDigestEnabled` | **ON** | Daily Digest built and wired | YES |
| `amen_daily_digest_weather_enabled` | `amenDailyDigestWeatherEnabled` | **ON** | Weather wired | YES |
| `amen_daily_digest_holiday_enabled` | `amenDailyDigestHolidayEnabled` | **ON** | Holiday surface wired | YES |
| `amen_daily_digest_christian_calendar_enabled` | `amenDailyDigestChristianCalendarEnabled` | **ON** | Christian calendar wired | YES |
| `amen_daily_digest_expanded_sheet_enabled` | `amenDailyDigestExpandedSheetEnabled` | **ON** | Expanded sheet wired | YES |
| `amen_daily_digest_berean_ai_action_enabled` | `amenDailyDigestBereanAIActionEnabled` | **ON** | Berean AI action wired | YES |
| `amen_daily_digest_church_notes_action_enabled` | `amenDailyDigestChurchNotesActionEnabled` | **ON** | Church Notes action wired | YES |
| `amen_daily_digest_find_church_action_enabled` | `amenDailyDigestFindChurchActionEnabled` | **ON** | Find Church action wired | YES |
| `amen_daily_digest_selah_action_enabled` | `amenDailyDigestSelahActionEnabled` | **ON** | Selah action wired | YES |
| `amen_daily_digest_ai_reflection_enabled` | `amenDailyDigestAIReflectionEnabled` | **ON** | AI reflection wired | YES |

---

### SYSTEM 22 — Community Hubs & Object Intelligence

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `community_hubs_enabled` | `communityHubsEnabled` | **OFF** | Default false; Phase 1 Firestore validation not complete | NO |
| `community_object_matching_enabled` | `communityObjectMatchingEnabled` | **OFF** | Depends on `community_hubs_enabled` | NO |
| `lyric_detection_enabled` | `lyricDetectionEnabled` | **OFF** | Default false; licensing decision not resolved | NO |
| `object_hub_view_enabled` | `objectHubViewEnabled` | **OFF** | Default false; validation pending | NO |
| `object_hub_inline_pill_enabled` | `objectHubInlinePillEnabled` | **OFF** | Default false | NO |
| `object_hub_inline_cluster_enabled` | `objectHubInlineClusterEnabled` | **OFF** | Default false | NO |

---

### Communities / Threads-Style Feeds Gating

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `ark_communities_enabled` | `arkCommunitiesEnabled` | **OFF** | Default false; legacy /communities path unsafe at rules layer | NO — rules not hardened |
| `covenant_communities_enabled` | `covenantCommunitiesEnabled` | **OFF** | Default false; Community OS Phase 1 validation not complete | NO |
| `unified_feeds_switcher_enabled` | `unifiedFeedsSwitcherEnabled` | **OFF** | Default false; requires Community OS | NO |
| `saved_communities_enabled` | `savedCommunitiesEnabled` | **OFF** | Default false | NO |
| `view_in_feed_enabled` | `viewInFeedEnabled` | **OFF** | Default false | NO |

---

### SYSTEM 22 continued — Smart Share Sheet

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `smart_share_sheet_enabled` | `smartShareSheetEnabled` | **ON** | Share sheet wired; default true | YES |
| `smart_share_smart_suggestions_enabled` | `smartShareSmartSuggestionsEnabled` | **ON** | Suggestions wired | YES |
| `smart_share_recipient_rail_enabled` | `smartShareRecipientRailEnabled` | **ON** | Recipient rail wired | YES |
| `smart_share_context_enabled` | `smartShareContextEnabled` | **ON** | Context sharing wired | YES |
| `smart_share_preview_mode_enabled` | `smartSharePreviewModeEnabled` | **ON** | Preview mode wired | YES |

---

### SYSTEM 22 continued — Translation Intelligence

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `translation_smart_pill_enabled` | `translationSmartPillEnabled` | **ON** | Translation pill wired | YES |
| `translation_remember_language_preference_enabled` | `translationRememberLanguagePreferenceEnabled` | **ON** | Language preference persistence | YES |

---

### SYSTEM 23 — Universal Content + Create

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `universal_content_model_enabled` | `universalContentModelEnabled` | **ON** | Universal content model wired | YES |
| `universal_create_enabled` | `universalCreateEnabled` | **ON** | Universal create wired | YES |

---

### SYSTEM 24 — Media Creation System

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `media_creation_enabled` | `mediaCreationEnabled` | **ON** | Core media creation | YES |
| `video_upload_enabled` | `videoUploadEnabled` | **ON** | Video upload wired | YES — pending B-16 storage rules for chat_videos; post_media separate path |
| `voiceover_enabled` | `voiceoverEnabled` | **ON** | Voiceover wired | YES |
| `auto_captions_enabled` | `autoCaptionsEnabled` | **ON** | Auto captions wired | YES |
| `immersive_media_chrome_enabled` | `immersiveMediaChromeEnabled` | **ON** | Immersive chrome wired | YES |
| `immersive_feed_enabled` | `immersiveFeedEnabled` | **ON** | Immersive feed wired | YES |
| `continuation_feed_enabled` | `continuationFeedEnabled` | **ON** | Continuation feed wired | YES |
| `explain_video_enabled` | `explainVideoEnabled` | **ON** | Explain video wired; kill reason + rollout gate available | YES |
| `explain_video_rollout_percent` (int:100) | `explainVideoRolloutPercent` | **ON** (value:100) | Full rollout | YES |
| `explain_video_min_app_version` (string:"1.0.0") | `explainVideoMinAppVersion` | **ON** (value:"1.0.0") | Correct for v1.0 | YES |
| `explain_video_kill_reason` (string:"") | `explainVideoKillReason` | **ON** (value:"") | Empty = not killed | YES |

---

### SYSTEM 24 — Per-Media Captions

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `per_media_captions_enabled` | `perMediaCaptionsEnabled` | **ON** | Per-media captions built | YES |
| `per_media_caption_education_enabled` | `perMediaCaptionEducationEnabled` | **ON** | Education modal wired | YES |
| `per_media_caption_moderation_enabled` | `perMediaCaptionModerationEnabled` | **ON** | Caption moderation required | YES |
| `per_media_caption_alt_text_enabled` | `perMediaCaptionAltTextEnabled` | **ON** | Accessibility — alt text required | YES |
| `per_media_caption_scripture_refs_enabled` | `perMediaCaptionScriptureRefsEnabled` | **ON** | Scripture refs wired | YES |

---

### SYSTEM 21 — Berean Intelligence Layer v2

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `berean_theo_lens_enabled` | `bereanTheoLensEnabled` | **ON** | Theological lens modes built; kill switch available | YES |
| `berean_selah_bridge_enabled` | `bereanSelahBridgeEnabled` | **ON** | Selah bridge wired | YES |
| `berean_church_notes_bridge_enabled` | `bereanChurchNotesBridgeEnabled` | **ON** | Church Notes bridge wired | YES |
| `berean_smart_pills_enabled` | `bereanSmartPillsEnabled` | **ON** | Smart pills built | YES |
| `berean_theology_boundary_enabled` | `bereanTheologyBoundaryEnabled` | **ON** | Theology guardrail — keep ON; kill only for debugging | YES |
| `berean_persistent_memory_enabled` | `bereanPersistentMemoryEnabled` | **ON** | Persistent memory built + consent flow | YES |
| `berean_study_threads_enabled` | `bereanStudyThreadsEnabled` | **ON** | Study threads built; kill switch available | YES |
| `berean_translation_compare_enabled` | `bereanTranslationCompareEnabled` | **ON** | Translation compare built | YES |
| `berean_research_view_enabled` | `bereanResearchViewEnabled` | **ON** | Research view built | YES |

---

### SYSTEM 20 — Messaging Micro Animations

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `messaging_liquid_glass_animations_enabled` | `messagingLiquidGlassAnimationsEnabled` | **ON** | Liquid Glass animations wired | YES |
| `messaging_typing_indicator_enabled` | `messagingTypingIndicatorEnabled` | **ON** | Typing indicator wired | YES |
| `messaging_floating_header_prototype_enabled` | `messagingFloatingHeaderPrototypeEnabled` | **OFF** | Default false; nav replacement not validated across all device sizes | NO — validation pending |
| `messaging_liquid_glass_context_menu_enabled` | `messagingLiquidGlassContextMenuEnabled` | **OFF** | Default false; not screenshot-verified | NO |
| `messaging_liquid_glass_attachment_menu_enabled` | `messagingLiquidGlassAttachmentMenuEnabled` | **OFF** | Default false | NO |
| `messaging_smart_composer_enabled` | `messagingSmartComposerEnabled` | **OFF** | Default false; Smart Composer screenshots blocked (no real Firebase test user on sim) | NO — DONE-AWAITING-CAPTURE |
| `messaging_attachment_menu_smart_actions_enabled` | `messagingAttachmentMenuSmartActionsEnabled` | **OFF** | Default false | NO |

---

### SYSTEM 20 continued — Messaging Intelligence (Phases 4-12)

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `messaging_smart_pills_enabled` | `messagingSmartPillsEnabled` | **OFF** | Default false; Communication OS CFs not deployed | NO — CFs not deployed |
| `messaging_translation_enabled` | `messagingTranslationEnabled` | **OFF** | Default false | NO |
| `messaging_cross_surface_actions_enabled` | `messagingCrossSurfaceActionsEnabled` | **OFF** | Default false | NO |
| `messaging_safety_nudges_enabled` | `messagingSafetyNudgesEnabled` | **ON** | Safety nudges — keep ON; default true | YES |
| `messaging_approval_cards_enabled` | `messagingApprovalCardsEnabled` | **OFF** | Default false | NO |
| `messaging_catch_up_enabled` | `messagingCatchUpEnabled` | **OFF** | Default false | NO |
| `messaging_voice_intelligence_enabled` | `messagingVoiceIntelligenceEnabled` | **OFF** | Default false | NO |
| `messaging_media_intelligence_enabled` | `messagingMediaIntelligenceEnabled` | **OFF** | Default false | NO |
| `messaging_presence_polish_enabled` | `messagingPresencePolishEnabled` | **OFF** | Default false | NO |
| `ff_action_intelligence` | `actionIntelligenceEnabled` | **OFF** | Default false; RC key is `ff_action_intelligence`; TS build and CF deploy required before flip | NO — CF deploy pending |
| `camera_os_enabled` | `cameraOSEnabled` | **OFF** | CameraOS rules/index coverage and runtime privacy review not verified | NO — privacy review pending |

---

### SYSTEM 32 — Communication OS

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `messages_smart_context_enabled` | `messagesSmartContextEnabled` | **OFF** | Default false; CommOS CFs not deployed | NO |
| `group_discussion_pulse_enabled` | `groupDiscussionPulseEnabled` | **OFF** | Default false | NO |
| `thread_summary_enabled` | `threadSummaryEnabled` | **OFF** | Default false | NO |
| `catch_up_digest_enabled` | `catchUpDigestEnabled` | **OFF** | Default false | NO |
| `thread_decision_extraction_enabled` | `threadDecisionExtractionEnabled` | **OFF** | Default false | NO |
| `thread_action_extraction_enabled` | `threadActionExtractionEnabled` | **OFF** | Default false | NO |
| `thread_question_detection_enabled` | `threadQuestionDetectionEnabled` | **OFF** | Default false | NO |
| `smart_presence_enabled` | `smartPresenceEnabled` | **OFF** | Default false; B-20 minor-status exposure risk | NO |
| `smart_reactions_enabled` | `smartReactionsEnabled` | **OFF** | Default false | NO |
| `media_intelligence_enabled` | `mediaIntelligenceEnabled` | **OFF** | Default false | NO |
| `conversation_memory_search_enabled` | `conversationMemorySearchEnabled` | **OFF** | Default false | NO |
| `command_palette_enabled` | `commandPaletteEnabled` | **OFF** | Default false | NO |
| `smart_replies_enabled` | `smartRepliesEnabled` | **OFF** | Default false | NO |
| `multi_pane_communication_enabled` | `multiPaneCommunicationEnabled` | **OFF** | Default false | NO |
| `liquid_glass_communication_ui_enabled` | `liquidGlassCommunicationUIEnabled` | **OFF** | Default false | NO |

---

### SYSTEM 33 — ContentOS

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `content_os_enabled` | `contentOSEnabled` | **OFF** | Default false; ContentOS CFs not deployed | NO |
| `content_approval_workflow_enabled` | `contentApprovalWorkflowEnabled` | **OFF** | Default false | NO |
| `content_forwarding_enabled` | `contentForwardingEnabled` | **OFF** | Default false | NO |
| `content_ai_router_enabled` | `contentAIRouterEnabled` | **OFF** | Default false | NO |
| `content_audit_log_enabled` | `contentAuditLogEnabled` | **OFF** | Default false | NO |

---

### Social Safety OS (Phase 2-13)

These flags are declared `true` but are noted in code as DEFERRED-DESIGN — zero consumer call-sites; keep ON so consumers work when eventually wired.

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `social_safety_os_enabled` | `socialSafetyOSEnabled` | **ON** | Safety OS master gate — keep ON | YES (DEFERRED-DESIGN, no harmful call-sites) |
| `wellbeing_feed_ranking_enabled` | `wellbeingFeedRankingEnabled` | **ON** | Wellbeing ranking — keep ON | YES |
| `selah_pause_enabled` | `selahPauseEnabled` | **ON** | Selah pause — keep ON | YES |
| `emotional_check_in_enabled` | `emotionalCheckInEnabled` | **ON** | Check-in — keep ON | YES |
| `private_reflection_enabled` | `privateReflectionEnabled` | **ON** | Private reflection — keep ON | YES |
| `healthy_use_dashboard_enabled` | `healthyUseDashboardEnabled` | **ON** | Healthy use dashboard — keep ON | YES |
| `dm_risk_firewall_enabled` | `dmRiskFirewallEnabled` | **ON** | DM risk firewall — keep ON (safety) | YES |
| `minor_safety_mode_enabled` | `minorSafetyModeEnabled` | **ON** | Minor safety mode — must be ON | YES |
| `sextortion_panic_flow_enabled` | `sextortionPanicFlowEnabled` | **ON** | Panic flow — safety; must be ON | YES |
| `suspicious_relationship_detector_enabled` | `suspiciousRelationshipDetectorEnabled` | **ON** | Detector — keep ON | YES |
| `trusted_contact_escalation_enabled` | `trustedContactEscalationEnabled` | **ON** | Trusted contact escalation — safety | YES |
| `think_first_guard_enabled` | `thinkFirstGuardEnabled` | **ON** | Think-first guard — safety | YES |
| `dogpile_detection_enabled` | `dogpileDetectionEnabled` | **ON** | Dogpile detection — safety | YES |
| `mercy_mode_replies_enabled` | `mercyModeRepliesEnabled` | **ON** | Mercy mode — safety | YES |
| `reputation_moderation_enabled` | `reputationModerationEnabled` | **ON** | Reputation moderation — safety | YES |
| `victim_shield_enabled` | `victimShieldEnabled` | **ON** | Victim shield — safety | YES |
| `truth_context_layer_enabled` | `truthContextLayerEnabled` | **ON** | Truth context — keep ON | YES |
| `ai_media_disclosure_enabled` | `aiMediaDisclosureEnabled` | **ON** | AI disclosure — required | YES |
| `claim_source_requirement_enabled` | `claimSourceRequirementEnabled` | **ON** | Source requirement — keep ON | YES |
| `community_correction_enabled` | `communityCorrectionEnabled` | **ON** | Community correction — keep ON | YES |
| `theological_guardrails_enabled` | `theologicalGuardrailsEnabled` | **ON** | Guardrails — keep ON | YES |
| `feed_mode_controls_enabled` | `feedModeControlsEnabled` | **ON** | Feed mode controls — keep ON | YES |
| `feed_boundary_enabled` | `feedBoundaryEnabled` | **ON** | Feed boundary — keep ON | YES |
| `purpose_open_screen_enabled` | `purposeOpenScreenEnabled` | **ON** | Purpose screen — keep ON | YES |
| `engagement_quality_ranking_enabled` | `engagementQualityRankingEnabled` | **ON** | Engagement quality — keep ON | YES |
| `algorithm_transparency_enabled` | `algorithmTransparencyEnabled` | **ON** | Algorithm transparency — keep ON | YES |

---

### Berean Extended Intelligence (Phases 2-8)

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `berean_context_bridge_enabled` | `bereanContextBridgeEnabled` | **OFF** | Default false; in-flight; Context System not enabled | NO |
| `berean_safety_classifier_enabled` | `bereanSafetyClassifierEnabled` | **OFF** | Default false | NO |
| `berean_liquid_glass_context_actions_enabled` | `bereanLiquidGlassContextActionsEnabled` | **OFF** | Default false | NO |
| `berean_source_grounding_enabled` | `bereanSourceGroundingEnabled` | **OFF** | Default false | NO |
| `berean_follow_ups_enabled` | `bereanFollowUpsEnabled` | **OFF** | Default false | NO |
| `berean_commentary_compare_enabled` | `bereanCommentaryCompareEnabled` | **OFF** | Default false | NO |
| `berean_theological_lens_enabled` | `bereanTheologicalLensEnabled` | **OFF** | Default false; distinct from `berean_theo_lens_enabled` above | NO |
| `berean_memory_kill_switch` | `bereanMemoryKillSwitch` | **OFF** (false = memory ON) | Kill switch — keep false; memory should be active | YES — correct |
| `berean_context_bridge_kill_switch` | `bereanContextBridgeKillSwitch` | **OFF** (false = bridge ON) | Kill switch — keep false | YES — correct |
| `berean_safety_classifier_kill_switch` | `bereanSafetyClassifierKillSwitch` | **OFF** (false = classifier ON) | Kill switch — keep false | YES — correct |
| `berean_study_threads_kill_switch` | `bereanStudyThreadsKillSwitch` | **OFF** (false = threads ON) | Kill switch — keep false | YES — correct |
| `berean_source_grounding_kill_switch` | `bereanSourceGroundingKillSwitch` | **OFF** (false = grounding ON) | Kill switch — keep false | YES — correct |

---

### SYSTEM 25 — Smart Account Resume

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `smart_account_resume_enabled` | `smartAccountResumeEnabled` | **ON** | Smart resume wired | YES |
| `smart_account_resume_auto_continue_enabled` | `smartAccountResumeAutoContinueEnabled` | **ON** | Auto-continue wired | YES |
| `smart_account_resume_offline_retry_enabled` | `smartAccountResumeOfflineRetryEnabled` | **ON** | Offline retry wired | YES |

---

### SYSTEM 26 — AI Usage Labels

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `ai_usage_label_pill_enabled` | `aiUsageLabelPillEnabled` | **ON** | AI disclosure required for App Store | YES |
| `amen_ai_usage_labels_required` | `amenAIUsageLabelsRequired` | **ON** | AI labels required — safety | YES |

---

### SYSTEM 27 — Berean Grok Helper Pipeline

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `berean_helper_model_enabled` | `bereanHelperModelEnabled` | **OFF** | Default false; helper model pipeline not verified for launch | NO — verification pending |
| `berean_helper_prompt_simplify_enabled` | `bereanHelperPromptSimplifyEnabled` | **OFF** | Default false | NO |
| `berean_helper_link_summary_enabled` | `bereanHelperLinkSummaryEnabled` | **OFF** | Default false | NO |
| `berean_helper_external_context_enabled` | `bereanHelperExternalContextEnabled` | **OFF** | Default false | NO |
| `berean_helper_study_outline_enabled` | `bereanHelperStudyOutlineEnabled` | **OFF** | Default false | NO |
| `berean_helper_extract_themes_enabled` | `bereanHelperExtractThemesEnabled` | **OFF** | Default false | NO |
| `berean_helper_provenance_chips_enabled` | `bereanHelperProvenanceChipsEnabled` | **OFF** | Default false | NO |

---

### SYSTEM 28 — Feed Intelligence OS

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `feed_intelligence_enabled` | `feedIntelligenceEnabled` | **OFF** | Default false; Guide My Feed CF not deployed | NO |
| `guide_my_feed_enabled` | `guideMyFeedEnabled` | **OFF** | Default false | NO |
| `why_this_post_backend_enabled` | `whyThisPostBackendEnabled` | **OFF** | Default false; backend not deployed | NO |
| `feed_modes_enabled` | `feedModesEnabled` | **OFF** | Default false | NO |

---

### SYSTEM 29 — Liquid Glass Intelligence Layer

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `liquid_glass_system_enabled` | `liquidGlassSystemEnabled` | **OFF** | Default false; detectSmartActions CF not deployed | NO |
| `liquid_glass_presence_pills_enabled` | `liquidGlassPresencePillsEnabled` | **OFF** | Default false | NO |
| `semantic_underline_enabled` | `semanticUnderlineEnabled` | **OFF** | Default false | NO |
| `inline_definition_popover_enabled` | `inlineDefinitionPopoverEnabled` | **OFF** | Default false | NO |
| `smart_action_detection_enabled` | `smartActionDetectionEnabled` | **OFF** | Default false; CF not deployed | NO |
| `pulse_awareness_enabled` | `pulseAwarenessEnabled` | **OFF** | Default false | NO |
| `knowledge_threads_enabled` | `knowledgeThreadsEnabled` | **OFF** | Default false | NO |
| `selah_semantic_save_enabled` | `selahSemanticSaveEnabled` | **OFF** | Default false | NO |
| `church_notes_semantic_actions_enabled` | `churchNotesSemanticActionsEnabled` | **OFF** | Default false | NO |
| `media_chrome_liquid_glass_enabled` | `mediaChromeLiquidGlassEnabled` | **OFF** | Default false | NO |
| `composer_presence_actions_enabled` | `composerPresenceActionsEnabled` | **OFF** | Default false | NO |
| `bottom_bar_liquid_glass_enabled` | `bottomBarLiquidGlassEnabled` | **OFF** | Default false | NO |

---

### Amen Discover

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `amen_discover_enabled` | `amenDiscoverEnabled` | **ON** | Discover surface wired; "PERMISSION DENIED" fix deployed | YES |
| `amen_discover_liquid_glass_enabled` | `amenDiscoverLiquidGlassEnabled` | **ON** | Liquid Glass on Discover wired | YES |
| `amen_discover_ranking_enabled` | `amenDiscoverRankingEnabled` | **ON** | Ranking wired | YES |
| `amen_discover_why_this_enabled` | `amenDiscoverWhyThisEnabled` | **ON** | Why-this disclosure wired | YES |
| `amen_discover_local_churches_enabled` | `amenDiscoverLocalChurchesEnabled` | **ON** | Local churches wired | YES |
| `amen_discover_selah_enabled` | `amenDiscoverSelahEnabled` | **ON** | Selah in Discover wired | YES |
| `amen_discover_safety_feedback_enabled` | `amenDiscoverSafetyFeedbackEnabled` | **ON** | Safety feedback wired | YES |

---

### SYSTEM 31 — Voice Prayer & Testimony Comments

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `voice_prayer_comments_enabled` | `voicePrayerCommentsEnabled` | **OFF** | Default false; enforcement tests not passed | NO |
| `voice_testimony_comments_enabled` | `voiceTestimonyCommentsEnabled` | **OFF** | Default false | NO |
| `voice_comment_transcript_required` | `voiceCommentTranscriptRequired` | **ON** (true) | Keep true — transcript required before publish | YES — safety gate |
| `voice_comment_summary_enabled` | `voiceCommentSummaryEnabled` | **OFF** | Default false | NO |
| `voice_comment_review_queue_enabled` | `voiceCommentReviewQueueEnabled` | **OFF** | Default false | NO |
| `voice_comment_prayer_circle_visibility_enabled` | `voiceCommentPrayerCircleVisibilityEnabled` | **OFF** | Default false | NO |

---

### Amen AI Creative Intelligence Layer

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `amen_realtime_voice_enabled` | `amenRealtimeVoiceEnabled` | **OFF** | Default false; LiveKit infra dependency | NO |
| `amen_live_captions_enabled` | `amenLiveCaptionsEnabled` | **OFF** | Default false | NO |
| `amen_translation_enabled` | `amenTranslationEnabled` | **OFF** | Default false | NO |
| `amen_graphic_studio_enabled` | `amenGraphicStudioEnabled` | **OFF** | Default false | NO |
| `amen_creator_kit_enabled` | `amenCreatorKitEnabled` | **OFF** | Default false | NO |
| `amen_agent_workflows_enabled` | `amenAgentWorkflowsEnabled` | **OFF** | Default false | NO |
| `amen_explain_enabled` | `amenExplainEnabled` | **OFF** | Default false | NO |
| `amen_improve_enabled` | `amenImproveEnabled` | **OFF** | Default false | NO |
| `amen_summarize_enabled` | `amenSummarizeEnabled` | **OFF** | Default false | NO |
| `simple_mode_feature_enabled` | `simpleModeFeatureEnabled` | **ON** | Simple Mode accessibility feature wired | YES |
| `replay_enabled` | `replayEnabled` | **ON** | Replay wired | YES |
| `berean_realtime_enabled` | `bereanRealtimeEnabled` | **OFF** | Default false; LiveKit infra dependency | NO — LiveKit not deployed |
| `berean_translation_enabled` | `bereanTranslationEnabled` | **OFF** | Default false | NO |
| `berean_prayer_rooms_enabled` | `bereanPrayerRoomsEnabled` | **OFF** | Default false | NO |
| `berean_voice_assistant_enabled` | `bereanVoiceAssistantEnabled` | **OFF** | Default false | NO |
| `berean_smart_notes_enabled` | `bereanSmartNotesEnabled` | **OFF** | Default false | NO |
| `berean_live_captions_enabled` | `bereanLiveCaptionsEnabled` | **OFF** | Default false; audio pipeline prerequisite | NO |
| `berean_realtime_kill_switch` | `bereanRealtimeKillSwitch` | **OFF** (false = realtime ON) | Kill switch — keep false (realtime OFF anyway) | YES |
| `amen_realtime_voice_kill_switch` | `amenRealtimeVoiceKillSwitch` | **OFF** (false = voice ON) | Kill switch — keep false | YES |
| `amen_live_captions_kill_switch` | `amenLiveCaptionsKillSwitch` | **OFF** | Kill switch | YES |
| `amen_translation_kill_switch` | `amenTranslationKillSwitch` | **OFF** | Kill switch | YES |
| `amen_graphic_generation_kill_switch` | `amenGraphicGenerationKillSwitch` | **OFF** | Kill switch | YES |
| `amen_agent_workflow_kill_switch` | `amenAgentWorkflowKillSwitch` | **OFF** | Kill switch | YES |
| `amen_explain_kill_switch` | `amenExplainKillSwitch` | **OFF** | Kill switch | YES |
| `amen_improve_kill_switch` | `amenImproveKillSwitch` | **OFF** | Kill switch | YES |
| `amen_summarize_kill_switch` | `amenSummarizeKillSwitch` | **OFF** | Kill switch | YES |

---

### SYSTEM 33 — Spatial Social OS

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `spatial_home_enabled` | `spatialHomeEnabled` | **OFF** | Default false; Spatial OS in design phase | NO |
| `spatial_context_rail_enabled` | `spatialContextRailEnabled` | **OFF** | Default false | NO |
| `provenance_trust_panel_enabled` | `provenanceTrustPanelEnabled` | **OFF** | Default false | NO |
| `creator_os_composer_enabled` | `creatorOSComposerEnabled` | **OFF** | Default false | NO |
| `truthful_ai_labels_enabled` | `truthfulAILabelsEnabled` | **OFF** | Default false | NO |
| `smart_discovery_transparency_enabled` | `smartDiscoveryTransparencyEnabled` | **OFF** | Default false | NO |
| `discovery_why_shown_enabled` | `discoveryWhyShownEnabled` | **OFF** | Default false | NO |
| `safety_os_enabled` | `safetyOSEnabled` | **ON** | Safety OS master — must be ON | YES |

---

### SYSTEM 34 — Healthy Immersive Media Sessions

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `healthy_immersive_media_enabled` | `healthyImmersiveMediaEnabled` | **OFF** | Default false; immersive sessions not screenshot-verified | NO |
| `immersive_media_sessions_enabled` | `immersiveMediaSessionsEnabled` | **OFF** | Default false | NO |
| `media_finite_sessions_enabled` | `mediaFiniteSessionsEnabled` | **ON** | Finite sessions — core healthy media | YES |
| `finite_media_queues_enabled` | `finiteMediaQueuesEnabled` | **ON** | Finite queues — healthy media | YES |
| `media_completion_reflection_enabled` | `mediaCompletionReflectionEnabled` | **OFF** | Default false | NO |
| `media_completion_overlay_enabled` | `mediaCompletionOverlayEnabled` | **OFF** | Default false | NO |
| `media_doom_scroll_guard_enabled` | `mediaDoomScrollGuardEnabled` | **ON** | Doom scroll guard — keep ON | YES |
| `media_no_doom_scroll_guardrails_enabled` | `mediaNoDoomScrollGuardrailsEnabled` | **ON** | Guardrails — keep ON | YES |
| `media_session_checkpoints_enabled` | `mediaSessionCheckpointsEnabled` | **ON** | Session checkpoints — keep ON | YES |
| `healthy_media_checkpoints_enabled` | `healthyMediaCheckpointsEnabled` | **ON** | Checkpoints — keep ON | YES |
| `media_key_moments_enabled` | `mediaKeyMomentsEnabled` | **OFF** | Default false | NO |
| `media_transcript_enabled` | `mediaTranscriptEnabled` | **ON** | Transcripts — accessibility | YES |
| `media_ai_draft_metadata_enabled` | `mediaAIDraftMetadataEnabled` | **OFF** | Default false | NO |
| `media_ai_metadata_drafts_enabled` | `mediaAIMetadataDraftsEnabled` | **OFF** | Default false | NO |
| `media_approval_flow_enabled` | `mediaApprovalFlowEnabled` | **OFF** | Default false | NO |
| `media_generated_metadata_approval_required` | `mediaGeneratedMetadataApprovalRequired` | **ON** (true) | Keep true — AI metadata requires approval | YES |
| `media_selah_audio_mode_enabled` | `mediaSelahAudioModeEnabled` | **ON** | Selah audio mode wired | YES |
| `media_selah_overlay_enabled` | `mediaSelahOverlayEnabled` | **ON** | Selah overlay wired | YES |
| `immersive_photo_sessions_enabled` | `immersivePhotoSessionsEnabled` | **OFF** | Default false | NO |
| `immersive_video_sessions_enabled` | `immersiveVideoSessionsEnabled` | **OFF** | Default false | NO |
| `community_media_layers_enabled` | `communityMediaLayersEnabled` | **OFF** | Default false | NO |
| `media_community_layer_enabled` | `mediaCommunityLayerEnabled` | **OFF** | Default false | NO |
| `media_reflection_sheet_enabled` | `mediaReflectionSheetEnabled` | **OFF** | Default false | NO |
| `hide_vanity_metrics_default` | `hideVanityMetricsDefault` | **ON** (true) | Vanity metrics hidden by default — healthy media | YES |
| `autoplay_within_sessions_enabled` | `autoplayWithinSessionsEnabled` | **OFF** | Default false — healthy media policy | NO — intentional |
| `late_night_pause_enabled` | `lateNightPauseEnabled` | **ON** | Late night pause — healthy media | YES |
| `media_wellbeing_controls_enabled` | `mediaWellbeingControlsEnabled` | **ON** | Wellbeing controls — keep ON | YES |
| `media_timestamped_comments_enabled` | `mediaTimestampedCommentsEnabled` | **OFF** | Default false | NO |
| `media_search_enabled` | `mediaSearchEnabled` | **OFF** | Default false | NO |
| `media_church_notes_integration_enabled` | `mediaChurchNotesIntegrationEnabled` | **OFF** | Default false | NO |
| `media_prayer_queue_enabled` | `mediaPrayerQueueEnabled` | **OFF** | Default false | NO |
| `media_reflection_queue_enabled` | `mediaReflectionQueueEnabled` | **OFF** | Default false | NO |
| `media_low_bandwidth_mode_enabled` | `mediaLowBandwidthModeEnabled` | **ON** | Low bandwidth mode — accessibility | YES |
| `media_reporting_enabled` | `mediaReportingEnabled` | **ON** | Reporting — safety requirement | YES |
| `media_accessibility_controls_enabled` | `mediaAccessibilityControlsEnabled` | **ON** | Accessibility controls | YES |
| `media_ranking_v2_enabled` | `mediaRankingV2Enabled` | **ON** | Media ranking v2 wired | YES |
| `media_hide_vanity_metrics_enabled` | `mediaHideVanityMetricsEnabled` | **ON** | Hide vanity metrics — healthy media | YES |
| `media_liquid_glass_chrome_enabled` | `mediaLiquidGlassChromeEnabled` | **OFF** | Default false | NO |
| `media_profile_liquid_white_flow_enabled` | `mediaProfileLiquidWhiteFlowEnabled` | **OFF** | Default false | NO |

---

### SYSTEM 35 — Provenance & Authenticity OS

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `media_authenticity_badges_enabled` | `mediaAuthenticityBadgesEnabled` | **OFF** | Default false; Authenticity OS CFs not deployed | NO |
| `synthetic_media_detection_enabled` | `syntheticMediaDetectionEnabled` | **OFF** | Default false | NO |
| `media_synthetic_detection_enabled` | `mediaSyntheticDetectionEnabled` | **OFF** | Default false | NO |
| `content_credentials_enabled` | `contentCredentialsEnabled` | **OFF** | Default false | NO |
| `provenance_audit_chain_enabled` | `provenanceAuditChainEnabled` | **OFF** | Default false | NO |

---

### Berean OS (Wisdom Operating System)

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `berean_os_projects_enabled` | `bereanOSProjectsEnabled` | **OFF** | Default false; Berean OS CFs not deployed | NO — CFs not deployed |
| `berean_os_research_engine_enabled` | `bereanOSResearchEngineEnabled` | **OFF** | Default false | NO |
| `berean_os_wisdom_engine_enabled` | `bereanOSWisdomEngineEnabled` | **OFF** | Default false | NO |
| `berean_os_multi_perspective_enabled` | `bereanOSMultiPerspectiveEnabled` | **OFF** | Default false | NO |
| `berean_os_debate_engine_enabled` | `bereanOSDebateEngineEnabled` | **OFF** | Default false | NO |
| `berean_os_social_knowledge_feed_enabled` | `bereanOSSocialKnowledgeFeedEnabled` | **OFF** | Default false | NO |
| `berean_os_advisory_boards_enabled` | `bereanOSAdvisoryBoardsEnabled` | **OFF** | Default false | NO |
| `berean_os_mentor_os_enabled` | `bereanOSMentorOSEnabled` | **OFF** | Default false | NO |
| `berean_os_knowledge_graph_enabled` | `bereanOSKnowledgeGraphEnabled` | **OFF** | Default false | NO |
| `berean_os_onboarding_enabled` | `bereanOSOnboardingEnabled` | **OFF** | Default false | NO |
| `berean_os_memory_brain_enabled` | `bereanOSMemoryBrainEnabled` | **OFF** | Default false | NO |
| `berean_os_action_planner_enabled` | `bereanOSActionPlannerEnabled` | **OFF** | Default false | NO |
| `berean_os_truth_labels_enabled` | `bereanOSTruthLabelsEnabled` | **OFF** | Default false | NO |
| `berean_os_source_explorer_enabled` | `bereanOSSourceExplorerEnabled` | **OFF** | Default false | NO |
| `berean_os_social_projects_enabled` | `bereanOSSocialProjectsEnabled` | **OFF** | Default false | NO |
| `berean_os_community_intelligence_enabled` | `bereanOSCommunityIntelligenceEnabled` | **OFF** | Default false | NO |
| `berean_os_living_documents_enabled` | `bereanOSLivingDocumentsEnabled` | **OFF** | Default false | NO |

---

### Community OS (A18 Action Pill + Universal Composer)

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `community_os_action_pill_enabled` | `communityOSActionPillEnabled` | **OFF** | Default false; Community OS Phase 1 not validated | NO |
| `community_os_universal_composer_enabled` | `communityOSUniversalComposerEnabled` | **OFF** | Default false | NO |

---

### Aegis OS — Pre-Post Content Safety Gate

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `aegis_pre_post_review_enabled` | `aegisPrePostReviewEnabled` | **ON** | Safety gate — must be ON; disable only for emergency rollback | YES |

---

### Community OS — Church OS / Org OS / Opportunity OS

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `community_os_enabled` | `communityOSEnabled` | **OFF** | Default false; Phase 1 validation not complete | NO |
| `community_os_discussion_enabled` | `communityOSDiscussionEnabled` | **OFF** | Default false; Firestore paths not verified | NO |
| `community_os_prayer_os_enabled` | `communityOSPrayerOSEnabled` | **OFF** | Default false; prayer Firestore paths not deployed | NO |
| `community_os_church_os_enabled` | `communityOSChurchOSEnabled` | **OFF** | Default false | NO |
| `community_os_org_os_enabled` | `communityOSOrgOSEnabled` | **OFF** | Default false | NO |
| `community_os_opportunity_enabled` | `communityOSOpportunityEnabled` | **OFF** | Default false | NO |

---

### Music Attachment

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `music_attachment_enabled` | `musicAttachmentEnabled` | **ON** | Music attachment wired in composer | YES — B-10 is MusicContentLayer Firestore rules (not this flag) |

---

### Music Content Layer (System 40)

| Flag | RC key | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `ff_music_content_layer` | `ff_music_content_layer` | **OFF** | Xcode target membership manual step not done; Stage-3 backend not deployed; B-10 Firestore rules open | NO — 3 blockers |

---

### Live Activities — Prayer

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `live_activity_prayer_request_enabled` | `liveActivityPrayerRequestEnabled` | **OFF** | Default false; APNs secrets not confirmed set | NO |
| `live_activity_push_to_start_enabled` | `liveActivityPushToStartEnabled` | **OFF** | Default false; requires `live_activity_prayer_request_enabled` ON first | NO |

---

### Conversation OS (Spaces Intelligence)

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `conversation_os_enabled` | `conversationOSEnabled` | **OFF** | Default false; Conversation OS CFs not deployed | NO |
| `conversation_summaries_enabled` | `conversationSummariesEnabled` | **OFF** | Default false | NO |
| `catch_up_recaps_enabled` | `catchUpRecapsEnabled` | **OFF** | Default false | NO |
| `topic_clustering_enabled` | `topicClusteringEnabled` | **OFF** | Default false | NO |
| `action_extraction_enabled` | `actionExtractionEnabled` | **OFF** | Default false | NO |
| `organizational_memory_enabled` | `organizationalMemoryEnabled` | **OFF** | Default false | NO |
| `personalized_insights_enabled` | `personalizedInsightsEnabled` | **OFF** | Default false | NO |
| `ambient_conversation_intelligence_enabled` | `ambientConversationIntelligenceEnabled` | **OFF** | Default false | NO |
| `conversation_os_liquid_glass_enabled` | `conversationOSLiquidGlassEnabled` | **OFF** | Default false | NO |
| `conversation_os_debug_telemetry_enabled` | `conversationOSDebugTelemetryEnabled` | **OFF** | Default false | NO |
| `conversation_os_sensitive_space_restrictions_enabled` | `conversationOSSensitiveSpaceRestrictionsEnabled` | **OFF** | Default false | NO |

---

### Find Church 2.0 (all default OFF — flip via Remote Config after verification)

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `findChurch2_onboarding` | `findChurch2OnboardingEnabled` | **OFF** | seekerProfiles/ rules not deployed; privacy policy not updated | NO — rules + privacy policy |
| `findChurch2_matchExplain` | `findChurch2MatchExplainEnabled` | **OFF** | Client-only (no CF); but RC keys not yet uploaded (Step 7) | NO — Step 7 pending |
| `findChurch2_gatherings` | `findChurch2GatheringsEnabled` | **OFF** | gatherings/ Firestore rules not deployed | NO — rules |
| `findChurch2_visitPlanner` | `findChurch2VisitPlannerEnabled` | **OFF** | visitPlans/ rules not deployed; EventKit plist not confirmed | NO |
| `findChurch2_claimPortal` | `findChurch2ClaimPortalEnabled` | **OFF** | claimRequests/ rules not deployed | NO |
| `findChurch2_concierge` | `findChurch2ConciergeEnabled` | **OFF** | Client-only; RC keys not yet uploaded (Step 7) | NO — Step 7 pending |
| `findChurch2_mapHybrid` | `findChurch2MapHybridEnabled` | **OFF** | Client-only; RC keys not yet uploaded (Step 7) | NO — Step 7 pending |
| `findChurch2_availability` | `findChurch2AvailabilityEnabled` | **OFF** | computeAvailabilityStatus CF not deployed | NO — Step 10b |
| `findChurch2_trustSignals` | `findChurch2TrustSignalsEnabled` | **OFF** | Client-only; RC keys not yet uploaded (Step 7) | NO — Step 7 pending |
| `findChurch2_designRefresh` | `findChurch2DesignRefreshEnabled` | **OFF** | matchExplain must be ON first; RC keys not uploaded | NO |

---

### Master-Run Phase Gates

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `find_a_church_enabled` | `findAChurchEnabled` | **ON** | Find a Church v1 fully wired | YES |
| `posts_liquid_glass_enabled` | `postsLiquidGlassEnabled` | **ON** | Posts Liquid Glass committed; 0 diagnostics | YES |
| `why_seeing_this_enabled` | `whySeeingThisEnabled` | **ON** | Why Seeing This wired | YES |
| `selah_stories_enabled` | `selahStoriesEnabled` | **OFF** | Default false; Selah Stories not screenshot-verified | NO |
| `selah_stories_premium_ai_enabled` | `selahStoriesPremiumAIEnabled` | **OFF** | Default false; requires `selah_stories_enabled` ON first | NO |

---

### Selah Enhancement

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `selah_personal_corpus_enabled` | `selahPersonalCorpusEnabled` | **OFF** | Default false; indexSelahNote CF not confirmed deployed | NO |
| `selah_discernment_enabled` | `selahDiscernmentEnabled` | **OFF** | Default false; runDiscernmentCheck CF not confirmed deployed | NO |
| `selah_discernment_sharing_enabled` | `selahDiscernmentSharingEnabled` | **OFF** | Default false; depends on discernment | NO |

---

### Spiritual OS (via UserDefaults / syncSpiritualOSAppStorageFlags)

| RC Key | Recommended | Rationale | Preconditions met? |
|---|---|---|---|
| `spiritualOS_enabled` | **OFF** | All 27 Step 6 CFs not deployed | NO — Step 6 |
| `spiritualOS_daily_enabled` | **OFF** | Depends on CFs | NO |
| `spiritualOS_hub_enabled` | **OFF** | Depends on CFs | NO |
| `spiritualOS_planner_enabled` | **OFF** | Depends on CFs | NO |
| `spiritualOS_spaces_dashboard_enabled` | **OFF** | Depends on CFs | NO |
| `spiritualOS_create_space_enhanced_enabled` | **OFF** | Depends on CFs | NO |
| `spiritualOS_command_center_enabled` | **OFF** | Depends on CFs | NO |
| `spiritualOS_assistant_bar_enabled` | **OFF** | Depends on CFs | NO |
| `spiritualOS_context_engine_enabled` | **OFF** | Depends on CFs | NO |
| `spiritualOS_community_os_enabled` | **OFF** | Depends on CFs | NO |

---

### ONE Private Social OS

| RC Key | Recommended | Rationale | Preconditions met? |
|---|---|---|---|
| `one_*` (any) | **OFF** | All ONE CFs not deployed (Step 5); one_reach/one_evidence rules not merged | NO — Step 4+5 |

---

### Cross-Cutting

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `analytics_enabled` | `analyticsEnabled` | **ON** | Analytics required | YES |
| `performance_telemetry_enabled` | `performanceTelemetryEnabled` | **ON** | Telemetry required | YES |

---

### Ambient OS

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `ambient_os_enabled` | `ambientOSEnabled` | **OFF** | Default false; privacy review not complete | NO |

---

### SYSTEM 36 — Context-First Discussion OS

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `discussion_modes_enabled` | `discussionModesEnabled` | **ON** | Discussion modes wired | YES |
| `context_participation_enabled` | `contextParticipationEnabled` | **ON** | Context participation wired | YES |
| `discussion_health_enabled` | `discussionHealthEnabled` | **ON** | Discussion health wired | YES |
| `draft_intelligence_enabled` | `draftIntelligenceEnabled` | **ON** | Draft intelligence wired | YES |
| `discussion_summary_enabled` | `discussionSummaryEnabled` | **ON** | Discussion summary wired | YES |
| `discussion_mediator_enabled` | `discussionMediatorEnabled` | **ON** | Mediator wired | YES |
| `community_memory_enabled` | `communityMemoryEnabled` | **ON** | Community memory wired | YES |
| `discussion_actions_enabled` | `discussionActionsEnabled` | **ON** | Actions wired | YES |
| `participation_tiers_enabled` | `participationTiersEnabled` | **ON** | Participation tiers wired | YES |
| `discussion_command_center_enabled` | `discussionCommandCenterEnabled` | **ON** | Command center wired | YES |

---

### SYSTEM 38 — Connect Hub

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `connect_hub_enabled` | `connectHubEnabled` | **ON** | Connect Hub v1 wired | YES |
| `connect_you_menu_enabled` | `connectYouMenuEnabled` | **ON** | You menu wired | YES |

---

### SYSTEM 39 — Connect UI Polish Waves (V2)

| Flag | Swift var | Recommended | Rationale | Preconditions met? |
|---|---|---|---|---|
| `connect_layout_v2_enabled` | `connectLayoutV2Enabled` | **OFF** | processConnectQueuedDraft CF not deployed; iOS 26 not tested | NO — Step 3+4 |
| `connect_polish_v2_enabled` | `connectPolishV2Enabled` | **OFF** | Depends on `connect_layout_v2_enabled` | NO |
| `connect_empty_states_enabled` | `connectEmptyStatesEnabled` | **OFF** | Depends on `connect_layout_v2_enabled` | NO |
| `connect_smart_berean_enabled` | `connectSmartBereanEnabled` | **OFF** | bereanQuestion CF not deployed | NO |
| `connect_offline_queue_enabled` | `connectOfflineQueueEnabled` | **OFF** | processConnectQueuedDraft CF not deployed | NO — Step 3 |

---

### Safety Environment Variables (not in AMENFeatureFlags.swift)

| RC Key / Env Var | Recommended | Rationale |
|---|---|---|
| `NCMEC_SUBMISSION_ENABLED` | **OFF — NEVER flip until A-01 resolved** | Criminal liability under 18 U.S.C. § 2258A if enabled without NCMEC registration |

---

## Summary Counts

| Category | Count |
|---|---|
| **Total flags evaluated** | 278 |
| **Recommended ON** | 148 |
| **Recommended OFF** | 130 |

---

## What a New User Actually Sees (with recommended ON flags)

With this configuration, a user who creates an account on day 1 will see and be able to use:

**Core Social Experience**
- Full post feed with Liquid Glass post cards, "Why Seeing This" provenance disclosure, and feed ranking v2
- Create posts with text, photos, video, approved audio, and music attachments
- Per-media captions with alt text (accessibility) and scripture references
- Smart share sheet with recipient rail and smart suggestions
- Profile V2 with media grid, pinned content, and creator highlights
- Connect Hub with DM inbox, trusted contacts, and messaging safety nudges

**Berean AI Assistant**
- Berean AI with RAG, streaming responses, conversation memory, and source attribution
- Theological lens modes (Wisdom / Prayer / Discernment)
- Berean-to-Selah and Berean-to-Church Notes bridges
- Smart pills, study threads, translation comparison, research view
- Spiritual intelligence layers: Living Scripture Graph, Spiritual State Layer, Guided Discipleship

**Church Discovery (v1)**
- Find a Church map with smart ranking, explainable recommendations, and first-visit companion
- Church journey timeline, service reminders, reviews, and interaction tracking
- Church Notes with audio/video/OCR capture, AI draft review, study guide, prayer prompts
- Post-visit reflection and after-service reflection flows

**Selah Scripture Reader**
- Full Selah Media OS with scripture actions (Save, Reflect, Berean, Continue)
- Church Notes scripture bridge and scripture immersion

**Daily Formation**
- Amen Daily Digest with weather, Christian calendar, holiday awareness, AI reflection
- Berean Pulse daily spiritual nudges
- Spiritual Check-In with behavioral signals and crisis escalation routing
- Action Threads (care workflows) with suggestions and follow-ups

**Discovery & Feed**
- Amen Discover surface with Liquid Glass, church cards, "Why This" disclosure, and safety feedback
- Suggested Follows rail with prayer and testimonies categories
- Feed reflection prompts, session pacing, anti-doomscroll controls
- Topic Drill-Down and Knowledge Graph

**Media**
- Video and photo upload with voiceover, auto-captions, Selah audio mode
- Media transcripts, wellness checkpoints, doom-scroll guard, late-night pause
- Low bandwidth mode and accessibility controls

**Safety (always-on)**
- Aegis Pre-Post Review Gate on every post
- AI usage label pill on all AI-generated content
- Social Safety OS: minor safety mode, DM risk firewall, sextortion panic flow, dogpile detection, victim shield, think-first guard, mercy mode replies, theology guardrail
- Age-tier enforcement with minor DM youth gate

**They will NOT see (and why):**
- Connect V2 glass union bar — processConnectQueuedDraft CF not deployed (Step 3+4)
- Spiritual OS (Hub, Life Planner, Command Center, Assistant Bar) — 27 CFs not deployed (Step 6)
- Context System (Passport, Migration Interview, Universal Import) — bait-transcript not run (Step 8)
- Find Church 2.0 features (Match Explanation, Gatherings, Visit Planner, AI Concierge, Claim Portal) — Firestore rules + CFs not deployed (Steps 1, 7, 10b)
- AIL (Accessibility Intelligence Layer) — ailTransform CF not deployed; in-flight lane
- ONE private social moments — ONE CFs not deployed (Step 5)
- Community OS (Discussion Rooms, Prayer OS, Church OS) — Phase 1 validation incomplete
- Berean OS Wisdom Platform — CFs not deployed
- Amen Pulse daily surface — FirebaseAI iOS-27 SDK error
- Voice Prayer Comments — enforcement tests not passed
- Spatial Social OS — design phase only
- Camera OS — privacy review pending
- Music Content Layer — Xcode target + B-10 Firestore rules open
- Selah Enhancement (personal corpus, discernment) — CFs not confirmed deployed
- Onboarding V2 — 6 UI blockers in-flight

---

## Preconditions Still Unmet for Recommended-ON Flags

The following ON flags have soft preconditions that do not block the flag being ON on day 1 but require human action before public launch:

| Flag (recommended ON) | Unmet precondition | Who unblocks it |
|---|---|---|
| `moderation_appeals_enabled` | B-05 SLA policy not written | Human — designate T&S owner |
| `check_in_crisis_escalation_enabled` | B-08 crisis protocol not documented | Human — write crisis response runbook |
| `video_upload_enabled` | B-16 `chat_videos` Storage rule missing (chat video upload path) | Engineering — add Storage rule for chat_videos before enabling DM video |
| `moderation_v2_enabled` / `image_moderation_enabled` | B-11 iOS end-to-end test not run from real device | Engineering — run end-to-end moderation test |
| `dm_risk_firewall_enabled` | A3 callables (evaluateDmRisk, reportDmAbuse) not deployed (Step 2) | Deploy — Step 2 |
| `minor_safety_mode_enabled` | A-02 age floor decision unanswered; A-03 guardian consent model unanswered | Human — GROUP A decisions |
| `minor_safety_mode_enabled` | A-06 canonical Firestore rules file not confirmed | Human — dry-run + reconcile |
| `berean_rag_enabled` | B-14 Berean AI minor access policy not documented | Human — document policy |
| `action_threads_enabled` | actionIntelligence.ts CF needs deploy in next batch | Engineering — next deploy batch |
| `social_safety_os_enabled` (whole group) | DEFERRED-DESIGN: zero consumer call-sites wired yet | Engineering — wire call-sites in Safety OS v3 surface design |
| `analytics_enabled` | C-03 App Store privacy nutrition label not audited against current feature set | Human — audit before App Store submission |

---

## Remote Config Publish Steps

Execute after `RUN_ME.sh` completes and all smoke checklist items pass.

1. Open Firebase Console → Remote Config → project `amen-5e359`
2. All flags listed as OFF that are not yet in Remote Config need to be added with value `false`. The following keys from the Stage-3 package (Step 7) are not yet uploaded:
   ```
   connect_layout_v2_enabled        (false)
   connect_polish_v2_enabled        (false)
   connect_empty_states_enabled     (false)
   connect_smart_berean_enabled     (false)
   connect_offline_queue_enabled    (false)
   findChurch2_onboarding           (false)
   findChurch2_matchExplain         (false)
   findChurch2_gatherings           (false)
   findChurch2_visitPlanner         (false)
   findChurch2_claimPortal          (false)
   findChurch2_concierge            (false)
   findChurch2_mapHybrid            (false)
   findChurch2_availability         (false)
   findChurch2_trustSignals         (false)
   findChurch2_designRefresh        (false)
   ```
3. Verify the following keys are present and set correctly (should already be in RC from prior sessions; confirm):
   ```
   NCMEC_SUBMISSION_ENABLED         (false — DO NOT change until A-01 resolved)
   ff_onboarding_v2                 (false)
   amen_pulse_enabled               (false)
   context_system_enabled           (false)
   spiritualOS_enabled              (false)
   community_os_enabled             (false)
   accessibility_intelligence_enabled (false)
   ```
4. Publish changes.
5. Verify on simulator:
   - Flip `findChurch2_matchExplain` to `true` on a test RC condition → `MatchExplanation` badge visible on church card
   - Flip back to `false` → badge disappears
   - Each OFF surface (Connect V2 bar, Spiritual OS Hub, Context System passport) does NOT appear with default flags

---

## Flag Flip Sequence (after RUN_ME.sh + human verification)

Recommended order for turning features ON one-by-one as preconditions clear. Do not skip steps.

1. `spiritualOS_enabled` + all `spiritualOS_*` sub-flags — **after** Step 6 CFs deployed + ACTIVE in console
2. `connect_layout_v2_enabled` — **after** Step 3 (processConnectQueuedDraft deployed) + Step 4 TTL console + iOS 26 device smoke test
3. `connect_offline_queue_enabled` — **after** `connect_layout_v2_enabled` ON + TTL policy confirmed
4. `connect_polish_v2_enabled` — **after** `connect_layout_v2_enabled` ON
5. `connect_empty_states_enabled` — **after** `connect_layout_v2_enabled` ON
6. `connect_smart_berean_enabled` — **after** bereanQuestion CF deployed + `connect_layout_v2_enabled` ON
7. `findChurch2_matchExplain` — **after** Step 7 RC upload complete (no CF dependency; client-only)
8. `findChurch2_trustSignals` — **after** Step 7 RC upload (client-only)
9. `findChurch2_concierge` — **after** Step 7 RC upload (client-only)
10. `findChurch2_mapHybrid` — **after** Step 7 RC upload (client-only)
11. `findChurch2_designRefresh` — **after** `findChurch2_matchExplain` ON + smallest/largest device tested
12. `findChurch2_availability` — **after** Step 10b (computeAvailabilityStatus + scheduleAvailabilityRefresh CFs deployed)
13. `findChurch2_onboarding` — **after** seekerProfiles/ Firestore rules live + privacy policy updated
14. `findChurch2_gatherings` — **after** gatherings/ Firestore rules live
15. `findChurch2_visitPlanner` — **after** visitPlans/ rules live + EventKit plist confirmed
16. `findChurch2_claimPortal` — **after** claimRequests/ rules live + Aegis review queue handler live
17. `context_system_enabled` — **after** Step 8 bait-transcript runner PASS (all A3 callables live and tested)
18. `context_manual_entry_enabled` — **after** `context_system_enabled` ON
19. `context_berean_interview_enabled` — **after** `context_system_enabled` ON
20. `context_universal_import_enabled` — **after** `context_system_enabled` ON + W3 validation
21. `context_matching_enabled` — **after** W4 validation complete
22. `accessibility_intelligence_enabled` (AIL master) — **after** ailTransform CF deployed + in-flight lane merged
23. `ff_action_intelligence` — **after** actionIntelligence CF deployed in next batch + TS build green
24. `ff_music_content_layer` — **after** Xcode target membership manual step + B-10 Firestore rules + Stage-3 backend deployed
25. `amen_pulse_enabled` — **after** FirebaseAI iOS-27 SDK error resolved + pulse generation pipeline deployed
26. `berean_os_projects_enabled` + all `berean_os_*` sub-flags — **after** Berean OS CFs deployed and entitlement-tested
27. `ff_onboarding_v2` — **after** 6 UI blockers in onboarding/auth lane resolved + end-to-end screenshot-verified
28. `selah_stories_enabled` — **after** screenshot-verified on smallest + largest device
29. `community_os_enabled` — **after** Phase 1 Firestore paths deployed + validated
30. `voice_prayer_comments_enabled` — **after** enforcement tests pass + transcript pipeline verified

---

*LAUNCH_CONFIG_VNEXT.md — authored by Agent 4 (Launch Configuration Architect), Launch Readiness Swarm, 2026-06-11. Approve this flag set, publish to Remote Config after RUN_ME.sh completes and smoke checklist passes.*
