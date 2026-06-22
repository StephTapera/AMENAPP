// Safe analytics event names and parameter keys for Communication OS.
// These events track interactions, NEVER raw content.
//
// Usage:
//   Analytics.logEvent(CommunicationOSAnalyticsEvent.smartMessageActionTapped.rawValue, parameters: [
//       CommunicationOSAnalyticsParam.actionKey.rawValue: "createReminder",
//       CommunicationOSAnalyticsParam.detectionType.rawValue: "date",
//   ])

enum CommunicationOSAnalyticsEvent: String {
    case smartMessageContextDetected  = "smart_message_context_detected"
    case smartMessageActionTapped     = "smart_message_action_tapped"
    case conversationMemorySaved      = "conversation_memory_saved"
    case privateContactNoteSaved      = "private_contact_note_saved"
    case smartPostContextDetected     = "smart_post_context_detected"
    case smartPostActionTapped        = "smart_post_action_tapped"
    case moderationWarningShown       = "moderation_warning_shown"
    case moderationBlockedContent     = "moderation_blocked_content"
    case liquidGlassMenuOpened        = "liquid_glass_menu_opened"
    case threadMiniSummaryGenerated   = "thread_mini_summary_generated"
}

enum CommunicationOSAnalyticsParam: String {
    case detectionType = "detection_type"   // e.g. "link", "date", "music"
    case actionKey     = "action_key"       // e.g. "createReminder"
    case memoryType    = "memory_type"      // e.g. "link", "date"
    case severity      = "severity"         // e.g. "safe", "review"
    case category      = "category"         // e.g. "spam"
    // NEVER log: message_text, note_text, post_text, uid_target
}
