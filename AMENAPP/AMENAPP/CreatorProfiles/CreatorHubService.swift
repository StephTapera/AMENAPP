// CreatorHubService.swift
// AMEN — Creator Profiles (ministry hubs) — Wave 3
//
// Callable client for the Creator Hub backend. Mirrors the exact pattern used by
// ConnectDiscoveryFeedService: Functions.functions(region: "us-east1") + httpsCallable +
// JSONSerialization → JSONDecoder.creatorHubDecoder via a private decodeResult<T> helper.
//
// All decode paths go through `creatorHubDecoder` (ISO-8601 dates) so wire timestamps
// (ISO-8601 strings) decode into Date correctly.
//
// In-memory cache (`cachedPayloads`) gives instant re-entry: CreatorProfileView renders a
// cached payload immediately, then re-hydrates from `assembleProfile`.

import Foundation
import FirebaseFunctions

// MARK: - In-file response shapes (not part of the frozen contract surface)

/// One teaching-search hit returned by `searchCreatorTeachings`.
struct CreatorHubTeachingSearchHit: Codable {
    let teaching: CreatorHubTeaching
    let snippet: String
    let scriptureRefs: [String]
    let timestampSec: Double?
}

/// Calendar payload for an event RSVP — maps to wire `{ title, startsAt, endsAt?, timeZone, location? }`.
struct CreatorHubCalendarPayload: Codable {
    let title: String
    let startsAt: Date
    let endsAt: Date?
    let timeZone: String
    let location: String?
}

/// Reminder payload for an event RSVP — maps to wire `{ leaveByISO, travelMinutes? }`.
struct CreatorHubReminder: Codable {
    let leaveByISO: String
    let travelMinutes: Int?
}

/// Result of `rsvpCreatorEvent`.
struct CreatorHubRsvpResult: Codable {
    let calendar: CreatorHubCalendarPayload
    let reminder: CreatorHubReminder
}

// MARK: - Service

@MainActor
final class CreatorHubService {

    static let shared = CreatorHubService()

    private let functions = Functions.functions(region: "us-east1")
    private let decoder = JSONDecoder.creatorHubDecoder

    /// Last-assembled payload per creator. Powers instant re-entry into CreatorProfileView.
    private(set) var cachedPayloads: [String: CreatorHubProfilePayload] = [:]

    private init() {}

    // MARK: - Assembly (single round trip)

    /// Assemble the full creator profile payload. On success the payload is cached.
    func assembleProfile(creatorId: String) async throws -> CreatorHubProfilePayload {
        let callable = functions.httpsCallable("assembleCreatorProfile")
        let result = try await callable.call(["creatorId": creatorId])
        let payload = try decodeResult(result.data, as: CreatorHubProfilePayload.self)
        cachedPayloads[creatorId] = payload
        return payload
    }

    // MARK: - Module pagination

    func pageEvents(creatorId: String, cursor: String?) async throws -> ([CreatorHubEvent], nextCursor: String?) {
        try await pageModule(creatorId: creatorId, module: .events, cursor: cursor)
    }

    func pageTeachings(creatorId: String, cursor: String?) async throws -> ([CreatorHubTeaching], nextCursor: String?) {
        try await pageModule(creatorId: creatorId, module: .teachings, cursor: cursor)
    }

    func pageResources(creatorId: String, cursor: String?) async throws -> ([CreatorHubResource], nextCursor: String?) {
        try await pageModule(creatorId: creatorId, module: .resources, cursor: cursor)
    }

    func pagePrayer(creatorId: String, cursor: String?) async throws -> ([CreatorHubPrayerRequest], nextCursor: String?) {
        try await pageModule(creatorId: creatorId, module: .prayer, cursor: cursor)
    }

    func pageCommunity(creatorId: String, cursor: String?) async throws -> ([CreatorHubCommunityPost], nextCursor: String?) {
        try await pageModule(creatorId: creatorId, module: .community, cursor: cursor)
    }

