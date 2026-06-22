import Foundation

struct RichTextCommandApplier {
    func formattingCommand(for action: ChurchNoteToolbarAction, activeHighlight: ChurchNoteHighlightType?) -> ChurchNoteRichEditorView.FormattingCommand? {
        switch action {
        case .bold: return .bold
        case .italic: return .italic
        case .underline: return .underline
        case .highlight(let type):
            return activeHighlight == type ? .removeHighlight : .highlight(type)
        default:
            return nil
        }
    }

    func convertedBlock(from text: String, type: ChurchNoteBlockType, tags: [String] = []) -> ChurchNoteBlock {
        ChurchNoteBlock(type: type, text: text.trimmingCharacters(in: .whitespacesAndNewlines), tags: tags)
    }
}
