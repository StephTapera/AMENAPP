import Foundation

struct ChurchNoteScriptureReference: Codable, Identifiable, Hashable {
    var id: String
    var reference: String

    init(id: String = UUID().uuidString, reference: String) {
        self.id = id
        self.reference = reference
    }
}
