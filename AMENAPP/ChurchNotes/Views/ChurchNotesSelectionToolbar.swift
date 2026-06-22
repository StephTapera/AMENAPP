import SwiftUI

struct ChurchNotesSelectionToolbar: View {
    let activeFormats: ChurchNoteActiveFormats
    let hasSelection: Bool
    let onBold: () -> Void
    let onItalic: () -> Void
    let onUnderline: () -> Void
    let onHighlight: (ChurchNoteHighlightType) -> Void
    let onRemoveHighlight: () -> Void
    let onConvertBlock: (ChurchNoteBlockType) -> Void

    var body: some View {
        ChurchNoteSelectionToolbar(
            activeFormats: activeFormats,
            hasSelection: hasSelection,
            onBold: onBold,
            onItalic: onItalic,
            onUnderline: onUnderline,
            onHighlight: onHighlight,
            onRemoveHighlight: onRemoveHighlight,
            onConvertBlock: onConvertBlock
        )
    }
}
