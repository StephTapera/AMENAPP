import Foundation

struct ChurchServiceTime: Codable, Hashable, Identifiable {
    var id: String { "\(dayOfWeek)-\(startTime)-\(label ?? "")" }

    let dayOfWeek: String
    let startTime: String
    let label: String?
}
