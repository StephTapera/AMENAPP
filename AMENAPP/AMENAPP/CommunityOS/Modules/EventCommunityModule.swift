// EventCommunityModule.swift
// AMEN App — Community Around Content OS
//
// Models, services, and views for event-type ContentObjects.
// Depends on CommunityOSContracts.swift — do NOT redefine types from that file.
// NOTE: Named AmenEventCommunityMetadata (not EventCommunityMetadata) to avoid
// collisions with other Event types in the codebase.

import Foundation
import SwiftUI
import FirebaseFirestore

// MARK: - AmenEventCommunityMetadata

struct AmenEventCommunityMetadata: Codable, Equatable {
    var eventDate: Date?
    var location: String?
    var churchName: String?
    var attendeeCount: Int
    var registrationURL: String?
}

// MARK: - EventCommunityService

actor EventCommunityService {

    private let db = Firestore.firestore()

    // MARK: Community Node

    /// Fetches the CommunityNode for an event ContentObject.
    func fetchEventCommunity(contentObjectId: String) async throws -> CommunityNode? {
        let snaps = try await db
            .collection("communityNodes")
            .whereField("contentObjectId", isEqualTo: contentObjectId)
            .limit(to: 1)
            .getDocuments()
        guard let doc = snaps.documents.first else { return nil }
        let decoder = Firestore.Decoder()
        return try? decoder.decode(CommunityNode.self, from: doc.data())
    }

    // MARK: Interest Registration

    /// Records a user's interest in attending an event.
    func registerInterest(contentObjectId: String, userId: String) async throws {
        let payload: [String: Any] = [
            "userId": userId,
            "registeredAt": FieldValue.serverTimestamp()
        ]
        try await db
            .collection("contentObjects")
            .document(contentObjectId)
            .collection("interestedUsers")
            .document(userId)
            .setData(payload)
        dlog("[EventCommunityService] User \(userId) registered interest for \(contentObjectId)")
    }

    // MARK: Photos

    /// Returns photo URLs from `contentObjects/{id}/photos`.
    func fetchPhotos(contentObjectId: String) async throws -> [String] {
        let snaps = try await db
            .collection("contentObjects")
            .document(contentObjectId)
            .collection("photos")
            .order(by: "uploadedAt", descending: true)
            .getDocuments()
        return snaps.documents.compactMap { $0.data()["url"] as? String }
    }

    // MARK: Follow-Up Posts

    /// Posts a follow-up message to an event community.
    func postFollowUp(contentObjectId: String, userId: String, text: String) async throws {
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
            .collection("followUpPosts")
            .document(id)
            .setData(payload)
        dlog("[EventCommunityService] Follow-up posted by \(userId) for event \(contentObjectId)")
    }
}

// MARK: - EventCommunityHubView

struct EventCommunityHubView: View {

    let contentObject: ContentObject

    @State private var community: CommunityNode?
    @State private var photoURLs: [String] = []
    @State private var followUpPosts: [EventFollowUpPost] = []
    @State private var isInterested: Bool = false
    @State private var attendeeCount: Int = 0
    @State private var followUpText: String = ""
    @State private var isSubmittingFollowUp = false
    @State private var isLoading = false

    private let service = EventCommunityService()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                // Event Details
                eventDetailsSection

                // Photos
                if !photoURLs.isEmpty {
                    photosSection
                }

                // Follow-Up Discussions
                followUpSection

