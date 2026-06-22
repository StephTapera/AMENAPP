// AmenCreationDraft.swift
// AMENAPP
// Universal Create draft model (Phase 2).

import Foundation

enum AmenCreationIntent: String, Codable, CaseIterable, Identifiable {
    case textPost
    case photoPost
    case videoPost
    case carousel
    case note
    case selahReflection
    case churchNote
    case designCard
    case discussionPrompt

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .textPost: return "Text Post"
        case .photoPost: return "Photo Post"
        case .videoPost: return "Video Post"
        case .carousel: return "Carousel"
        case .note: return "Note"
        case .selahReflection: return "Selah Reflection"
        case .churchNote: return "Church Note"
        case .designCard: return "Design / Card"
        case .discussionPrompt: return "Discussion Prompt"
        }
    }

    var contentType: AmenContentType {
        switch self {
        case .textPost: return .post
        case .photoPost: return .post
        case .videoPost: return .video
        case .carousel: return .post
        case .note: return .note
        case .selahReflection: return .selah
        case .churchNote: return .churchNote
        case .designCard: return .design
        case .discussionPrompt: return .discussion
        }
    }

    var allowsMultipleMedia: Bool {
        switch self {
        case .carousel: return true
        case .photoPost, .videoPost: return false
        default: return true
        }
    }
}

enum AmenDraftSyncState: String, Codable, CaseIterable {
    case localOnly
    case syncing
    case synced
    case failed
}

struct AmenCreationDraft: Identifiable, Codable, Equatable {
    var id: String
    var ownerId: String
    var intent: AmenCreationIntent
    var title: String?
    var text: String
    var blocks: [ContentBlock]
    var mediaRefs: [MediaRef]
    var intendedVisibility: AmenVisibility
    var createdAt: Date
    var updatedAt: Date
    var publishTarget: String?
    var syncState: AmenDraftSyncState

    init(
        id: String = UUID().uuidString,
        ownerId: String,
        intent: AmenCreationIntent,
        title: String? = nil,
        text: String = "",
        blocks: [ContentBlock] = [],
        mediaRefs: [MediaRef] = [],
        intendedVisibility: AmenVisibility = .public,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        publishTarget: String? = nil,
        syncState: AmenDraftSyncState = .localOnly
    ) {
        self.id = id
        self.ownerId = ownerId
        self.intent = intent
        self.title = title
        self.text = text
        self.blocks = blocks
        self.mediaRefs = mediaRefs
        self.intendedVisibility = intendedVisibility
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.publishTarget = publishTarget
        self.syncState = syncState
    }

    var contentType: AmenContentType { intent.contentType }

    mutating func updateText(_ newText: String) {
        text = newText
        updatedAt = Date()
        if blocks.isEmpty {
            blocks = [ContentBlock(type: .text, text: newText, order: 0)]
        } else {
            blocks[0].text = newText
        }
    }

    mutating func updateMedia(_ refs: [MediaRef]) {
        mediaRefs = refs
        updatedAt = Date()
    }

    func toContentNode() -> ContentNode {
        let author = ContentAuthorMetadata(displayName: "You", username: nil, avatarURL: nil, initials: nil)
        let blocks = blocks.isEmpty ? [ContentBlock(type: .text, text: text, order: 0)] : blocks
        return ContentNode(
            id: id,
            ownerId: ownerId,
            author: author,
            type: contentType,
            visibility: intendedVisibility,
            title: title,
            text: text,
            blocks: blocks,
            mediaRefs: mediaRefs,
            collaborators: [],
            moderationState: .pending,
            aiMetadata: .none,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: nil,
            sourceReferences: [],
            parentContentId: nil,
            remixSourceId: nil,
            saveEligible: true,
            shareEligible: true,
            accessibility: nil,
            language: nil,
            translation: nil,
            publishState: .draft
        )
    }
}
