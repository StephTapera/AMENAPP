// CommunityModule.swift
// AMEN — Creator Profiles (ministry hubs) — Wave 3 UI
//
// Moderated community space. Segmented control: Questions / Testimonies / Study Notes /
// Event Discussion (CreatorHubCommunityKind). Shows ONLY approved posts. Threaded replies
// (parentRef) are rendered one level deep beneath their parent.
//
// HONESTY: composing a post submits via CreatorHubService.submitCommunity and shows an explicit
// "Pending review" confirmation. The just-submitted post is NOT injected into the approved list.
//
// Exact initializer (mandated): CommunityModule(creatorId: String, posts: [CreatorHubCommunityPost]).
//
// Conventions: white bg / black text; translucent glass post cards on plain background (no
// glass-on-glass); AmenTheme.Colors.* tokens; Dynamic Type; VoiceOver labels; reduce-motion safe.

import SwiftUI

struct CommunityModule: View {
    let creatorId: String

    @State private var posts: [CreatorHubCommunityPost]
    @State private var selectedKind: CreatorHubCommunityKind = .question
    @State private var showingComposer = false

    init(creatorId: String, posts: [CreatorHubCommunityPost]) {
        self.creatorId = creatorId
        _posts = State(initialValue: posts)
    }

    // Approved, top-level posts of the selected kind.
    private var topLevel: [CreatorHubCommunityPost] {
        posts.filter { $0.status == .approved && $0.kind == selectedKind && $0.parentRef == nil }
    }

    private func replies(of parentId: String) -> [CreatorHubCommunityPost] {
        posts.filter { $0.status == .approved && $0.parentRef == parentId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            segmentedControl

            if topLevel.isEmpty {
                emptyState
            } else {
                ForEach(topLevel) { post in
                    postCard(post)
                }
            }

            Text("That's everything for now.")
                .font(.footnote)
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showingComposer) {
            CommunityComposer(creatorId: creatorId, kind: selectedKind)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Community")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                showingComposer = true
            } label: {
                Label("New post", systemImage: "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AmenTheme.Colors.buttonPrimaryText)
            .background(Capsule().fill(AmenTheme.Colors.buttonPrimary))
            .accessibilityLabel("New community post")
            .accessibilityHint("Opens a form. Posts are reviewed before they appear.")
        }
    }

    // MARK: Segmented control

    private var segmentedControl: some View {
        Picker("Community section", selection: $selectedKind) {
            Text("Questions").tag(CreatorHubCommunityKind.question)
            Text("Testimonies").tag(CreatorHubCommunityKind.testimony)
            Text("Study Notes").tag(CreatorHubCommunityKind.studyNote)
            Text("Event Discussion").tag(CreatorHubCommunityKind.eventDiscussion)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Community section")
    }

    // MARK: Post card + one level of replies

    private func postCard(_ post: CreatorHubCommunityPost) -> some View {
        let childReplies = replies(of: post.id)
        return VStack(alignment: .leading, spacing: 10) {
            Text(post.body)
                .font(.body)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if !childReplies.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(childReplies) { reply in
                        HStack(alignment: .top, spacing: 8) {
                            Rectangle()
                                .fill(AmenTheme.Colors.separatorSubtle)
                                .frame(width: 2)
                                .accessibilityHidden(true)
                            Text(reply.body)
                                .font(.callout)
                                .foregroundStyle(AmenTheme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel("Reply. \(reply.body)")
                        }
                    }
                }
                .padding(.leading, 6)
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .amenGlassCard(cornerRadius: 18)
        .accessibilityElement(children: .contain)
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.largeTitle)
                .foregroundStyle(AmenTheme.Colors.iconSecondary)
            Text("Nothing here yet")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Nothing here yet")
    }
}

// MARK: - Community composer (pending-honest)

struct CommunityComposer: View {
    let creatorId: String
    let kind: CreatorHubCommunityKind

    @Environment(\.dismiss) private var dismiss

    @State private var body_: String = ""
    @State private var phase: Phase = .editing
    @State private var errorMessage: String?

    private enum Phase: Equatable { case editing, submitting, submitted }

    private var trimmed: String {
        body_.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .editing, .submitting: editor
                case .submitted:            pending
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AmenTheme.Colors.backgroundPrimary)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(phase == .submitted ? "Done" : "Cancel") { dismiss() }
                }
            }
        }
    }

    private var title: String {
        switch kind {
        case .question:        return "Ask a question"
        case .testimony:       return "Share a testimony"
        case .studyNote:       return "Share a study note"
        case .eventDiscussion: return "Join the discussion"
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextEditor(text: $body_)
                .font(.body)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 140)
                .padding(10)
                .amenGlassInputBar(cornerRadius: 16)
                .accessibilityLabel("Your message")

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(AmenTheme.Colors.statusError)
            }

            Label("Posts are reviewed before they appear publicly.",
                  systemImage: "checkmark.shield")
                .font(.caption)
                .foregroundStyle(AmenTheme.Colors.textSecondary)

            Spacer(minLength: 0)

            Button {
                Task { await submit() }
            } label: {
                HStack {
                    Spacer()
                    if phase == .submitting {
                        ProgressView().tint(AmenTheme.Colors.buttonPrimaryText)
                    } else {
                        Text("Submit for review").font(.headline)
                    }
                    Spacer()
                }
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AmenTheme.Colors.buttonPrimaryText)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AmenTheme.Colors.buttonPrimary.opacity(trimmed.isEmpty ? 0.4 : 1))
            )
            .disabled(trimmed.isEmpty || phase == .submitting)
            .accessibilityLabel("Submit for review")
        }
    }

    private var pending: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 48))
                .foregroundStyle(AmenTheme.Colors.statusSuccess)
            Text("Pending review — not yet public")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
            Text("Thanks for sharing. It will appear once it's been reviewed and approved.")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AmenTheme.Colors.buttonPrimaryText)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AmenTheme.Colors.buttonPrimary)
            )
            .padding(.top, 8)
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pending review. Not yet public.")
    }

    private func submit() async {
        guard !trimmed.isEmpty else { return }
        phase = .submitting
        errorMessage = nil
        do {
            try await CreatorHubService.shared.submitCommunity(
                creatorId: creatorId, kind: kind, body: trimmed
            )
            phase = .submitted
        } catch {
            phase = .editing
            errorMessage = "Couldn't submit. Please try again."
        }
    }
}

#if DEBUG
#Preview("CommunityModule") {
    ScrollView {
        CommunityModule(creatorId: "demo", posts: [
            CreatorHubCommunityPost(id: "1", creatorId: "demo", authorId: "u1",
                                    kind: .question, body: "How do I start reading the Bible?",
                                    parentRef: nil, status: .approved),
            CreatorHubCommunityPost(id: "2", creatorId: "demo", authorId: "u2",
                                    kind: .question, body: "Start with the Gospel of John.",
                                    parentRef: "1", status: .approved)
        ])
    }
    .background(AmenTheme.Colors.backgroundPrimary)
}
#endif
