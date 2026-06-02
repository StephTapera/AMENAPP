// AMENAnalyticsService.swift
// AMEN App — Product Analytics & Observability
//
// Design principles:
//   - Meaningful product metrics, not vanity metrics
//   - No raw behavioral data stored server-side
//   - Aggregated + anonymized where possible
//   - Privacy-first: users can opt out
//   - Instrumented across all 7 major systems
//
// Metric categories:
//   - Feed quality (meaningful engagement ratio, not raw views)
//   - Moderation health (false positive rate, action distribution)
//   - Assistant quality (latency, source attribution rate)
//   - Church discovery (search → save → visit funnel)
//   - Check-in effectiveness (dismissal rate, positive response rate)
//   - Knowledge graph utility (related content clicks)
//   - Studio (opportunity discovery, creator profile completeness)

import Foundation
import UIKit
import FirebaseFirestore
import FirebaseAuth
import FirebaseAnalytics

// MARK: - Analytics Event

enum AMENAnalyticsEvent {
    // Feed
    case feedSessionStarted
    case feedSessionEnded(durationMinutes: Double, qualityScore: Double)
    case feedMeaningfulInteraction(type: String)   // "save", "comment", "prayer_response"
    case feedReflectionPromptShown
    case feedReflectionPromptEngaged
    case feedPacingPromptShown
    case feedPacingPromptEngaged

    // Moderation
    case moderationDecisionMade(context: String, action: String, riskLevel: String)
    case moderationAppealSubmitted
    case userReportSubmitted(type: String)

    // Berean AI
    case bereanSessionStarted
    case bereanChatMessageSent(tier: String, mode: String)
    case bereanResponseGenerated(latencyMs: Double, sourceCount: Int)
    case bereanSourceTapped(sourceType: String)
    case bereanFollowUpUsed
    case bereanMessageSaved
    case bereanFeatureFlagBlocked(feature: String)
    case bereanStudyActionStarted(action: String)
    case bereanStudyActionCompleted(action: String)
    case bereanTheoLensSelected(lens: String)
    case bereanProviderFailure(reason: String)
    case bereanChurchNoteSaveStarted
    case bereanChurchNoteSaveCompleted
    case bereanTierDowngradeBannerShown(requestedTier: String, grantedTier: String)
    case bereanRateLimitHit(surface: String)
    case bereanDailyQuotaHit(tier: String)
    case bereanPremiumGateHit(requestedMode: String, surface: String)
    case bereanModelDowngraded(requestedMode: String, grantedMode: String, tier: String)
    case bereanCrisisEscalationDetected(surface: String)
    case bereanTheologyBoundaryViolation(surface: String)
    case bereanSafetyOutputRewritten(violationCount: Int)
    case bereanAppCheckFailure(surface: String)

    // Berean Onboarding
    case bereanOnboardingStarted
    case bereanOnboardingPageViewed(page: String)
    case bereanOnboardingSkipped(fromPage: String)
    case bereanOnboardingCompleted
    case bereanWelcomeBackShown

    // Spiritual Check-In
    case checkInShown(tier: Int)
    case checkInEngaged
    case checkInDismissed
    case checkInSnoozed

    // Church Discovery
    case churchSearchPerformed
    case churchProfileViewed
    case churchSaved
    case churchDirectionsTapped
    case churchFirstVisitGuideOpened
    case churchPreferenceOnboardingCompleted

    // Knowledge Graph
    case relatedContentShown(nodeType: String)
    case relatedContentTapped(nodeType: String)
    case topicFollowed(topicSlug: String)

    // Studio
    case studioProfileViewed
    case studioInquirySent
    case studioJobApplied

    // Account
    case accountTypeSelected(type: String)

    // Media Feed Mode
    case mediaModeSwitched(toMode: String)
    case mediaGridTileOpened(postId: String)
    case mediaDetailClosed
    case mediaDetailJumpedToPost(postId: String)
    case mediaGridEmptyStateViewed
    case mediaFilterChanged(filter: String)

    // Suggested Accounts
    case suggestionImpression(suggestedUserId: String, position: Int, reasonType: String)
    case suggestionFollowTap(suggestedUserId: String, position: Int)
    case suggestionFollowSuccess(suggestedUserId: String)
    case suggestionFollowFailure(suggestedUserId: String)
    case suggestionProfileOpen(suggestedUserId: String)
    case suggestionDismiss(suggestedUserId: String)
    case suggestionsRailSeen(count: Int)
    case suggestionsModuleHidden
    case suggestionsModuleRestored
    case suggestionPeekOpen(suggestedUserId: String, surface: String)
    case suggestionPeekExpand(suggestedUserId: String, surface: String)
    case suggestionFullProfileOpen(suggestedUserId: String, surface: String)
    case suggestionRailHidden(surface: String)
    case suggestionRailRestored(surface: String)
    case suggestionShowFewer(surface: String)
    case suggestionWhyShown(surface: String)

