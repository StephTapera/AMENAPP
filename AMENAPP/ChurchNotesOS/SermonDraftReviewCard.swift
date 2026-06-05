// SermonReviewDraftReviewCard.swift
// AMENAPP — ChurchNotesOS
// Mandatory approval card shown after live sermon AI processing.
// User MUST tap "Approve & Save" — there is no auto-save path.

import SwiftUI

// MARK: - Sermon Draft

struct SermonReviewDraft {
    var summary: String
    var discussionQuestions: [String]
    var closingPrayer: String
    var speakerName: String?
    var seriesTitle: String?

    static let empty = SermonReviewDraft(
        summary: "",
        discussionQuestions: ["", "", ""],
        closingPrayer: "",
        speakerName: nil,
        seriesTitle: nil
    )
}

// MARK: - Review Card

struct SermonReviewDraftReviewCard: View {
    @Binding var draft: SermonReviewDraft
    let onApproveAndSave: (SermonReviewDraft) -> Void
    let onDiscard: () -> Void

    @State private var isEditing = false
    @State private var showDiscardConfirm = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Label("Sermon Summary", systemImage: "doc.text.fill")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("Review before saving")
                        .font(.caption)
                        .foregroundStyle(Color.amenGold)
                }

                // Summary
                sectionCard(icon: "text.quote", title: "Summary") {
                    if isEditing {
                        TextEditor(text: $draft.summary)
                            .font(.subheadline)
                            .frame(minHeight: 80)
                    } else {
                        Text(draft.summary.isEmpty ? "No summary generated." : draft.summary)
                            .font(.subheadline)
                            .foregroundStyle(draft.summary.isEmpty ? .secondary : .primary)
                    }
                }

                // Discussion Questions
                sectionCard(icon: "questionmark.bubble.fill", title: "Discussion Questions") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(draft.discussionQuestions.enumerated()), id: \.offset) { index, _ in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.amenGold)
                                    .frame(width: 18, alignment: .leading)
                                if isEditing {
                                    TextField("Question \(index + 1)", text: $draft.discussionQuestions[index])
                                        .font(.subheadline)
                                } else {
                                    Text(draft.discussionQuestions[index].isEmpty
                                         ? "Question \(index + 1)"
                                         : draft.discussionQuestions[index])
                                        .font(.subheadline)
                                        .foregroundStyle(draft.discussionQuestions[index].isEmpty ? .secondary : .primary)
                                }
                            }
                        }
                    }
                }

                // Closing Prayer
                sectionCard(icon: "hands.sparkles.fill", title: "Closing Prayer") {
                    if isEditing {
                        TextEditor(text: $draft.closingPrayer)
                            .font(.subheadline)
                            .frame(minHeight: 60)
                    } else {
                        Text(draft.closingPrayer.isEmpty ? "No prayer generated." : draft.closingPrayer)
                            .font(.subheadline)
                            .foregroundStyle(draft.closingPrayer.isEmpty ? .secondary : .primary)
                    }
                }

                // Action buttons
                VStack(spacing: 10) {
                    // Edit toggle
                    Button {
                        withAnimation { isEditing.toggle() }
                    } label: {
                        Label(isEditing ? "Done Editing" : "Edit Draft", systemImage: isEditing ? "checkmark" : "pencil")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    // Approve & Save
                    Button {
                        onApproveAndSave(draft)
                    } label: {
                        Label("Approve & Save", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.amenGold, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Approve and save sermon notes")

                    // Discard
                    Button {
                        showDiscardConfirm = true
                    } label: {
                        Label("Discard", systemImage: "trash")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Discard sermon notes")
                }
                .confirmationDialog("Discard Sermon Notes?", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
                    Button("Discard", role: .destructive) { onDiscard() }
                    Button("Keep Editing", role: .cancel) {}
                } message: {
                    Text("This AI-generated draft will be permanently deleted. Your raw notes are kept.")
                }
            }
            .padding(16)
        }
        .background(reduceTransparency ? Color(.systemBackground) : Color(.systemBackground).opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 16, x: 0, y: 4)
    }

    @ViewBuilder
    private func sectionCard<Content: View>(icon: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.amenGold)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var draft = SermonReviewDraft(
        summary: "Pastor James shared a powerful message about trusting God's timing, drawing from Psalm 27. The sermon emphasized that waiting on the Lord is not passive but an active, expectant faith.",
        discussionQuestions: [
            "When have you found it hardest to wait on God?",
            "What does 'active waiting' look like in your daily life?",
            "How can our community support each other through seasons of waiting?"
        ],
        closingPrayer: "Lord, teach us to wait with hope and expectation. Help us to trust that your timing is perfect, even when we cannot see the path ahead. Amen.",
        speakerName: "Pastor James",
        seriesTitle: "Walking by Faith"
    )
    SermonReviewDraftReviewCard(
        draft: $draft,
        onApproveAndSave: { _ in },
        onDiscard: {}
    )
    .padding()
}
