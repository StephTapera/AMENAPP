import Foundation

enum SetupChecklistItemKind: String, CaseIterable, Hashable {
    case addProfilePhoto
    case writeIntro
    case chooseScriptureTopics
    case shareFirstReflection
    case connectChurch
    case startFirstPrayer

    case startVerification
    case addServiceTimes
    case addLocation
    case createFirstAnnouncement
    case uploadLogo
    case assignStaffRoles
    case addSermonSource

    case addCategory
    case addWebsite
    case writeMissionStatement
    case featureFirstResource
    case configureAnalytics
    case createFirstProfessionalPost
}
