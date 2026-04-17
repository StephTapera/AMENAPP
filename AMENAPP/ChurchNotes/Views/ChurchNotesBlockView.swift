import SwiftUI

struct ChurchNotesBlockView: View {
    let block: ChurchNoteBlock
    let onDelete: () -> Void
    let onUpdate: (ChurchNoteBlock) -> Void

    var body: some View {
        ChurchNoteBlockView(block: block, onDelete: onDelete, onUpdate: onUpdate)
    }
}