    // Smart Catch-Up
    case catchUpItemEngaged
    case catchUpDigestOpened(itemCount: Int)

    // Command Palette
    case commandPaletteResultSelected
    case prayerSignalEngaged
    case replyPreviewTapped(postId: String, type: String, replyId: String)
    case replyPreviewShown(postId: String, type: String)
    case replyPreviewType(type: String)
    case commandPaletteOpened(surface: String)

    // Berean Smart Pills
    case bereanSmartPillTapped(pill: String)
    case bereanScriptureContextOpened
    case bereanHumanSupportSuggested(context: String)
    case bereanResearchViewOpened
    case bereanSafetyRewrite(patternsDetected: Int)
    case bereanSelahSaveStarted(entryType: String)
    case manageSubscriptionOpened(surface: String)
    case homeFeedLoadSucceeded(postCount: Int)
    case homeFeedLoadFailed(reason: String)
    case bereanSelahSaveCompleted(entryType: String)

    // Living Hero
    case livingHeroImpression(surface: String, sceneId: String)
    case livingHeroAction(surface: String, sceneId: String, action: String)
    case livingHeroFallbackShown(surface: String, sceneId: String, reason: String)

    // Smart Context / Smart Reply / Smart Actions
    case smartContextViewed(threadType: String)
    case smartContextRefreshRequested(threadType: String)
    case smartReplySelected(wasEdited: Bool)
    case smartReplyDismissed
    case smartActionCorrected(actionType: String)
    case smartActionAccepted(actionType: String)
    case smartActionDismissed(actionType: String)

    // Selah Scripture
    case selahVerseAddedToChurchNotes
    case scriptureAddedToChurchNote(source: String)
    case churchStudyCompanionOpened(source: String)
    case churchNotesStartedFromChurch
    case churchStudySessionStarted(source: String)
    case afterServiceReflectionStarted
    case afterServiceReflectionSaved
    case prayerVisibilitySelected(visibility: String)
    case churchContextAttachedToNote

    // Profile Mini Actions
    case profileMiniUnfollowTap(userId: String, surface: String)
    case profileMiniMessageTap(userId: String, surface: String, viewerId: String)
    case profileMiniMessageBlocked(userId: String, surface: String)
    case profileMiniPrimaryCTATap(userId: String, surface: String, ctaType: String)
    case profileMiniSecondaryCTATap(userId: String, surface: String, ctaType: String)
    case profileMiniSaveSuggestion(userId: String, surface: String)
    case profileMiniSeeSimilar(userId: String, surface: String)
    case profileMiniShare(userId: String, surface: String)
    case profileMiniUndoHide(userId: String, surface: String)
    case profileMiniOverflowTapped(userId: String, surface: String)

    // Covenant Paywall / Purchase
    case paywallShown(surface: String, feature: String)
    case purchaseStarted(surface: String, productId: String)
    case purchaseSucceeded(surface: String, productId: String)
    case purchaseFailed(surface: String, reason: String)
    case purchaseCanceled(surface: String)

    // Command Layer
    case commandLayerOpened(surface: String)
    case commandLayerDismissed(surface: String)
    case commandLayerActionTapped(surface: String, actionId: String)
    case commandLayerRouteSucceeded(surface: String, actionId: String, routeId: String)
    case commandLayerUnavailableActionTapped(surface: String, actionId: String, reason: String)
    case commandLayerRouteFailed(surface: String, actionId: String, reason: String)

    // Messaging
    case messageFilterSelected(filter: String)
    case messageFilterCleared
    case messageSearchOpened(surface: String)
    case messageComposeOpened
    case messageThreadFilterSelected(filter: String)
    case messageSearchResultTapped(surface: String, kind: String)
    case messageSearchSubmitted(surface: String, hasResults: Bool, resultBuckets: Int)

    // Music / Smart Attachment
    case musicAttachmentRemoved(provider: String)
    case musicAttachmentResolved(provider: String, entityType: String)

    // Safety OS
    case safetyOSDiscernmentAction(postId: String, surface: String, trigger: String, action: String)
    case smartPresenceUpdated(stateCategory: String)

    // Inline post
    case homeInlinePostStarted

    // Post interactions
    case homePostLightbulbTapped(postId: String)
    case homePostAmenReactionTapped(postId: String)

    // Media captions
    case mediaCaptionEdited(mediaIndex: Int, mediaType: String)
    case mediaCaptionRemoved(mediaIndex: Int, mediaType: String)
    case mediaCaptionComposerShown(mediaCount: Int)

    // Content renderer
    case contentNodeRendered(type: String)

    // Group Pulse
    case groupPulseViewed(urgencyLevel: String)

    // Prayer Signal
    case prayerSignalDismissed

