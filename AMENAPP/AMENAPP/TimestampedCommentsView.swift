// TimestampedCommentsView.swift
// AMENAPP
//
// Displays comments anchored to specific playback timestamps for a video post.
// Only comments within ±5 s of the current playback position are surfaced.
// Gated by `mediaTimestampedCommentsEnabled`.

import SwiftUI
import FirebaseFirestore
import FirebaseFunctions

// MARK: - Model

struct TimestampedComment: Identifiable {
    let id: String
    let authorId: String
    let authorDisplayName: String
    let timestampSeconds: Double
    let text: String
    let createdAt: Date
}

// MARK: - View

struct TimestampedCommentsView: View {

    let postId: String
    let currentPlaybackTime: Double   // seconds

    @State private var comments: [TimestampedComment] = []
    @State private var isLoading = false
    @State private var newCommentText = ""
    @State private var isSubmitting = false
    @State private var listenerRegistration: ListenerRegistration?

    @ObservedObject private var flags = AMENFeatureFlags.shared

    private let windowSeconds: Double = 5.0

    // MARK: - Filtered Comments

    private var visibleComments: [TimestampedComment] {
        comments.filter {
            abs($0.timestampSeconds - currentPlaybackTime) <= windowSeconds
        }
    }

    // MARK: - Body

    var body: some View {
        if !flags.mediaTimestampedCommentsEnabled {
            EmptyView()
        } else {
            commentPanel
                .onAppear { startListening() }
                .onDisappear { stopListening() }
        }
    }

    private var commentPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Comments at \(formattedTime(currentPlaybackTime))", systemImage: "bubble.left.and.bubble.right")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // Comment list
            if visibleComments.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "bubble.left")
                        .font(.title3)
                        .foregroundStyle(.quaternary)
                    Text("No comments at this moment")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleComments) { comment in
                            commentRow(comment)
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }

            Divider()

            // Input bar
            inputBar
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Comment Row

    private func commentRow(_ comment: TimestampedComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Timestamp chip
            Text(formattedTime(comment.timestampSeconds))
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.blue.opacity(0.8))
                .clipShape(Capsule())
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(comment.authorDisplayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text(comment.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Comment at \(formattedTime(currentPlaybackTime))…", text: $newCommentText)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .submitLabel(.send)
                .onSubmit { submitComment() }

            Button(action: submitComment) {
                if isSubmitting {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(newCommentText.trimmingCharacters(in: .whitespaces).isEmpty ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color.blue))
                }
            }
            .disabled(newCommentText.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Firestore Listener

    private func startListening() {
        guard flags.mediaTimestampedCommentsEnabled else { return }
        isLoading = true
        dlog("[TimestampedCommentsView] Starting listener for postId: \(postId)")

        let db = Firestore.firestore()
        let ref = db
            .collection("posts")
            .document(postId)
            .collection("timestampedComments")
            .order(by: "timestampSeconds")

        listenerRegistration = ref.addSnapshotListener { snapshot, error in
            isLoading = false
            if let error {
                dlog("[TimestampedCommentsView] Listener error: \(error.localizedDescription)")
                return
            }
            comments = snapshot?.documents.compactMap { doc -> TimestampedComment? in
                let data = doc.data()
                guard
                    let authorId = data["authorId"] as? String,
                    let authorDisplayName = data["authorDisplayName"] as? String,
                    let timestampSeconds = data["timestampSeconds"] as? Double,
                    let text = data["text"] as? String
                else { return nil }

                let createdAt: Date
                if let ts = data["createdAt"] as? Timestamp {
                    createdAt = ts.dateValue()
                } else {
                    createdAt = Date()
                }

                return TimestampedComment(
                    id: doc.documentID,
                    authorId: authorId,
                    authorDisplayName: authorDisplayName,
                    timestampSeconds: timestampSeconds,
                    text: text,
                    createdAt: createdAt
                )
            } ?? []
            dlog("[TimestampedCommentsView] Loaded \(comments.count) comments")
        }
    }

    private func stopListening() {
        listenerRegistration?.remove()
        listenerRegistration = nil
        dlog("[TimestampedCommentsView] Listener removed for postId: \(postId)")
    }

    // MARK: - Submit

    private func submitComment() {
        let text = newCommentText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isSubmitting else { return }

        isSubmitting = true
        newCommentText = ""
        dlog("[TimestampedCommentsView] Submitting comment at \(currentPlaybackTime)s")

        Task {
            do {
                try await Functions.functions()
                    .httpsCallable("addTimestampedComment")
                    .call([
                        "postId": postId,
                        "timestamp": currentPlaybackTime,
                        "text": text
                    ])
                dlog("[TimestampedCommentsView] Comment submitted successfully")
            } catch {
                dlog("[TimestampedCommentsView] Submit error: \(error.localizedDescription)")
            }
            isSubmitting = false
        }
    }

    // MARK: - Formatting

    private func formattedTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