                // Prayer
                prayerSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(Color(.systemBackground))
        .task { await loadContent() }
    }

    // MARK: Event Details Section

    private var eventDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Event Details")
                .font(.headline)
                .foregroundStyle(Color(.label))

            Text(contentObject.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color(.label))

            if let subtitle = contentObject.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryLabel))
            }

            // Attendee count — displayed without vanity framing
            HStack(spacing: 4) {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(Color(.secondaryLabel))
                Text("\(attendeeCount) interested")
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryLabel))
            }

            // Interest toggle — Liquid Glass on the active state only
            interestButton
        }
    }

    // MARK: Interest Button

    private var interestButton: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(AppAnimation.stateChange) {
                    toggleInterest()
                }
            } label: {
                Label(
                    isInterested ? "Going" : "I'm Interested",
                    systemImage: isInterested ? "checkmark.circle.fill" : "plus.circle"
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(.label))
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            .modifier(InterestButtonModifier(isActive: isInterested))
            .accessibilityLabel(isInterested ? "Going — tap to remove interest" : "I'm Interested — tap to register")
        }
    }

    // MARK: Photos Section

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Photos")
                .font(.headline)
                .foregroundStyle(Color(.label))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(photoURLs.indices, id: \.self) { index in
                        AsyncImage(url: URL(string: photoURLs[index])) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                Color(.secondarySystemBackground)
                                    .overlay(
                                        Image(systemName: "photo")
                                            .foregroundStyle(Color(.tertiaryLabel))
                                    )
                            case .empty:
                                Color(.secondarySystemBackground)
                            @unknown default:
                                Color(.secondarySystemBackground)
                            }
                        }
                        .frame(width: 140, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityLabel("Event photo \(index + 1)")
                    }
                }
            }
        }
    }

    // MARK: Follow-Up Discussions Section

    private var followUpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Follow-Up Discussions")
                .font(.headline)
                .foregroundStyle(Color(.label))

            // Compose area
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Share a follow-up thought…", text: $followUpText, axis: .vertical)
                    .font(.subheadline)
                    .foregroundStyle(Color(.label))
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .lineLimit(1...4)
                    .accessibilityLabel("Follow-up message")

                Button {
                    Task { await submitFollowUp() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(
                            followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color(.tertiaryLabel)
                                : Color(.label)
                        )
                }
                .buttonStyle(.plain)
                .disabled(
                    followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || isSubmittingFollowUp
                )
                .accessibilityLabel("Post follow-up")
            }

            // Existing posts
            if followUpPosts.isEmpty {
                Text("No follow-up posts yet. Be the first!")
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryLabel))
                    .padding(.top, 4)
            } else {
                ForEach(followUpPosts) { post in
                    EventFollowUpPostCardView(post: post)
                }
            }
        }
    }

    // MARK: Prayer Section

    private var prayerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prayer")
                .font(.headline)
                .foregroundStyle(Color(.label))
            Text("Pray for the impact of this event and those who attended.")
                .font(.subheadline)
                .foregroundStyle(Color(.secondaryLabel))

            HStack(spacing: 4) {
                Image(systemName: "hands.sparkles.fill")
                    .foregroundStyle(Color(.secondaryLabel))
                Text("\(contentObject.prayerCount) prayers")
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryLabel))
            }
        }
    }

    // MARK: Actions

    private func toggleInterest() {
        isInterested.toggle()
        attendeeCount += isInterested ? 1 : -1
        Task {
            try? await service.registerInterest(
                contentObjectId: contentObject.id,
                userId: "currentUser"   // Replaced by authenticated user ID at call site.
            )
        }
    }

    private func submitFollowUp() async {
        let trimmed = followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSubmittingFollowUp = true
        defer { isSubmittingFollowUp = false }

        do {
            try await service.postFollowUp(
                contentObjectId: contentObject.id,
                userId: "currentUser",   // Replaced by authenticated user ID at call site.
                text: trimmed
            )
            let newPost = EventFollowUpPost(
                id: UUID().uuidString,
                userId: "currentUser",
                text: trimmed,
                createdAt: Date()
            )
            withAnimation(AppAnimation.stateChange) {
                followUpPosts.insert(newPost, at: 0)
                followUpText = ""
            }
        } catch {
            dlog("[EventCommunityHub] Follow-up post failed: \(error)")
        }
    }

    // MARK: Data loading

    private func loadContent() async {
        isLoading = true
        defer { isLoading = false }

        async let fetchedCommunity = try? service.fetchEventCommunity(contentObjectId: contentObject.id)
        async let fetchedPhotos = try? service.fetchPhotos(contentObjectId: contentObject.id)

        let (comm, photos) = await (fetchedCommunity, fetchedPhotos)
        community = comm
        photoURLs = photos ?? []
        attendeeCount = comm?.memberCount ?? 0

        dlog("[EventCommunityHub] Loaded for \(contentObject.id): community=\(community != nil), photos=\(photoURLs.count)")
    }
}

// MARK: - InterestButtonModifier

/// Applies Liquid Glass styling only when the button is in the active (interested) state.
private struct InterestButtonModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            content
                .background(Color(.label).opacity(0.06))
                .glassEffect(.regular.tint(.white.opacity(0.12)).interactive(), in: Capsule())
        } else {
            content
                .background(Color(.secondarySystemBackground))
                .clipShape(Capsule())
        }
    }
}

// MARK: - EventFollowUpPost (local model)

private struct EventFollowUpPost: Identifiable {
    var id: String
    var userId: String
    var text: String
    var createdAt: Date
}

// MARK: - EventFollowUpPostCardView

private struct EventFollowUpPostCardView: View {
    let post: EventFollowUpPost

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color(.secondaryLabel).opacity(0.2))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.caption)
                        .foregroundStyle(Color(.secondaryLabel))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(post.text)
                    .font(.subheadline)
                    .foregroundStyle(Color(.label))
                    .fixedSize(horizontal: false, vertical: true)
                Text(post.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
