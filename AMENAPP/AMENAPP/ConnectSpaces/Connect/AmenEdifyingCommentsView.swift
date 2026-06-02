// AmenEdifyingCommentsView.swift
// AMEN Connect — Discipleship Learning & Knowledge Graph (Agent 7)
//
// Structured, edifying comment section for a Connect video.
// Comments sorted by edificationScore descending (score is PRIVATE, never shown).
// Low-score comments (< 0.3) are collapsed behind a tap, not deleted.
// No likes, no reply counts, no view counts.
//
// Frozen contracts: ConnectSpacesPhase0Contracts.swift — do not edit.
// Callable proxy: AmenConnectSpacesPhase0BindingService.swift

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Color tokens (file-private)

// MARK: - ViewModel

@MainActor
final class AmenEdifyingCommentsViewModel: ObservableObject {
    @Published var comments: [AmenConnectSpacesConnectComment] = []
    @Published var isLoading: Bool = false
    @Published var isPosting: Bool = false
    @Published var errorMessage: String?

    // Composer state
    @Published var composerType: AmenConnectSpacesCommentType = .question
    @Published var composerBody: String = ""

    // Expanded low-score comments (revealed by user tap)
    @Published var revealedLowScoreIds: Set<String> = []

    private let videoId: String
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    init(videoId: String) {
        self.videoId = videoId
    }

    deinit {
        listener?.remove()
    }

    // MARK: Load & listen

    func startListening() {
        isLoading = true
        let ref = db
            .collection(AmenConnectSpacesFirestoreBinding.connectVideosCollection)
            .document(videoId)
            .collection(AmenConnectSpacesFirestoreBinding.commentsSubcollection)

        listener = ref.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
                return
            }
            let docs = snapshot?.documents ?? []
            let parsed: [AmenConnectSpacesConnectComment] = docs.compactMap {
                try? AmenConnectSpacesFirestoreBinding.bindConnectComment($0)
            }
            // Sort by edificationScore descending — score is private, not shown
            self.comments = parsed.sorted { $0.edificationScore > $1.edificationScore }
            self.isLoading = false
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    // MARK: Post comment

    func postComment() async {
        let body = composerBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        guard let userId = Auth.auth().currentUser?.uid else {
            errorMessage = "You must be signed in to comment."
            return
        }

        isPosting = true
        errorMessage = nil

        let commentId = UUID().uuidString
        let type = composerType

        do {
            // 1. Score the comment via CF
            let score = try await AmenConnectSpacesCallableProxy.shared.scoreEdifyingComment(
                videoId: videoId,
                commentId: commentId,
                type: type,
                body: body
            )

            // 2. Write to Firestore
            let comment = AmenConnectSpacesConnectComment(
                id: commentId,
                type: type,
                body: body,
                authorId: userId,
                edificationScore: score,
                createdAt: Date()
            )
            let payload = try AmenConnectSpacesFirestoreBinding.firestorePayload(for: comment)
            try await db
                .collection(AmenConnectSpacesFirestoreBinding.connectVideosCollection)
                .document(videoId)
                .collection(AmenConnectSpacesFirestoreBinding.commentsSubcollection)
                .document(commentId)
                .setData(payload)

            // Reset composer
            composerBody = ""
            composerType = .question
        } catch {
            errorMessage = error.localizedDescription
        }
        isPosting = false
    }

    // MARK: Reveal a low-score comment

    func revealLowScore(_ id: String) {
        revealedLowScoreIds.insert(id)
    }
}

// MARK: - Main view

struct AmenEdifyingCommentsView: View {

    let videoId: String

    @StateObject private var vm: AmenEdifyingCommentsViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(videoId: String) {
        self.videoId = videoId
        _vm = StateObject(wrappedValue: AmenEdifyingCommentsViewModel(videoId: videoId))
    }

    var body: some View {
        VStack(spacing: 0) {
            commentsHeader
            Divider()
            if vm.isLoading {
                loadingView
            } else {
                commentsList
            }
            Divider()
            composerView
        }
        .task {
            vm.startListening()
        }
        .onDisappear {
            vm.stopListening()
        }
    }

    // MARK: - Header (glass chrome)

