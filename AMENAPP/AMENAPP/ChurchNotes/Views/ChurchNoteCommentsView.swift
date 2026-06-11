import SwiftUI

struct ChurchNoteCommentsView: View {
    let noteId: String
    let currentRole: ChurchNoteCollaboratorRole
    let defaultAnchorText: String
    @ObservedObject var service: ChurchNotesCommentsService
    @Environment(\.dismiss) private var dismiss

    @State private var commentBody = ""
    @State private var replyBodies: [String: String] = [:]
    @State private var actionStatusMessage: String?

    private var canComment: Bool { currentRole.canComment }
    private var rootComments: [ChurchNoteCommentThread] { service.comments.filter { !$0.isReply } }

    var body: some View {
        NavigationStack {
            List {
                Section("Add Comment") {
                    Text(defaultAnchorText.isEmpty ? "Whole note" : defaultAnchorText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Comment", text: $commentBody, axis: .vertical)
                        .lineLimit(2...5)
                        .disabled(!canComment)
                    Button {
                        Task {
                            await service.addComment(noteId: noteId, anchorText: defaultAnchorText, anchorStart: nil, anchorEnd: nil, body: commentBody)
                            commentBody = ""
                        }
                    } label: {
                        Label("Add Comment", systemImage: "text.bubble")
                    }
                    .disabled(!canComment || commentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("Threads") {
                    if service.isLoading {
                        ProgressView("Loading comments")
                    } else if rootComments.isEmpty {
                        ContentUnavailableView("No comments", systemImage: "text.bubble", description: Text(canComment ? "Start a thread on this note." : "Viewers can read comments but cannot add them."))
                    } else {
                        ForEach(rootComments) { comment in
                            commentThread(comment)
                        }
                    }
                }

                if let actionStatusMessage {
                    Section {
                        Label(actionStatusMessage, systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = service.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .background(Color(.systemBackground))
        }
    }

    private func commentThread(_ comment: ChurchNoteCommentThread) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            commentBubble(comment)
            ForEach(service.comments.filter { $0.parentCommentId == comment.id }) { reply in
                commentBubble(reply)
                    .padding(.leading, 20)
            }
            if canComment && !comment.resolved {
                TextField("Reply", text: Binding(
                    get: { replyBodies[comment.id] ?? "" },
                    set: { replyBodies[comment.id] = $0 }
                ), axis: .vertical)
                .lineLimit(1...3)
                Button {
                    Task {
                        await service.reply(noteId: noteId, parentCommentId: comment.id, body: replyBodies[comment.id] ?? "")
                        replyBodies[comment.id] = ""
                    }
                } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                }
                .disabled((replyBodies[comment.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.vertical, 4)
    }

    private func commentBubble(_ comment: ChurchNoteCommentThread) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(comment.authorName)
                    .font(.subheadline.weight(.semibold))
                if comment.resolved {
                    Label("Resolved", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Spacer()
                Menu {
                    if comment.resolved {
                        Button("Reopen") {
                            Task { await service.setResolved(noteId: noteId, commentId: comment.id, resolved: false) }
                        }
                        .disabled(!canComment)
                    } else {
                        Button("Resolve") {
                            Task { await service.setResolved(noteId: noteId, commentId: comment.id, resolved: true) }
                        }
                        .disabled(!canComment)
                    }
                    Button("Delete", role: .destructive) {
                        Task { await service.deleteOwnComment(noteId: noteId, commentId: comment.id) }
                    }
                    .disabled(service.currentUid != comment.authorUid)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Comment actions")
            }
            if !comment.anchorText.isEmpty {
                Text(comment.anchorText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(comment.body)
                .font(.body)

            if let analysis = actionAnalysis(for: comment) {
                AmenActionIntelligenceCapsule(analysis: analysis) { action in
                    handleActionIntelligence(action, analysis: analysis, comment: comment)
                } onDismiss: {
                    actionStatusMessage = "Amen will suggest fewer actions like this here."
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func actionAnalysis(for comment: ChurchNoteCommentThread) -> AmenIntentAnalysis? {
        guard AMENFeatureFlags.shared.actionIntelligenceEnabled else { return nil }
        return ActionIntelligenceEngine.shared.analyze(
            source: ActionIntelligenceSource(
                id: comment.id,
                text: comment.body,
                surface: .comment,
                privacyTier: .confidential,
                authorId: comment.authorUid,
                currentUserId: service.currentUid,
                isAuthorLeader: false,
                isCurrentUserLeader: currentRole.canEdit
            )
        )
    }

    private func handleActionIntelligence(
        _ action: AmenActionSuggestion,
        analysis: AmenIntentAnalysis,
        comment: ChurchNoteCommentThread
    ) {
        let source = ActionIntelligenceSourcePayload(
            sourceId: comment.id,
            sourceType: "church_note_comment",
            sourceText: comment.body,
            postId: noteId,
            commentId: comment.id,
            authorId: nonEmpty(comment.authorUid),
            targetUserId: nonEmpty(comment.authorUid),
            targetDisplayName: comment.authorName,
            title: "\(analysis.intentKind.title) in Church Notes",
            scriptureReference: scriptureReferenceCandidate(from: comment.body, analysis: analysis)
        )

        Task {
            do {
                let result = try await ActionIntelligenceService.shared.execute(
                    action: action,
                    analysis: analysis,
                    source: source
                )
                actionStatusMessage = result.successMessage
            } catch {
                actionStatusMessage = error.localizedDescription
            }
        }
    }

    private func scriptureReferenceCandidate(from text: String, analysis: AmenIntentAnalysis) -> String? {
        guard analysis.intentKind == .scriptureReference else { return nil }
        return nonEmpty(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
}
