// PodcastCommunityModule.swift
// AMEN App — Community Around Content OS
//
// Services and views for podcast episode ContentObjects as community hubs.
// Depends on CommunityOSContracts.swift — do NOT redefine types from that file.

import Foundation
import SwiftUI
import FirebaseFirestore

// MARK: - PodcastEpisodeMetadata

struct PodcastEpisodeMetadata: Codable, Equatable {
    var showTitle: String
    var episodeNumber: Int?
    var season: Int?
    var durationSeconds: Int
    var hostNames: [String]
    var topics: [String]
    var keyTakeaways: [String]
}

// MARK: - EpisodeNote

struct EpisodeNote: Identifiable, Codable {
    var id: String
    var userId: String
    var contentObjectId: String
    var text: String
    /// Playhead position in the episode when the note was captured.
    var timestampSeconds: Int?
    var createdAt: Date
}

// MARK: - PodcastCommunityService

actor PodcastCommunityService {

    private let db = Firestore.firestore()

    // MARK: Episode Notes

    /// Fetches all notes for an episode, ordered newest first.
    func fetchEpisodeNotes(contentObjectId: String) async throws -> [EpisodeNote] {
        let snaps = try await db
            .collection("contentObjects")
            .document(contentObjectId)
            .collection("episodeNotes")
            .order(by: "createdAt", descending: true)
            .getDocuments()

        let decoder = Firestore.Decoder()
        return try snaps.documents.compactMap { doc in
            var data = doc.data()
            data["id"] = doc.documentID
            return try? decoder.decode(EpisodeNote.self, from: data)
        }
    }

    /// Saves a note to `contentObjects/{id}/episodeNotes/{noteId}`.
    func addEpisodeNote(_ note: EpisodeNote) async throws {
        let encoder = Firestore.Encoder()
        let data = try encoder.encode(note)
        try await db
            .collection("contentObjects")
            .document(note.contentObjectId)
            .collection("episodeNotes")
            .document(note.id)
            .setData(data)
        dlog("[PodcastCommunityService] Note \(note.id) saved for episode \(note.contentObjectId)")
    }

    // MARK: Discussion Questions

    /// Fetches AI-generated discussion questions for an episode.
    func fetchDiscussionQuestions(contentObjectId: String) async throws -> [String] {
        let snap = try await db
            .collection("contentObjects")
            .document(contentObjectId)
            .collection("generatedQuestions")
            .getDocuments()

        return snap.documents.compactMap { $0.data()["question"] as? String }
    }
}

// MARK: - PodcastCommunityHubView

struct PodcastCommunityHubView: View {

    let contentObject: ContentObject

    @State private var selectedTab: PodcastHubTab = .notes
    @State private var notes: [EpisodeNote] = []
    @State private var questions: [String] = []
    @State private var episodeMetadata: PodcastEpisodeMetadata?
    @State private var isLoading = false
    @State private var newNoteText: String = ""
    @State private var isAddingNote = false

    private let service = PodcastCommunityService()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            podcastHeader

