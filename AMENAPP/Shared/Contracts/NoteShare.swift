// NoteShare.swift
// AMENAPP - Shared/Contracts
//
// FROZEN - Wave 0 NOTE_SHARE_VIEWER contracts.
// Do not edit without Lead Orchestrator authorization and rebroadcast to all dependent agents.
// Frozen on 2026-06-09.
//
// Contract-only: no callables, repositories, routing handlers, or UI live here.

import Foundation

let NoteShareContractsVersion = "2026-06-09-wave0-v1"
let NoteShareFeatureFlagKey = "feature_note_share_viewer"
let NoteShareFeatureFlagDefault = false

// MARK: - Firestore Paths

enum NoteShareFirestorePathContract {
    static let sharesCollection = "noteShares"
    static let sourceNotesCollection = "churchNotes"
    static let sourceBlocksSubcollection = "blocks"
    static let analyticsCollection = "noteShareAnalytics"
}

// MARK: - Routing

struct NoteShareRouteContract: Codable, Equatable, Sendable {
    let shareId: String
    let noteId: String?

    var appPath: String { "amen://note-share/\(shareId)" }
    var webFallbackPath: String { "https://amenapp.com/note-share/\(shareId)" }
}

// MARK: - Share Document

enum NoteShareStatus: String, Codable, CaseIterable, Sendable {
    case active
    case revoked
    case expired
    case removedByModeration = "removed_by_moderation"
}

enum NoteShareAudience: String, Codable, CaseIterable, Sendable {
    case ownerOnly = "owner_only"
    case collaborators
    case followers
    case church
    case publicLink = "public_link"
}

enum NoteShareSignedOutAccess: String, Codable, CaseIterable, Sendable {
    case denied
    case previewOnly = "preview_only"
    case fullSnapshot = "full_snapshot"
}

enum NoteShareFollowerPolicy: String, Codable, CaseIterable, Sendable {
    case disabled
    case authorFollowers = "author_followers"
    case mutualFollowers = "mutual_followers"
}

enum NoteShareSnapshotSource: String, Codable, CaseIterable, Sendable {
    case churchNote = "church_note"
    case churchNoteBlock = "church_note_block"
    case postAttachment = "post_attachment"
}

struct NoteShareAccessPolicy: Codable, Equatable, Sendable {
    var audience: NoteShareAudience
    var signedOutAccess: NoteShareSignedOutAccess
    var followerPolicy: NoteShareFollowerPolicy
    var requiresAuth: Bool
    var allowExternalIndexing: Bool

    static let conservativeDefault = NoteShareAccessPolicy(
        audience: .ownerOnly,
        signedOutAccess: .denied,
        followerPolicy: .disabled,
        requiresAuth: true,
        allowExternalIndexing: false
    )
}

struct NoteShareSourceRef: Codable, Equatable, Sendable {
    let noteId: String
    let ownerUid: String
    let sourcePostId: String?
    let churchId: String?
    let source: NoteShareSnapshotSource
}

struct NoteShareBlockSnapshot: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let sourceBlockId: String
    let sortOrder: Double
    let text: String
    let semanticType: String
    let blockType: String
    let visibility: String
    let scriptureReference: String?
}

struct NoteShareSnapshot: Codable, Equatable, Sendable {
    let title: String
    let sermonTitle: String?
    let sermonSpeaker: String?
    let churchName: String?
    let scriptureReferences: [String]
    let excerpt: String
    let blocks: [NoteShareBlockSnapshot]
    let sourceSchemaVersion: Int
    let snapshotSchemaVersion: Int
}

struct NoteShareRecord: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let sourceRef: NoteShareSourceRef
    var status: NoteShareStatus
    var accessPolicy: NoteShareAccessPolicy
    var snapshot: NoteShareSnapshot
    let createdByUid: String
    let createdAt: Date
    var updatedAt: Date
    var expiresAt: Date?
    var revokedAt: Date?
}

// MARK: - API Contracts

struct CreateNoteShareRequest: Codable, Equatable, Sendable {
    let noteId: String
    let sourcePostId: String?
    let selectedBlockIds: [String]
    let accessPolicy: NoteShareAccessPolicy
}

struct CreateNoteShareResponse: Codable, Equatable, Sendable {
    let shareId: String
    let route: NoteShareRouteContract
    let status: NoteShareStatus
}

struct ResolveNoteShareRequest: Codable, Equatable, Sendable {
    let shareId: String
    let viewerUid: String?
    let source: String?
}

struct ResolveNoteShareResponse: Codable, Equatable, Sendable {
    let share: NoteShareRecord
    let viewerCanOpenSourceNote: Bool
    let viewerCanSeeFullSnapshot: Bool
}

struct RevokeNoteShareRequest: Codable, Equatable, Sendable {
    let shareId: String
    let noteId: String
}

struct RevokeNoteShareResponse: Codable, Equatable, Sendable {
    let shareId: String
    let status: NoteShareStatus
}

// MARK: - Analytics

enum NoteShareAnalyticsEvent: String, Codable, CaseIterable, Sendable {
    case noteShareCreated = "note_share_created"
    case noteShareCopied = "note_share_copied"
    case noteShareOpened = "note_share_opened"
    case noteShareResolved = "note_share_resolved"
    case noteShareDenied = "note_share_denied"
    case noteShareRevoked = "note_share_revoked"
}

enum NoteShareAnalyticsParam: String, Codable, CaseIterable, Sendable {
    case shareIdHashed = "share_id_hashed"
    case noteIdHashed = "note_id_hashed"
    case ownerUidHashed = "owner_uid_hashed"
    case viewerState = "viewer_state"
    case audience = "audience"
    case sourceSurface = "source_surface"
    case result = "result"
    case failureReason = "failure_reason"
}
