// BereanDriveSessionService.swift
// AMEN — Berean Drive CarPlay
//
// Firebase-backed session management for Berean Drive.
// Calls backend Cloud Functions:
//   bereanDriveRespond       — Berean voice Q&A, driving-safe response
//   bereanDriveSummarize     — Condenses long Berean answers (15–45 sec audio)
//   bereanDrivePrayerSession — Returns guided prayer audio prompt
//   bereanDriveChurchSearch  — Nearby church search with CarPlay payload
//   bereanDriveMessageSafetyReview — Server-side safety review for messages
//
// All callables enforce:
//   - Firebase App Check
//   - Authenticated user (idToken)
//   - Server-side rate limiting
//   - Abuse detection
//   - Youth / minor protections
//   - No markdown / no long prose — structured CarPlay payload only
//
// Continuity: session context is stored in Firestore under
//   berean_drive_sessions/{userId}/{sessionId}

import Foundation
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth

@MainActor
final class BereanDriveSessionService: ObservableObject {

    static let shared = BereanDriveSessionService()

    // MARK: - State

    @Published private(set) var activeSession: BereanDriveSession?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: Error?

    private let functions = Functions.functions()
    private let db = Firestore.firestore()
    private let analytics = BereanCarPlayAnalytics.shared
    private let safetyGate = BereanCarPlaySafetyGate.shared

    // Client-side rate limiting: max 20 requests per 60s window
    private var requestTimestamps: [Date] = []
    private let rateLimitMaxRequests = 20
    private let rateLimitWindowSeconds: Double = 60

    private init() {}

    // MARK: - Session Lifecycle

    func startSession(mode: BereanDriveMode = .home) async -> BereanDriveSession? {
        guard let userId = Auth.auth().currentUser?.uid else { return nil }
        let session = BereanDriveSession.new(userId: userId, mode: mode)
        activeSession = session
        analytics.track(.sessionStarted)

        Task {
            do {
                try await db
                    .collection("berean_drive_sessions")
                    .document(userId)
                    .collection("sessions")
                    .document(session.sessionId)
                    .setData(try JSONEncoder().encodeAsDictionary(session))
            } catch {
                dlog("⚠️ [BereanDriveSession] Firestore write failed: \(error)")
            }
        }

        return session
    }

    func endSession() {
        guard let session = activeSession else { return }
        analytics.track(.sessionEnded)
        Task {
            guard let userId = Auth.auth().currentUser?.uid else { return }
            try? await db
                .collection("berean_drive_sessions")
                .document(userId)
                .collection("sessions")
                .document(session.sessionId)
                .updateData(["phase": "ended", "endedAt": FieldValue.serverTimestamp()])
        }
        activeSession = nil
    }

    // MARK: - Berean Drive Q&A

    func askBerean(question: String, preferences: BereanDrivePreferences) async -> BereanDriveResponse {
        // B-23: Gate — bereanDriveRespond CF is not yet deployed.
        guard AMENFeatureFlags.shared.bereanDriveEnabled else {
            return errorResponse("Berean Drive is coming soon. Please check back after the next update.")
        }
        guard isWithinRateLimit() else {
            return rateLimitedResponse()
        }
        recordRequest()
        isLoading = true
        defer { isLoading = false }

        let payload: [String: Any] = [
            "question": question,
            "translation": preferences.preferredScriptureTranslation,
            "sessionId": activeSession?.sessionId ?? "",
            "maxSpokenChars": BereanDriveResponsePolicy.maxSpokenCharacters,
            "youthSafetyEnabled": preferences.youthSafetyEnabled
        ]

        do {
            let result = try await functions.httpsCallable(BereanDriveCallableNames.respond).call(payload)
            guard let data = result.data as? [String: Any] else {
                return errorResponse("Unable to get a response right now.")
            }
            let response = parseDriveResponse(data)
            return safetyGate.validateDriveResponse(response, youthSafetyEnabled: preferences.youthSafetyEnabled)
        } catch {
            dlog("⚠️ [BereanDriveSession] bereanDriveRespond error: \(error)")
            return errorResponse("Berean isn't available right now. Please check back later.")
        }
    }

    // MARK: - Driving-Safe Summarizer