            // Tab pill bar
            tabBar
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            // Content
            Group {
                switch selectedTab {
                case .notes:
                    notesTab
                case .questions:
                    questionsTab
                case .prayers:
                    prayersTab
                case .study:
                    studyTab
                }
            }
            .animation(AppAnimation.stateChange, value: selectedTab)
        }
        .background(Color(.systemBackground))
        .task { await loadContent() }
    }

    // MARK: Header

    private var podcastHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let meta = episodeMetadata {
                Text(meta.showTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(.secondaryLabel))

                if let ep = meta.episodeNumber {
                    Text("Episode \(ep)" + (meta.season.map { " · Season \($0)" } ?? ""))
                        .font(.caption)
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }

            Text(contentObject.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color(.label))
                .lineLimit(2)

            if let meta = episodeMetadata, !meta.hostNames.isEmpty {
                Text("with " + meta.hostNames.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryLabel))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: Tab Bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PodcastHubTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(AppAnimation.stateChange) {
                            selectedTab = tab
                        }
                    } label: {
                        Text(tab.displayName)
                            .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab ? Color(.label) : Color(.secondaryLabel))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                    .background(
                        selectedTab == tab
                            ? Color(.label).opacity(0.08)
                            : Color.clear
                    )
                    .clipShape(Capsule())
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                }
            }
        }
    }

    // MARK: Notes Tab

    private var notesTab: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if notes.isEmpty && !isLoading {
                    EmptyStateView(
                        icon: "note.text",
                        title: "No notes yet",
                        subtitle: "Be the first to capture a note from this episode."
                    )
                    .padding(.top, 40)
                } else {
                    ForEach(notes) { note in
                        EpisodeNoteCardView(note: note)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    // MARK: Questions Tab

    private var questionsTab: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if questions.isEmpty && !isLoading {
                    EmptyStateView(
                        icon: "questionmark.bubble.fill",
                        title: "No questions yet",
                        subtitle: "Discussion questions will appear here once generated."
                    )
                    .padding(.top, 40)
                } else {
                    ForEach(questions.indices, id: \.self) { index in
                        DiscussionQuestionCardView(
                            question: questions[index],
                            onDiscuss: {
                                dlog("[PodcastCommunityHub] Discuss tapped for Q\(index)")
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    // MARK: Prayers Tab

    private var prayersTab: some View {
        ScrollView {
            EmptyStateView(
                icon: "hands.sparkles.fill",
                title: "Prayer is growing",
                subtitle: "Community prayers for this episode will appear here."
            )
            .padding(.top, 40)
            .padding(.horizontal, 16)
        }
    }

    // MARK: Study Tab

    private var studyTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let meta = episodeMetadata, !meta.keyTakeaways.isEmpty {
                    Text("Key Takeaways")
                        .font(.headline)
                        .foregroundStyle(Color(.label))

                    ForEach(meta.keyTakeaways.indices, id: \.self) { i in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(i + 1).")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color(.secondaryLabel))
                            Text(meta.keyTakeaways[i])
                                .font(.subheadline)
                                .foregroundStyle(Color(.label))
                        }
                    }
                } else {
                    EmptyStateView(
                        icon: "text.book.closed.fill",
                        title: "Study material coming",
                        subtitle: "Key takeaways and study notes will appear here."
                    )
                    .padding(.top, 40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    // MARK: Data loading

    private func loadContent() async {
        isLoading = true
        defer { isLoading = false }

        async let fetchedNotes = try? service.fetchEpisodeNotes(contentObjectId: contentObject.id)
        async let fetchedQuestions = try? service.fetchDiscussionQuestions(contentObjectId: contentObject.id)

        let (n, q) = await (fetchedNotes, fetchedQuestions)
        notes = n ?? []
        questions = q ?? []

        dlog("[PodcastCommunityHub] Loaded \(notes.count) notes, \(questions.count) questions for \(contentObject.id)")
    }
}

// MARK: - PodcastHubTab

private enum PodcastHubTab: String, CaseIterable {
    case notes     = "notes"
    case questions = "questions"
    case prayers   = "prayers"
    case study     = "study"

    var displayName: String {
        switch self {
        case .notes:     return "Notes"
        case .questions: return "Questions"
        case .prayers:   return "Prayers"
        case .study:     return "Study"
        }
    }
}

// MARK: - EpisodeNoteCardView

private struct EpisodeNoteCardView: View {
    let note: EpisodeNote

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // User avatar placeholder
            Circle()
                .fill(Color(.secondaryLabel).opacity(0.2))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.caption)
                        .foregroundStyle(Color(.secondaryLabel))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(note.text)
                    .font(.subheadline)
                    .foregroundStyle(Color(.label))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    if let ts = note.timestampSeconds {
                        Text(formattedTimestamp(ts))
                            .font(.caption2)
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                    Text(note.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func formattedTimestamp(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - DiscussionQuestionCardView

private struct DiscussionQuestionCardView: View {
    let question: String
    let onDiscuss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(question)
                .font(.subheadline)
                .foregroundStyle(Color(.label))
                .fixedSize(horizontal: false, vertical: true)

            Button("Discuss", action: onDiscuss)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.label))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .glassEffect(.regular.tint(.white.opacity(0.10)).interactive(), in: Capsule())
                .accessibilityHint("Start a discussion about this question")
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

