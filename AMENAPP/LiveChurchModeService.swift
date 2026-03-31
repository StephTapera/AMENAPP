// LiveChurchModeService.swift
// AMENAPP
//
// Backend service for the Live Church Mode feature.
// All Firestore interactions are stubbed with inline comments describing
// the exact calls that would be made. No Firebase SDK is imported here.

import Foundation
import Combine

// MARK: - LiveSessionState

/// Represents the lifecycle state of a live church session.
enum LiveSessionState: String, Codable {
    case idle       = "idle"
    case starting   = "starting"
    case live       = "live"
    case ending     = "ending"
    case completed  = "completed"
}

// MARK: - LiveSession

/// A live streaming session hosted by a church account.
struct LiveSession: Identifiable, Codable {
    let id: String
    let churchId: String
    let hostUserId: String
    let title: String
    var state: LiveSessionState
    var startedAt: Date?
    var endedAt: Date?
    var peakViewerCount: Int
    var chapterMarkers: [LiveChapterMarker]
    var replayAvailable: Bool
    var aiRecapGenerated: Bool
    var aiRecapText: String?
    var createdAt: Date
}

/// A timestamped chapter marker within a live session, used for replay navigation.
struct LiveChapterMarker: Identifiable, Codable {
    let id: String
    let title: String
    let offsetSeconds: TimeInterval
    let addedBy: String
    let addedAt: Date
}

// MARK: - LiveChatEntry

/// A single chat message sent during a live session.
struct LiveChatEntry: Identifiable, Codable {
    let id: String
    let sessionId: String
    let authorId: String
    let authorName: String
    let text: String
    let isPrayerRequest: Bool
    var isFlagged: Bool
    var isHidden: Bool
    let timestamp: Date
}

// MARK: - LivePrayerRequest

/// A prayer request submitted by a viewer during a live session.
struct LivePrayerRequest: Identifiable, Codable {
    let id: String
    let sessionId: String
    let authorId: String
    let authorName: String
    let request: String
    var isAddressed: Bool
    var addressedBy: String?
    let submittedAt: Date
}

// MARK: - LiveChurchModeError

/// Typed errors for all LiveChurchModeService operations.
enum LiveChurchModeError: LocalizedError {
    case sessionNotFound
    case sessionAlreadyActive
    case sessionNotLive
    case unauthorizedHost
    case messageNotFound
    case prayerRequestNotFound
    case recapGenerationFailed(reason: String)
    case networkError(underlying: Error)
    case unknown

    var errorDescription: String? {
        switch self {
        case .sessionNotFound:
            return "The requested live session could not be found."
        case .sessionAlreadyActive:
            return "A live session is already active for this church."
        case .sessionNotLive:
            return "This operation requires an active live session."
        case .unauthorizedHost:
            return "You are not authorised to manage this session."
        case .messageNotFound:
            return "The specified chat message could not be found."
        case .prayerRequestNotFound:
            return "The specified prayer request could not be found."
        case .recapGenerationFailed(let reason):
            return "AI recap generation failed: \(reason)"
        case .networkError(let underlying):
            return "A network error occurred: \(underlying.localizedDescription)"
        case .unknown:
            return "An unknown error occurred."
        }
    }
}

// MARK: - LiveChurchModeService

/// Service that manages the full lifecycle of a live church session, including
/// chat moderation, prayer queue, chapter markers, AI recap generation,
/// and real-time viewer count tracking.
///
/// All Firestore and network calls are stubbed. Each stub contains inline
/// comments describing the exact Firestore path and operation that would
/// be executed in production.
@MainActor
final class LiveChurchModeService: ObservableObject {

    /// The currently active or most recently loaded session.
    @Published private(set) var currentSession: LiveSession?

    /// Reflects the state of the current session in real time.
    @Published private(set) var sessionState: LiveSessionState = .idle

    /// Live-updating chat messages for the current session.
    @Published private(set) var chatMessages: [LiveChatEntry] = []

    /// Prayer requests queued for the current session.
    @Published private(set) var prayerRequests: [LivePrayerRequest] = []

    /// Current viewer count as reported by the presence system.
    @Published private(set) var viewerCount: Int = 0

    /// Indicates a network operation is in progress.
    @Published private(set) var isLoading = false

    private var sessionListener: AnyCancellable?
    private var chatListener: AnyCancellable?

    // MARK: - Session Lifecycle

