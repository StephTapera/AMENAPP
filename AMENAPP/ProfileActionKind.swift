import Foundation

enum ProfileActionKind: String, CaseIterable, Hashable {
    case follow
    case message
    case prayWith
    case viewTestimony

    case planVisit
    case messageChurch
    case viewEvents
    case watchSermon
    case submitPrayerRequest

    case contact
    case collaborate
    case visitWebsite
    case viewResources
}
