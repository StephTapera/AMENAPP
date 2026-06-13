// PrayerOSService.swift
// AMEN Capabilities v1 — Prayer OS backend service (Wave 1: Lane D)
//
// Calls the four prayerOS_* Firebase callables.
// Flag-gated: throws FeatureDisabledError when prayerOSEnabled is OFF.
//
// Contract: Docs/Capabilities/CONTRACTS.md §3.3
// Models:   AMENAPP/AMENAPP/Capabilities/CapabilityModels.swift (FROZEN)

import Foundation
import FirebaseFunctions

// MARK: - FeatureDisabledError

/// Thrown when a prayerOS callable is invoked while the flag is OFF.
struct FeatureDisabledError: LocalizedError {
    let featureName: String

    var errorDescription: String? {
        "\(featureName) is not available right now."
    }
}

// MARK: - PrayerUpdatePatch

/// Partial update sent to `prayerOS_updateCard`.
/// Only non-nil fields are serialised to the wire payload.
struct PrayerUpdatePatch {
    var detail: String?
    var category: PrayerCategory?
    var status: PrayerStatus?
    var reminders: [PrayerReminder]?
    var followUps: [PrayerFollowUp]?
}

// MARK: - PrayerOSService

@MainActor
final class PrayerOSService: ObservableObject {

    // MARK: Singleton

    static let shared = PrayerOSService()

    // MARK: Published state

    @Published private(set) var cards: [PrayerCard] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    // MARK: Private dependencies

    private let functions = Functions.functions(region: "us-central1")

    private init() {}

    // MARK: - Public API

