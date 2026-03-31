import Foundation

enum SetupChecklistItemKind: String, CaseIterable, Hashable {
    case addProfilePhoto
    case writeIntro
    case chooseScriptureTopics
    case shareFirstReflection

    case startVerification
    case addServiceTimes
    case addLocation
    case createFirstAnnouncement

    case addCategory
    case addWebsite
    case writeMissionStatement
    case featureFirstResource
}
