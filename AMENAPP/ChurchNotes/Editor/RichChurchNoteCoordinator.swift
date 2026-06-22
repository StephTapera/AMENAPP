import Foundation

@MainActor
final class RichChurchNoteCoordinator: ObservableObject {
    @Published var selectionState = RichTextSelectionState()
    let commandApplier = RichTextCommandApplier()

    func updateSelection(range: NSRange?, formats: ChurchNoteActiveFormats) {
        var styles = Set<ChurchNoteFormatStyle>()
        if formats.isBold { styles.insert(.bold) }
        if formats.isItalic { styles.insert(.italic) }
        if formats.isUnderline { styles.insert(.underline) }
        selectionState = RichTextSelectionState(
            selectedRange: range,
            activeStyles: styles,
            activeHighlight: formats.highlightType
        )
    }
}
