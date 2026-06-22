import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

// MARK: - BereanActionPlanService

@MainActor
final class BereanActionPlanService: ObservableObject {
    static let shared = BereanActionPlanService()

    @Published private(set) var plans: [BereanActionPlan] = []
    @Published private(set) var isGenerating = false

    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Generate Plan

    func generatePlan(
        goal: String,
        planType: BereanActionPlanType,
        projectId: String
    ) async throws -> BereanActionPlan {
        guard AMENFeatureFlags.shared.bereanOSActionPlannerEnabled else {
            throw BereanActionPlanError.featureDisabled
        }
        guard let uid = Auth.auth().currentUser?.uid else {
            throw BereanActionPlanError.unauthenticated
        }

        isGenerating = true
        defer { isGenerating = false }

        let functions = Functions.functions(region: "us-central1")
        let result = try await functions.httpsCallable("bereanGenerateActionPlan").call([
            "goal": goal,
            "planType": planType.rawValue
        ])

        guard let data = result.data as? [String: Any],
              let planData = data["plan"] as? [String: Any] else {
            throw BereanActionPlanError.invalidResponse
        }

        let plan = try decodePlan(from: planData, projectId: projectId)

        // Persist to Firestore
        let path = BereanOSFirestore.actionPlans(uid: uid, projectId: projectId)
        let encoded = encodePlan(plan)
        try await db.collection(path).document(plan.id).setData(encoded)

        plans.insert(plan, at: 0)
        return plan
    }

    // MARK: - Update Milestone Status

    func updateMilestoneStatus(
        planId: String,
        milestoneId: String,
        status: BereanTaskStatus,
        projectId: String
    ) async throws {
        guard AMENFeatureFlags.shared.bereanOSActionPlannerEnabled else {
            throw BereanActionPlanError.featureDisabled
        }
        guard let uid = Auth.auth().currentUser?.uid else {
            throw BereanActionPlanError.unauthenticated
        }

        guard let planIdx = plans.firstIndex(where: { $0.id == planId }),
              let milestoneIdx = plans[planIdx].milestones.firstIndex(where: { $0.id == milestoneId })
        else {
            throw BereanActionPlanError.notFound
        }

        var updatedPlan = plans[planIdx]
        var milestone = updatedPlan.milestones[milestoneIdx]
        milestone = BereanMilestone(
            id: milestone.id,
            title: milestone.title,
            dueDate: milestone.dueDate,
            status: status,
            dependsOnIds: milestone.dependsOnIds,
            tasks: milestone.tasks
        )
        updatedPlan.milestones[milestoneIdx] = milestone

        // Firestore nested update: replace the milestones array
        let path = BereanOSFirestore.actionPlans(uid: uid, projectId: projectId)
        let encodedMilestones = updatedPlan.milestones.map { encodeMilestone($0) }
        try await db.collection(path).document(planId).updateData([
            "milestones": encodedMilestones,
            "updatedAt": Timestamp(date: Date())
        ])

        plans[planIdx] = updatedPlan
    }

    // MARK: - Update Task Status

    func updateTaskStatus(
        planId: String,
        milestoneId: String,
        taskId: String,
        status: BereanTaskStatus,
        projectId: String
    ) async throws {
        guard AMENFeatureFlags.shared.bereanOSActionPlannerEnabled else {
            throw BereanActionPlanError.featureDisabled
        }
        guard let uid = Auth.auth().currentUser?.uid else {
            throw BereanActionPlanError.unauthenticated
        }

        guard let planIdx = plans.firstIndex(where: { $0.id == planId }),
              let milestoneIdx = plans[planIdx].milestones.firstIndex(where: { $0.id == milestoneId }),
              let taskIdx = plans[planIdx].milestones[milestoneIdx].tasks.firstIndex(where: { $0.id == taskId })
        else {
            throw BereanActionPlanError.notFound
        }

        var updatedPlan = plans[planIdx]
        var milestone = updatedPlan.milestones[milestoneIdx]
        var task = milestone.tasks[taskIdx]
        task = BereanOSTask(
            id: task.id,
            title: task.title,
            assignedTo: task.assignedTo,
            dueDate: task.dueDate,
            status: status,
            priority: task.priority
        )
        milestone.tasks[taskIdx] = task
        updatedPlan.milestones[milestoneIdx] = milestone

        let path = BereanOSFirestore.actionPlans(uid: uid, projectId: projectId)
        let encodedMilestones = updatedPlan.milestones.map { encodeMilestone($0) }
        try await db.collection(path).document(planId).updateData([
            "milestones": encodedMilestones,
            "updatedAt": Timestamp(date: Date())
        ])

        plans[planIdx] = updatedPlan
    }

    // MARK: - Fetch Plans

    func fetchPlans(projectId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw BereanActionPlanError.unauthenticated
        }