    // Discover
    case discoverView
    case discoverFeedLoaded(count: Int)
    case discoverEmptyStateSeen
    case discoverErrorSeen(message: String)
    case discoverFilterChanged(filter: String)
    case discoverDetailOpened(itemType: String)
    case discoverItemTapped(itemType: String)
    case discoverWhyThisOpened
    case discoverFeedbackSubmitted(type: String)

    // Voice Prayer Comments
    case voiceCommentReacted(postId: String, reaction: String)
    case voiceCommentRecordStarted(postId: String, type: String)
    case voiceCommentProcessingStarted(postId: String)
    case voiceCommentEntryTapped(postId: String, type: String)
    case voiceCommentReported(postId: String)
    case voiceCommentDeleted(postId: String)
    case voiceCommentPreviewPlayed(postId: String)
    case voiceCommentSubmitted(postId: String, type: String)
    case voiceCommentRecordCancelled(postId: String, type: String)
    case voiceCommentTranscriptReady(postId: String)
    case voiceCommentPublished(postId: String, type: String, durationMs: Int)
    case voiceCommentHeldForReview(postId: String)
    case voiceCommentBlocked(postId: String)
    case voiceCommentVisibilityChanged(postId: String, visibility: String)

    // Walk With Christ
    case walkWithChristOpened
    case walkWithChristOnboardingCompleted(path: String)
    case walkWithChristSeasonSelected(season: String)
    case walkWithChristBereanLaunched(sourceSurface: String)
    case walkWithChristApplicationStepCompleted(stepIndex: Int)
    case walkWithChristFollowThroughPlanCreated(area: String, frequency: String)
    case walkWithChristFollowThroughCompleted(planId: String, streakDays: Int)
    case walkWithChristReminderEnabled

    // Smart Prompts
    case smartPromptImpression(promptType: String, surface: String)
    case smartPromptPrimaryAction(promptType: String, surface: String)
    case smartPromptPermissionRequested(promptType: String, permissionType: String)
    case smartPromptSecondaryAction(promptType: String, surface: String)
    case smartPromptDismissed(promptType: String, surface: String, reason: String)
    case smartPromptPermissionGranted(promptType: String, permissionType: String)
    case smartPromptPermissionDenied(promptType: String, permissionType: String)
    case smartPromptSuppressed(surface: String, reason: String)

    // Smart Context Bar
    case smartContextDismissed(threadType: String)

    // Create Hub
    case createHubOpened
    case creationIntentSelected(intent: String)

    // Draft Persistence
    case draftRestored(type: String)
    case draftSaved(type: String)
    case draftDeleted(type: String)
    case draftPublished(type: String)

    // Daily Digest
    case amenDailyDigestLoaded(dateKey: String, priority: String, hasWeather: Bool, hasHoliday: Bool, source: String)
    case amenDailyWeatherShown(dateKey: String, priority: String, hasWeather: Bool, hasHoliday: Bool, source: String)
    case amenDailyHolidayShown(dateKey: String, priority: String, hasWeather: Bool, hasHoliday: Bool, source: String)
    case amenDailyDigestFallbackUsed(dateKey: String, priority: String, hasWeather: Bool, hasHoliday: Bool, source: String)

    // Custom / escape hatch
    case custom(name: String, parameters: [String: String])

