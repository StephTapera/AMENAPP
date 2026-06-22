// AmenContentType.swift
// AMENAPP
// Universal content types for Phase 1.

import Foundation

enum AmenContentType: String, Codable, CaseIterable, Identifiable {
    case post
    case video
    case note
    case design
    case selah
    case churchNote
    case discussion
    case aiSession
    // Contextual reaction subtypes
    case comment
    case reply
    case mediaPost
    case prayerPost
    case testimonyPost
    case scripturePost

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .post: return "Post"
        case .video: return "Video"
        case .note: return "Note"
        case .design: return "Design"
        case .selah: return "Selah"
        case .churchNote: return "Church Note"
        case .discussion: return "Discussion"
        case .aiSession: return "AI Session"
        case .comment: return "Comment"
        case .reply: return "Reply"
        case .mediaPost: return "Media Post"
        case .prayerPost: return "Prayer Post"
        case .testimonyPost: return "Testimony Post"
        case .scripturePost: return "Scripture Post"
        }
    }
}
