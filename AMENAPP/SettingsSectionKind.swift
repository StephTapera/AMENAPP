import Foundation

enum SettingsSectionKind: String, CaseIterable, Hashable {
    case personalFaithVisibility
    case prayerPrivacy
    case testimonyControls

    case churchVerification
    case churchAdmins
    case serviceTimes
    case eventsAndSermons

    case businessDetails
    case businessLinks
    case analyticsPreferences
}