        let path = BereanOSFirestore.actionPlans(uid: uid, projectId: projectId)
        let snapshot = try await db.collection(path)
            .order(by: "createdAt", descending: true)
            .getDocuments()

        plans = snapshot.documents.compactMap { snap in
            try? decodePlan(from: snap.data(), projectId: projectId)
        }
    }

    // MARK: - Encode / Decode Helpers

    private func encodePlan(_ plan: BereanActionPlan) -> [String: Any] {
        [
            "id": plan.id,
            "projectId": plan.projectId,
            "title": plan.title,
            "planType": plan.planType.rawValue,
            "milestones": plan.milestones.map { encodeMilestone($0) },
            "risks": plan.risks,
            "successMetrics": plan.successMetrics,
            "createdAt": Timestamp(date: plan.createdAt),
            "updatedAt": Timestamp(date: plan.updatedAt)
        ]
    }

    private func encodeMilestone(_ m: BereanMilestone) -> [String: Any] {
        var d: [String: Any] = [
            "id": m.id,
            "title": m.title,
            "status": m.status.rawValue,
            "dependsOnIds": m.dependsOnIds,
            "tasks": m.tasks.map { encodeTask($0) }
        ]
        if let due = m.dueDate {
            d["dueDate"] = Timestamp(date: due)
        }
        return d
    }

    private func encodeTask(_ t: BereanOSTask) -> [String: Any] {
        var d: [String: Any] = [
            "id": t.id,
            "title": t.title,
            "status": t.status.rawValue,
            "priority": t.priority.rawValue
        ]
        if let assignedTo = t.assignedTo { d["assignedTo"] = assignedTo }
        if let due = t.dueDate { d["dueDate"] = Timestamp(date: due) }
        return d
    }

    private func decodePlan(from data: [String: Any], projectId: String) throws -> BereanActionPlan {
        guard
            let id = data["id"] as? String,
            let title = data["title"] as? String,
            let planTypeRaw = data["planType"] as? String,
            let planType = BereanActionPlanType(rawValue: planTypeRaw),
            let createdAtTs = data["createdAt"] as? Timestamp,
            let updatedAtTs = data["updatedAt"] as? Timestamp
        else {
            throw BereanActionPlanError.decodingFailed
        }

        let storedProjectId = data["projectId"] as? String ?? projectId
        let risks = data["risks"] as? [String] ?? []
        let successMetrics = data["successMetrics"] as? [String] ?? []

        let milestonesData = data["milestones"] as? [[String: Any]] ?? []
        let milestones = milestonesData.compactMap { decodeMilestone(from: $0) }

        return BereanActionPlan(
            id: id,
            projectId: storedProjectId,
            title: title,
            planType: planType,
            milestones: milestones,
            risks: risks,
            successMetrics: successMetrics,
            createdAt: createdAtTs.dateValue(),
            updatedAt: updatedAtTs.dateValue()
        )
    }

    private func decodeMilestone(from data: [String: Any]) -> BereanMilestone? {
        guard
            let id = data["id"] as? String,
            let title = data["title"] as? String,
            let statusRaw = data["status"] as? String,
            let status = BereanTaskStatus(rawValue: statusRaw)
        else { return nil }

        let dueDate = (data["dueDate"] as? Timestamp)?.dateValue()
        let dependsOnIds = data["dependsOnIds"] as? [String] ?? []
        let tasksData = data["tasks"] as? [[String: Any]] ?? []
        let tasks = tasksData.compactMap { decodeTask(from: $0) }

        return BereanMilestone(
            id: id,
            title: title,
            dueDate: dueDate,
            status: status,
            dependsOnIds: dependsOnIds,
            tasks: tasks
        )
    }

    private func decodeTask(from data: [String: Any]) -> BereanOSTask? {
        guard
            let id = data["id"] as? String,
            let title = data["title"] as? String,
            let statusRaw = data["status"] as? String,
            let status = BereanTaskStatus(rawValue: statusRaw),
            let priorityRaw = data["priority"] as? String,
            let priority = BereanTaskPriority(rawValue: priorityRaw)
        else { return nil }

        let assignedTo = data["assignedTo"] as? String
        let dueDate = (data["dueDate"] as? Timestamp)?.dateValue()

        return BereanOSTask(
            id: id,
            title: title,
            assignedTo: assignedTo,
            dueDate: dueDate,
            status: status,
            priority: priority
        )
    }
}

// MARK: - Errors

enum BereanActionPlanError: LocalizedError {
    case featureDisabled
    case unauthenticated
    case notFound
    case invalidResponse
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .featureDisabled: return "Action Planner feature is not currently enabled."
        case .unauthenticated: return "You must be signed in to use the Action Planner."
        case .notFound: return "Plan or milestone not found."
        case .invalidResponse: return "Unexpected response from AI service."
        case .decodingFailed: return "Unable to read plan data."
        }
    }
}
