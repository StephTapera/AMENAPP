import Foundation

struct ChurchAddress: Codable, Hashable {
    let street1: String
    let street2: String?
    let city: String
    let state: String
    let postalCode: String
    let country: String
    let latitude: Double?
    let longitude: Double?
}