    var name: String {
        switch self {
        case .feedSessionStarted: return "feed_session_started"
        case .feedSessionEnded: return "feed_session_ended"
        case .feedMeaningfulInteraction: return "feed_meaningful_interaction"
        case .feedReflectionPromptShown: return "feed_reflection_prompt_shown"
        case .feedReflectionPromptEngaged: return "feed_reflection_prompt_engaged"
        case .feedPacingPromptShown: return "feed_pacing_prompt_shown"
        case .feedPacingPromptEngaged: return "feed_pacing_prompt_engaged"
        case .moderationDecisionMade: return "moderation_decision_made"
        case .moderationAppealSubmitted: return "moderation_appeal_submitted"
        case .userReportSubmitted: return "user_report_submitted"
        case .bereanSessionStarted: return "berean_session_started"
        case .bereanChatMessageSent: return "berean_chat_message_sent"
        case .bereanChurchNoteSaveStarted: return "berean_church_note_save_started"
        case .bereanChurchNoteSaveCompleted: return "berean_church_note_save_completed"
        case .bereanTierDowngradeBannerShown: return "berean_tier_downgrade_banner_shown"
        case .bereanResponseGenerated: return "berean_response_generated"
        case .bereanSourceTapped: return "berean_source_tapped"
        case .bereanFollowUpUsed: return "berean_follow_up_used"
        case .bereanMessageSaved: return "berean_message_saved"
        case .bereanFeatureFlagBlocked: return "berean_feature_flag_blocked"
        case .bereanStudyActionStarted: return "berean_study_action_started"
        case .bereanStudyActionCompleted: return "berean_study_action_completed"
        case .bereanTheoLensSelected: return "berean_theo_lens_selected"
        case .bereanProviderFailure: return "berean_provider_failure"
        case .bereanRateLimitHit: return "berean_rate_limit_hit"
        case .bereanDailyQuotaHit: return "berean_daily_quota_hit"
        case .bereanPremiumGateHit: return "berean_premium_gate_hit"
        case .bereanModelDowngraded: return "berean_model_downgraded"
        case .bereanCrisisEscalationDetected: return "berean_crisis_escalation_detected"
        case .bereanTheologyBoundaryViolation: return "berean_theology_boundary_violation"
        case .bereanSafetyOutputRewritten: return "berean_safety_output_rewritten"
        case .bereanAppCheckFailure: return "berean_app_check_failure"
        case .bereanOnboardingStarted:    return "berean_onboarding_started"
        case .bereanOnboardingPageViewed: return "berean_onboarding_page_viewed"
        case .bereanOnboardingSkipped:    return "berean_onboarding_skipped"
        case .bereanOnboardingCompleted:  return "berean_onboarding_completed"
        case .bereanWelcomeBackShown:     return "berean_welcome_back_shown"
        case .checkInShown: return "check_in_shown"
        case .checkInEngaged: return "check_in_engaged"
        case .checkInDismissed: return "check_in_dismissed"
        case .checkInSnoozed: return "check_in_snoozed"
        case .churchSearchPerformed: return "church_search_performed"
        case .churchProfileViewed: return "church_profile_viewed"
        case .churchSaved: return "church_saved"
        case .churchDirectionsTapped: return "church_directions_tapped"
        case .churchFirstVisitGuideOpened: return "church_first_visit_guide_opened"
        case .churchPreferenceOnboardingCompleted: return "church_preference_onboarding_completed"
        case .relatedContentShown: return "related_content_shown"
        case .relatedContentTapped: return "related_content_tapped"
        case .topicFollowed: return "topic_followed"
        case .studioProfileViewed: return "studio_profile_viewed"
        case .studioInquirySent: return "studio_inquiry_sent"
        case .studioJobApplied: return "studio_job_applied"
        case .accountTypeSelected: return "account_type_selected"
        case .mediaModeSwitched: return "media_mode_switched"
        case .mediaGridTileOpened: return "media_grid_tile_opened"
        case .mediaDetailClosed: return "media_detail_closed"
        case .mediaDetailJumpedToPost: return "media_detail_jumped_to_post"
        case .mediaGridEmptyStateViewed: return "media_grid_empty_state_viewed"
        case .mediaFilterChanged: return "media_filter_changed"
        case .suggestionImpression: return "suggestion_impression"
        case .suggestionFollowTap: return "suggestion_follow_tap"
        case .suggestionFollowSuccess: return "suggestion_follow_success"
        case .suggestionFollowFailure: return "suggestion_follow_failure"
        case .suggestionProfileOpen: return "suggestion_profile_open"
        case .suggestionDismiss: return "suggestion_dismiss"
        case .suggestionsRailSeen: return "suggestions_rail_seen"
        case .suggestionsModuleHidden: return "suggestions_module_hidden"
        case .suggestionsModuleRestored: return "suggestions_module_restored"
        case .suggestionPeekOpen: return "suggestion_peek_open"
        case .suggestionPeekExpand: return "suggestion_peek_expand"
        case .suggestionFullProfileOpen: return "suggestion_full_profile_open"
        case .suggestionRailHidden: return "suggestion_rail_hidden"
        case .suggestionRailRestored: return "suggestion_rail_restored"
        case .suggestionShowFewer: return "suggestion_show_fewer"
        case .suggestionWhyShown: return "suggestion_why_shown"
        case .catchUpItemEngaged: return "catch_up_item_engaged"
        case .catchUpDigestOpened: return "catch_up_digest_opened"
        case .commandPaletteResultSelected: return "command_palette_result_selected"
        case .prayerSignalEngaged: return "prayer_signal_engaged"
        case .replyPreviewTapped: return "reply_preview_tapped"
        case .replyPreviewShown: return "reply_preview_shown"
        case .replyPreviewType: return "reply_preview_type"
        case .commandPaletteOpened: return "command_palette_opened"
        case .bereanSmartPillTapped: return "berean_smart_pill_tapped"
        case .bereanScriptureContextOpened: return "berean_scripture_context_opened"
        case .bereanHumanSupportSuggested: return "berean_human_support_suggested"
        case .bereanResearchViewOpened: return "berean_research_view_opened"
        case .bereanSafetyRewrite: return "berean_safety_rewrite"
        case .bereanSelahSaveStarted: return "berean_selah_save_started"
        case .manageSubscriptionOpened: return "manage_subscription_opened"
        case .homeFeedLoadSucceeded: return "home_feed_load_succeeded"
        case .homeFeedLoadFailed: return "home_feed_load_failed"
        case .bereanSelahSaveCompleted: return "berean_selah_save_completed"
        case .livingHeroImpression: return "living_hero_impression"
        case .livingHeroAction: return "living_hero_action"
        case .livingHeroFallbackShown: return "living_hero_fallback_shown"
        case .smartContextViewed: return "smart_context_viewed"
        case .smartContextRefreshRequested: return "smart_context_refresh_requested"
        case .smartReplySelected: return "smart_reply_selected"
        case .smartReplyDismissed: return "smart_reply_dismissed"
        case .smartActionCorrected: return "smart_action_corrected"
        case .smartActionAccepted: return "smart_action_accepted"
        case .smartActionDismissed: return "smart_action_dismissed"
        case .selahVerseAddedToChurchNotes: return "selah_verse_added_to_church_notes"
        case .scriptureAddedToChurchNote: return "scripture_added_to_church_note"
        case .churchStudyCompanionOpened: return "church_study_companion_opened"
        case .churchNotesStartedFromChurch: return "church_notes_started_from_church"
        case .churchStudySessionStarted: return "church_study_session_started"
        case .afterServiceReflectionStarted: return "after_service_reflection_started"
        case .afterServiceReflectionSaved: return "after_service_reflection_saved"
        case .prayerVisibilitySelected: return "prayer_visibility_selected"
        case .churchContextAttachedToNote: return "church_context_attached_to_note"
        case .profileMiniUnfollowTap: return "profile_mini_unfollow_tap"
        case .profileMiniMessageTap: return "profile_mini_message_tap"
        case .profileMiniMessageBlocked: return "profile_mini_message_blocked"
        case .profileMiniPrimaryCTATap: return "profile_mini_primary_cta_tap"
        case .profileMiniSecondaryCTATap: return "profile_mini_secondary_cta_tap"
        case .profileMiniSaveSuggestion: return "profile_mini_save_suggestion"
        case .profileMiniSeeSimilar: return "profile_mini_see_similar"
        case .profileMiniShare: return "profile_mini_share"
        case .profileMiniUndoHide: return "profile_mini_undo_hide"
        case .profileMiniOverflowTapped: return "profile_mini_overflow_tapped"
        case .paywallShown: return "paywall_shown"
        case .purchaseStarted: return "purchase_started"
        case .purchaseSucceeded: return "purchase_succeeded"
        case .purchaseFailed: return "purchase_failed"
        case .purchaseCanceled: return "purchase_canceled"
        case .commandLayerOpened: return "command_layer_opened"
        case .commandLayerDismissed: return "command_layer_dismissed"
        case .commandLayerActionTapped: return "command_layer_action_tapped"
        case .commandLayerRouteSucceeded: return "command_layer_route_succeeded"
        case .commandLayerUnavailableActionTapped: return "command_layer_unavailable_action_tapped"
        case .commandLayerRouteFailed: return "command_layer_route_failed"
        case .messageFilterSelected: return "message_filter_selected"
        case .messageFilterCleared: return "message_filter_cleared"
        case .messageSearchOpened: return "message_search_opened"
        case .messageComposeOpened: return "message_compose_opened"
        case .messageThreadFilterSelected: return "message_thread_filter_selected"
        case .messageSearchResultTapped: return "message_search_result_tapped"
        case .messageSearchSubmitted(_, _, _): return "message_search_submitted"
        case .musicAttachmentRemoved: return "music_attachment_removed"
        case .musicAttachmentResolved: return "music_attachment_resolved"
        case .safetyOSDiscernmentAction: return "safety_os_discernment_action"
        case .smartPresenceUpdated: return "smart_presence_updated"
        case .homeInlinePostStarted: return "home_inline_post_started"
        case .mediaCaptionEdited: return "media_caption_edited"
        case .mediaCaptionRemoved: return "media_caption_removed"
        case .mediaCaptionComposerShown: return "media_caption_composer_shown"
        case .contentNodeRendered: return "content_node_rendered"
        case .groupPulseViewed: return "group_pulse_viewed"
        case .prayerSignalDismissed: return "prayer_signal_dismissed"
        case .discoverView: return "discover_view"
        case .discoverFeedLoaded: return "discover_feed_loaded"
        case .discoverEmptyStateSeen: return "discover_empty_state_seen"
        case .discoverErrorSeen: return "discover_error_seen"
        case .discoverFilterChanged: return "discover_filter_changed"
        case .discoverDetailOpened: return "discover_detail_opened"
        case .discoverItemTapped: return "discover_item_tapped"
        case .discoverWhyThisOpened: return "discover_why_this_opened"
        case .discoverFeedbackSubmitted: return "discover_feedback_submitted"
        case .voiceCommentReacted: return "voice_comment_reacted"
        case .voiceCommentRecordStarted: return "voice_comment_record_started"
        case .voiceCommentProcessingStarted: return "voice_comment_processing_started"
        case .voiceCommentEntryTapped: return "voice_comment_entry_tapped"
        case .voiceCommentReported: return "voice_comment_reported"
        case .voiceCommentDeleted: return "voice_comment_deleted"
        case .voiceCommentPreviewPlayed: return "voice_comment_preview_played"
        case .voiceCommentSubmitted: return "voice_comment_submitted"
        case .voiceCommentRecordCancelled: return "voice_comment_record_cancelled"
        case .voiceCommentTranscriptReady: return "voice_comment_transcript_ready"
        case .voiceCommentPublished: return "voice_comment_published"
        case .voiceCommentHeldForReview: return "voice_comment_held_for_review"
        case .voiceCommentBlocked: return "voice_comment_blocked"
        case .voiceCommentVisibilityChanged: return "voice_comment_visibility_changed"
        case .walkWithChristOpened: return "walk_with_christ_opened"
        case .walkWithChristOnboardingCompleted: return "walk_with_christ_onboarding_completed"
        case .walkWithChristSeasonSelected: return "walk_with_christ_season_selected"
        case .walkWithChristBereanLaunched: return "walk_with_christ_berean_launched"
        case .walkWithChristApplicationStepCompleted: return "walk_with_christ_application_step_completed"
        case .walkWithChristFollowThroughPlanCreated: return "walk_with_christ_follow_through_plan_created"
        case .walkWithChristFollowThroughCompleted: return "walk_with_christ_follow_through_completed"
        case .walkWithChristReminderEnabled: return "walk_with_christ_reminder_enabled"
        case .smartPromptImpression: return "smart_prompt_impression"
        case .smartPromptPrimaryAction: return "smart_prompt_primary_action"
        case .smartPromptPermissionRequested: return "smart_prompt_permission_requested"
        case .smartPromptSecondaryAction: return "smart_prompt_secondary_action"
        case .smartPromptDismissed: return "smart_prompt_dismissed"
        case .smartPromptPermissionGranted: return "smart_prompt_permission_granted"
        case .smartPromptPermissionDenied: return "smart_prompt_permission_denied"
        case .smartPromptSuppressed: return "smart_prompt_suppressed"
        case .smartContextDismissed: return "smart_context_dismissed"
        case .createHubOpened: return "create_hub_opened"
        case .creationIntentSelected: return "creation_intent_selected"
        case .draftRestored: return "draft_restored"
        case .draftSaved: return "draft_saved"
        case .draftDeleted: return "draft_deleted"
        case .draftPublished: return "draft_published"
        case .amenDailyDigestLoaded: return "amen_daily_digest_loaded"
        case .amenDailyWeatherShown: return "amen_daily_weather_shown"
        case .amenDailyHolidayShown: return "amen_daily_holiday_shown"
        case .amenDailyDigestFallbackUsed: return "amen_daily_digest_fallback_used"
        case .homePostLightbulbTapped: return "home_post_lightbulb_tapped"
        case .homePostAmenReactionTapped: return "home_post_amen_reaction_tapped"
        case .custom(let eventName, _): return eventName
        }
    }