    /// Creates and starts a new live session for the given church.
    ///
    /// - Parameters:
    ///   - churchId: The Firestore document ID of the hosting church account.
    ///   - hostUserId: The UID of the user initiating the session.
    ///   - title: A human-readable title shown to viewers (e.g. "Sunday Morning Service").
    /// - Returns: The newly created `LiveSession`.
    /// - Throws: `LiveChurchModeError.sessionAlreadyActive` if a live session
    ///   already exists for this church.
    func startSession(churchId: String, hostUserId: String, title: String) async throws -> LiveSession {
        isLoading = true
        defer { isLoading = false }

        // Firestore: check for an existing active session
        // let existingQuery = db.collection("liveSessions")
        //     .whereField("churchId", isEqualTo: churchId)
        //     .whereField("state", in: [LiveSessionState.starting.rawValue,
        //                               LiveSessionState.live.rawValue])
        //     .limit(to: 1)
        // let existingSnapshot = try await existingQuery.getDocuments()
        // guard existingSnapshot.isEmpty else { throw LiveChurchModeError.sessionAlreadyActive }

        // Firestore: create new session document
        // let newSessionRef = db.collection("liveSessions").document()
        // let newSession = LiveSession(
        //     id: newSessionRef.documentID,
        //     churchId: churchId,
        //     hostUserId: hostUserId,
        //     title: title,
        //     state: .starting,
        //     startedAt: nil,
        //     endedAt: nil,
        //     peakViewerCount: 0,
        //     chapterMarkers: [],
        //     replayAvailable: false,
        //     aiRecapGenerated: false,
        //     aiRecapText: nil,
        //     createdAt: Date()
        // )
        // try await newSessionRef.setData(Firestore.Encoder().encode(newSession))

        // Firestore: transition state to .live and record startedAt
        // try await newSessionRef.updateData([
        //     "state": LiveSessionState.live.rawValue,
        //     "startedAt": FieldValue.serverTimestamp()
        // ])

        let stubSession = LiveSession(
            id: UUID().uuidString,
            churchId: churchId,
            hostUserId: hostUserId,
            title: title,
            state: .live,
            startedAt: Date(),
            endedAt: nil,
            peakViewerCount: 0,
            chapterMarkers: [],
            replayAvailable: false,
            aiRecapGenerated: false,
            aiRecapText: nil,
            createdAt: Date()
        )

        currentSession = stubSession
        sessionState = .live
        return stubSession
    }

    /// Ends an active live session, marking it as completed and triggering
    /// replay availability if applicable.
    ///
    /// - Parameter sessionId: The Firestore document ID of the session to end.
    /// - Throws: `LiveChurchModeError.sessionNotFound` if the session does not exist,
    ///   or `LiveChurchModeError.sessionNotLive` if it is not currently active.
    func endSession(sessionId: String) async throws {
        isLoading = true
        defer { isLoading = false }

        // Firestore: verify session exists and is live
        // let sessionRef = db.collection("liveSessions").document(sessionId)
        // let snapshot = try await sessionRef.getDocument()
        // guard snapshot.exists else { throw LiveChurchModeError.sessionNotFound }
        // guard let data = snapshot.data(),
        //       let stateRaw = data["state"] as? String,
        //       stateRaw == LiveSessionState.live.rawValue
        // else { throw LiveChurchModeError.sessionNotLive }

        // Firestore: transition to .ending, then .completed
        // try await sessionRef.updateData(["state": LiveSessionState.ending.rawValue])
        // try await sessionRef.updateData([
        //     "state": LiveSessionState.completed.rawValue,
        //     "endedAt": FieldValue.serverTimestamp(),
        //     "replayAvailable": true
        // ])

        // Cloud Function trigger: "onSessionEnd" processes the replay,
        // archives chat, and optionally kicks off AI recap generation.

        sessionState = .completed
        if var session = currentSession {
            session.state = .completed
            session.endedAt = Date()
            session.replayAvailable = true
            currentSession = session
        }
    }

    /// Fetches the currently active live session for a church, if one exists.
    ///
    /// - Parameter churchId: The Firestore document ID of the church.
    /// - Returns: The active `LiveSession`, or `nil` if no session is live.
    func fetchActiveSession(churchId: String) async throws -> LiveSession? {
        // Firestore: query for an active session
        // let query = db.collection("liveSessions")
        //     .whereField("churchId", isEqualTo: churchId)
        //     .whereField("state", isEqualTo: LiveSessionState.live.rawValue)
        //     .limit(to: 1)
        // let snapshot = try await query.getDocuments()
        // return try snapshot.documents.first.map { try $0.data(as: LiveSession.self) }

        return currentSession
    }

