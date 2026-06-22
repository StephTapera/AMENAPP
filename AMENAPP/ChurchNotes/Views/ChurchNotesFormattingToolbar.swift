import SwiftUI

struct ChurchNotesFormattingToolbar: View {
    let activeFormats: ChurchNoteActiveFormats
    let activeHighlight: ChurchNoteHighlightType?
    let hasSelection: Bool
    let onBold: () -> Void
    let onItalic: () -> Void
    let onUnderline: () -> Void
    let onHighlight: (ChurchNoteHighlightType) -> Void
    let onBlockConvert: (ChurchNoteBlockType) -> Void

    var body: some View {
        ChurchNoteFormattingBar(
            activeFormats: activeFormats,
            activeHighlight: activeHighlight,
            hasSelection: hasSelection,
            onBold: onBold,
            onItalic: onItalic,
            onUnderline: onUnderline,
            onHighlight: onHighlight,
            onBlockConvert: onBlockConvert
        )
    }
}
