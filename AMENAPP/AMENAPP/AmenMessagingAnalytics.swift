// AmenMessagingAnalytics.swift
// AMENAPP
//
// Lightweight analytics for messaging intelligence features.
// Routes through dlog() — no external service dependency required.

import Foundation

enum AmenMessagingAnalyticsEvent: String, CaseIterable {
    // Smart Pills
    case smartPillRowShown          = "msg_smart_pill_row_shown"
    case smartPillTapped            = "msg_smart_pill_tapped"
    case smartPillDismissed         = "msg_smart_pill_dismissed"
    case smartPillUnavailable       = "msg_smart_pill_unavailable"

    // Translation
    case translationRequested       = "msg_translation_requested"
    case translationSucceeded       = "msg_translation_succeeded"
    case translationFailed          = "msg_translation_failed"
    case translationOriginalToggled = "msg_translation_original_toggled"

    // Save / Cross-Surface
    case saveSheetShown             = "msg_save_sheet_shown"
    case saveToSelahTapped          = "msg_save_selah_tapped"
    // saveToSelahSucceeded — removed: no real save service wired (NB-6 fix)
    case addToChurchNotesTapped     = "msg_add_church_notes_tapped"
    // addToChurchNotesSucceeded — removed: no real save service wired (NB-6 fix)
    case saveToNotesTapped          = "msg_save_notes_tapped"
    case remindMeTapped             = "msg_remind_me_tapped"
    case extractActionsTapped       = "msg_extract_actions_tapped"

    // Safety
    case safetyNudgeShown           = "msg_safety_nudge_shown"
    case safetyNudgeEdited          = "msg_safety_nudge_edited"
    case safetyNudgeSentAnyway      = "msg_safety_nudge_sent_anyway"
    case safetyNudgeCancelled       = "msg_safety_nudge_cancelled"

    // Approval
    case approvalCardShown          = "msg_approval_card_shown"
    case approvalCardAccepted       = "msg_approval_card_accepted"
    case approvalCardDeclined       = "msg_approval_card_declined"

    // Catch Me Up
    case catchUpTrayShown           = "msg_catch_up_tray_shown"
    case catchUpRequested           = "msg_catch_up_requested"
    case catchUpFailed              = "msg_catch_up_failed"
    case catchUpUnavailable         = "msg_catch_up_unavailable"
    case catchUpDismissed           = "msg_catch_up_dismissed"

    // Smart Context
    case decisionCardSeen           = "msg_decision_card_seen"
    case decisionConfirmed          = "msg_decision_confirmed"
    case decisionChallenged         = "msg_decision_challenged"
    case questionCardSeen           = "msg_question_card_seen"
    case questionDismissed          = "msg_question_dismissed"
    case actionCardSeen             = "msg_action_card_seen"
    case actionAccepted             = "msg_action_accepted"
    case actionDone                 = "msg_action_done"
    case actionDismissed            = "msg_action_dismissed"
    case smartContextBarOpened      = "msg_smart_context_bar_opened"
    case threadSummaryOpened        = "msg_thread_summary_opened"
    case threadSummaryGenerated     = "msg_thread_summary_generated"

    // Group Pulse
    case groupPulseOpened           = "msg_group_pulse_opened"
    case groupPulseGenerated        = "msg_group_pulse_generated"

    // Command Palette
    case commandPaletteOpened          = "msg_command_palette_opened"
    case commandPaletteAction          = "msg_command_palette_action"
    case commandPaletteResultSelected  = "msg_command_palette_result_selected"

    // Media Intelligence
    case mediaContextOpened         = "msg_media_context_opened"
    case mediaSummaryGenerated      = "msg_media_summary_generated"
    case mediaTranscribed           = "msg_media_transcribed"

    // Memory / Search
    case conversationMemorySearch   = "msg_conversation_memory_search"

    // Smart Replies
    case smartReplyUsed             = "msg_smart_reply_used"

    // Attachment Menu
    case attachmentMenuOpened       = "msg_attachment_menu_opened"
    case attachmentMenuActionTapped = "msg_attachment_menu_action_tapped"
    case attachmentMenuUnavailable  = "msg_attachment_menu_unavailable"

    // Presence
    case presenceStatusChanged      = "msg_presence_status_changed"
    case focusModeEnabled           = "msg_focus_mode_enabled"
    case quietModeEnabled           = "msg_quiet_mode_enabled"

    // Message Action Cluster
    case messageActionClusterShown  = "msg_action_cluster_shown"
    case messageActionTapped        = "msg_action_tapped"

    // Voice
    case voiceTranscriptRequested   = "msg_voice_transcript_requested"
    case voiceTranscriptUnavailable = "msg_voice_transcript_unavailable"

    // Media
    case mediaActionsShown          = "msg_media_actions_shown"
    case mediaSavedToLibrary        = "msg_media_saved_to_library"
    case mediaShared                = "msg_media_shared"

    // Presence
    case readReceiptShown           = "msg_read_receipt_shown"
}

struct AmenMessagingAnalytics {
    static func track(_ event: AmenMessagingAnalyticsEvent, parameters: [String: Any] = [:]) {
        guard AMENFeatureFlags.shared.analyticsEnabled else { return }
        dlog("[MsgAnalytics] \(event.rawValue)\(parameters.isEmpty ? "" : " \(parameters)")")
    }
}