    var properties: [String: Any] {
        switch self {
        case .feedSessionEnded(let duration, let quality):
            return ["duration_minutes": duration, "quality_score": quality]
        case .feedMeaningfulInteraction(let type):
            return ["interaction_type": type]
        case .moderationDecisionMade(let ctx, let action, let risk):
            return ["context": ctx, "action": action, "risk_level": risk]
        case .userReportSubmitted(let type):
            return ["report_type": type]
        case .bereanResponseGenerated(let latency, let sources):
            return ["latency_ms": latency, "source_count": sources]
        case .bereanSourceTapped(let type):
            return ["source_type": type]
        case .checkInShown(let tier):
            return ["tier": tier]
        case .relatedContentShown(let type), .relatedContentTapped(let type):
            return ["node_type": type]
        case .topicFollowed(let slug):
            return ["topic_slug": slug]
        case .accountTypeSelected(let type):
            return ["account_type": type]
        case .mediaModeSwitched(let mode):
            return ["to_mode": mode]
        case .mediaGridTileOpened(let postId):
            return ["post_id": postId]
        case .mediaDetailJumpedToPost(let postId):
            return ["post_id": postId]
        case .mediaFilterChanged(let filter):
            return ["filter": filter]
        case .suggestionImpression(let userId, let position, let reason):
            return ["suggested_user_id": userId, "position": position, "reason_type": reason]
        case .suggestionFollowTap(let userId, let position):
            return ["suggested_user_id": userId, "position": position]
        case .suggestionFollowSuccess(let userId):
            return ["suggested_user_id": userId]
        case .suggestionFollowFailure(let userId):
            return ["suggested_user_id": userId]
        case .suggestionProfileOpen(let userId):
            return ["suggested_user_id": userId]
        case .suggestionDismiss(let userId):
            return ["suggested_user_id": userId]
        case .suggestionsRailSeen(let count):
            return ["suggestion_count": count]
        case .suggestionPeekOpen(let userId, let surface):
            return ["suggested_user_id": userId, "surface": surface]
        case .suggestionPeekExpand(let userId, let surface):
            return ["suggested_user_id": userId, "surface": surface]
        case .suggestionFullProfileOpen(let userId, let surface):
            return ["suggested_user_id": userId, "surface": surface]
        case .suggestionRailHidden(let surface):
            return ["surface": surface]
        case .suggestionRailRestored(let surface):
            return ["surface": surface]
        case .suggestionShowFewer(let surface):
            return ["surface": surface]
        case .suggestionWhyShown(let surface):
            return ["surface": surface]
        case .catchUpDigestOpened(let itemCount):
            return ["item_count": itemCount]
        case .bereanFeatureFlagBlocked(let feature):
            return ["feature": feature]
        case .bereanStudyActionStarted(let action):
            return ["action": action]
        case .bereanStudyActionCompleted(let action):
            return ["action": action]
        case .scriptureAddedToChurchNote(let source):
            return ["source": source]
        case .churchStudyCompanionOpened(let source):
            return ["source": source]
        case .churchStudySessionStarted(let source):
            return ["source": source]
        case .prayerVisibilitySelected(let visibility):
            return ["visibility": visibility]
        case .bereanTheoLensSelected(let lens):
            return ["lens": lens]
        case .bereanProviderFailure(let reason):
            return ["reason": reason]
        case .bereanRateLimitHit(let surface):
            return ["surface": surface]
        case .bereanDailyQuotaHit(let tier):
            return ["tier": tier]
        case .bereanPremiumGateHit(let requestedMode, let surface):
            return ["requested_mode": requestedMode, "surface": surface]
        case .bereanModelDowngraded(let requestedMode, let grantedMode, let tier):
            return ["requested_mode": requestedMode, "granted_mode": grantedMode, "tier": tier]
        case .bereanCrisisEscalationDetected(let surface):
            return ["surface": surface]
        case .bereanTheologyBoundaryViolation(let surface):
            return ["surface": surface]
        case .bereanSafetyOutputRewritten(let violationCount):
            return ["violation_count": violationCount]
        case .bereanAppCheckFailure(let surface):
            return ["surface": surface]
        case .bereanOnboardingPageViewed(let page):
            return ["page": page]
        case .bereanOnboardingSkipped(let fromPage):
            return ["from_page": fromPage]
        case .groupPulseViewed(let urgency):
            return ["urgency_level": urgency]
        case .voiceCommentReacted(let postId, let reaction):
            return ["post_id": postId, "reaction": reaction]
        case .voiceCommentRecordStarted(let postId, let type):
            return ["post_id": postId, "type": type]
        case .voiceCommentProcessingStarted(let postId):
            return ["post_id": postId]
        case .voiceCommentEntryTapped(let postId, let type):
            return ["post_id": postId, "type": type]
        case .voiceCommentReported(let postId):
            return ["post_id": postId]
        case .voiceCommentDeleted(let postId):
            return ["post_id": postId]
        case .voiceCommentPreviewPlayed(let postId):
            return ["post_id": postId]
        case .voiceCommentSubmitted(let postId, let type):
            return ["post_id": postId, "type": type]
        case .voiceCommentRecordCancelled(let postId, let type):
            return ["post_id": postId, "type": type]
        case .voiceCommentTranscriptReady(let postId):
            return ["post_id": postId]
        case .voiceCommentPublished(let postId, let type, let durationMs):
            return ["post_id": postId, "type": type, "duration_ms": durationMs]
        case .voiceCommentHeldForReview(let postId):
            return ["post_id": postId]
        case .voiceCommentBlocked(let postId):
            return ["post_id": postId]
        case .voiceCommentVisibilityChanged(let postId, let visibility):
            return ["post_id": postId, "visibility": visibility]
        case .walkWithChristOnboardingCompleted(let path):
            return ["path": path]
        case .walkWithChristSeasonSelected(let season):
            return ["season": season]
        case .walkWithChristBereanLaunched(let sourceSurface):
            return ["source_surface": sourceSurface]
        case .walkWithChristApplicationStepCompleted(let stepIndex):
            return ["step_index": stepIndex]
        case .walkWithChristFollowThroughPlanCreated(let area, let frequency):
            return ["practice_area": area, "frequency": frequency]
        case .walkWithChristFollowThroughCompleted(let planId, let streakDays):
            return ["plan_id": planId, "streak_days": streakDays]
        case .homePostLightbulbTapped(let postId):
            return ["post_id": postId]
        case .homePostAmenReactionTapped(let postId):
            return ["post_id": postId]
        default:
            return [:]
        }
    }
}

