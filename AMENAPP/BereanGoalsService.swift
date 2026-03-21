//
//  BereanGoalsService.swift
//  AMENAPP
//
//  Local goal persistence for the Berean AI goals feature.
//  Uses UserDefaults to store [BereanGoal].
//

import Combine
import Foundation

// MARK: - BereanGoalCategory

enum BereanGoalCategory: String, CaseIterable, Codable {
    case spiritual     = "spiritual"
    case health        = "health"
    case work          = "work"
    case relationships = "relationships"

    var icon: String {
        switch self {
        case .spiritual:     return "cross.circle.fill"
        case .health:        return "heart.fill"
        case .work:          return "briefcase.fill"
        case .relationships: return "person.2.fill"
        }
    }

    var displayName: String {
        switch self {
        case .spiritual:     return "Spiritual"
        case .health:        return "Health"
        case .work:          return "Work"
        case .relationships: return "Relationships"
        }
    }

    var accentColorHex: String {
        switch self {
        case .spiritual:     return "7C5CBF"  // purple
        case .health:        return "E05D5D"  // coral/red
        case .work:          return "3A82F6"  // blue
        case .relationships: return "27AE60"  // green
        }
    }
}

// MARK: - BereanGoal Model

struct BereanGoal: Codable, Identifiable {
    let id: UUID
    var title: String
    var category: String            // BereanGoalCategory.rawValue
    var isCompleted: Bool
    let createdAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        category: String = BereanGoalCategory.spiritual.rawValue,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    var goalCategory: BereanGoalCategory {
        BereanGoalCategory(rawValue: category) ?? .spiritual
    }
}

// MARK: - BereanGoalsService

final class BereanGoalsService: ObservableObject {

    static let shared = BereanGoalsService()

    private let storageKey = "berean_goals_v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    @Published private(set) var goals: [BereanGoal] = []

    private init() {
        goals = loadGoals()
    }

    // MARK: - Public API

    /// Persist the provided goal list, replacing existing storage.
    func saveGoals(_ goals: [BereanGoal]) {
        persist(goals)
        DispatchQueue.main.async { self.goals = goals }
    }

    /// Add a single new goal, or update if id already exists.
    func addOrUpdate(_ goal: BereanGoal) {
        var current = loadGoals()
        if let index = current.firstIndex(where: { $0.id == goal.id }) {
            current[index] = goal
        } else {
            current.insert(goal, at: 0)
        }
        persist(current)
        DispatchQueue.main.async { self.goals = current }
    }

    /// Load all goals from UserDefaults (active goals first, then completed).
    func loadGoals() -> [BereanGoal] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? decoder.decode([BereanGoal].self, from: data) else {
            return []
        }
        return decoded.sorted { !$0.isCompleted && $1.isCompleted }
    }

    /// Mark a goal as complete by its UUID. Sets completedAt to now.
    func markComplete(_ id: UUID) {
        var current = loadGoals()
        guard let index = current.firstIndex(where: { $0.id == id }) else { return }
        current[index].isCompleted = true
        current[index].completedAt = Date()
        persist(current)
        DispatchQueue.main.async { self.goals = current }
    }

    /// Toggle the completion state of a goal.
    func toggleComplete(_ id: UUID) {
        var current = loadGoals()
        guard let index = current.firstIndex(where: { $0.id == id }) else { return }
        current[index].isCompleted.toggle()
        current[index].completedAt = current[index].isCompleted ? Date() : nil
        persist(current)
        DispatchQueue.main.async { self.goals = current }
    }

    /// Delete a goal by UUID.
    func deleteGoal(_ id: UUID) {
        var current = loadGoals()
        current.removeAll { $0.id == id }
        persist(current)
        DispatchQueue.main.async { self.goals = current }
    }

    // MARK: - Helpers

    var activeGoals: [BereanGoal] { goals.filter { !$0.isCompleted } }
    var completedGoals: [BereanGoal] { goals.filter { $0.isCompleted } }

    // MARK: - Private

    private func persist(_ goals: [BereanGoal]) {
        if let data = try? encoder.encode(goals) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
