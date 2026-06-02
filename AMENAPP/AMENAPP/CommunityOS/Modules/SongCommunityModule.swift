// SongCommunityModule.swift
// AMEN App — Community Around Content OS
//
// Models, services, and views for song-type ContentObjects.
// Depends on CommunityOSContracts.swift and CommunityOSFeatureFlags.swift — do NOT redefine
// types from those files.

import Foundation
import SwiftUI
import FirebaseFirestore

// MARK: - SongCommunityMetadata

/// Extends ContentObject metadata for song-type objects.
struct SongCommunityMetadata: Codable, Equatable {
    var artist: String
    var album: String
    var durationSeconds: Int
    var genre: String
    /// Spiritual theme carried by this song, e.g. "Trust", "Praise", "Healing".
    var worshipTheme: String?
    var isLiveWorship: Bool
}

// MARK: - SongCommunityService

actor SongCommunityService {

    private let db = Firestore.firestore()

    // MARK: Metadata

    /// Fetches the song-specific metadata stored in `contentObjects/{id}/songMeta/default`.
    func fetchMetadata(for contentObjectId: String) async throws -> SongCommunityMetadata? {
        let snap = try await db
            .collection("contentObjects")
            .document(contentObjectId)
            .collection("songMeta")
            .document("default")
            .getDocument()
        guard snap.exists, let data = snap.data() else { return nil }
        return try Firestore.Decoder().decode(SongCommunityMetadata.self, from: data)
    }

    // MARK: Church Worship Library

    /// Fetches up to 50 songs from a church's worship library, ordered newest first.
    func getChurchWorshipLibrary(churchId: String) async throws -> [ContentObject] {
        let snaps = try await db
            .collection("churches")
            .document(churchId)
            .collection("worshipLibrary")
            .order(by: "addedAt", descending: true)
            .limit(to: 50)
            .getDocuments()

        return snaps.documents.compactMap { doc in
            ContentObject(from: doc.data())
        }
    }

    /// Writes a song ContentObject into a church's worship library.
    func addToChurchLibrary(songContentObjectId: String, churchId: String) async throws {
        let payload: [String: Any] = [
            "songContentObjectId": songContentObjectId,
            "addedAt": FieldValue.serverTimestamp()
        ]
        try await db
            .collection("churches")
            .document(churchId)
            .collection("worshipLibrary")
            .document(songContentObjectId)
            .setData(payload)
        dlog("[SongCommunityService] Added song \(songContentObjectId) to church \(churchId) library")
    }

    // MARK: Testimonies

    /// Returns up to 20 raw testimony documents for a song.
    func getTestimoniesForSong(contentObjectId: String) async throws -> [[String: Any]] {
        let snaps = try await db
            .collection("contentObjects")
            .document(contentObjectId)
            .collection("testimonies")
            .limit(to: 20)
            .getDocuments()
        return snaps.documents.map { $0.data() }
    }

    /// Adds a new testimony for a song.
    func addTestimony(contentObjectId: String, userId: String, text: String) async throws {
        let id = UUID().uuidString
        let payload: [String: Any] = [
            "id": id,
            "userId": userId,
            "text": text,
            "createdAt": FieldValue.serverTimestamp()
        ]
        try await db
            .collection("contentObjects")
            .document(contentObjectId)
            .collection("testimonies")
            .document(id)
            .setData(payload)
        dlog("[SongCommunityService] Testimony added for \(contentObjectId) by \(userId)")
    }
}

// MARK: - SongCommunityCardView

/// Compact card for a song ContentObject displayed inside a community surface.
struct SongCommunityCardView: View {

    let contentObject: ContentObject
    let metadata: SongCommunityMetadata?
    /// Tapped when the user requests the "Listen Together" Prayer Jam experience.
    var onListenTogether: (() -> Void)?

    @State private var worshipModeManager = WorshipModeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top row: genre badge + purity rating
            HStack(spacing: 8) {
                if let genre = metadata?.genre {
                    GenreBadgeView(genre: genre)
                }
                Spacer()
                PurityBadgeView(rating: contentObject.purityRating)
            }

            // Artist + title
            VStack(alignment: .leading, spacing: 2) {
                Text(contentObject.title)
                    .font(.headline)
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)

                if let artist = metadata?.artist {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryLabel))
                        .lineLimit(1)
                }
            }

            // Worship theme tag
            if let theme = metadata?.worshipTheme {
                HStack(spacing: 4) {
                    Image(systemName: "music.note")
                        .font(.caption2)
                        .foregroundStyle(Color(.secondaryLabel))
                    Text(theme)
                        .font(.caption)
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }

            // Community stats
            CommunityStatsRowView(
                discussionCount: contentObject.discussionCount,
                prayerCount: contentObject.prayerCount,
                testimonyCount: contentObject.testimonyCount
            )

            // "Listen Together" — gated on .prayerJam flag
            if CommunityOSFlagService.shared.isEnabled(.prayerJam) {
                Button {
                    onListenTogether?()
                } label: {
                    Label("Listen Together", systemImage: "headphones.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(.white.opacity(0.12)).interactive(), in: Capsule())
                .accessibilityHint("Start a Prayer Jam listening session with others")
                .animation(AppAnimation.stateChange, value: worshipModeManager.state)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Supporting subviews (private to this file)

private struct GenreBadgeView: View {
    let genre: String

    var body: some View {
        Text(genre)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color(.label))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(.secondaryLabel).opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct CommunityStatsRowView: View {
    let discussionCount: Int
    let prayerCount: Int
    let testimonyCount: Int

    var body: some View {
        HStack(spacing: 14) {
            StatPillView(icon: "bubble.left.fill", count: discussionCount)
            StatPillView(icon: "hands.sparkles.fill", count: prayerCount)
            StatPillView(icon: "star.bubble.fill", count: testimonyCount)
        }
        .foregroundStyle(Color(.secondaryLabel))
    }
}

private struct StatPillView: View {
    let icon: String
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
            Text("\(count)")
                .font(.caption2)
        }
    }
}
