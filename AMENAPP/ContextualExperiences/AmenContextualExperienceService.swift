import Foundation
import FirebaseFunctions
import UIKit

@MainActor
final class AmenContextualExperienceService: ObservableObject {
    static let shared = AmenContextualExperienceService()

    private let functions = Functions.functions()

    private init() {}

    func createExperience(_ draft: AmenExperienceDraft) async throws -> String {
        let result = try await call("createContextualExperience", payload: draft.payload)
        guard let id = result["experienceId"] as? String else { throw AmenContextualExperienceError.invalidResponse }
        return id
    }

    func updateExperience(id: String, draft: AmenExperienceDraft) async throws {
        var payload = draft.payload
        payload["experienceId"] = id
        _ = try await call("updateContextualExperience", payload: payload)
    }

    func publishExperience(id: String) async throws { try await statusCall("publishContextualExperience", id: id) }
    func unpublishExperience(id: String) async throws { try await statusCall("unpublishContextualExperience", id: id) }
    func archiveExperience(id: String) async throws { try await statusCall("archiveContextualExperience", id: id) }
    func deleteExperience(id: String) async throws { try await statusCall("deleteContextualExperience", id: id) }
    func joinExperience(id: String) async throws { try await statusCall("joinContextualExperience", id: id) }
    func leaveExperience(id: String) async throws { try await statusCall("leaveContextualExperience", id: id) }

    func listOrganizationExperiences(organizationId: String) async throws -> [AmenContextualExperience] {
        let result = try await call("listOrganizationExperiences", payload: ["organizationId": organizationId])
        let rows = result["experiences"] as? [[String: Any]] ?? []
        return rows.compactMap { AmenContextualExperience.from($0) }
    }

    func getExperience(id: String) async throws -> (AmenContextualExperience, Bool) {
        let result = try await call("getContextualExperience", payload: ["experienceId": id])
        guard let raw = result["experience"] as? [String: Any] else { throw AmenContextualExperienceError.invalidResponse }
        let canManage = result["canManage"] as? Bool ?? false
        guard let experience = AmenContextualExperience.from(raw, canManage: canManage) else { throw AmenContextualExperienceError.invalidResponse }
        return (experience, canManage)
    }

    func createEvent(experienceId: String, title: String, body: String) async throws -> String { try await createModule(function: "createExperienceEvent", experienceId: experienceId, title: title, body: body) }
    func createPrayerPrompt(experienceId: String, title: String, body: String) async throws -> String { try await createModule(function: "createExperiencePrayerPrompt", experienceId: experienceId, title: title, body: body) }
    func createDiscussion(experienceId: String, title: String, body: String) async throws -> String { try await createModule(function: "createExperienceDiscussion", experienceId: experienceId, title: title, body: body) }
    func createMemory(experienceId: String, title: String, body: String) async throws -> String { try await createModule(function: "createExperienceMemory", experienceId: experienceId, title: title, body: body) }
    func createTradition(experienceId: String, title: String, body: String) async throws -> String { try await createModule(function: "createExperienceTradition", experienceId: experienceId, title: title, body: body) }

    func reportExperience(id: String, reason: String) async throws {
        _ = try await call("reportExperienceContent", payload: ["experienceId": id, "reason": reason])
    }

    func moderateContent(experienceId: String, moduleType: String, moduleId: String, action: String) async throws {
        _ = try await call("moderateExperienceContent", payload: [
            "experienceId": experienceId,
            "moduleType": moduleType,
            "moduleId": moduleId,
            "action": action
        ])
    }

    func updateNotifications(experienceId: String, enabled: Bool, quietMode: Bool) async throws {
        _ = try await call("updateExperienceNotificationSettings", payload: [
            "experienceId": experienceId,
            "enabled": enabled,
            "quietMode": quietMode
        ])
    }

