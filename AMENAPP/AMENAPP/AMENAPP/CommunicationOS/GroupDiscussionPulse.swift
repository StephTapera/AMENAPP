import Foundation

enum GroupDiscussionActivityLevel: String, Codable, CaseIterable {
    case quiet
    case active
    case high
}

// UI coordination model — lightweight, not persisted to Firestore.
// The Firestore-backed canonical type is GroupDiscussionPulse in AmenSmartCollaborationContracts.swift.
struct GroupDiscussionPulseUI: Identifiable, Codable, Equatable {
    var id: String = "main"
    var groupId: String
    var discussionId: String
    var activeTopic: String
    var activityLevel: GroupDiscussionActivityLevel
    var openQuestionsCount: Int
    var pendingDecisionCount: Int
    var taskCount: Int
    var recentMediaCount: Int
    var peopleNeedingResponse: [String]
    var suggestedNextAction: String?
    var generatedAt: Date
}
