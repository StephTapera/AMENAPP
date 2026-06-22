import Foundation

struct ChurchNoteContent: Codable, Hashable {
    var blocks: [ChurchNoteBlock]

    init(blocks: [ChurchNoteBlock] = []) {
        self.blocks = blocks
    }
}
extension ChurchNote {
    var metadataValue: ChurchNoteMetadata {
        ChurchNoteMetadata(note: self)
    }

    var semanticContent: ChurchNoteContent {
        ChurchNoteContent(blocks: blocks)
    }
}