// MARK: - Analytics Service

@MainActor
final class AMENAnalyticsService {

    static let shared = AMENAnalyticsService()

    private lazy var db = Firestore.firestore()
    private let flags = AMENFeatureFlags.shared

    // P2 FIX: Session ID — a UUID generated fresh on each app foreground session.
    // Threaded through all events so the analytics backend can reconstruct a full
    // user session funnel (e.g. feed_session_started → berean_session_started →
    // feed_meaningful_interaction) without relying on timestamp proximity alone.
    private(set) var sessionId: String = UUID().uuidString

    /// Call this when the app moves to foreground (scenePhase == .active) to start
    /// a fresh session. Events fired before this retain the prior session ID.
    func startNewSession() {
        sessionId = UUID().uuidString
        dlog("📊 Analytics: new session \(sessionId.prefix(8))…")
    }

    // In-memory buffer for batching (flush every 30s or 20 events).
    // Hard cap at 200 events: if Firestore writes fail repeatedly and the buffer
    // grows past this limit, the oldest events are dropped to prevent OOM.
    private var eventBuffer: [(name: String, props: [String: Any], ts: Date)] = []
    private static let maxBufferSize = 200
    private var flushTask: Task<Void, Never>?

    // MARK: - User Opt-Out (GDPR Article 21)