    // MARK: - Chapter Markers

    /// Adds a chapter marker at the current offset within a live session.
    /// Useful for hosts to timestamp key sermon moments for replay navigation.
    ///
    /// - Parameters:
    ///   - sessionId: The ID of the target session.
    ///   - title: A short label for this chapter (e.g. "Main Scripture Reading").
    ///   - addedBy: The UID of the user adding the marker.
    ///   - offsetSeconds: The elapsed time in seconds from session start.
    func addChapterMarker(
        sessionId: String,
        title: String,
        addedBy: String,
        offsetSeconds: TimeInterval
    ) async throws {
        // Firestore: add a sub-document under chapterMarkers collection
        // let markerRef = db.collection("liveSessions")
        //     .document(sessionId)
        //     .collection("chapterMarkers")
        //     .document()
        // let marker = LiveChapterMarker(
        //     id: markerRef.documentID,
        //     title: title,
        //     offsetSeconds: offsetSeconds,
        //     addedBy: addedBy,
        //     addedAt: Date()
        // )
        // try await markerRef.setData(Firestore.Encoder().encode(marker))

        // Also update the parent session document's chapterMarkers array
        // try await db.collection("liveSessions").document(sessionId).updateData([
        //     "chapterMarkers": FieldValue.arrayUnion([Firestore.Encoder().encode(marker)])
        // ])
    }

    /// Fetches all chapter markers for a given session, ordered by offset.
    ///
    /// - Parameter sessionId: The ID of the session.
    /// - Returns: An array of `LiveChapterMarker` sorted by `offsetSeconds`.
    func fetchChapterMarkers(sessionId: String) async throws -> [LiveChapterMarker] {
        // Firestore: fetch chapterMarkers sub-collection ordered by offsetSeconds
        // let snapshot = try await db.collection("liveSessions")
        //     .document(sessionId)
        //     .collection("chapterMarkers")
        //     .order(by: "offsetSeconds")
        //     .getDocuments()
        // return try snapshot.documents.map { try $0.data(as: LiveChapterMarker.self) }

        return currentSession?.chapterMarkers ?? []
    }

    // MARK: - Chat

    /// Sends a chat message to the live session's public chat stream.
    /// If `isPrayerRequest` is true, the message is also routed to the prayer queue.
    ///
    /// - Parameters:
    ///   - sessionId: The ID of the target session.
    ///   - authorId: The UID of the sending user.
    ///   - authorName: The display name of the sending user.
    ///   - text: The message body.
    ///   - isPrayerRequest: When `true`, the message also creates a `LivePrayerRequest`.
    func sendChatMessage(
        sessionId: String,
        authorId: String,
        authorName: String,
        text: String,
        isPrayerRequest: Bool
    ) async throws {
        // Firestore: add document to liveSessions/{sessionId}/chat sub-collection
        // let chatRef = db.collection("liveSessions")
        //     .document(sessionId)
        //     .collection("chat")
        //     .document()
        // let entry = LiveChatEntry(
        //     id: chatRef.documentID,
        //     sessionId: sessionId,
        //     authorId: authorId,
        //     authorName: authorName,
        //     text: text,
        //     isPrayerRequest: isPrayerRequest,
        //     isFlagged: false,
        //     isHidden: false,
        //     timestamp: Date()
        // )
        // try await chatRef.setData(Firestore.Encoder().encode(entry))

        // If prayer request, also create an entry in the prayer queue
        // if isPrayerRequest {
        //     try await submitPrayerRequest(
        //         sessionId: sessionId,
        //         authorId: authorId,
        //         authorName: authorName,
        //         request: text
        //     )
        // }
    }

