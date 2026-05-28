//
//  AmenPrivateResonanceStore.swift
//  AMENAPP
//
//  Private engagement event tracking. Records how users resonated with content
//  without exposing any public counters. All data is user-scoped and never
//  surfaced as visible metrics to other users.
//

import Foundation
import FirebaseAuth
import FirebaseAnalytics
import FirebaseFirestore

// MARK: - Event Types

enum AmenResonanceEventType: String, Codable, CaseIterable {
    case heart          = "heart"
    case save           = "save"
    case reflect        = "reflect"
    case pray           = "pray"
    case encourage      = "encourage"
    case ask            = "ask"
    case sendIntent     = "send_intent"
    case continueLater  = "continue_later"
    case sessionComplete = "session_complete"
    case quietMode      = "quiet_mode"
    case topicSwitch    = "topic_switch"
    case saveToNotes    = "save_to_notes"
    case saveToSelah    = "save_to_selah"

    var analyticsName: String { rawValue }
}

struct AmenResonanceEvent: Codable {
    let id: String
    let userId: String
    let contentId: String
    let contentType: String
    let eventType: AmenResonanceEventType
    let sessionId: String
    let topicContext: String?
    let timestamp: Date

    init(
        contentId: String,
        contentType: String,
        eventType: AmenResonanceEventType,
        sessionId: String,
        topicContext: String? = nil
    ) {
        self.id = UUID().uuidString
        self.userId = Auth.auth().currentUser?.uid ?? "anonymous"
        self.contentId = contentId
        self.contentType = contentType
        self.eventType = eventType
        self.sessionId = sessionId
        self.topicContext = topicContext
        self.timestamp = Date()
    }
}

// MARK: - Store

@MainActor
final class AmenPrivateResonanceStore: ObservableObject {
    static let shared = AmenPrivateResonanceStore()
    private init() {}

    // In-memory log for the current session. Not persisted to Firestore as public data.
    private(set) var sessionEvents: [AmenResonanceEvent] = []

    // MARK: - Record

    func record(
        _ eventType: AmenResonanceEventType,
        contentId: String,
        contentType: String = "post",
        topicContext: String? = nil
    ) {
        let event = AmenResonanceEvent(
            contentId: contentId,
            contentType: contentType,
            eventType: eventType,
            sessionId: FeedSessionManager.shared.sessionId,
            topicContext: topicContext
        )
        sessionEvents.append(event)
        logAnalytics(event)
        persistToFirestore(event)
    }

    // MARK: - Convenience wrappers

    func recordHeart(contentId: String, contentType: String = "post") {
        record(.heart, contentId: contentId, contentType: contentType)
    }

    func recordSave(contentId: String, contentType: String = "post") {
        record(.save, contentId: contentId, contentType: contentType)
    }

    func recordPray(contentId: String, contentType: String = "post") {
        record(.pray, contentId: contentId, contentType: contentType)
    }

    func recordReflect(contentId: String, contentType: String = "post") {
        record(.reflect, contentId: contentId, contentType: contentType)
    }

    func recordEncourage(contentId: String, contentType: String = "post") {
        record(.encourage, contentId: contentId, contentType: contentType)
    }

    func recordAsk(contentId: String, contentType: String = "post") {
        record(.ask, contentId: contentId, contentType: contentType)
    }

    func recordSaveToNotes(contentId: String) {
        record(.saveToNotes, contentId: contentId, contentType: "post")
    }

    func recordSaveToSelah(contentId: String) {
        record(.saveToSelah, contentId: contentId, contentType: "verse")
    }

    func recordQuietMode() {
        record(.quietMode, contentId: "session", contentType: "session")
    }

    func recordTopicSwitch(to topic: String) {
        record(.topicSwitch, contentId: topic, contentType: "topic", topicContext: topic)
    }

    // MARK: - Session helpers

    func eventCount(for type: AmenResonanceEventType) -> Int {
        sessionEvents.filter { $0.eventType == type }.count
    }

    func hasResonated(contentId: String) -> Bool {
        sessionEvents.contains { $0.contentId == contentId }
    }

    func clearSession() {
        sessionEvents.removeAll()
    }

    // MARK: - Persistence

    private func persistToFirestore(_ event: AmenResonanceEvent) {
        guard event.userId != "anonymous" else { return }
        Task {
            let db = Firestore.firestore()
            var data: [String: Any] = [
                "eventType":   event.eventType.rawValue,
                "contentId":   event.contentId,
                "contentType": event.contentType,
                "sessionId":   event.sessionId,
                "timestamp":   Timestamp(date: event.timestamp)
            ]
            if let topic = event.topicContext {
                data["topicContext"] = topic
            }
            try? await db
                .collection("users").document(event.userId)
                .collection("resonanceEvents").document(event.id)
                .setData(data)
        }
    }

    // MARK: - Analytics (private, user-scoped only)

    private func logAnalytics(_ event: AmenResonanceEvent) {
        Analytics.logEvent("private_resonance", parameters: [
            "event_type": event.eventType.analyticsName,
            "content_type": event.contentType,
            "session_id": event.sessionId,
            "topic_context": event.topicContext ?? ""
        ])
    }
}
