import Foundation

// MARK: - Spiritual OS surface identifier
// Used by AssistantBar and Context Engine to scope quick-prompts and mode switches.
// Defined in SharedComponents.contract.md — do not add cases without Lead sign-off.

enum SOSurface: String, Codable, Hashable {
    case dailyDigest    = "daily_digest"
    case unifiedHub     = "unified_hub"
    case lifePlanner    = "life_planner"
    case spaceDashboard = "space_dashboard"
    case createSpace    = "create_space"
    case commandCenter  = "command_center"
    case assistantBar   = "assistant_bar"
    case contextEngine  = "context_engine"
    case communityOS    = "community_os"
}

// MARK: - Context mode
// Produced by the Context Engine (Agent H). All surfaces subscribe via ContextEngineService.

enum SOContextMode: String, Codable, Hashable {
    case `default`         = "default"
    case worshipMode       = "worship_mode"
    case driveMode         = "drive_mode"
    case travelMode        = "travel_mode"
    case eveningReflection = "evening_reflection"
}
