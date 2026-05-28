// AmenGatheringService.swift
// AMENAPP — Amen Gatherings Firebase Callable Wrapper
//
// All mutations go through backend callables — never direct Firestore writes.
// App Check is enforced server-side on every callable.

import Foundation
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class AmenGatheringService: ObservableObject {
    static let shared = AmenGatheringService()

    private lazy var functions = Functions.functions()

    private init() {}

    // MARK: - Create

    func createGathering(_ input: AmenCreateGatheringInput) async throws -> AmenCreateGatheringResponse {
        let payload = buildCreatePayload(input)
        let result = try await functions.httpsCallable("createGathering").call(payload)
        guard let data = result.data as? [String: Any] else {
            throw CloudFunctionsError.invalidResponse
        }
        if let code = data["errorCode"] as? String { throw AmenGatheringError.from(code: code) }
        return try decode(AmenCreateGatheringResponse.self, from: data)
    }

    func updateGathering(_ input: AmenGatheringUpdateInput) async throws {
        var payload: [String: Any] = ["gatheringId": input.gatheringId]
        if let v = input.title       { payload["title"] = v }
        if let v = input.description { payload["description"] = v }
        if let v = input.startAt     { payload["startAt"] = v.timeIntervalSince1970 * 1000 }
        if let v = input.endAt       { payload["endAt"] = v.timeIntervalSince1970 * 1000 }
        if let v = input.location    { payload["location"] = encodeLocation(v) }
        if let v = input.visibility  { payload["visibility"] = v.rawValue }
        if let v = input.details     { payload["details"] = encodeDetails(v) }
        if let v = input.spiritual   { payload["spiritual"] = encodeSpiritual(v) }
        if let v = input.theme       { payload["theme"] = encodeTheme(v) }
        if let v = input.access      { payload["access"] = encodeAccess(v) }
        if let v = input.rsvpSettings { payload["rsvpSettings"] = encodeRsvpSettings(v) }
        _ = try await functions.httpsCallable("updateGathering").call(payload)
    }

    func publishGathering(gatheringId: String) async throws -> AmenCreateGatheringResponse {
        let result = try await functions.httpsCallable("publishGathering").call(["gatheringId": gatheringId])
        guard let data = result.data as? [String: Any] else {
            throw CloudFunctionsError.invalidResponse
        }
        if let code = data["errorCode"] as? String { throw AmenGatheringError.from(code: code) }
        return try decode(AmenCreateGatheringResponse.self, from: data)
    }

    func cancelGathering(gatheringId: String, notifyAttendees: Bool = true) async throws {
        _ = try await functions.httpsCallable("cancelGathering").call([
            "gatheringId": gatheringId,
            "notifyAttendees": notifyAttendees
        ])
    }

    func duplicateGathering(gatheringId: String) async throws -> AmenCreateGatheringResponse {
        let result = try await functions.httpsCallable("duplicateGathering").call(["gatheringId": gatheringId])
        guard let data = result.data as? [String: Any] else {
            throw CloudFunctionsError.invalidResponse
        }
        return try decode(AmenCreateGatheringResponse.self, from: data)
    }

    // MARK: - RSVP

    func rsvpToGathering(_ input: AmenGatheringRsvpInput) async throws {
        var payload: [String: Any] = [
            "gatheringId": input.gatheringId,
            "status": input.status.rawValue
        ]
        if let v = input.answers, !v.isEmpty     { payload["answers"] = v }
        if let v = input.requestedPrayer         { payload["requestedPrayer"] = v }
        if let v = input.requestedPastoralFollowUp { payload["requestedPastoralFollowUp"] = v }
        let result = try await functions.httpsCallable("rsvpToGathering").call(payload)
        guard let data = result.data as? [String: Any] else {
            throw CloudFunctionsError.invalidResponse
        }
        if let code = data["errorCode"] as? String { throw AmenGatheringError.from(code: code) }
    }

    func checkInToGathering(gatheringId: String, accessPassId: String, token: String) async throws {
        let result = try await functions.httpsCallable("checkInToGathering").call([
            "gatheringId": gatheringId,
            "accessPassId": accessPassId,
            "token": token
        ])
        guard let data = result.data as? [String: Any] else {
            throw CloudFunctionsError.invalidResponse
        }
        if let code = data["errorCode"] as? String { throw AmenGatheringError.from(code: code) }
    }

    // MARK: - Fetch / Feed

    func getGatheringPreview(gatheringId: String) async throws -> AmenGathering {
        let result = try await functions.httpsCallable("getGatheringPreview").call(["gatheringId": gatheringId])
        guard let data = result.data as? [String: Any] else {
            throw CloudFunctionsError.invalidResponse
        }
        if let code = data["errorCode"] as? String { throw AmenGatheringError.from(code: code) }
        return try decode(AmenGathering.self, from: data)
    }

    func listGatheringsFeed(
        hostId: String? = nil,
        churchId: String? = nil,
        organizationId: String? = nil,
        type: AmenGatheringType? = nil,
        limitCount: Int = 30
    ) async throws -> [AmenGatheringFeedCard] {
        var payload: [String: Any] = ["limit": limitCount]
        if let v = hostId         { payload["hostId"] = v }
        if let v = churchId       { payload["churchId"] = v }
        if let v = organizationId { payload["organizationId"] = v }
        if let v = type           { payload["type"] = v.rawValue }
        let result = try await functions.httpsCallable("listGatheringsFeed").call(payload)
        guard let data = result.data as? [String: Any],
              let items = data["gatherings"] as? [[String: Any]] else { return [] }
        return items.compactMap { try? decode(AmenGatheringFeedCard.self, from: $0) }
    }

    func listHostGatherings(hostId: String, hostType: AmenGatheringHostType) async throws -> [AmenGathering] {
        let result = try await functions.httpsCallable("listHostGatherings").call([
            "hostId": hostId,
            "hostType": hostType.rawValue
        ])
        guard let data = result.data as? [String: Any],
              let items = data["gatherings"] as? [[String: Any]] else { return [] }
        return items.compactMap { try? decode(AmenGathering.self, from: $0) }
    }

    func listGatheringRsvps(gatheringId: String) async throws -> [AmenGatheringRsvp] {
        let result = try await functions.httpsCallable("listGatheringRsvps").call(["gatheringId": gatheringId])
        guard let data = result.data as? [String: Any],
              let items = data["rsvps"] as? [[String: Any]] else { return [] }
        return items.compactMap { try? decode(AmenGatheringRsvp.self, from: $0) }
    }

    // MARK: - Questions

    func createGatheringQuestion(gatheringId: String, question: AmenCreateQuestionInput) async throws {
        _ = try await functions.httpsCallable("createGatheringQuestion").call([
            "gatheringId": gatheringId,
            "prompt": question.prompt,
            "type": question.type.rawValue,
            "options": question.options,
            "required": question.required,
            "sensitive": question.sensitive,
            "sortOrder": question.sortOrder
        ] as [String: Any])
    }

    func deleteGatheringQuestion(gatheringId: String, questionId: String) async throws {
        _ = try await functions.httpsCallable("deleteGatheringQuestion").call([
            "gatheringId": gatheringId,
            "questionId": questionId
        ])
    }

    // MARK: - Host Actions

    func updateGuestRsvpStatus(gatheringId: String, userId: String, status: AmenGatheringRsvpStatus) async throws {
        _ = try await functions.httpsCallable("updateGuestRsvpStatus").call([
            "gatheringId": gatheringId,
            "userId": userId,
            "status": status.rawValue
        ])
    }

    func sendGatheringUpdate(_ input: AmenGatheringSendUpdateInput) async throws {
        var payload: [String: Any] = [
            "gatheringId": input.gatheringId,
            "title": input.title,
            "body": input.body
        ]
        if let v = input.deepLinkPath { payload["deepLinkPath"] = v }
        _ = try await functions.httpsCallable("sendGatheringUpdate").call(payload)
    }

    // MARK: - Helpers

    private func decode<T: Decodable>(_ type: T.Type, from dict: [String: Any]) throws -> T {
        let jsonData = try JSONSerialization.data(withJSONObject: dict)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: jsonData)
    }

    // MARK: - Payload Builders

    private func buildCreatePayload(_ input: AmenCreateGatheringInput) -> [String: Any] {
        var payload: [String: Any] = [
            "title": input.title,
            "type": input.type.rawValue,
            "hostType": input.hostType.rawValue,
            "hostId": input.hostId,
            "startAt": input.startAt.timeIntervalSince1970 * 1000,
            "location": encodeLocation(input.location),
            "visibility": input.visibility.rawValue,
            "theme": encodeTheme(input.theme),
            "details": encodeDetails(input.details),
            "spiritual": encodeSpiritual(input.spiritual),
            "rsvpSettings": encodeRsvpSettings(input.rsvpSettings),
            "safety": encodeSafety(input.safety),
            "connectedTargets": encodeConnectedTargets(input.connectedTargets),
            "access": encodeAccess(input.access),
            "waitlistEnabled": input.waitlistEnabled,
            "publishImmediately": input.publishImmediately,
            "questions": input.questions.map { q -> [String: Any] in
                ["prompt": q.prompt, "type": q.type.rawValue, "options": q.options,
                 "required": q.required, "sensitive": q.sensitive, "sortOrder": q.sortOrder]
            }
        ]
        if let v = input.description { payload["description"] = v }
        if let v = input.endAt       { payload["endAt"] = v.timeIntervalSince1970 * 1000 }
        if let v = input.timezone    { payload["timezone"] = v }
        if let v = input.capacity    { payload["capacity"] = v }
        return payload
    }

    private func encodeLocation(_ l: AmenGatheringLocation) -> [String: Any] {
        var d: [String: Any] = ["type": l.type.rawValue]
        if let v = l.name          { d["name"] = v }
        if let v = l.address       { d["address"] = v }
        if let v = l.city          { d["city"] = v }
        if let v = l.region        { d["region"] = v }
        if let v = l.country       { d["country"] = v }
        if let v = l.onlineUrl     { d["onlineUrl"] = v }
        if let v = l.directionsUrl { d["directionsUrl"] = v }
        return d
    }

    private func encodeTheme(_ t: AmenGatheringTheme) -> [String: Any] {
        var d: [String: Any] = [:]
        if let v = t.coverImageUrl       { d["coverImageUrl"] = v }
        if let v = t.gradientName        { d["gradientName"] = v }
        if let v = t.templateId          { d["templateId"] = v }
        if let v = t.iconName            { d["iconName"] = v }
        if let v = t.scriptureReference  { d["scriptureReference"] = v }
        if let v = t.scriptureTextPreview { d["scriptureTextPreview"] = v }
        return d
    }

    private func encodeDetails(_ det: AmenGatheringDetails) -> [String: Any] {
        var d: [String: Any] = [:]
        if let v = det.speaker            { d["speaker"] = v }
        if let v = det.leader             { d["leader"] = v }
        if let v = det.whatToBring        { d["whatToBring"] = v }
        if let v = det.childcare          { d["childcare"] = v }
        if let v = det.parking            { d["parking"] = v }
        if let v = det.accessibilityNotes { d["accessibilityNotes"] = v }
        if let v = det.contactEmail       { d["contactEmail"] = v }
        if let v = det.contactPhone       { d["contactPhone"] = v }
        return d
    }

    private func encodeSpiritual(_ s: AmenGatheringSpiritual) -> [String: Any] {
        var d: [String: Any] = [
            "allowPrayerRequests": s.allowPrayerRequests,
            "allowPastoralFollowUp": s.allowPastoralFollowUp,
            "allowTestimonies": s.allowTestimonies
        ]
        if let v = s.prayerFocus        { d["prayerFocus"] = v }
        if let v = s.scriptureReference { d["scriptureReference"] = v }
        return d
    }

    private func encodeRsvpSettings(_ r: AmenGatheringRsvpSettings) -> [String: Any] {
        [
            "allowGoing": r.allowGoing,
            "allowMaybe": r.allowMaybe,
            "allowDecline": r.allowDecline,
            "questionsEnabled": r.questionsEnabled,
            "guestListVisibility": r.guestListVisibility.rawValue,
            "answersVisibility": r.answersVisibility.rawValue
        ]
    }

    private func encodeSafety(_ s: AmenGatheringSafety) -> [String: Any] {
        [
            "isSensitive": s.isSensitive,
            "isYouthRelated": s.isYouthRelated,
            "requiresModeration": s.requiresModeration,
            "allowPublicComments": s.allowPublicComments,
            "prayerRequestsPrivateByDefault": s.prayerRequestsPrivateByDefault
        ]
    }

    private func encodeConnectedTargets(_ c: AmenGatheringConnectedTargets) -> [String: Any] {
        var d: [String: Any] = [:]
        if let v = c.spaceId        { d["spaceId"] = v }
        if let v = c.discussionId   { d["discussionId"] = v }
        if let v = c.churchId       { d["churchId"] = v }
        if let v = c.organizationId { d["organizationId"] = v }
        if let v = c.smallGroupId   { d["smallGroupId"] = v }
        if let v = c.prayerRoomId   { d["prayerRoomId"] = v }
        if let v = c.sermonNotesId  { d["sermonNotesId"] = v }
        return d
    }

    private func encodeAccess(_ a: AmenGatheringAccess) -> [String: Any] {
        var d: [String: Any] = [
            "accessPassEnabled": a.accessPassEnabled,
            "mode": a.mode.rawValue,
            "requiresApproval": a.requiresApproval,
            "allowGuestPreview": a.allowGuestPreview,
            "allowUnauthenticatedRsvp": a.allowUnauthenticatedRsvp
        ]
        if let v = a.defaultAccessPassId { d["defaultAccessPassId"] = v }
        return d
    }
}