    /// Flags a chat message for moderator review.
    ///
    /// - Parameters:
    ///   - messageId: The ID of the chat message document.
    ///   - sessionId: The ID of the session that contains the message.
    ///   - reportedBy: The UID of the user submitting the report.
    func flagMessage(messageId: String, sessionId: String, reportedBy: String) async throws {
        // Firestore: update isFlagged on the chat message document
        // let msgRef = db.collection("liveSessions")
        //     .document(sessionId)
        //     .collection("chat")
        //     .document(messageId)
        // let snapshot = try await msgRef.getDocument()
        // guard snapshot.exists else { throw LiveChurchModeError.messageNotFound }
        // try await msgRef.updateData(["isFlagged": true])

        // Also write a moderation report to a top-level collection for admin review
        // let reportRef = db.collection("moderationReports").document()
        // try await reportRef.setData([
        //     "type": "liveChat",
        //     "targetId": messageId,
        //     "sessionId": sessionId,
        //     "reportedBy": reportedBy,
        //     "createdAt": FieldValue.serverTimestamp()
        // ])
    }

    /// Hides a chat message from the public chat view. Only callable by session moderators.
    ///
    /// - Parameters:
    ///   - messageId: The ID of the chat message document.
    ///   - sessionId: The ID of the session that contains the message.
    ///   - moderatorId: The UID of the moderator performing the action.
    func hideMessage(messageId: String, sessionId: String, moderatorId: String) async throws {
        // Firestore: set isHidden = true on the message document
        // Firestore security rules enforce that only users with the moderator
        // role for this church can perform this write.
        // let msgRef = db.collection("liveSessions")
        //     .document(sessionId)
        //     .collection("chat")
        //     .document(messageId)
        // let snapshot = try await msgRef.getDocument()
        // guard snapshot.exists else { throw LiveChurchModeError.messageNotFound }
        // try await msgRef.updateData([
        //     "isHidden": true,
        //     "hiddenBy": moderatorId,
        //     "hiddenAt": FieldValue.serverTimestamp()
        // ])
    }

    // MARK: - Prayer Queue

    /// Submits a prayer request to the session's prayer queue.
    ///
    /// - Parameters:
    ///   - sessionId: The ID of the session.
    ///   - authorId: The UID of the user submitting the request.
    ///   - authorName: The display name of the submitting user.
    ///   - request: The text of the prayer request.
    func submitPrayerRequest(
        sessionId: String,
        authorId: String,
        authorName: String,
        request: String
    ) async throws {
        // Firestore: add document to liveSessions/{sessionId}/prayerQueue sub-collection
        // let prayerRef = db.collection("liveSessions")
        //     .document(sessionId)
        //     .collection("prayerQueue")
        //     .document()
        // let prayerRequest = LivePrayerRequest(
        //     id: prayerRef.documentID,
        //     sessionId: sessionId,
        //     authorId: authorId,
        //     authorName: authorName,
        //     request: request,
        //     isAddressed: false,
        //     addressedBy: nil,
        //     submittedAt: Date()
        // )
        // try await prayerRef.setData(Firestore.Encoder().encode(prayerRequest))

        // Also increment the church's total prayer requests metric (Cloud Function handles this)
    }

    /// Marks a prayer request as addressed by the host or a pastor.
    ///
    /// - Parameters:
    ///   - requestId: The document ID of the prayer request.
    ///   - addressedBy: The UID of the pastor or host who addressed it.
    func markPrayerAddressed(requestId: String, addressedBy: String) async throws {
        // Firestore: find the prayer request across active sessions
        // (typically the host passes sessionId down; shown here as a collectionGroup query)
        // let query = db.collectionGroup("prayerQueue")
        //     .whereField(FieldPath.documentID(), isEqualTo: requestId)
        //     .limit(to: 1)
        // let snapshot = try await query.getDocuments()
        // guard let docRef = snapshot.documents.first?.reference
        // else { throw LiveChurchModeError.prayerRequestNotFound }
        // try await docRef.updateData([
        //     "isAddressed": true,
        //     "addressedBy": addressedBy,
        //     "addressedAt": FieldValue.serverTimestamp()
        // ])
    }

    /// Fetches all prayer requests for a session, ordered by submission time.
    ///
    /// - Parameter sessionId: The ID of the session.
    /// - Returns: An array of `LivePrayerRequest` sorted by `submittedAt`.
    func fetchPrayerQueue(sessionId: String) async throws -> [LivePrayerRequest] {
        // Firestore: fetch prayerQueue sub-collection ordered by submittedAt
        // let snapshot = try await db.collection("liveSessions")
        //     .document(sessionId)
        //     .collection("prayerQueue")
        //     .order(by: "submittedAt")
        //     .getDocuments()
        // return try snapshot.documents.map { try $0.data(as: LivePrayerRequest.self) }

        return prayerRequests
    }

    // MARK: - AI Recap

