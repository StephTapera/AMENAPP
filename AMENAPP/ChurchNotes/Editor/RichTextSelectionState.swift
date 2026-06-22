import Foundation

struct RichTextSelectionState: Equatable {
    var selectedRange: NSRange?
    var activeStyles: Set<ChurchNoteFormatStyle> = []
    var activeHighlight: ChurchNoteHighlightType?

    var hasSelection: Bool { (selectedRange?.length ?? 0) > 0 }
}