    /// UserDefaults key for the user's analytics opt-out preference.
    static let analyticsOptOutKey = "amen.analyticsOptOut"

    /// True when the current user has opted out of analytics collection.
    var isUserOptedOut: Bool {
        UserDefaults.standard.bool(forKey: Self.analyticsOptOutKey)
    }

    /// Set the user's analytics opt-out preference.
    /// Also toggles Firebase Analytics collection immediately.
    func setAnalyticsOptOut(_ optOut: Bool) {
        UserDefaults.standard.set(optOut, forKey: Self.analyticsOptOutKey)
        Analytics.setAnalyticsCollectionEnabled(!optOut)
        dlog("📊 Analytics collection \(optOut ? "DISABLED" : "ENABLED") by user preference")
    }

    private init() {
        // Apply stored opt-out preference on launch
        let storedOptOut = UserDefaults.standard.bool(forKey: Self.analyticsOptOutKey)
        if storedOptOut {
            Analytics.setAnalyticsCollectionEnabled(false)
        }

        schedulePeriodicFlush()

        // P1 FIX: Flush buffered Firestore events before the app is suspended.
        // Previously, events batched just before backgrounding were lost if the
        // process was terminated. Firebase Analytics events are already durable
        // (the SDK queues them), so this only applies to the Firestore secondary write.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.flush()
            }
        }
    }

    // MARK: - Track

    func track(_ event: AMENAnalyticsEvent) {
        guard flags.analyticsEnabled, !isUserOptedOut else { return }

        // P1 FIX: Fire to Firebase Analytics immediately — events are durable and
        // survive sign-out and process termination. The Firestore batch write below
        // is secondary (for custom dashboards) and requires a signed-in user.
        // P2 FIX: Thread sessionId through every event so the backend can reconstruct
        // complete user sessions without relying on timestamp proximity.
        var enriched = event.properties
        enriched["session_id"] = sessionId
        let params: [String: Any]? = enriched.isEmpty ? nil : enriched
        Analytics.logEvent(event.name, parameters: params)

        // Buffer for secondary Firestore write (requires auth).
        // Drop oldest entry first if the buffer has reached the hard cap,
        // preventing unbounded growth when Firestore writes fail repeatedly.
        if eventBuffer.count >= Self.maxBufferSize {
            eventBuffer.removeFirst()
        }
        eventBuffer.append((event.name, enriched, Date()))
        if eventBuffer.count >= 20 {
            Task { await flush() }
        }
    }

    // MARK: - Flush (Firestore secondary write)

    private func flush() async {
        guard !eventBuffer.isEmpty else { return }

        let toFlush = eventBuffer
        eventBuffer.removeAll()

        // P1 FIX: Don't drop events on sign-out — Firebase Analytics already fired.
        // Only skip the Firestore write if there's no authenticated user, since the
        // Firestore rules require auth. Events are NOT discarded from the perspective
        // of the analytics platform (Firebase Analytics received them above).
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let batch = db.batch()
        for event in toFlush {
            var data: [String: Any] = ["event": event.name, "ts": Timestamp(date: event.ts)]
            for (k, v) in event.props { data[k] = v }
            let ref = db
                .collection("analytics")
                .document(uid)
                .collection("events")
                .document()
            batch.setData(data, forDocument: ref)
        }
        try? await batch.commit()
    }

    private func schedulePeriodicFlush() {
        flushTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)  // 30s
                await flush()
            }
        }
    }

    // MARK: - Performance Telemetry

    func recordLatency(operation: String, milliseconds: Double) {
        guard flags.performanceTelemetryEnabled else { return }
        track(.bereanResponseGenerated(latencyMs: milliseconds, sourceCount: 0))
    }
}
