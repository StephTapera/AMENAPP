// VoicePrayerCommentsSection.swift
// AMEN App — Voice Prayer & Testimony Comments
//
// Firestore-backed section inserted into CommentsView.
// Shows published voice comments for a post.
// Invisible when feature flags are off — no UI leak.

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct VoicePrayerCommentsSection: View {
    let post: Post
    let currentUserId: String

    @StateObject private var viewModel: VoicePrayerCommentsSectionViewModel
    @State private var showRecorderFor: VoiceCommentType?
    @State private var showSafetyGate = false
    @State private var pendingType: VoiceCommentType?

    private let flags = AMENFeatureFlags.shared

    init(post: Post, currentUserId: String) {
        self.post = post
        self.currentUserId = currentUserId
        _viewModel = StateObject(wrappedValue: VoicePrayerCommentsSectionViewModel(postId: post.firestoreId))
    }

    // Which voice comment types are available for this post category
    private var availableTypes: [VoiceCommentType] {
        var types: [VoiceCommentType] = []
        if flags.voicePrayerCommentsEnabled && post.category == .prayer {
            types.append(.prayer)
        }
        if flags.voiceTestimonyCommentsEnabled && post.category == .testimonies {
            types.append(.testimony)
        }
        return types
    }

    var body: some View {
        // Do not render at all if both flags are off
        if availableTypes.isEmpty && viewModel.voiceComments.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // Section header
                if !viewModel.voiceComments.isEmpty {
                    sectionHeader
                }

                // Voice entry buttons — only shown when enabled by flag
                if !availableTypes.isEmpty {
                    entryCluster
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }

                // Comment list
                if viewModel.isLoading {
                    skeletonRows
                } else if !viewModel.voiceComments.isEmpty {
                    commentList
                }
            }
            .task { await viewModel.startListening() }
            .onDisappear { viewModel.stopListening() }
            .sheet(isPresented: $showSafetyGate) {
                if let types = availableTypesForGate {
                    VoicePrayerSafetyGateView(
                        availableTypes: types,
                        onSelect: { type in
                            pendingType = nil
                            showRecorderFor = type
                            AMENAnalyticsService.shared.track(.voiceCommentRecordStarted(postId: post.firestoreId, type: type.rawValue))
                        },
                        onUseTextInstead: { }
                    )
                }
            }
            .sheet(item: $showRecorderFor) { type in
                VoicePrayerRecorderView(
                    commentType: type,
                    postId: post.firestoreId,
                    onPublished: { comment in
                        viewModel.insertOptimistic(comment)
                        AMENAnalyticsService.shared.track(.voiceCommentProcessingStarted(postId: post.firestoreId))
                    }
                )
            }
        }
    }

    // MARK: - Section header

    private var sectionHeader: some View {
        HStack {
            Image(systemName: "waveform")
                .font(.systemScaled(12, weight: .medium))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
            Text("Voice Prayers & Testimonies")
                .font(.systemScaled(12, weight: .semibold))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .textCase(nil)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Entry cluster

    private var entryCluster: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(availableTypes, id: \.self) { type in
                    voiceEntryButton(type: type)
                }
            }
        }
    }

    @ViewBuilder
    private func voiceEntryButton(type: VoiceCommentType) -> some View {
        Button {
            AMENAnalyticsService.shared.track(.voiceCommentEntryTapped(postId: post.firestoreId, type: type.rawValue))
            HapticManager.impact(style: .light)
            pendingType = type
            showSafetyGate = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: type.systemIcon)
                    .font(.systemScaled(14, weight: .semibold))
                Text(type.recordButtonLabel)
                    .font(.systemScaled(14, weight: .semibold))
            }
            .foregroundStyle(Color(uiColor: .label))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color(uiColor: .separator).opacity(0.4), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(type.recordButtonLabel)
    }

    // MARK: - Skeleton

    private var skeletonRows: some View {
        VStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .frame(height: 72)
                    .padding(.horizontal, 16)

            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Comment list

    private var commentList: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.voiceComments) { comment in
                VoicePrayerCommentRowView(
                    comment: comment,
                    currentUserId: currentUserId,
                    onReact: { reaction in
                        Task { await viewModel.react(to: comment, reaction: reaction) }
                    },
                    onReport: {
                        AMENAnalyticsService.shared.track(.voiceCommentReported(postId: post.firestoreId))
                    },
                    onDelete: comment.authorUid == currentUserId ? {
                        Task { await viewModel.delete(comment: comment) }
                    } : nil,
                    onSaveToPrayerList: {
                        // Route to existing prayer list save
                    }
                )
                .padding(.horizontal, 16)

                if comment.id != viewModel.voiceComments.last?.id {
                    Divider().padding(.horizontal, 16)
                }
            }
        }
    }

    private var availableTypesForGate: [VoiceCommentType]? {
        let types = availableTypes
        return types.isEmpty ? nil : types
    }
}

// MARK: - VoicePrayerCommentsSectionViewModel

@MainActor
final class VoicePrayerCommentsSectionViewModel: ObservableObject {
    @Published private(set) var voiceComments: [VoiceComment] = []
    @Published private(set) var isLoading = true

    private let postId: String
    private var listener: ListenerRegistration?
    private let db = Firestore.firestore()

    init(postId: String) {
        self.postId = postId
    }

    func startListening() async {
        let ref = db
            .collection("posts").document(postId)
            .collection("voiceComments")
            .whereField("status", isEqualTo: VoiceCommentStatus.published.rawValue)
            .order(by: "createdAt", descending: false)
            .limit(to: 50)

        listener = ref.addSnapshotListener { [weak self] snapshot, _ in
            guard let self, let docs = snapshot?.documents else { return }
            let decoder = Firestore.Decoder()
            self.voiceComments = docs.compactMap { doc in
                var data = doc.data()
                data["id"] = doc.documentID
                return try? decoder.decode(VoiceComment.self, from: data)
            }
            self.isLoading = false
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    func insertOptimistic(_ comment: VoiceComment) {
        // Show processing comment immediately; Firestore listener will replace it
        if !voiceComments.contains(where: { $0.id == comment.id }) {
            voiceComments.append(comment)
        }
    }

    func react(to comment: VoiceComment, reaction: VoiceCommentReaction) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try? await VoicePrayerUploadService.react(
            voiceCommentId: comment.id,
            postId: postId,
            reaction: reaction.rawValue,
            userId: uid
        )
    }

    func delete(comment: VoiceComment) async {
        guard let uid = Auth.auth().currentUser?.uid, uid == comment.authorUid else { return }
        do {
            try await VoicePrayerUploadService.delete(voiceCommentId: comment.id, postId: postId)
            voiceComments.removeAll { $0.id == comment.id }
            AMENAnalyticsService.shared.track(.voiceCommentDeleted(postId: postId))
        } catch {
            dlog("⚠️ VoiceComment delete failed: \(error)")
        }
    }
}

// MARK: - Sheet item support

extension VoiceCommentType: Identifiable {
    public var id: String { rawValue }
}
