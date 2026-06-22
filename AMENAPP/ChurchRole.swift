import Foundation

enum ChurchRole: String, Codable, CaseIterable {
    case owner
    case pastor
    case admin
    case mediaManager
    case eventsManager
    case moderator
}

struct RolePermissions: Codable, Hashable {
    var manageProfile: Bool
    var manageLive: Bool
    var manageEvents: Bool
    var moderateComments: Bool
    var manageSermons: Bool
    var manageAdmins: Bool
    var manageAnnouncements: Bool

    static let owner = RolePermissions(
        manageProfile: true, manageLive: true, manageEvents: true,
        moderateComments: true, manageSermons: true, manageAdmins: true, manageAnnouncements: true
    )
    static let pastor = RolePermissions(
        manageProfile: true, manageLive: true, manageEvents: true,
        moderateComments: true, manageSermons: true, manageAdmins: false, manageAnnouncements: true
    )
    static let admin = RolePermissions(
        manageProfile: true, manageLive: false, manageEvents: true,
        moderateComments: true, manageSermons: false, manageAdmins: false, manageAnnouncements: true
    )
    static let mediaManager = RolePermissions(
        manageProfile: false, manageLive: true, manageEvents: false,
        moderateComments: false, manageSermons: true, manageAdmins: false, manageAnnouncements: false
    )
    static let eventsManager = RolePermissions(
        manageProfile: false, manageLive: false, manageEvents: true,
        moderateComments: false, manageSermons: false, manageAdmins: false, manageAnnouncements: true
    )
    static let moderator = RolePermissions(
        manageProfile: false, manageLive: false, manageEvents: false,
        moderateComments: true, manageSermons: false, manageAdmins: false, manageAnnouncements: false
    )
}
