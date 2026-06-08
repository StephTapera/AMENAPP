import SwiftUI

struct ChurchNotesEditorCard<EditorContent: View>: View {
    let title: String
    @Binding var sermonTitle: String
    @Binding var noteTags: [String]
    let noteContent: String
    let isReviewMode: Bool
    let summary: ChurchNoteReviewSummary
    let onReviewToggle: () -> Void
    let onTagChanged: () -> Void
    @ViewBuilder let editorContent: () -> EditorContent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Note Title", text: .constant(title))
                .font(.systemScaled(28, weight: .semibold))
                .disabled(true)
                .padding(.horizontal, 16)
                .padding(.top, 20)
            TextField("Sermon title (optional)", text: $sermonTitle)
                .font(.systemScaled(15))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            ChurchNoteTagTray(appliedTags: $noteTags, noteContent: noteContent)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .onChange(of: noteTags) { _, _ in onTagChanged() }
            HStack {
                Divider().padding(.leading, 16)
                Spacer()
                Button(isReviewMode ? "Edit" : "Review", action: onReviewToggle)
                    .font(.systemScaled(11, weight: .medium))
                    .padding(.trailing, 16)
            }
            .padding(.vertical, 4)
            if isReviewMode {
                ChurchNotesReviewSummaryView(summary: summary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
            }
            editorContent()
        }
        .churchNotesGlassCard()
    }
}
