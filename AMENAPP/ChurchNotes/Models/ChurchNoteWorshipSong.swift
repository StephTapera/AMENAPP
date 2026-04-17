import Foundation

struct ChurchNoteWorshipSong: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var artist: String?
    var provider: String?

    init(id: String = UUID().uuidString, title: String, artist: String? = nil, provider: String? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.provider = provider
    }
}

extension ChurchNoteWorshipSong {
    init(reference: WorshipSongReference) {
        self.init(id: reference.id, title: reference.title, artist: reference.artist, provider: reference.provider.rawValue)
    }
}
