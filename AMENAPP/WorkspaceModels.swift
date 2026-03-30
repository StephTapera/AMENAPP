// WorkspaceModels.swift
// AMENAPP — Cadence Workspace shared models (KORA, VERGE, HELIX)

import Foundation
import FirebaseFirestore

// MARK: - Workspace

struct Workspace: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var description: String
    var logoURL: String?
    var ownerId: String
    var memberIds: [String]
    var enabledPlatforms: [String]   // "kora", "verge", "helix"
    var plan: String                 // "free" | "pro" | "enterprise"
    var createdAt: Date?
    var memberCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case logoURL        = "logoURL"
        case ownerId        = "ownerId"
        case memberIds      = "memberIds"
        case enabledPlatforms = "enabledPlatforms"
        case plan
        case createdAt      = "createdAt"
        case memberCount    = "memberCount"
    }
}

// MARK: - WorkspaceMember

struct WorkspaceMember: Identifiable, Codable {
    @DocumentID var id: String?
    var workspaceId: String
    var userId: String
    var role: String        // "owner" | "admin" | "member" | "guest"
    var joinedAt: Date?
    var platforms: [String] // platforms the member has access to within this workspace

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceId  = "workspaceId"
        case userId       = "userId"
        case role
        case joinedAt     = "joinedAt"
        case platforms
    }
}