    func updateTheme(experienceId: String, theme: AmenExperienceTheme) async throws {
        _ = try await call("updateExperienceTheme", payload: [
            "experienceId": experienceId,
            "theme": [
                "accentName": theme.accentName,
                "accentHex": theme.accentHex as Any,
                "glassIntensity": theme.glassIntensity,
                "liquidGlassBehavior": theme.liquidGlassBehavior,
                "symbolName": theme.symbolName,
                "prefersQuietVisuals": theme.prefersQuietVisuals
            ]
        ])
    }

    func getAnalytics(experienceId: String) async throws -> [String: Any] {
        let result = try await call("getExperienceAnalytics", payload: ["experienceId": experienceId])
        return result["analytics"] as? [String: Any] ?? [:]
    }

    func manageRoles(experienceId: String, roles: [String]) async throws {
        _ = try await call("manageExperienceRoles", payload: [
            "experienceId": experienceId,
            "rolesAllowedToManage": roles
        ])
    }

    func resolveStack(organizationIds: [String], region: String = Locale.current.region?.identifier ?? "global", adminPreview: Bool = false) async throws -> AmenContextualExperienceStackResolution {
        let payload: [String: Any] = [
            "organizationIds": organizationIds,
            "region": region,
            "adminPreview": adminPreview,
            "accessibility": [
                "reduceMotion": UIAccessibility.isReduceMotionEnabled,
                "reduceTransparency": UIAccessibility.isReduceTransparencyEnabled,
                "highContrast": UIAccessibility.isDarkerSystemColorsEnabled
            ],
            "emotionalContext": [
                "griefSensitive": false,
                "sensitiveMode": false
            ]
        ]
        let result = try await call("resolveContextualExperienceStack", payload: payload)
        return parseResolution(result)
    }

    private func statusCall(_ function: String, id: String) async throws {
        _ = try await call(function, payload: ["experienceId": id])
    }

    private func createModule(function: String, experienceId: String, title: String, body: String) async throws -> String {
        let result = try await call(function, payload: [
            "experienceId": experienceId,
            "title": title,
            "body": body
        ])
        guard let id = result["moduleId"] as? String else { throw AmenContextualExperienceError.invalidResponse }
        return id
    }

    private func call(_ name: String, payload: [String: Any]) async throws -> [String: Any] {
        guard AMENFeatureFlags.shared.contextualExperiencesEnabled || name == "resolveContextualExperienceStack" else {
            throw AmenContextualExperienceError.featureDisabled
        }
        let result = try await functions.httpsCallable(name).call(payload)
        guard let data = result.data as? [String: Any] else { throw AmenContextualExperienceError.invalidResponse }
        return data
    }

    private func parseResolution(_ raw: [String: Any]) -> AmenContextualExperienceStackResolution {
        let banner = raw["activeBanner"] as? [String: Any]
        let secondaries = (raw["secondaryExperiences"] as? [[String: Any]] ?? []).compactMap { AmenContextualExperience.from($0) }
        let debugRows = (raw["debugMetadata"] as? [[String: Any]] ?? []).map { row in
            "\(row["sourceLayer"] as? String ?? "layer") · \(row["title"] as? String ?? "Experience") · \(row["resolverScore"] ?? 0)"
        }
        return AmenContextualExperienceStackResolution(
            activeExperienceId: raw["activeExperienceId"] as? String,
            sourceLayer: AmenContextualExperienceLayer(rawValue: raw["sourceLayer"] as? String ?? "default") ?? .default,
            theme: AmenExperienceTheme.from(raw["themeTokens"] as? [String: Any]),
            bannerTitle: banner?["title"] as? String,
            bannerSubtitle: banner?["subtitle"] as? String,
            secondaryExperiences: secondaries,
            debugRows: debugRows
        )
    }
}

enum AmenContextualExperienceError: LocalizedError {
    case invalidResponse
    case featureDisabled

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "The experience service returned an unexpected response."
        case .featureDisabled: return "Contextual experiences are not enabled for this build or account."
        }
    }
}