    func summarizeForDriving(longText: String, preferences: BereanDrivePreferences) async -> BereanDriveResponse {
        // B-23: Gate — bereanDriveSummarize CF is not yet deployed.
        guard AMENFeatureFlags.shared.bereanDriveEnabled else {
            return errorResponse("Berean Drive is coming soon.")
        }
        guard isWithinRateLimit() else { return rateLimitedResponse() }
        recordRequest()
        isLoading = true
        defer { isLoading = false }

        let payload: [String: Any] = [
            "text": longText,
            "maxSpokenChars": BereanDriveResponsePolicy.maxSpokenCharacters,
            "sessionId": activeSession?.sessionId ?? ""
        ]

        do {
            let result = try await functions.httpsCallable(BereanDriveCallableNames.summarize).call(payload)
            guard let data = result.data as? [String: Any] else { return errorResponse("Summary unavailable.") }
            let response = parseDriveResponse(data)
            return safetyGate.validateDriveResponse(response, youthSafetyEnabled: preferences.youthSafetyEnabled)
        } catch {
            dlog("⚠️ [BereanDriveSession] bereanDriveSummarize error: \(error)")
            return errorResponse("Summary unavailable right now.")
        }
    }

    // MARK: - Prayer Session

    func startPrayerSession(mode: BereanPrayerMode, preferences: BereanDrivePreferences) async -> BereanDriveResponse {
        // B-23: Gate — bereanDrivePrayerSession CF is not yet deployed.
        guard AMENFeatureFlags.shared.bereanDriveEnabled else {
            return localPrayerFallback(mode: mode)
        }
        guard isWithinRateLimit() else { return rateLimitedResponse() }
        recordRequest()
        isLoading = true
        defer { isLoading = false }

        analytics.track(.prayerStarted(mode: mode.rawValue))

        let payload: [String: Any] = [
            "prayerMode": mode.rawValue,
            "prayerStyle": preferences.prayerStyle.rawValue,
            "translation": preferences.preferredScriptureTranslation,
            "maxSpokenChars": BereanDriveResponsePolicy.maxSpokenCharacters,
            "sessionId": activeSession?.sessionId ?? ""
        ]

        do {
            let result = try await functions.httpsCallable(BereanDriveCallableNames.prayerSession).call(payload)
            guard let data = result.data as? [String: Any] else {
                return localPrayerFallback(mode: mode)
            }
            let response = parseDriveResponse(data)
            return safetyGate.validateDriveResponse(response, youthSafetyEnabled: preferences.youthSafetyEnabled)
        } catch {
            dlog("⚠️ [BereanDriveSession] bereanDrivePrayerSession error: \(error)")
            return localPrayerFallback(mode: mode)
        }
    }

    // MARK: - Church Search

    func searchNearbyChurches(
        latitude: Double,
        longitude: Double,
        preferences: BereanDrivePreferences
    ) async -> [BereanDriveChurchResult] {
        // B-23: Gate — bereanDriveChurchSearch CF is not yet deployed.
        guard AMENFeatureFlags.shared.bereanDriveEnabled else { return [] }
        guard isWithinRateLimit() else { return [] }
        recordRequest()
        isLoading = true
        defer { isLoading = false }

        analytics.track(.churchNavigationStarted)

        let payload: [String: Any] = [
            "latitude": latitude,
            "longitude": longitude,
            "radiusMiles": preferences.churchSearchRadiusMiles,
            "maxResults": BereanDriveResponsePolicy.maxChurchResults,
            "personalized": preferences.churchDiscoveryPersonalizationEnabled,
            "sessionId": activeSession?.sessionId ?? ""
        ]

        do {
            let result = try await functions.httpsCallable(BereanDriveCallableNames.churchSearch).call(payload)
            guard let data = result.data as? [String: Any],
                  let churches = data["churches"] as? [[String: Any]] else { return [] }
            return churches.compactMap { parseChurchResult($0) }
        } catch {
            dlog("⚠️ [BereanDriveSession] bereanDriveChurchSearch error: \(error)")
            return []
        }
    }

    // MARK: - Message Safety Review (server-side)

    func reviewMessageSafety(
        messageText: String,
        senderId: String,
        youthSafetyEnabled: Bool
    ) async -> BereanCarPlaySafetyResult {
        // Always run local gate first
        let localResult = BereanCarPlaySafetyGate.shared.screenForReadAloud(
            messageText,
            youthSafetyEnabled: youthSafetyEnabled
        )
        guard localResult.isSafe else { return localResult }

        // B-23: Gate — bereanDriveMessageSafetyReview CF is not yet deployed.
        // Return local result when flag is off (fail-safe: already passed local screen above).
        guard AMENFeatureFlags.shared.bereanDriveEnabled else { return localResult }

        // Server review for borderline content
        let payload: [String: Any] = [
            "messageText": messageText,
            "senderId": senderId,
            "youthSafetyEnabled": youthSafetyEnabled,
            "context": "carplay_read_aloud"
        ]

        do {
            let result = try await functions.httpsCallable(BereanDriveCallableNames.messageSafetyReview).call(payload)
            guard let data = result.data as? [String: Any] else { return localResult }
            let isSafe = data["isSafe"] as? Bool ?? false
            let category = data["blockedCategory"] as? String ?? ""
            if isSafe {
                return .init(outcome: .safe, originalTextLength: messageText.count)
            } else {
                let blockCat = BereanCarPlayBlockCategory(rawValue: category) ?? .profanity
                return .init(outcome: .blocked(category: blockCat,
                                                calmReplacement: BereanCarPlaySafetyGate.calmDefaultMessage),
                             originalTextLength: messageText.count)
            }
        } catch {
            dlog("⚠️ [BereanDriveSession] Message safety review error: \(error)")
            // On server error, fail safe — don't read the message
            return .init(outcome: .blocked(category: .profanity,
                                            calmReplacement: BereanCarPlaySafetyGate.calmDefaultMessage),
                         originalTextLength: messageText.count)
        }
    }