    /// Loads prayer cards for the given status filter.
    /// Calls `prayerOS_listCards`.
    /// Throws `FeatureDisabledError` when `prayerOSEnabled` is OFF.
    func loadCards(status: PrayerStatus = .active) async throws {
        try assertFlagEnabled()

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let params: [String: Any] = [
                "status": status.rawValue,
                "pageSize": 50
            ]
            let result = try await functions
                .httpsCallable("prayerOS_listCards")
                .call(params)

            let decoded = try decodeResponse(PrayerListResponse.self, from: result.data)
            cards = decoded.cards

        } catch {
            self.error = error
            throw error
        }
    }

    /// Creates a new prayer card.
    /// Calls `prayerOS_createCard`.
    /// Returns a `PrayerCreateResponse` that may contain a `dedupeWarning`.
    /// Throws `FeatureDisabledError` when `prayerOSEnabled` is OFF.
    func createCard(
        subject: PrayerSubject,
        category: PrayerCategory,
        detail: String,
        reminders: [PrayerReminder],
        followUps: [PrayerFollowUp]
    ) async throws -> PrayerCreateResponse {
        try assertFlagEnabled()

        var params: [String: Any] = [
            "subject": [
                "type": subject.type.rawValue,
                "displayName": subject.displayName
            ] as [String: Any],
            "category": category.rawValue,
            "detail": detail
        ]

        if let linkedRef = subject.linkedContactRef {
            var subjectDict = params["subject"] as? [String: Any] ?? [:]
            subjectDict["linkedContactRef"] = linkedRef
            params["subject"] = subjectDict
        }

        if !reminders.isEmpty {
            params["reminders"] = reminders.map { reminder in
                [
                    "rrule": reminder.rrule,
                    "nextFireAt": ISO8601DateFormatter().string(from: reminder.nextFireAt)
                ] as [String: Any]
            }
        }

        if !followUps.isEmpty {
            params["followUps"] = followUps.map { fu in
                var dict: [String: Any] = [
                    "dueAt": ISO8601DateFormatter().string(from: fu.dueAt),
                    "status": fu.status.rawValue
                ]
                if let note = fu.note { dict["note"] = note }
                return dict
            }
        }

        let result = try await functions
            .httpsCallable("prayerOS_createCard")
            .call(params)

        return try decodeResponse(PrayerCreateResponse.self, from: result.data)
    }

    /// Updates an existing prayer card with the provided patch fields.
    /// Calls `prayerOS_updateCard`.
    /// Throws `FeatureDisabledError` when `prayerOSEnabled` is OFF.
    func updateCard(cardId: String, patch: PrayerUpdatePatch) async throws {
        try assertFlagEnabled()

        var patchDict: [String: Any] = [:]

        if let detail = patch.detail {
            patchDict["detail"] = detail
        }
        if let category = patch.category {
            patchDict["category"] = category.rawValue
        }
        if let status = patch.status {
            patchDict["status"] = status.rawValue
        }
        if let reminders = patch.reminders {
            let iso = ISO8601DateFormatter()
            patchDict["reminders"] = reminders.map { r in
                ["rrule": r.rrule, "nextFireAt": iso.string(from: r.nextFireAt)] as [String: Any]
            }
        }
        if let followUps = patch.followUps {
            let iso = ISO8601DateFormatter()
            patchDict["followUps"] = followUps.map { fu in
                var dict: [String: Any] = [
                    "dueAt": iso.string(from: fu.dueAt),
                    "status": fu.status.rawValue
                ]
                if let note = fu.note { dict["note"] = note }
                return dict
            }
        }

        let params: [String: Any] = [
            "cardId": cardId,
            "patch": patchDict
        ]

        _ = try await functions
            .httpsCallable("prayerOS_updateCard")
            .call(params)
    }

    /// Marks a specific follow-up as completed.
    /// Calls `prayerOS_completeFollowUp`.
    /// Throws `FeatureDisabledError` when `prayerOSEnabled` is OFF.
    func completeFollowUp(cardId: String, followUpIndex: Int, note: String?) async throws {
        try assertFlagEnabled()

        var params: [String: Any] = [
            "cardId": cardId,
            "followUpIndex": followUpIndex
        ]
        if let note = note {
            params["note"] = note
        }

        _ = try await functions
            .httpsCallable("prayerOS_completeFollowUp")
            .call(params)
    }

    // MARK: - Private helpers

    /// Throws `FeatureDisabledError` when either core capabilities or Prayer OS flag is OFF.
    private func assertFlagEnabled() throws {
        guard AMENFeatureFlags.shared.capabilitiesCoreEnabled,
              AMENFeatureFlags.shared.prayerOSEnabled else {
            throw FeatureDisabledError(featureName: "Prayer OS")
        }
    }

    /// Decodes a Firebase callable response to the target Codable type.
    /// Uses `JSONSerialization` → `JSONDecoder` with ISO8601 date strategy,
    /// consistent with other AMEN callable patterns (see CapabilityRegistryStore).
    ///
    /// Wire/model key mismatch note: the backend sends `cardId` for PrayerCard objects,
    /// but the frozen Swift model (CapabilityModels.swift) uses `id`. This helper
    /// normalises the mismatch by remapping `cardId` → `id` in any nested dicts before
    /// handing off to `JSONDecoder`, without touching the frozen model.
    private func decodeResponse<T: Decodable>(_ type: T.Type, from data: Any) throws -> T {
        guard let mutableData = data as? [String: Any] else {
            throw PrayerOSError.invalidResponse
        }
        let remapped = remapCardIdKeys(in: mutableData)
        guard let jsonData = try? JSONSerialization.data(withJSONObject: remapped) else {
            throw PrayerOSError.invalidResponse
        }
        let decoder = JSONDecoder()
        // Accept both ISO-8601 strings and epoch-second doubles (backend may return either)
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            // Try ISO-8601 string first
            if let isoString = try? container.decode(String.self),
               let date = ISO8601DateFormatter().date(from: isoString) {
                return date
            }
            // Fall back to epoch seconds
            let epochSeconds = try container.decode(Double.self)
            return Date(timeIntervalSince1970: epochSeconds)
        }
        do {
            return try decoder.decode(type, from: jsonData)
        } catch {
            throw PrayerOSError.invalidResponse
        }
    }

    /// Recursively walks a `[String: Any]` response dict and renames the wire key
    /// `"cardId"` to `"id"` so it aligns with `PrayerCard.id` in the frozen model.
    private func remapCardIdKeys(in dict: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in dict {
            let newKey = key == "cardId" ? "id" : key
            if let nestedDict = value as? [String: Any] {
                result[newKey] = remapCardIdKeys(in: nestedDict)
            } else if let nestedArray = value as? [[String: Any]] {
                result[newKey] = nestedArray.map { remapCardIdKeys(in: $0) }
            } else {
                result[newKey] = value
            }
        }
        return result
    }
}

// MARK: - PrayerOSError

enum PrayerOSError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Prayer OS returned an unexpected response. Please try again."
        }
    }
}
