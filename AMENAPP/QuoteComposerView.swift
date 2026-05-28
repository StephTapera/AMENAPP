import SwiftUI

struct QuoteComposerView: View {
    let context: QuoteComposerContext

    @Environment(\.dismiss) private var dismiss
    @State private var reflectionText: String = ""
    @State private var isPosting = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                QuoteExcerptCard(context: context)
                    .padding(.top, 8)

                TextEditor(text: $reflectionText)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .padding(12)
                    .frame(minHeight: 140)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .overlay(alignment: .topLeading) {
                        if reflectionText.isEmpty {
                            Text("Add a reflection (optional)...")
                                .font(.custom("OpenSans-Regular", size: 16))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 18)
                        }
                    }

                Spacer(minLength: 0)

                Button {
                    submitQuotePost()
                } label: {
                    HStack(spacing: 8) {
                        if isPosting {
                            ProgressView()
                                .progressViewStyle(.circular)
                        }
                        Text(isPosting ? "Posting..." : "Post Quote")
                            .font(AMENFont.semiBold(16))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.black)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }
                .disabled(isPosting)
            }
            .padding(.horizontal, 16)
            .navigationTitle("Quote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .amenAlert(
                isPresented: $showError,
                config: LiquidGlassAlertConfig(
                    title: "Unable to Post",
                    message: errorMessage.isEmpty ? nil : errorMessage,
                    icon: "exclamationmark.bubble",
                    primaryButton: LiquidGlassAlertButton("Try Again", tone: .primary, action: { showError = false }),
                    secondaryButton: .cancel()
                )
            )
        }
    }

    private func submitQuotePost() {
        guard !isPosting else { return }
        let trimmed = reflectionText.trimmingCharacters(in: .whitespacesAndNewlines)

        let source = context.sourcePost
        let sourcePostId = source.firebaseId ?? source.id.uuidString
        let quote = PostQuoteMetadata(
            sourcePostId: sourcePostId,
            sourceAuthorId: context.sourceAuthorId,
            sourceAuthorName: context.sourceAuthorName,
            sourceAuthorUsername: context.sourceAuthorUsername,
            sourceExcerpt: context.selection.text,
            selectionStart: context.selection.range.location,
            selectionLength: context.selection.range.length,
            quoteType: context.selection.suggestedQuoteType,
            createdAt: Date()
        )

        isPosting = true
        let contentToPost = trimmed
        PostsManager.shared.createPost(
            content: contentToPost,
            category: source.category,
            topicTag: source.topicTag,
            visibility: source.visibility,
            allowComments: true,
            imageURLs: nil,
            linkURL: nil,
            churchNoteId: nil,
            quote: quote
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isPosting = false
            dismiss()
        }
    }
}

private struct QuoteExcerptCard: View {
    let context: QuoteComposerContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(context.sourceAuthorName)
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(.primary)
                if let username = context.sourceAuthorUsername, !username.isEmpty {
                    Text("@\(username)")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                }
            }

            Text(context.selection.text)
                .font(AMENFont.regular(15))
                .foregroundStyle(.primary)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(red: 1.0, green: 0.95, blue: 0.75))
                )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
        )
    }
}