    // MARK: - Rate Limiting

    private func isWithinRateLimit() -> Bool {
        let now = Date()
        requestTimestamps = requestTimestamps.filter {
            now.timeIntervalSince($0) < rateLimitWindowSeconds
        }
        return requestTimestamps.count < rateLimitMaxRequests
    }

    private func recordRequest() {
        requestTimestamps.append(Date())
    }

    // MARK: - Response Parsers

    private func parseDriveResponse(_ data: [String: Any]) -> BereanDriveResponse {
        let spoken = data["spokenText"] as? String ?? ""
        let title = data["displayTitle"] as? String ?? "Berean Drive"
        let subtitle = data["displaySubtitle"] as? String
        let safetyRaw = data["safetyState"] as? String ?? "safe"
        let safety = BereanDriveSafetyState(rawValue: safetyRaw) ?? .safe
        let handoff = data["handoffRequired"] as? Bool ?? false
        let handoffReason = data["handoffReason"] as? String
        let sourceRefs = data["sourceRefs"] as? [String] ?? []
        let buttons = (data["actionButtons"] as? [[String: Any]] ?? [])
            .compactMap { parseAction($0) }
            .prefix(BereanDriveResponsePolicy.maxActionButtons)
        let duration = data["audioDurationEstimateSeconds"] as? Double

        return BereanDriveResponse(
            spokenText: spoken,
            displayTitle: title,
            displaySubtitle: subtitle,
            safetyState: safety,
            handoffRequired: handoff,
            handoffReason: handoffReason,
            sourceRefs: sourceRefs,
            actionButtons: Array(buttons),
            audioDurationEstimateSeconds: duration
        )
    }

    private func parseAction(_ data: [String: Any]) -> BereanDriveAction? {
        guard let id = data["id"] as? String,
              let label = data["label"] as? String,
              let typeRaw = data["actionType"] as? String,
              let actionType = BereanDriveActionType(rawValue: typeRaw) else { return nil }
        return BereanDriveAction(id: id, label: label, actionType: actionType, payload: data["payload"] as? String)
    }

    private func parseChurchResult(_ data: [String: Any]) -> BereanDriveChurchResult? {
        guard let id = data["id"] as? String, let name = data["name"] as? String else { return nil }
        return BereanDriveChurchResult(
            id: id,
            name: name,
            distanceMiles: data["distanceMiles"] as? Double,
            address: data["address"] as? String,
            phoneNumber: data["phoneNumber"] as? String,
            nextServiceTime: data["nextServiceTime"] as? String,
            denomination: data["denomination"] as? String,
            latitude: data["latitude"] as? Double,
            longitude: data["longitude"] as? Double,
            amenSpaceId: data["amenSpaceId"] as? String
        )
    }

    // MARK: - Fallbacks

    private func errorResponse(_ message: String) -> BereanDriveResponse {
        BereanDriveResponse(
            spokenText: message,
            displayTitle: "Unavailable",
            displaySubtitle: nil,
            safetyState: .safe,
            handoffRequired: false,
            handoffReason: nil,
            sourceRefs: [],
            actionButtons: [],
            audioDurationEstimateSeconds: nil
        )
    }

    private func rateLimitedResponse() -> BereanDriveResponse {
        errorResponse("Please wait a moment before asking another question.")
    }

    private func localPrayerFallback(mode: BereanPrayerMode) -> BereanDriveResponse {
        BereanDriveResponse(
            spokenText: mode.prayerPrompt,
            displayTitle: mode.displayTitle,
            displaySubtitle: "Guided Prayer",
            safetyState: .safe,
            handoffRequired: false,
            handoffReason: nil,
            sourceRefs: [],
            actionButtons: [],
            audioDurationEstimateSeconds: nil
        )
    }
}

// MARK: - Encodable Helper

private extension JSONEncoder {
    func encodeAsDictionary<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try encode(value)
        let obj = try JSONSerialization.jsonObject(with: data)
        return obj as? [String: Any] ?? [:]
    }
}
