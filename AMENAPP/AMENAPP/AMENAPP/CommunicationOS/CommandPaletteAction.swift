import Foundation

enum CommandPaletteIntent: String, Codable, CaseIterable {
    case summarizeThread = "summarize_thread"
    case catchUp = "catch_up"
    case showQuestions = "show_questions"
    case showBlockers = "show_blockers"
    case createTask = "create_task"
    case searchMemory = "search_memory"
    case showDecisions = "show_decisions"
    case findOwner = "find_owner"
    case draftResponse = "draft_response"
    case showMedia = "show_media"
    case createWorkspace = "create_workspace"
    case navigate
}

struct CommandPaletteAction: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var intent: CommandPaletteIntent
    var query: String
    var sourceThreadId: String?
    var sourceMessageId: String?
    var confidence: Double?
}
