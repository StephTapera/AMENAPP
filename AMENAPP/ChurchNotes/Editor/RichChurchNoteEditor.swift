import SwiftUI

struct RichChurchNoteEditor: View {
    @Binding var attributedText: NSAttributedString
    @Binding var plainText: String
    @Binding var selectionRange: NSRange?
    @Binding var activeFormats: ChurchNoteActiveFormats
    @Binding var isFirstResponder: Bool
    var formattingCommand: ChurchNoteRichEditorView.FormattingCommand?
    var onCommandExecuted: (() -> Void)?
    var onCoordinatorReady: ((ChurchNoteRichEditorView.Coordinator) -> Void)?

    var body: some View {
        RichChurchNoteTextView(
            attributedText: $attributedText,
            plainText: $plainText,
            selectionRange: $selectionRange,
            activeFormats: $activeFormats,
            isFirstResponder: $isFirstResponder,
            formattingCommand: formattingCommand,
            onCommandExecuted: onCommandExecuted,
            onCoordinatorReady: onCoordinatorReady
        )
    }
}
