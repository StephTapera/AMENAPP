import Foundation

enum ChurchNoteToolbarAction: Hashable {
    case bold
    case italic
    case underline
    case highlight(ChurchNoteHighlightType)
    case tag
    case convertToQuote
    case convertToPrayer
    case convertToAction
    case convertToScripture
}
