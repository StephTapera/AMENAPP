// ContextualExperienceService.swift
// AMENAPP — Multi-Tenant Contextual Experience System
//
// Firestore + Cloud Functions service layer for AMEN Contextual Experiences.
// All mutations go through Cloud Functions (camelCase names match the backend
// agent's deployment). Reads use direct Firestore access where applicable.
//
// Constraints:
//   - @MainActor throughout
//   - No Combine — async/await + @Published
//   - No force-unwrap
//   - NEVER log prayer content or user PII in dlog calls

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

// MARK: - ContextualExperienceError

enum ContextualExperienceError: LocalizedError {
    case notAuthenticated
    case notFound
    case permissionDenied
    case encodingFailed
    case invalidResponse
    case invalidArgument(String)
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in."
        case .notFound:
            return "The experience was not found."
        case .permissionDenied:
            return "You do not have permission to perform this action."
        case .encodingFailed:
            return "Failed to encode the data."
        case .invalidResponse:
            return "Received an unexpected response from the server."
        case .invalidArgument(let msg):
            return msg
        case .underlying(let error):
            return error.localizedDescription
        }
    }
}

// MARK: - ContextualExperienceService

@MainActor
final class ContextualExperienceService: ObservableObject {

    static let shared = ContextualExperienceService()

    private let db = Firestore.firestore()
    private let functions = Functions.functions(region: "us-central1")

    private init() {}

    // MARK: - Auth helper

    private var currentUID: String {
        get throws {
            guard let uid = Auth.auth().currentUser?.uid else {
                throw ContextualExperienceError.notAuthenticated
            }
            return uid
        }
    }

    // MARK: - CF helper

    private func call(_ name: String, _ payload: [String: Any]) async throws -> [String: Any] {
        let callable = functions.httpsCallable(name)
        do {
            let result = try await callable.call(payload)
            guard let data = result.data as? [String: Any] else {
                throw ContextualExperienceError.invalidResponse
            }
            return data
        } catch let err as ContextualExperienceError {
            throw err
        } catch {
            throw ContextualExperienceError.underlying(error)
        }
    }

    // MARK: - Create / Modify