    private var commentsHeader: some View {
        HStack {
            Image(systemName: "bubble.left.and.bubble.right")
                .foregroundStyle(Color.amenPurple)
            Text("Community Discussion")
                .font(.headline)
                .foregroundStyle(Color.amenBlack)
            Spacer()
            Text("\(vm.comments.count) responses")
                .font(.caption)
                .foregroundStyle(Color.amenBlack.opacity(0.4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color(.systemBackground)
                .glassEffect(in: .rect(cornerRadius: 0))
        )
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading discussion…")
                .font(.subheadline)
                .foregroundStyle(Color.amenBlack.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Comments list

    private var commentsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let error = vm.errorMessage {
                    errorBanner(error)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }

                if vm.comments.isEmpty {
                    emptyState
                } else {
                    ForEach(vm.comments) { comment in
                        commentRow(comment)
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left")
                .font(.largeTitle)
                .foregroundStyle(Color.amenBlue.opacity(0.3))
            Text("Be the first to share a thoughtful response.")
                .font(.subheadline)
                .foregroundStyle(Color.amenBlack.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Comment row

    @ViewBuilder
    private func commentRow(_ comment: AmenConnectSpacesConnectComment) -> some View {
        let isLowScore = comment.edificationScore < 0.3
        let isRevealed = vm.revealedLowScoreIds.contains(comment.id)

        if isLowScore && !isRevealed {
            // Collapsed low-score comment
            Button {
                vm.revealLowScore(comment.id)
            } label: {
                HStack {
                    Image(systemName: "eye.slash")
                        .foregroundStyle(Color.amenBlack.opacity(0.3))
                    Text("Show lower-value comment")
                        .font(.caption)
                        .foregroundStyle(Color.amenBlack.opacity(0.4))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show collapsed comment")
        } else {
            AmenEdifyingCommentRow(comment: comment)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
    }

    // MARK: - Composer

    private var composerView: some View {
        VStack(spacing: 10) {
            // Type picker (glass segmented)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(AmenConnectSpacesCommentType.allCases, id: \.self) { type in
                        commentTypeChip(type, isSelected: vm.composerType == type)
                    }
                }
                .padding(.horizontal, 16)
            }
            .glassEffect(in: .rect(cornerRadius: 12))
            .frame(height: 44)

            // Text field (matte)
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Add a \(vm.composerType.rawValue.lowercased())…", text: $vm.composerBody, axis: .vertical)
                    .lineLimit(4, reservesSpace: false)
                    .font(.subheadline)
                    .foregroundStyle(Color.amenBlack)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(.systemBackground))
                    )
                    .accessibilityLabel("Comment text input")

                Button {
                    Task { await vm.postComment() }
                } label: {
                    if vm.isPosting {
                        ProgressView()
                            .frame(width: 36, height: 36)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(
                                vm.composerBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? Color.amenPurple.opacity(0.35)
                                    : Color.amenPurple
                            )
                    }
                }
                .buttonStyle(.plain)
                .disabled(vm.isPosting || vm.composerBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Post comment")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .padding(.top, 10)
        .background(Color(.systemBackground))
    }

    private func commentTypeChip(_ type: AmenConnectSpacesCommentType, isSelected: Bool) -> some View {
        let badge = AmenCommentTypeBadgeInfo.info(for: type)
        return Button {
            vm.composerType = type
        } label: {
            HStack(spacing: 4) {
                Text(badge.icon)
                    .font(.caption)
                Text(badge.label)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? badge.tint : Color.amenBlack.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? badge.tint.opacity(0.15) : Color.clear)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isSelected ? badge.tint.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.amenBlack)
            Spacer()
            Button {
                vm.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(Color.amenBlack.opacity(0.4))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.1))
        )
    }
}

// MARK: - Comment row component

struct AmenEdifyingCommentRow: View {
    let comment: AmenConnectSpacesConnectComment

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Author avatar (stub)
            Circle()
                .fill(Color.amenBlue.opacity(0.2))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "person.fill")
                        .foregroundStyle(Color.amenBlue.opacity(0.6))
                        .font(.callout)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    // Type badge (glass pill)
                    AmenCommentTypeBadgeView(type: comment.type)
                    // Author stub — no user data exposed
                    Text("A member")
                        .font(.caption)
                        .foregroundStyle(Color.amenBlack.opacity(0.45))
                    Spacer()
                    Text(comment.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(Color.amenBlack.opacity(0.3))
                }

                // Body — matte, never glass
                Text(comment.body)
                    .font(.subheadline)
                    .foregroundStyle(Color.amenBlack)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(AmenCommentTypeBadgeInfo.info(for: comment.type).label) from a member: \(comment.body)")
    }
}

// MARK: - Type badge view

struct AmenCommentTypeBadgeView: View {
    let type: AmenConnectSpacesCommentType

    var body: some View {
        let info = AmenCommentTypeBadgeInfo.info(for: type)
        HStack(spacing: 3) {
            Text(info.icon)
                .font(.caption2)
            Text(info.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(info.tint)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(info.tint.opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(info.tint.opacity(0.3), lineWidth: 0.5)
        )
        .glassEffect(in: .capsule)
        .accessibilityLabel(info.label)
    }
}

// MARK: - Badge info helper

struct AmenCommentTypeBadgeInfo {
    let icon: String
    let label: String
    let tint: Color

    static func info(for type: AmenConnectSpacesCommentType) -> AmenCommentTypeBadgeInfo {
        switch type {
        case .question:
            return AmenCommentTypeBadgeInfo(icon: "❓", label: "Question", tint: .amenBlue)
        case .correction:
            return AmenCommentTypeBadgeInfo(icon: "🔵", label: "Respectful Correction", tint: .amenBlue)
        case .experience:
            return AmenCommentTypeBadgeInfo(icon: "✨", label: "Lived Experience", tint: .amenGold)
        case .citation:
            return AmenCommentTypeBadgeInfo(icon: "📖", label: "Citation", tint: .amenPurple)
        case .encouragement:
            return AmenCommentTypeBadgeInfo(icon: "💛", label: "Encouragement", tint: .amenGold)
        case .respectfulDisagree:
            return AmenCommentTypeBadgeInfo(icon: "🤝", label: "Respectful Disagreement", tint: .amenPurple)
        }
    }
}
