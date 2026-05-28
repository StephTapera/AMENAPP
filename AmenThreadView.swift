import SwiftUI

struct AmenThreadView: View {
    let content: ContentNode

    @State private var replyText = ""
    @State private var summary = ""
    @State private var statusMessage = ""
    @State private var isPostingReply = false
    @State private var isSummarizing = false
    @State private var isSavingNote = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                contentHeader
                Divider()
                replyComposer
                summarySection
                statusSection
            }
            .padding(20)
        }
        .background(Color(.systemBackground))
        .navigationTitle("Thread")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
    }

    private var contentHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(content.author.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if let title = content.title, !title.isEmpty {
                Text(title)
                    .font(.title3.weight(.semibold))
            }
            SmartMessageText(
                text: content.displayText.isEmpty ? "No thread text available." : content.displayText,
                context: .local(messageId: content.id, surface: "amen_thread"),
                foregroundColor: .primary
            )
            .font(.body)
            .textSelection(.enabled)
        }
    }

    private var replyComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reply")
                .font(.headline)
            TextEditor(text: $replyText)
                .frame(minHeight: 92)
                .padding(8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel("Reply text")
            Button {
                Task { await postReply() }
            } label: {
                Label(isPostingReply ? "Posting" : "Post Reply", systemImage: "arrowshape.turn.up.left.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPostingReply)
            .accessibilityLabel("Post reply")
        }
    }

    private var summarySection: some View {
        SmartDiscussionSummaryCard(
            insight: summary.isEmpty ? nil : SmartDiscussionInsight(
                summary: summary,
                keyTakeaways: [],
                scriptures: SmartMessageLocalDetector.detect(in: summary).filter { $0.type == .scriptureReference }.map(\.normalizedValue),
                prayerRequests: SmartMessageLocalDetector.detect(in: summary).filter { $0.type == .prayerRequest }.map(\.sourceText),
                topics: SmartMessageLocalDetector.detect(in: summary).filter { $0.type == .topic }.map(\.normalizedValue),
                actionItems: [],
                unresolvedQuestions: SmartMessageLocalDetector.detect(in: summary).filter { $0.type == .question }.map(\.sourceText),
                suggestedNextActions: []
            ),
            isLoading: isSummarizing,
            onSummarize: { Task { await summarize() } },
            onRefresh: { Task { await summarize() } },
            onSaveToStudy: { statusMessage = "Open Study Mode from a Space thread to persist a shared study session." },
            onShare: { UIPasteboard.general.string = summary; statusMessage = "Summary copied." },
            onAskBerean: { askBereanAboutSummary() }
        )
    }

    @ViewBuilder
    private var statusSection: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
                .accessibilityLabel("Error: \(errorMessage)")
        } else if !statusMessage.isEmpty {
            Text(statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel(statusMessage)
        }
    }

    private func postReply() async {
        let body = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        errorMessage = nil
        isPostingReply = true
        defer { isPostingReply = false }
        do {
            _ = try await AmenUniversalContentService.shared.createReply(contentId: content.id, body: body)
            replyText = ""
            statusMessage = "Reply submitted for safety review."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func summarize() async {
        errorMessage = nil
        isSummarizing = true
        defer { isSummarizing = false }
        do {
            summary = try await AmenUniversalContentService.shared.summarizeThread(contentId: content.id)
            statusMessage = "Summary generated."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveToNote() async {
        errorMessage = nil
        isSavingNote = true
        defer { isSavingNote = false }
        do {
            _ = try await AmenUniversalContentService.shared.saveThreadToNote(contentId: content.id, summary: summary)
            statusMessage = "Thread saved to Notes."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func askBereanAboutSummary() {
        let payload = BereanContextPayload(
            selectedText: summary.isEmpty ? content.displayText : summary,
            surroundingText: content.displayText,
            sourceSurface: "amen_thread_summary",
            sourceId: content.id,
            contentType: .message
        )
        BereanContextMenuManager.shared.activate(payload: payload, action: .summarize)
    }
}
