import SwiftUI

struct ChurchNotesTagTray: View {
    @Binding var appliedTags: [String]
    let noteContent: String

    var body: some View {
        ChurchNoteTagTray(appliedTags: $appliedTags, noteContent: noteContent)
    }
}