@MainActor
final class AmenContextualExperienceDashboardViewModel: ObservableObject {
    @Published var experiences: [AmenContextualExperience] = []
    @Published var selectedExperience: AmenContextualExperience?
    @Published var resolution: AmenContextualExperienceStackResolution = .empty
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var analytics: [String: Any] = [:]
    @Published var toast: String?

    let organizationId: String
    private let service: AmenContextualExperienceService

    init(organizationId: String) {
        self.organizationId = organizationId
        self.service = AmenContextualExperienceService.shared
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            experiences = try await service.listOrganizationExperiences(organizationId: organizationId)
            resolution = try await service.resolveStack(organizationIds: [organizationId], adminPreview: true)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func create(_ draft: AmenExperienceDraft) async -> String? {
        await performReturningId("Created") { try await service.createExperience(draft) }
    }

    func update(id: String, draft: AmenExperienceDraft) async {
        await perform("Updated") { try await service.updateExperience(id: id, draft: draft) }
    }

    func publish(_ experience: AmenContextualExperience) async { await perform("Published") { try await service.publishExperience(id: experience.id) } }
    func unpublish(_ experience: AmenContextualExperience) async { await perform("Unpublished") { try await service.unpublishExperience(id: experience.id) } }
    func archive(_ experience: AmenContextualExperience) async { await perform("Archived") { try await service.archiveExperience(id: experience.id) } }
    func delete(_ experience: AmenContextualExperience) async { await perform("Deleted") { try await service.deleteExperience(id: experience.id) } }
    func join(_ experience: AmenContextualExperience) async { await perform("Joined") { try await service.joinExperience(id: experience.id) } }
    func leave(_ experience: AmenContextualExperience) async { await perform("Left") { try await service.leaveExperience(id: experience.id) } }
    func report(_ experience: AmenContextualExperience, reason: String) async { await perform("Reported") { try await service.reportExperience(id: experience.id, reason: reason) } }
    func updateNotifications(_ experience: AmenContextualExperience, enabled: Bool, quietMode: Bool) async { await perform("Notifications updated") { try await service.updateNotifications(experienceId: experience.id, enabled: enabled, quietMode: quietMode) } }
    func manageRoles(_ experience: AmenContextualExperience, roles: [String]) async { await perform("Roles updated") { try await service.manageRoles(experienceId: experience.id, roles: roles) } }
    func moderate(_ experience: AmenContextualExperience, moduleType: String, moduleId: String, action: String) async {
        await perform("Moderation updated") {
            try await service.moderateContent(experienceId: experience.id, moduleType: moduleType, moduleId: moduleId, action: action)
        }
    }

    func addModule(_ kind: AmenExperienceModuleKind, experience: AmenContextualExperience, title: String, body: String) async {
        await perform("Added \(kind.label)") {
            switch kind {
            case .event: _ = try await service.createEvent(experienceId: experience.id, title: title, body: body)
            case .prayer: _ = try await service.createPrayerPrompt(experienceId: experience.id, title: title, body: body)
            case .discussion: _ = try await service.createDiscussion(experienceId: experience.id, title: title, body: body)
            case .memory: _ = try await service.createMemory(experienceId: experience.id, title: title, body: body)
            case .tradition: _ = try await service.createTradition(experienceId: experience.id, title: title, body: body)
            }
        }
    }

    func loadAnalytics(for experience: AmenContextualExperience) async {
        do {
            analytics = try await service.getAnalytics(experienceId: experience.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func perform(_ success: String, action: () async throws -> Void) async {
        do {
            try await action()
            toast = success
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performReturningId(_ success: String, action: () async throws -> String) async -> String? {
        do {
            let id = try await action()
            toast = success
            await load()
            return id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

enum AmenExperienceModuleKind: String, CaseIterable, Identifiable {
    case event
    case prayer
    case discussion
    case memory
    case tradition

    var id: String { rawValue }
    var label: String {
        switch self {
        case .event: return "Event"
        case .prayer: return "Prayer Prompt"
        case .discussion: return "Discussion"
        case .memory: return "Memory"
        case .tradition: return "Tradition"
        }
    }
}
