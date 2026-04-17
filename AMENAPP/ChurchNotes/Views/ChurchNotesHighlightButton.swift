import SwiftUI

struct ChurchNotesHighlightButton: View {
    let type: ChurchNoteHighlightType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        ChurchNoteHighlightButton(type: type, isSelected: isSelected, action: action)
    }
}
