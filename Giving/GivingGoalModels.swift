import Foundation
import FirebaseFirestore

enum GoalFrequency: String, Codable, CaseIterable {
    case monthly, quarterly, yearly, custom
    var displayName: String { rawValue.capitalized }
}

enum ReminderFrequency: String, Codable, CaseIterable {
    case weekly, biweekly, daily
    var displayName: String {
        switch self { case .weekly: return "Weekly"; case .biweekly: return "Every 2 Weeks"; case .daily: return "Daily" }
    }
}

struct GivingGoal: Identifiable, Codable {
    @DocumentID var id: String?
    var title: String
    var description: String
    var targetAmount: Int?
    var targetCount: Int?
    var currentAmount: Int
    var currentCount: Int
    var status: GoalStatus
    var createdAt: Timestamp?
    var deadline: Timestamp?
    var frequency: GoalFrequency
    var reminderFrequency: ReminderFrequency
    var organizations: [GoalOrganization]

    enum GoalStatus: String, Codable {
        case active, paused, completed
        var displayName: String { rawValue.capitalized }
        var color: String {
            switch self { case .active: return "green"; case .paused: return "orange"; case .completed: return "blue" }
        }
    }

    struct GoalOrganization: Codable, Identifiable {
        var id: String { orgId }
        var orgId: String
        var orgName: String
        var targetAmount: Int?
        var currentAmount: Int
    }

    var countProgressFraction: Double {
        guard let target = targetCount, target > 0 else { return 0 }
        return min(Double(currentCount) / Double(target), 1.0)
    }

    var amountProgressFraction: Double {
        guard let target = targetAmount, target > 0 else { return 0 }
        return min(Double(currentAmount) / Double(target), 1.0)
    }

    var isCompleted: Bool {
        if let count = targetCount, currentCount >= count { return true }
        if let amount = targetAmount, currentAmount >= amount { return true }
        return false
    }
}
