// VoicePrayerModels.swift
// AMEN App — Voice Prayer & Testimony Comments
//
// Client-side model layer for voice comments.
// All server-owned fields (moderation, intent, spiritualContext, summary,
// transcript, status) are read-only from the client.
// The backend (voicePrayerComments.ts) owns all status transitions and
// content classifications — the client never trusts these values for
// publish decisions.

import Foundation
import FirebaseFirestore

// MARK: - Enums

enum VoiceCommentType: String, Codable, CaseIterable {
    case prayer    = "prayer"
    case testimony = "testimony"

    var displayName: String {
        switch self {
        case .prayer:    return "Prayer"
        case .testimony: return "Testimony"
        }
    }

    var recordButtonLabel: String {
        switch self {
        case .prayer:    return "Pray by Voice"
        case .testimony: return "Share Testimony"
        }
    }

    var systemIcon: String {
        switch self {
        case .prayer:    return "hands.sparkles.fill"
        case .testimony: return "star.fill"
        }
    }

    /// Max recording seconds enforced client-side. Backend validates as well.
    var maxDurationSeconds: Double {
        switch self {
        case .prayer:    return 90
        case .testimony: return 180
        }
    }

    /// Warning threshold (client warns user before hard cutoff)
    var warningThresholdSeconds: Double {
        return maxDurationSeconds - 15
    }
}

enum VoiceCommentStatus: String, Codable {
    case processing     = "processing"
    case published      = "published"
    case heldForReview  = "held_for_review"
    case blocked        = "blocked"
}

enum VoiceCommentVisibility: String, Codable, CaseIterable {
    case `public`     = "public"
    case followers    = "followers"
    case church       = "church"
    case prayerCircle = "prayer_circle"
    case `private`    = "private"

    var displayName: String {
        switch self {
        case .public:      return "Public"
        case .followers:   return "Followers"
        case .church:      return "Church Community"
        case .prayerCircle: return "Prayer Circle"
        case .private:     return "Private Note"
        }
    }

    var systemIcon: String {
        switch self {
        case .public:      return "globe"
        case .followers:   return "person.2.fill"
        case .church:      return "building.columns.fill"
        case .prayerCircle: return "circle.grid.3x3.fill"
        case .private:     return "lock.fill"
        }
    }
}

enum VoiceCommentTranscriptStatus: String, Codable {
    case pending = "pending"
    case ready   = "ready"
    case failed  = "failed"
}

enum VoiceCommentIntentLabel: String, Codable {
    case prayerRequest  = "prayer_request"
    case prayerResponse = "prayer_response"
    case testimony      = "testimony"
    // Backend may return off-topic values; client treats them as unknown
    case unknown        = "unknown"
}

// MARK: - Sub-models (read-only from client)

struct VoiceCommentModeration: Codable {
    let decision:   String  // "allow" | "review" | "block"
    let riskLevel:  String  // "low" | "medium" | "high"
    let categories: [String]
    let reasonCode: String
}

struct VoiceCommentIntent: Codable {
    let label:      VoiceCommentIntentLabel
    let confidence: Double
}

struct VoiceCommentSpiritualContext: Codable {
    let tone:                   String
    let confidence:             Double
    let containsSensitiveDetails: Bool
    let suggestedVisibility:    String?
}

struct VoiceCommentCounts: Codable {
    var prayed:    Int
    var amen:      Int
    var encourage: Int
    var replies:   Int
    var reports:   Int
}

// MARK: - Main Document Model

struct VoiceComment: Identifiable, Codable {
    let id: String
    let postId: String
    let parentCommentId: String?
    let authorUid: String

    let type:   VoiceCommentType
    let status: VoiceCommentStatus

    let audioStoragePath: String
    let audioDurationMs:  Int
    let waveform:         [Double]

    let transcript:       String
    let transcriptStatus: VoiceCommentTranscriptStatus

    let summary:  String
    let language: String

    let moderation:      VoiceCommentModeration?
    let intent:          VoiceCommentIntent?
    let spiritualContext: VoiceCommentSpiritualContext?

    let visibility: VoiceCommentVisibility
    var counts:     VoiceCommentCounts

    let createdAt: Date
    let updatedAt: Date

    // MARK: Firestore mapping

