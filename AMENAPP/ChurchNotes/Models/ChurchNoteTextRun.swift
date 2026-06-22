import Foundation

struct ChurchNoteTextRun: Codable, Identifiable, Hashable {
    var id: String
    var text: String
    var styles: Set<ChurchNoteFormatStyle>
    var highlight: ChurchNoteHighlightType?

    init(
        id: String = UUID().uuidString,
        text: String,
        styles: Set<ChurchNoteFormatStyle> = [],
        highlight: ChurchNoteHighlightType? = nil
    ) {
        self.id = id
        self.text = text
        self.styles = styles
        self.highlight = highlight
    }
}