    /// Creates a new experience in the organization.
    /// Returns the new experienceId on success.
    func createExperience(
        orgId: String,
        orgType: OrganizationType,
        type: ExperienceType,
        title: String,
        description: String,
        region: String?,
        startDate: Date,
        endDate: Date,
        visibility: ExperienceScope,
        theme: ExperienceThemeConfig,
        modules: [ExperienceModuleType],
        safety: ExperienceSafetyConfig
    ) async throws -> String {
        guard !orgId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ContextualExperienceError.invalidArgument("orgId cannot be empty.")
        }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ContextualExperienceError.invalidArgument("title cannot be empty.")
        }

        var payload: [String: Any] = [
            "orgId": orgId,
            "orgType": orgType.rawValue,
            "type": type.rawValue,
            "title": title,
            "description": description,
            "startDate": startDate.timeIntervalSince1970,
            "endDate": endDate.timeIntervalSince1970,
            "visibility": visibility.rawValue,
            "theme": [
                "accentColorHex": theme.accentColorHex,
                "motionIntensity": theme.motionIntensity,
                "glassOpacity": theme.glassOpacity,
                "backgroundStyle": theme.backgroundStyle
            ],
            "modules": modules.map(\.rawValue),
            "safety": [
                "requiresYouthProtection": safety.requiresYouthProtection,
                "moderationStrictness": safety.moderationStrictness,
                "allowAnonymousPrayer": safety.allowAnonymousPrayer,
                "requireApprovalToJoin": safety.requireApprovalToJoin,
                "griefSensitiveMode": safety.griefSensitiveMode
            ]
        ]
        if let region {
            payload["region"] = region
        }

        let response = try await call("createContextualExperience", payload)
        guard let experienceId = response["experienceId"] as? String, !experienceId.isEmpty else {
            throw ContextualExperienceError.invalidResponse
        }
        dlog("createExperience: created \(experienceId) in org \(orgId)")
        return experienceId
    }

    func updateExperience(id: String, updates: [String: Any]) async throws {
        guard !id.isEmpty else {
            throw ContextualExperienceError.invalidArgument("id cannot be empty.")
        }
        var payload = updates
        payload["experienceId"] = id
        _ = try await call("updateContextualExperience", payload)
        dlog("updateExperience: updated \(id)")
    }

    func publishExperience(id: String) async throws {
        guard !id.isEmpty else {
            throw ContextualExperienceError.invalidArgument("id cannot be empty.")
        }
        _ = try await call("publishContextualExperience", ["experienceId": id])
        dlog("publishExperience: published \(id)")
    }

    func unpublishExperience(id: String) async throws {
        guard !id.isEmpty else {
            throw ContextualExperienceError.invalidArgument("id cannot be empty.")
        }
        _ = try await call("unpublishContextualExperience", ["experienceId": id])
        dlog("unpublishExperience: unpublished \(id)")
    }

    func archiveExperience(id: String) async throws {
        guard !id.isEmpty else {
            throw ContextualExperienceError.invalidArgument("id cannot be empty.")
        }
        _ = try await call("archiveContextualExperience", ["experienceId": id])
        dlog("archiveExperience: archived \(id)")
    }

    func deleteExperience(id: String) async throws {
        guard !id.isEmpty else {
            throw ContextualExperienceError.invalidArgument("id cannot be empty.")
        }
        _ = try await call("deleteContextualExperience", ["experienceId": id])
        dlog("deleteExperience: deleted \(id)")
    }

    // MARK: - Participation

    func joinExperience(id: String) async throws {
        guard !id.isEmpty else {
            throw ContextualExperienceError.invalidArgument("id cannot be empty.")
        }
        _ = try await call("joinContextualExperience", ["experienceId": id])
        dlog("joinExperience: joined \(id)")
    }

    func leaveExperience(id: String) async throws {
        guard !id.isEmpty else {
            throw ContextualExperienceError.invalidArgument("id cannot be empty.")
        }
        _ = try await call("leaveContextualExperience", ["experienceId": id])
        dlog("leaveExperience: left \(id)")
    }

    // MARK: - List / Fetch

    func listOrgExperiences(orgId: String, status: ContextualExperienceStatus?) async throws -> [ContextualExperience] {
        guard !orgId.isEmpty else {
            throw ContextualExperienceError.invalidArgument("orgId cannot be empty.")
        }
        var payload: [String: Any] = ["orgId": orgId]
        if let status {
            payload["status"] = status.rawValue
        }
        let response = try await call("listOrganizationExperiences", payload)
        guard let rawList = response["experiences"] as? [[String: Any]] else {
            return []
        }
        return rawList.compactMap { dict -> ContextualExperience? in
            guard let jsonData = try? JSONSerialization.data(withJSONObject: dict),
                  let decoded = try? JSONDecoder().decode(ContextualExperience.self, from: jsonData) else {
                return nil
            }
            return decoded
        }
    }

    func getExperience(id: String) async throws -> ContextualExperience {
        guard !id.isEmpty else {
            throw ContextualExperienceError.invalidArgument("id cannot be empty.")
        }
        let doc = try await db.collection("contextualExperiences").document(id).getDocument()
        guard doc.exists else {
            throw ContextualExperienceError.notFound
        }
        guard let experience = try? doc.data(as: ContextualExperience.self) else {
            throw ContextualExperienceError.encodingFailed
        }
        return experience
    }

    // MARK: - Modules

    func addEvent(
        to experienceId: String,
        title: String,
        description: String,
        startDate: Date,
        endDate: Date,
        location: String?
    ) async throws -> String {
        guard !experienceId.isEmpty else {
            throw ContextualExperienceError.invalidArgument("experienceId cannot be empty.")
        }
        var payload: [String: Any] = [
            "experienceId": experienceId,
            "title": title,
            "description": description,
            "startDate": startDate.timeIntervalSince1970,
            "endDate": endDate.timeIntervalSince1970
        ]
        if let location {
            payload["location"] = location
        }
        let response = try await call("createExperienceEvent", payload)
        guard let itemId = response["eventId"] as? String, !itemId.isEmpty else {
            throw ContextualExperienceError.invalidResponse
        }
        return itemId
    }

    func addPrayerPrompt(
        to experienceId: String,
        prompt: String,
        scripture: String?,
        anonymousAllowed: Bool
    ) async throws -> String {
        guard !experienceId.isEmpty else {
            throw ContextualExperienceError.invalidArgument("experienceId cannot be empty.")
        }
        // Never log prompt content
        var payload: [String: Any] = [
            "experienceId": experienceId,
            "anonymousAllowed": anonymousAllowed
        ]
        // Payload values must not be logged
        payload["prompt"] = prompt
        if let scripture {
            payload["scriptureReference"] = scripture
        }
        let response = try await call("createExperiencePrayerPrompt", payload)
        guard let itemId = response["promptId"] as? String, !itemId.isEmpty else {
            throw ContextualExperienceError.invalidResponse
        }
        return itemId
    }

    func addDiscussion(
        to experienceId: String,
        title: String,
        body: String
    ) async throws -> String {
        guard !experienceId.isEmpty else {
            throw ContextualExperienceError.invalidArgument("experienceId cannot be empty.")
        }
        let payload: [String: Any] = [
            "experienceId": experienceId,
            "title": title,
            "body": body
        ]
        let response = try await call("createExperienceDiscussion", payload)
        guard let itemId = response["discussionId"] as? String, !itemId.isEmpty else {
            throw ContextualExperienceError.invalidResponse
        }
        return itemId
    }

    func addMemory(
        to experienceId: String,
        title: String,
        imageURL: String?,
        note: String,
        scripture: String?
    ) async throws -> String {
        guard !experienceId.isEmpty else {
            throw ContextualExperienceError.invalidArgument("experienceId cannot be empty.")
        }
        var payload: [String: Any] = [
            "experienceId": experienceId,
            "title": title,
            "note": note
        ]
        if let imageURL {
            payload["imageURL"] = imageURL
        }
        if let scripture {
            payload["scriptureReference"] = scripture
        }
        let response = try await call("createExperienceMemory", payload)
        guard let itemId = response["memoryId"] as? String, !itemId.isEmpty else {
            throw ContextualExperienceError.invalidResponse
        }
        return itemId
    }

    func addTradition(
        to experienceId: String,
        title: String,
        description: String,
        recurrence: String
    ) async throws -> String {
        guard !experienceId.isEmpty else {
            throw ContextualExperienceError.invalidArgument("experienceId cannot be empty.")
        }
        let payload: [String: Any] = [
            "experienceId": experienceId,
            "title": title,
            "description": description,
            "recurrencePattern": recurrence
        ]
        let response = try await call("createExperienceTradition", payload)
        guard let itemId = response["traditionId"] as? String, !itemId.isEmpty else {
            throw ContextualExperienceError.invalidResponse
        }
        return itemId
    }

    // MARK: - Moderation

    func moderateContent(
        experienceId: String,
        contentType: String,
        contentId: String,
        action: String,
        reason: String?
    ) async throws {
        var payload: [String: Any] = [
            "experienceId": experienceId,
            "contentType": contentType,
            "contentId": contentId,
            "action": action
        ]
        if let reason {
            payload["reason"] = reason
        }
        _ = try await call("moderateExperienceContent", payload)
        dlog("moderateContent: \(action) on \(contentType)/\(contentId) in \(experienceId)")
    }

    func reportContent(
        experienceId: String,
        contentType: String,
        contentId: String,
        reason: String,
        details: String?
    ) async throws {
        var payload: [String: Any] = [
            "experienceId": experienceId,
            "contentType": contentType,
            "contentId": contentId,
            "reason": reason
        ]
        if let details {
            payload["details"] = details
        }
        _ = try await call("reportExperienceContent", payload)
        dlog("reportContent: \(contentType)/\(contentId) in \(experienceId)")
    }

    // MARK: - Settings

    func updateNotificationSettings(experienceId: String, settings: [String: Bool]) async throws {
        guard !experienceId.isEmpty else {
            throw ContextualExperienceError.invalidArgument("experienceId cannot be empty.")
        }
        let payload: [String: Any] = [
            "experienceId": experienceId,
            "settings": settings
        ]
        _ = try await call("updateExperienceNotificationSettings", payload)
        dlog("updateNotificationSettings: updated for \(experienceId)")
    }

    func updateTheme(experienceId: String, theme: ExperienceThemeConfig) async throws {
        guard !experienceId.isEmpty else {
            throw ContextualExperienceError.invalidArgument("experienceId cannot be empty.")
        }
        let payload: [String: Any] = [
            "experienceId": experienceId,
            "theme": [
                "accentColorHex": theme.accentColorHex,
                "motionIntensity": theme.motionIntensity,
                "glassOpacity": theme.glassOpacity,
                "backgroundStyle": theme.backgroundStyle
            ]
        ]
        _ = try await call("updateExperienceTheme", payload)
        dlog("updateTheme: updated for \(experienceId)")
    }

    func getAnalytics(experienceId: String) async throws -> ExperienceAnalytics {
        guard !experienceId.isEmpty else {
            throw ContextualExperienceError.invalidArgument("experienceId cannot be empty.")
        }
        let response = try await call("getExperienceAnalytics", ["experienceId": experienceId])
        guard let data = try? JSONSerialization.data(withJSONObject: response),
              let analytics = try? JSONDecoder().decode(ExperienceAnalytics.self, from: data) else {
            throw ContextualExperienceError.encodingFailed
        }
        return analytics
    }

    func manageRoles(
        orgId: String,
        targetUserId: String,
        role: OrgMemberRole,
        action: String
    ) async throws {
        guard !orgId.isEmpty, !targetUserId.isEmpty else {
            throw ContextualExperienceError.invalidArgument("orgId and targetUserId cannot be empty.")
        }
        let payload: [String: Any] = [
            "orgId": orgId,
            "targetUserId": targetUserId,
            "role": role.rawValue,
            "action": action
        ]
        _ = try await call("manageExperienceRoles", payload)
        dlog("manageRoles: \(action) role \(role.rawValue) for userId in org \(orgId)")
    }

    // MARK: - Real-time Listener

    /// Attaches a real-time Firestore listener for all experiences in an organization.
    /// Returns a `ListenerRegistration` that the caller must retain and call `remove()` on when done.
    nonisolated func startListeningToOrgExperiences(
        orgId: String,
        onUpdate: @escaping ([ContextualExperience]) -> Void
    ) -> ListenerRegistration {
        Firestore.firestore()
            .collection("contextualExperiences")
            .whereField("organizationId", isEqualTo: orgId)
            .whereField("status", isNotEqualTo: ContextualExperienceStatus.deleted.rawValue)
            .order(by: "status")
            .order(by: "startDate", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error {
                    dlog("startListeningToOrgExperiences error: \(error.localizedDescription)")
                    return
                }
                let experiences = snapshot?.documents.compactMap {
                    try? $0.data(as: ContextualExperience.self)
                } ?? []
                Task { @MainActor in
                    onUpdate(experiences)
                }
            }
    }

    // MARK: - Safety / Moderation controls

    /// Enables or disables slow mode for an experience.
    func setSlowMode(experienceId: String, enabled: Bool) async throws {
        guard !experienceId.isEmpty else {
            throw ContextualExperienceError.invalidArgument("experienceId cannot be empty.")
        }
        _ = try await call("setExperienceSlowMode", [
            "experienceId": experienceId,
            "enabled": enabled
        ])
        dlog("setSlowMode: \(enabled) for \(experienceId)")
    }

    /// Locks an experience, preventing all interactions.
    func lockExperience(experienceId: String) async throws {
        guard !experienceId.isEmpty else {
            throw ContextualExperienceError.invalidArgument("experienceId cannot be empty.")
        }
        _ = try await call("lockContextualExperience", ["experienceId": experienceId])
        dlog("lockExperience: locked \(experienceId)")
    }

    /// Fetches the report queue for a given experience.
    func fetchReports(experienceId: String) async throws -> [ExperienceContentReport] {
        guard !experienceId.isEmpty else {
            throw ContextualExperienceError.invalidArgument("experienceId cannot be empty.")
        }
        let snap = try await db
            .collection("contextualExperiences")
            .document(experienceId)
            .collection("reports")
            .whereField("status", isEqualTo: "pending")
            .order(by: "createdAt", descending: true)
            .getDocuments()
        return snap.documents.compactMap { doc -> ExperienceContentReport? in
            guard
                let reason = doc["reason"] as? String,
                let statusStr = doc["status"] as? String,
                let status = ExperienceContentReport.ReportStatus(rawValue: statusStr),
                let ts = doc["createdAt"] as? Timestamp
            else { return nil }
            return ExperienceContentReport(
                id: doc.documentID,
                reason: reason,
                status: status,
                createdAt: ts.dateValue()
            )
        }
    }

    // MARK: - Module content reads

    /// Returns all prayer prompts for an experience (Firestore direct read).
    func fetchPrayerPrompts(experienceId: String) async throws -> [ExperiencePrayerPrompt] {
        guard !experienceId.isEmpty else {
            throw ContextualExperienceError.invalidArgument("experienceId cannot be empty.")
        }
        let snap = try await db
            .collection("contextualExperiences")
            .document(experienceId)
            .collection("prayerPrompts")
            .order(by: "createdAt", descending: false)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: ExperiencePrayerPrompt.self) }
    }

    /// Returns all discussions for an experience (Firestore direct read).
    func fetchDiscussions(experienceId: String) async throws -> [ExperienceDiscussion] {
        guard !experienceId.isEmpty else {
            throw ContextualExperienceError.invalidArgument("experienceId cannot be empty.")
        }
        let snap = try await db
            .collection("contextualExperiences")
            .document(experienceId)
            .collection("discussions")
            .order(by: "createdAt", descending: true)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: ExperienceDiscussion.self) }
    }

    /// Returns all events for an experience (Firestore direct read).
    func fetchEvents(experienceId: String) async throws -> [ExperienceEvent] {
        guard !experienceId.isEmpty else {
            throw ContextualExperienceError.invalidArgument("experienceId cannot be empty.")
        }
        let snap = try await db
            .collection("contextualExperiences")
            .document(experienceId)
            .collection("events")
            .order(by: "startDate", descending: false)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: ExperienceEvent.self) }
    }

    /// Returns all memories for an experience (Firestore direct read).
    func fetchMemories(experienceId: String) async throws -> [ExperienceMemory] {
        guard !experienceId.isEmpty else {
            throw ContextualExperienceError.invalidArgument("experienceId cannot be empty.")
        }
        let snap = try await db
            .collection("contextualExperiences")
            .document(experienceId)
            .collection("memories")
            .order(by: "createdAt", descending: true)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: ExperienceMemory.self) }
    }

    /// Returns all traditions for an experience (Firestore direct read).
    func fetchTraditions(experienceId: String) async throws -> [ExperienceTradition] {
        guard !experienceId.isEmpty else {
            throw ContextualExperienceError.invalidArgument("experienceId cannot be empty.")
        }
        let snap = try await db
            .collection("contextualExperiences")
            .document(experienceId)
            .collection("traditions")
            .order(by: "createdAt", descending: false)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: ExperienceTradition.self) }
    }
}