    enum CodingKeys: String, CodingKey {
        case id, postId, parentCommentId, authorUid, type, status
        case audioStoragePath, audioDurationMs, waveform
        case transcript, transcriptStatus, summary, language
        case moderation, intent, spiritualContext
        case visibility, counts, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(String.self, forKey: .id)
        postId          = try c.decode(String.self, forKey: .postId)
        parentCommentId = try c.decodeIfPresent(String.self, forKey: .parentCommentId)
        authorUid       = try c.decode(String.self, forKey: .authorUid)
        type            = try c.decode(VoiceCommentType.self, forKey: .type)
        status          = (try? c.decode(VoiceCommentStatus.self, forKey: .status)) ?? .processing
        audioStoragePath = try c.decode(String.self, forKey: .audioStoragePath)
        audioDurationMs  = (try? c.decode(Int.self, forKey: .audioDurationMs)) ?? 0
        waveform        = (try? c.decode([Double].self, forKey: .waveform)) ?? []
        transcript      = (try? c.decode(String.self, forKey: .transcript)) ?? ""
        transcriptStatus = (try? c.decode(VoiceCommentTranscriptStatus.self, forKey: .transcriptStatus)) ?? .pending
        summary         = (try? c.decode(String.self, forKey: .summary)) ?? ""
        language        = (try? c.decode(String.self, forKey: .language)) ?? "en"
        moderation      = try? c.decodeIfPresent(VoiceCommentModeration.self, forKey: .moderation)
        intent          = try? c.decodeIfPresent(VoiceCommentIntent.self, forKey: .intent)
        spiritualContext = try? c.decodeIfPresent(VoiceCommentSpiritualContext.self, forKey: .spiritualContext)
        visibility      = (try? c.decode(VoiceCommentVisibility.self, forKey: .visibility)) ?? .public
        counts          = (try? c.decode(VoiceCommentCounts.self, forKey: .counts)) ?? VoiceCommentCounts(prayed: 0, amen: 0, encourage: 0, replies: 0, reports: 0)

        // Firestore Timestamps come as Double or Timestamp; decode both paths
        if let ts = try? c.decode(Timestamp.self, forKey: .createdAt) {
            createdAt = ts.dateValue()
        } else {
            createdAt = Date()
        }
        if let ts = try? c.decode(Timestamp.self, forKey: .updatedAt) {
            updatedAt = ts.dateValue()
        } else {
            updatedAt = Date()
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(postId, forKey: .postId)
        try c.encodeIfPresent(parentCommentId, forKey: .parentCommentId)
        try c.encode(authorUid, forKey: .authorUid)
        try c.encode(type.rawValue, forKey: .type)
        try c.encode(status.rawValue, forKey: .status)
        try c.encode(audioStoragePath, forKey: .audioStoragePath)
        try c.encode(audioDurationMs, forKey: .audioDurationMs)
        try c.encode(waveform, forKey: .waveform)
        try c.encode(transcript, forKey: .transcript)
        try c.encode(transcriptStatus.rawValue, forKey: .transcriptStatus)
        try c.encode(summary, forKey: .summary)
        try c.encode(language, forKey: .language)
        try c.encodeIfPresent(moderation, forKey: .moderation)
        try c.encodeIfPresent(intent, forKey: .intent)
        try c.encodeIfPresent(spiritualContext, forKey: .spiritualContext)
        try c.encode(visibility.rawValue, forKey: .visibility)
        try c.encode(counts, forKey: .counts)
    }

    /// Formatted duration string, e.g. "1:23"
    var durationString: String {
        let seconds = audioDurationMs / 1000
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// True when the transcript is worth showing (non-empty, ready)
    var hasTranscript: Bool {
        transcriptStatus == .ready && !transcript.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// True when backend returned a non-empty summary
    var hasSummary: Bool {
        !summary.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

// MARK: - Upload Session (response from createVoicePrayerUploadSession)

struct VoicePrayerUploadSession {
    let voiceCommentId: String
    let uploadPath:     String  // Firebase Storage path (uid/postId/voiceCommentId.m4a)
    let expiresAt:      Date
}

// MARK: - Reaction type

enum VoiceCommentReaction: String, CaseIterable {
    case prayed    = "prayed"
    case amen      = "amen"
    case encourage = "encourage"

    var displayLabel: String {
        switch self {
        case .prayed:    return "Prayed"
        case .amen:      return "Amen"
        case .encourage: return "Encourage"
        }
    }

    var systemIcon: String {
        switch self {
        case .prayed:    return "hands.sparkles"
        case .amen:      return "checkmark.seal"
        case .encourage: return "heart"
        }
    }
}