    func pageCourses(creatorId: String, cursor: String?) async throws -> ([CreatorHubCourse], nextCursor: String?) {
        try await pageModule(creatorId: creatorId, module: .courses, cursor: cursor)
    }

    /// Generic page call — calls "pageCreatorModule" with the module raw value and decodes
    /// CreatorHubModulePage<T>.
    private func pageModule<T: Codable>(
        creatorId: String,
        module: CreatorHubModuleKind,
        cursor: String?
    ) async throws -> ([T], nextCursor: String?) {
        let callable = functions.httpsCallable("pageCreatorModule")
        var params: [String: Any] = [
            "creatorId": creatorId,
            "module": module.rawValue,
        ]
        if let cursor { params["cursor"] = cursor }

        let result = try await callable.call(params)
        let page = try decodeResult(result.data, as: CreatorHubModulePage<T>.self)
        return (page.items, page.nextCursor)
    }

    // MARK: - Teaching search

    func searchTeachings(creatorId: String, query: String) async throws -> [CreatorHubTeachingSearchHit] {
        struct SearchEnvelope: Codable { let results: [CreatorHubTeachingSearchHit] }
        let callable = functions.httpsCallable("searchCreatorTeachings")
        let result = try await callable.call([
            "creatorId": creatorId,
            "query": query,
        ])
        let envelope = try decodeResult(result.data, as: SearchEnvelope.self)
        return envelope.results
    }

    // MARK: - AI Creator Assistant

    func ask(creatorId: String, query: String) async throws -> CreatorHubAssistantAnswer {
        let callable = functions.httpsCallable("askCreatorAssistant")
        let result = try await callable.call([
            "creatorId": creatorId,
            "query": query,
        ])
        return try decodeResult(result.data, as: CreatorHubAssistantAnswer.self)
    }

    // MARK: - Events RSVP

    func rsvp(creatorId: String, eventId: String, going: Bool) async throws -> CreatorHubRsvpResult {
        let callable = functions.httpsCallable("rsvpCreatorEvent")
        let result = try await callable.call([
            "creatorId": creatorId,
            "eventId": eventId,
            "going": going,
        ])
        return try decodeResult(result.data, as: CreatorHubRsvpResult.self)
    }

    // MARK: - Follow / subscription

    func setFollow(creatorId: String, categories: [CreatorHubFollowCategory]) async throws {
        let callable = functions.httpsCallable("setCreatorFollow")
        _ = try await callable.call([
            "creatorId": creatorId,
            "categories": categories.map { $0.rawValue },
        ])
    }

    // MARK: - Prayer board

    func submitPrayer(creatorId: String, body: String, isPrivate: Bool) async throws {
        let callable = functions.httpsCallable("submitCreatorPrayer")
        _ = try await callable.call([
            "creatorId": creatorId,
            "body": body,
            "isPrivate": isPrivate,
        ])
    }

    // MARK: - Community

    func submitCommunity(creatorId: String, kind: CreatorHubCommunityKind, body: String) async throws {
        let callable = functions.httpsCallable("submitCreatorCommunity")
        _ = try await callable.call([
            "creatorId": creatorId,
            "kind": kind.rawValue,
            "body": body,
        ])
    }

    // MARK: - Moderation

    func moderate(creatorId: String, target: String, refId: String, action: String) async throws {
        let callable = functions.httpsCallable("moderateCreatorContent")
        _ = try await callable.call([
            "creatorId": creatorId,
            "target": target,
            "refId": refId,
            "action": action,
        ])
    }

    // MARK: - Kingdom Metrics

    func metrics(creatorId: String) async throws -> CreatorHubMetrics {
        let callable = functions.httpsCallable("getCreatorMetrics")
        let result = try await callable.call(["creatorId": creatorId])
        return try decodeResult(result.data, as: CreatorHubMetrics.self)
    }

    // MARK: - Decode helper (identical to ConnectDiscoveryFeedService)

    private func decodeResult<T: Decodable>(_ data: Any, as type: T.Type) throws -> T {
        let jsonData = try JSONSerialization.data(withJSONObject: data)
        return try decoder.decode(type, from: jsonData)
    }
}
