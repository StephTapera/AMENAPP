import Foundation

struct ChurchNoteMetadata: Codable, Hashable {
    var churchName: String
    var pastorName: String
    var serviceDate: Date
    var campus: String?
    var serviceType: String?

    init(
        churchName: String = "",
        pastorName: String = "",
        serviceDate: Date = Date(),
        campus: String? = nil,
        serviceType: String? = nil
    ) {
        self.churchName = churchName
        self.pastorName = pastorName
        self.serviceDate = serviceDate
        self.campus = campus
        self.serviceType = serviceType
    }
}

extension ChurchNoteMetadata {
    init(note: ChurchNote) {
        self.init(
            churchName: note.churchName ?? "",
            pastorName: note.pastor ?? "",
            serviceDate: note.date
        )
    }

    func applying(to note: ChurchNote) -> ChurchNote {
        var note = note
        note.churchName = churchName.isEmpty ? nil : churchName
        note.pastor = pastorName.isEmpty ? nil : pastorName
        note.date = serviceDate
        return note
    }
}
