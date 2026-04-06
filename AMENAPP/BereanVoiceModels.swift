// BereanVoiceModels.swift
// AMENAPP
//
// Berean Live Voice — Data models, enums, session types
//
// Created for AMEN — all new types; no existing files modified.

import Foundation

// MARK: - Voice Mode

/// The conversational context Berean operates in during a live voice session.
enum BereanVoiceMode: String, CaseIterable, Codable {
    case conversation  = "conversation"
    case prayer        = "prayer"
    case churchNotes   = "churchNotes"
    case discovery     = "discovery"
    case wellness      = "wellness"

    var displayName: String {
        switch self {
        case .conversation: return "Conversation"
        case .prayer:       return "Prayer"
        case .churchNotes:  return "Church Notes"
        case .discovery:    return "Discovery"
        case .wellness:     return "Wellness"
        }
    }

    var systemIconName: String {
        switch self {
        case .conversation: return "bubble.left.and.bubble.right"
        case .prayer:       return "hands.sparkles"
        case .churchNotes:  return "note.text"
        case .discovery:    return "magnifyingglass"
        case .wellness:     return "heart"
        }
    }
}

// MARK: - Voice State

/// Current state of the live voice pipeline.
enum BereanVoiceState: String {
    case idle        = "idle"
    case listening   = "listening"
    case thinking    = "thinking"
    case speaking    = "speaking"
    case interrupted = "interrupted"
    case error       = "error"

    var displayLabel: String {
        switch self {
        case .idle:        return "Tap to begin"
        case .listening:   return "Listening…"
        case .thinking:    return "Thinking…"
        case .speaking:    return "Speaking…"
        case .interrupted: return "Interrupted"
        case .error:       return "Something went wrong"
        }
    }
}

// MARK: - Emotional State

/// Detected emotional register of the user utterance — used for response shaping.
enum BereanEmotionalState: String, Codable {
    case neutral   = "neutral"
    case distressed = "distressed"
    case seeking   = "seeking"
    case joyful    = "joyful"
}

// MARK: - Response Strategy

/// How Berean should sequence its response given latency and emotional context.
enum BereanResponseStrategy: String {
    /// Play a short verbal acknowledgment immediately, then stream the full response.
    case instantAcknowledgment  = "instantAcknowledgment"
    /// Begin streaming the response without a pre-acknowledgment.
    case partialStream          = "partialStream"
    /// Ask a clarifying question before answering.
    case clarifyFirst           = "clarifyFirst"
    /// Allow a brief pause before delivering a considered, deeper reply.
    case delayedDeepResponse    = "delayedDeepResponse"
}

// MARK: - Session

/// A single continuous live-voice session persisted to Firestore.
struct BereanVoiceSession: Codable, Identifiable {
    var id: String
    var userId: String
    var mode: BereanVoiceMode
    var startTime: Date
    var endTime: Date?
    var emotionalState: BereanEmotionalState
    var interruptionCount: Int
    var avgLatencyMs: Double
    var transcriptChunks: [String]
    var isActive: Bool

    /// Convenience initializer for creating a brand-new session.
    init(
        id: String = UUID().uuidString,
        userId: String,
        mode: BereanVoiceMode,
        emotionalState: BereanEmotionalState = .neutral
    ) {
        self.id = id
        self.userId = userId
        self.mode = mode
        self.startTime = Date()
        self.endTime = nil
        self.emotionalState = emotionalState
        self.interruptionCount = 0
        self.avgLatencyMs = 0
        self.transcriptChunks = []
        self.isActive = true
    }

    /// Firestore document representation (avoids Date encoding issues).
    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "id": id,
            "userId": userId,
            "mode": mode.rawValue,
            "startTime": startTime,
            "emotionalState": emotionalState.rawValue,
            "interruptionCount": interruptionCount,
            "avgLatencyMs": avgLatencyMs,
            "transcriptChunks": transcriptChunks,
            "isActive": isActive
        ]
        if let end = endTime { data["endTime"] = end }
        return data
    }
}

// MARK: - Voice Event

/// An auditable event emitted during a voice session.
struct BereanVoiceEvent: Codable, Identifiable {
    var id: String
    var sessionId: String
    var type: String
    var timestamp: Date
    var payload: [String: String]

    init(
        id: String = UUID().uuidString,
        sessionId: String,
        type: BereanVoiceEventType,
        payload: [String: String] = [:]
    ) {
        self.id = id
        self.sessionId = sessionId
        self.type = type.rawValue
        self.timestamp = Date()
        self.payload = payload
    }

    func toFirestoreData() -> [String: Any] {
        [
            "id": id,
            "sessionId": sessionId,
            "type": type,
            "timestamp": timestamp,
            "payload": payload
        ]
    }
}

// MARK: - Voice Event Type

enum BereanVoiceEventType: String {
    case interrupt       = "interrupt"
    case response        = "response"
    case pause           = "pause"
    case safetyFlag      = "safetyFlag"
    case bargein         = "bargein"
    case acknowledgment  = "acknowledgment"
}

// MARK: - Audio Chunk

/// A raw PCM audio chunk emitted by the streaming microphone pipeline.
struct BereanAudioChunk {
    let data: Data
    let timestamp: Date
    let durationMs: Double

    init(data: Data, durationMs: Double) {
        self.data = data
        self.timestamp = Date()
        self.durationMs = durationMs
    }
}

// MARK: - Transcript Segment

/// A single fragment of the rolling transcript — may be partial while ASR processes.
struct BereanTranscriptSegment: Identifiable {
    let id: UUID
    let text: String
    let isPartial: Bool
    let confidence: Double
    let timestamp: Date

    init(
        id: UUID = UUID(),
        text: String,
        isPartial: Bool = false,
        confidence: Double = 1.0
    ) {
        self.id = id
        self.text = text
        self.isPartial = isPartial
        self.confidence = confidence
        self.timestamp = Date()
    }
}

// MARK: - Voice Error

/// Typed errors surfaced by the Berean Live Voice pipeline.
enum BereanVoiceError: LocalizedError {
    case micPermissionDenied
    case audioEngineFailure(String)
    case sessionExpired
    case networkError(String)
    case safetyInterrupt
    case noActiveSession

    var errorDescription: String? {
        switch self {
        case .micPermissionDenied:
            return "Microphone access is required for voice mode. Please enable it in Settings."
        case .audioEngineFailure(let detail):
            return "Audio engine error: \(detail)"
        case .sessionExpired:
            return "Your voice session has expired. Please start a new session."
        case .networkError(let detail):
            return "Network error: \(detail)"
        case .safetyInterrupt:
            return "The conversation was paused for safety review."
        case .noActiveSession:
            return "No active voice session. Please start a session first."
        }
    }
}
