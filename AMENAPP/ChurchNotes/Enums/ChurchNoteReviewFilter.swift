import Foundation

enum ChurchNoteReviewFilter: String, Codable, CaseIterable, Hashable, Identifiable {
    case all
    case highlights
    case prayers
    case actions
    case scriptures
    case quotes

    var id: String { rawValue }
}
