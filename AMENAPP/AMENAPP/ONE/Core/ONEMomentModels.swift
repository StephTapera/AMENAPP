// ONEMomentModels.swift
// ONE — Core Moment Object
// P0-F | FROZEN contracts. See CONTRACTS.md §1.

import Foundation

// MARK: - ONEMoment

struct ONEMoment: Codable, Identifiable, Sendable {
    let id: String
    let authorUID: String
    let type: ONEMomentType
    var privacy: ONEPrivacyContract
    let content: ONEMomentContent
    let provenance: ONEProvenanceLabel
    let createdAt: Date
    var expiresAt: Date?
    var permanentAt: Date?
    var reachBudget: ONEReachBudget?
    let consentDNA: ONEConsentDNA
    let isE2E: Bool
    var reportedAt: Date?
}

// MARK: - ONEMomentType

enum ONEMomentType: String, Codable, Sendable, CaseIterable {
    case directMessage
    case snap
    case post
    case voice
    case reflection
    case locationShare
    case memory
    case album
    case creatorDrop
}

// MARK: - ONEMomentContent

enum ONEMomentContent: Sendable {
    case text(ONETextPayload)
    case image(ONEImagePayload)
    case video(ONEVideoPayload)
    case audio(ONEAudioPayload)
    case location(ONELocationPayload)
    case album(ONEAlbumPayload)
    case encrypted(ONEEncryptedPayload)
}

extension ONEMomentContent: Codable {
    private enum CodingKeys: String, CodingKey { case type, text, image, video, audio, location, album, encrypted }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let t = try c.decode(String.self, forKey: .type)
        switch t {
        case "text":      self = .text(try c.decode(ONETextPayload.self, forKey: .text))
        case "image":     self = .image(try c.decode(ONEImagePayload.self, forKey: .image))
        case "video":     self = .video(try c.decode(ONEVideoPayload.self, forKey: .video))
        case "audio":     self = .audio(try c.decode(ONEAudioPayload.self, forKey: .audio))
        case "location":  self = .location(try c.decode(ONELocationPayload.self, forKey: .location))
        case "album":     self = .album(try c.decode(ONEAlbumPayload.self, forKey: .album))
        case "encrypted": self = .encrypted(try c.decode(ONEEncryptedPayload.self, forKey: .encrypted))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown content type: \(t)")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let p):
            try c.encode("text", forKey: .type); try c.encode(p, forKey: .text)
        case .image(let p):
            try c.encode("image", forKey: .type); try c.encode(p, forKey: .image)
        case .video(let p):
            try c.encode("video", forKey: .type); try c.encode(p, forKey: .video)
        case .audio(let p):
            try c.encode("audio", forKey: .type); try c.encode(p, forKey: .audio)
        case .location(let p):
            try c.encode("location", forKey: .type); try c.encode(p, forKey: .location)
        case .album(let p):
            try c.encode("album", forKey: .type); try c.encode(p, forKey: .album)
        case .encrypted(let p):
            try c.encode("encrypted", forKey: .type); try c.encode(p, forKey: .encrypted)
        }
    }
}

// MARK: - Payload Types

struct ONETextPayload: Codable, Sendable {
    let body: String
    let mentionedUIDs: [String]
    let linkedScriptureRefs: [String]
}

struct ONEImagePayload: Codable, Sendable {
    let storageURL: String
    let provenanceLabel: ONEProvenanceLabel
    let altText: String?
    let facesBlurred: Bool
    let locationStripped: Bool
    let width: Int
    let height: Int
}

struct ONEVideoPayload: Codable, Sendable {
    let storageURL: String
    let thumbnailURL: String?
    let durationSeconds: Double
    let captionsURL: String?
    let provenanceLabel: ONEProvenanceLabel
    let autoplayEnabled: Bool
}

struct ONEAudioPayload: Codable, Sendable {
    let storageURL: String
    let durationSeconds: Double
    let transcriptText: String?
}

struct ONELocationPayload: Codable, Sendable {
    let precisionLevel: ONELocationPrecision
    let expiresAt: Date?
    // lat/lng stored only on device; server receives precision bucket only
}

enum ONELocationPrecision: String, Codable, Sendable {
    case exact
    case neighborhood
    case city
    case region
    case hidden
}

struct ONEAlbumPayload: Codable, Sendable {
    let title: String
    let contributorUIDs: [String]
    let itemIDs: [String]
    let isCollaborative: Bool
}

struct ONEEncryptedPayload: Codable, Sendable {
    let ciphertext: Data
    let epoch: UInt64             // key ratchet epoch
    let senderDeviceID: String
    let encryptionVersion: String // "cr_1.0"
}