    /// Generates an AI-powered recap of a completed session using a sermon title
    /// and/or a transcript snippet as context. The result is returned as a
    /// formatted string and can be saved separately via `saveAIRecap`.
    ///
    /// - Parameters:
    ///   - sessionId: The ID of the completed session.
    ///   - sermonTitle: Optional title used to anchor the recap narrative.
    ///   - transcriptSnippet: Optional partial transcript (≤ 2000 tokens recommended).
    /// - Returns: A formatted AI recap string.
    /// - Throws: `LiveChurchModeError.recapGenerationFailed` if the AI service returns
    ///   an error or an empty result.
    func generateAIRecap(
        sessionId: String,
        sermonTitle: String?,
        transcriptSnippet: String?
    ) async throws -> String {
        // Cloud Function: call "generateLiveSessionRecap" callable function
        // let functions = Functions.functions()
        // let callable = functions.httpsCallable("generateLiveSessionRecap")
        // let payload: [String: Any] = [
        //     "sessionId": sessionId,
        //     "sermonTitle": sermonTitle ?? "",
        //     "transcriptSnippet": transcriptSnippet ?? ""
        // ]
        // let result = try await callable.call(payload)
        // guard let recapText = (result.data as? [String: Any])?["recap"] as? String,
        //       !recapText.isEmpty
        // else { throw LiveChurchModeError.recapGenerationFailed(reason: "Empty response from AI service") }
        // return recapText

        // Stub: return placeholder recap text
        let title = sermonTitle ?? "Sunday Service"
        return """
        AI Recap — \(title)

        In today's service, the message centred on perseverance and faith, drawing from \
        key scripture passages shared during the session. Several moments of prayer were \
        marked, and the congregation responded with encouragement throughout.

        Key themes: Faith in difficulty · Community prayer · Scriptural grounding

        (This recap was auto-generated and can be edited before publishing.)
        """
    }

    /// Persists a generated AI recap to Firestore, marking the session as recapped.
    ///
    /// - Parameters:
    ///   - sessionId: The ID of the session to attach the recap to.
    ///   - recapText: The final recap text to store.
    func saveAIRecap(sessionId: String, recapText: String) async throws {
        // Firestore: update the session document with recap fields
        // let sessionRef = db.collection("liveSessions").document(sessionId)
        // try await sessionRef.updateData([
        //     "aiRecapGenerated": true,
        //     "aiRecapText": recapText,
        //     "aiRecapSavedAt": FieldValue.serverTimestamp()
        // ])

        if var session = currentSession, session.id == sessionId {
            session.aiRecapGenerated = true
            session.aiRecapText = recapText
            currentSession = session
        }
    }

    // MARK: - Viewer Count

    /// Updates the viewer count for a session by applying a delta (e.g. +1 on join, -1 on leave).
    /// Peak viewer count is tracked server-side via a Cloud Function.
    ///
    /// - Parameters:
    ///   - sessionId: The ID of the session.
    ///   - delta: The change to apply (+1 for join, -1 for leave).
    func updateViewerCount(sessionId: String, delta: Int) async throws {
        // Firestore: atomic increment using FieldValue.increment
        // let sessionRef = db.collection("liveSessions").document(sessionId)
        // try await sessionRef.updateData([
        //     "viewerCount": FieldValue.increment(Int64(delta))
        // ])

        // Cloud Function "onViewerCountUpdate" tracks peakViewerCount:
        // if newCount > currentPeak { update peakViewerCount = newCount }

        viewerCount = max(0, viewerCount + delta)
    }

    /// Subscribes to real-time viewer count updates for a session using a
    /// Firestore snapshot listener. Updates `viewerCount` on the main actor.
    ///
    /// - Parameter sessionId: The ID of the session to observe.
    func subscribeToViewerCount(sessionId: String) {
        // Firestore: attach a snapshot listener to the session document
        // let sessionRef = db.collection("liveSessions").document(sessionId)
        // sessionListener = sessionRef.addSnapshotListener { [weak self] snapshot, error in
        //     guard let self, let data = snapshot?.data() else { return }
        //     let count = data["viewerCount"] as? Int ?? 0
        //     Task { @MainActor in
        //         self.viewerCount = count
        //     }
        // }

        // Stub: simulate a Combine publisher that could be wired to a real-time source
        sessionListener = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                // In production this would be driven by Firestore listener updates,
                // not a timer. The timer is a non-functional placeholder only.
                _ = self
            }
    }
}
