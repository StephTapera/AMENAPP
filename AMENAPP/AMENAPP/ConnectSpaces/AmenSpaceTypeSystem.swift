// AmenSpaceTypeSystem.swift
// AMEN ConnectSpaces — Pure model/configuration layer for all 24 creator space types.
//
// Design constraints:
//   - No SwiftUI views — only model types, enums, and static config.
//   - Color(hex:) requires Color+Hex.swift to be in the same module.
//   - AmenSpaceTypeConfig.config(for:) is the single authority for per-type
//     tab/feature visibility; callers should not duplicate this logic.

import SwiftUI

// MARK: - AmenCreatorSpaceType

enum AmenCreatorSpaceType: String, Codable, CaseIterable, Identifiable {
    case church
    case campusMinistry
    case organization
    case nonprofit
    case podcast
    case bookClub
    case bibleStudy
    case smallGroup
    case mensMinistrry         // preserves historic spelling for Codable compatibility
    case womensMinistry
    case youthMinistry
    case mentor
    case coach
    case creator
    case conference
    case school
    case fitnessWellness
    case recoverySupport
    case missionTeam
    case familyGroup
    case friendGroup
    case businessTeam
    case worshipTeam
    case volunteerTeam

    var id: String { rawValue }

    // MARK: - Display name

    var displayName: String {
        switch self {
        case .church:           return "Church"
        case .campusMinistry:   return "Campus Ministry"
        case .organization:     return "Organization"
        case .nonprofit:        return "Nonprofit"
        case .podcast:          return "Podcast"
        case .bookClub:         return "Book Club"
        case .bibleStudy:       return "Bible Study"
        case .smallGroup:       return "Small Group"
        case .mensMinistrry:    return "Men's Ministry"
        case .womensMinistry:   return "Women's Ministry"
        case .youthMinistry:    return "Youth Ministry"
        case .mentor:           return "Mentor"
        case .coach:            return "Coach"
        case .creator:          return "Creator"
        case .conference:       return "Conference"
        case .school:           return "School"
        case .fitnessWellness:  return "Fitness & Wellness"
        case .recoverySupport:  return "Recovery & Support"
        case .missionTeam:      return "Mission Team"
        case .familyGroup:      return "Family Group"
        case .friendGroup:      return "Friend Group"
        case .businessTeam:     return "Business Team"
        case .worshipTeam:      return "Worship Team"
        case .volunteerTeam:    return "Volunteer Team"
        }
    }

    // MARK: - SF Symbol icon

    var systemIcon: String {
        switch self {
        case .church:           return "building.columns"
        case .campusMinistry:   return "graduationcap.fill"
        case .organization:     return "building.2.fill"
        case .nonprofit:        return "heart.fill"
        case .podcast:          return "mic.fill"
        case .bookClub:         return "book.closed.fill"
        case .bibleStudy:       return "text.book.closed.fill"
        case .smallGroup:       return "person.3.fill"
        case .mensMinistrry:    return "figure.stand"
        case .womensMinistry:   return "figure.dress.line.vertical.figure"
        case .youthMinistry:    return "figure.play"
        case .mentor:           return "person.badge.key.fill"
        case .coach:            return "trophy.fill"
        case .creator:          return "wand.and.stars"
        case .conference:       return "calendar.badge.plus"
        case .school:           return "pencil.and.ruler.fill"
        case .fitnessWellness:  return "figure.run"
        case .recoverySupport:  return "heart.circle.fill"
        case .missionTeam:      return "globe.americas.fill"
        case .familyGroup:      return "house.fill"
        case .friendGroup:      return "person.2.fill"
        case .businessTeam:     return "briefcase.fill"
        case .worshipTeam:      return "music.note.list"
        case .volunteerTeam:    return "hands.sparkles.fill"
        }
    }

    // MARK: - Accent color (distinct per type, no duplicates on adjacent types)

    var accentColor: Color {
        switch self {
        case .church:           return Color(hex: "D9A441")   // gold
        case .campusMinistry:   return Color(hex: "6E4BB5")   // purple
        case .organization:     return Color(hex: "245B8F")   // blue
        case .nonprofit:        return Color(hex: "D9A441")   // gold
        case .podcast:          return Color(hex: "A855F7")   // violet
        case .bookClub:         return Color(hex: "10B981")   // emerald
        case .bibleStudy:       return Color(hex: "F59E0B")   // amber
        case .smallGroup:       return Color(hex: "6E4BB5")   // purple
        case .mensMinistrry:    return Color(hex: "3B82F6")   // blue
        case .womensMinistry:   return Color(hex: "EC4899")   // pink
        case .youthMinistry:    return Color(hex: "F97316")   // orange
        case .mentor:           return Color(hex: "14B8A6")   // teal
        case .coach:            return Color(hex: "EAB308")   // yellow-gold
        case .creator:          return Color(hex: "A855F7")   // violet
        case .conference:       return Color(hex: "245B8F")   // blue
        case .school:           return Color(hex: "0EA5E9")   // sky
        case .fitnessWellness:  return Color(hex: "22C55E")   // green
        case .recoverySupport:  return Color(hex: "14B8A6")   // teal
        case .missionTeam:      return Color(hex: "F97316")   // orange
        case .familyGroup:      return Color(hex: "D9A441")   // gold
        case .friendGroup:      return Color(hex: "6E4BB5")   // purple
        case .businessTeam:     return Color(hex: "64748B")   // slate
        case .worshipTeam:      return Color(hex: "A855F7")   // violet
        case .volunteerTeam:    return Color(hex: "10B981")   // emerald
        }
    }

    // MARK: - One-sentence description

    var description: String {
        switch self {
        case .church:
            return "A local church community with services, sermon notes, and congregational care."
        case .campusMinistry:
            return "A university or college ministry connecting students through faith and fellowship."
        case .organization:
            return "A structured ministry or faith-based organization with staff and volunteers."
        case .nonprofit:
            return "A registered nonprofit serving a mission-driven community or cause."
        case .podcast:
            return "An audio or video podcast community for listeners and subscribers."
        case .bookClub:
            return "A reading community gathering around books, devotionals, or theology."
        case .bibleStudy:
            return "A focused study group working through scripture passage by passage."
        case .smallGroup:
            return "An intimate group of friends journeying together through life and faith."
        case .mensMinistrry:
            return "A brotherhood for men pursuing growth, accountability, and purpose."
        case .womensMinistry:
            return "A sisterhood for women cultivating faith, community, and encouragement."
        case .youthMinistry:
            return "A ministry for teens and young adults with age-appropriate programming."
        case .mentor:
            return "A one-on-one or small cohort mentoring relationship for personal growth."
        case .coach:
            return "A coaching community for leadership, career, or spiritual development."
        case .creator:
            return "A creative community for teachers, artists, and content makers of faith."
        case .conference:
            return "A conference, retreat, or multi-day event with speakers and sessions."
        case .school:
            return "A Christian school, seminary, or educational institution community."
        case .fitnessWellness:
            return "A community integrating physical health with spiritual wellness practices."
        case .recoverySupport:
            return "A safe, private community for those walking through recovery and healing."
        case .missionTeam:
            return "A missions team coordinating outreach, trips, and community service."
        case .familyGroup:
            return "A private family space for shared prayer, memories, and connection."
        case .friendGroup:
            return "A close-knit friend group sharing life, faith, and encouragement."
        case .businessTeam:
            return "A faith-integrated business team aligning work with values and prayer."
        case .worshipTeam:
            return "A worship team collaborating on music, setlists, and rehearsal notes."
        case .volunteerTeam:
            return "A volunteer team coordinating serve opportunities and schedules."
        }
    }

    // MARK: - Suggested tier names

    var suggestedTierNames: [String] {
        switch self {
        case .church:
            return ["Community", "Member", "Covenant Member"]
        case .campusMinistry:
            return ["Visitor", "Student", "Core Team"]
        case .organization:
            return ["Public", "Partner", "Staff"]
        case .nonprofit:
            return ["Supporter", "Partner", "Champion"]
        case .podcast:
            return ["Listener", "Subscriber", "Founding Member"]
        case .bookClub:
            return ["Reader", "Member", "Inner Circle"]
        case .bibleStudy:
            return ["Visitor", "Student", "Leader"]
        case .smallGroup:
            return ["Guest", "Member", "Core"]
        case .mensMinistrry:
            return ["Community", "Brother", "Covenant Brother"]
        case .womensMinistry:
            return ["Community", "Sister", "Covenant Sister"]
        case .youthMinistry:
            return ["Student", "Core Student", "Student Leader"]
        case .mentor:
            return ["Mentee", "Ongoing Mentee", "Alumni"]
        case .coach:
            return ["Cohort", "Member", "VIP"]
        case .creator:
            return ["Free", "Supporter", "Founding Member"]
        case .conference:
            return ["General", "Attendee", "VIP"]
        case .school:
            return ["Student", "Alumni", "Faculty"]
        case .fitnessWellness:
            return ["Community", "Member", "Premium"]
        case .recoverySupport:
            return ["Journey", "Member", "Mentor"]
        case .missionTeam:
            return ["Supporter", "Team Member", "Team Lead"]
        case .familyGroup:
            return ["Family"]
        case .friendGroup:
            return ["Friend"]
        case .businessTeam:
            return ["Team", "Core Team", "Leadership"]
        case .worshipTeam:
            return ["Team", "Core Team", "Leadership"]
        case .volunteerTeam:
            return ["Volunteer", "Regular", "Captain"]
        }
    }

    // MARK: - Default features

    var defaultFeatures: [String] {
        switch self {
        case .church:
            return ["Prayer room", "Sermon notes", "Live services", "Care routing", "Events calendar"]
        case .campusMinistry:
            return ["Bible study notes", "Events calendar", "Prayer room", "Announcements"]
        case .organization:
            return ["Announcements", "Events calendar", "Staff directory", "Prayer room"]
        case .nonprofit:
            return ["Mission updates", "Volunteer coordination", "Prayer room", "Donor stories"]
        case .podcast:
            return ["Episode library", "Study notes", "Community discussion", "Live Q&A"]
        case .bookClub:
            return ["Reading schedule", "Discussion threads", "Notes", "Live discussion"]
        case .bibleStudy:
            return ["Scripture notes", "Discussion threads", "Prayer room", "Study guides"]
        case .smallGroup:
            return ["Prayer room", "Discussion", "Events calendar", "Care routing"]
        case .mensMinistrry:
            return ["Accountability", "Prayer room", "Discussion", "Events calendar"]
        case .womensMinistry:
            return ["Prayer room", "Discussion", "Events calendar", "Devotional notes"]
        case .youthMinistry:
            return ["Announcements", "Events calendar", "Prayer room", "Curriculum notes"]
        case .mentor:
            return ["Session notes", "Goals tracker", "Prayer room", "Resources"]
        case .coach:
            return ["Curriculum", "Session notes", "Cohort discussion", "Events calendar"]
        case .creator:
            return ["Content library", "Live sessions", "Community discussion", "Study notes"]
        case .conference:
            return ["Schedule", "Speaker notes", "Events calendar", "Prayer room"]
        case .school:
            return ["Class notes", "Events calendar", "Prayer room", "Announcements"]
        case .fitnessWellness:
            return ["Workout plans", "Devotionals", "Community", "Prayer room"]
        case .recoverySupport:
            return ["Safe discussion", "Prayer room", "Resources", "Care routing"]
        case .missionTeam:
            return ["Trip coordination", "Prayer room", "Team updates", "Events calendar"]
        case .familyGroup:
            return ["Family feed", "Prayer room", "Events calendar", "Memories"]
        case .friendGroup:
            return ["Group feed", "Prayer room", "Events calendar"]
        case .businessTeam:
            return ["Team updates", "Prayer room", "Goals tracker", "Events calendar"]
        case .worshipTeam:
            return ["Setlists", "Rehearsal notes", "Prayer room", "Team schedule"]
        case .volunteerTeam:
            return ["Serve schedule", "Announcements", "Prayer room", "Events calendar"]
        }
    }

    // MARK: - Sensitive content flag

    var isSensitiveContent: Bool {
        switch self {
        case .recoverySupport:  return true
        default:                return false
        }
    }

    // MARK: - Verification requirement

    var requiresVerification: Bool {
        switch self {
        case .church, .nonprofit, .school, .organization:   return true
        default:                                             return false
        }
    }
}

// MARK: - AmenSpaceTypeConfig

/// Single authority for per-type tab/feature visibility. Callers read this
/// struct; they do not replicate the switch logic.
struct AmenSpaceTypeConfig {
    let type: AmenCreatorSpaceType
    let showPrayerTab: Bool
    let showChurchNotesTab: Bool
    let showMentorshipTab: Bool
    let showCoursesTab: Bool
    let showEventsTab: Bool
    let showLiveStreamTab: Bool
    let maxMembersPublic: Int?   // nil = unlimited

    // swiftlint:disable function_body_length cyclomatic_complexity
    static func config(for type: AmenCreatorSpaceType) -> AmenSpaceTypeConfig {
        switch type {

        case .church:
            return AmenSpaceTypeConfig(
                type: type,
                showPrayerTab: true,
                showChurchNotesTab: true,
                showMentorshipTab: false,
                showCoursesTab: false,
                showEventsTab: true,
                showLiveStreamTab: true,
                maxMembersPublic: nil
            )

        case .campusMinistry:
            return AmenSpaceTypeConfig(
                type: type,
                showPrayerTab: true,
                showChurchNotesTab: true,
                showMentorshipTab: true,
                showCoursesTab: false,
                showEventsTab: true,
                showLiveStreamTab: false,
                maxMembersPublic: 2000
            )

        case .organization:
            return AmenSpaceTypeConfig(
                type: type,
                showPrayerTab: true,
                showChurchNotesTab: false,
                showMentorshipTab: false,
                showCoursesTab: false,
                showEventsTab: true,
                showLiveStreamTab: false,
                maxMembersPublic: nil
            )

        case .nonprofit:
            return AmenSpaceTypeConfig(
                type: type,
                showPrayerTab: true,
                showChurchNotesTab: false,
                showMentorshipTab: false,
                showCoursesTab: false,
                showEventsTab: true,
                showLiveStreamTab: false,
                maxMembersPublic: nil
            )

        case .podcast:
            return AmenSpaceTypeConfig(
                type: type,
                showPrayerTab: false,
                showChurchNotesTab: false,
                showMentorshipTab: false,
                showCoursesTab: false,
                showEventsTab: true,
                showLiveStreamTab: true,
                maxMembersPublic: nil
            )

        case .bookClub:
            return AmenSpaceTypeConfig(
                type: type,
                showPrayerTab: false,
                showChurchNotesTab: false,
                showMentorshipTab: false,
                showCoursesTab: false,
                showEventsTab: true,
                showLiveStreamTab: false,
                maxMembersPublic: 500
            )

        case .bibleStudy:
            return AmenSpaceTypeConfig(
                type: type,
                showPrayerTab: true,
                showChurchNotesTab: true,
                showMentorshipTab: false,
                showCoursesTab: false,
                showEventsTab: true,
                showLiveStreamTab: false,
                maxMembersPublic: 200
            )

        case .smallGroup:
            return AmenSpaceTypeConfig(
                type: type,
                showPrayerTab: true,
                showChurchNotesTab: false,
                showMentorshipTab: false,
                showCoursesTab: false,
                showEventsTab: true,
                showLiveStreamTab: false,
                maxMembersPublic: 50
            )

        case .mensMinistrry:
            return AmenSpaceTypeConfig(
                type: type,
                showPrayerTab: true,
                showChurchNotesTab: false,
                showMentorshipTab: true,
                showCoursesTab: false,
                showEventsTab: true,
                showLiveStreamTab: false,
                maxMembersPublic: 500
            )

        case .womensMinistry:
            return AmenSpaceTypeConfig(
                type: type,
                showPrayerTab: true,
                showChurchNotesTab: false,
                showMentorshipTab: true,
                showCoursesTab: false,
                showEventsTab: true,
                showLiveStreamTab: false,
                maxMembersPublic: 500
            )

        case .youthMinistry:
            return AmenSpaceTypeConfig(
                type: type,
                showPrayerTab: true,
                showChurchNotesTab: true,
                showMentorshipTab: false,
                showCoursesTab: false,
                showEventsTab: true,
                showLiveStreamTab: false,
                maxMembersPublic: 1000
            )

        case .mentor:
            return AmenSpaceTypeConfig(
                type: type,
                showPrayerTab: true,
                showChurchNotesTab: false,
                showMentorshipTab: true,
                showCoursesTab: false,
                showEventsTab: false,
                showLiveStreamTab: false,
                maxMembersPublic: 25
            )

        case .coach:
            return AmenSpaceTypeConfig(
                type: type,
                showPrayerTab: false,
                showChurchNotesTab: false,
                showMentorshipTab: true,
                showCoursesTab: true,
                showEventsTab: true,
                showLiveStreamTab: true,
                maxMembersPublic: 300
            )

        case .creator:
            return AmenSpaceTypeConfig(
                type: type,
                showPrayerTab: false,
                showChurchNotesTab: false,
                showMentorshipTab: false,
                showCoursesTab: true,
                showEventsTab: true,
                showLiveStreamTab: true,
                maxMembersPublic: nil
            )

        case .conference:
            return AmenSpaceTypeConfig(
                type: type,
                showPrayerTab: true,
                showChurchNotesTab: false,
                showMentorshipTab: false,
                showCoursesTab: false,
                showEventsTab: true,
                showLiveStreamTab: true,
                maxMembersPublic: nil
            )

        case .school:
            return AmenSpaceTypeConfig(
                type: type,
                showPrayerTab: true,
                showChurchNotesTab: false,
                showMentorshipTab: false,
                showCoursesTab: true,
                showEventsTab: true,
                showLiveStreamTab: false,
                maxMembersPublic: nil
            )

        case .fitnessWellness:
            return AmenSpaceTypeConfig(
                type: type,
                showPrayerTab: true,
                showChurchNotesTab: false,
                showMentorshipTab: false,
                showCoursesTab: true,
                showEventsTab: true,
                showLiveStreamTab: false,
                maxMembersPublic: 1000
            )

        case .recoverySupport:
            return AmenSpaceTypeConfig(
                type: type,
                showPrayerTab: true,
                showChurchNotesTab: false,
                showMentorshipTab: true,
                showCoursesTab: false,
                showEventsTab: false,
                showLiveStreamTab: false,
                maxMembersPublic: 100
            )

        case .missionTeam:
            return AmenSpaceTypeConfig(
                type: type,
                showPrayerTab: true,
                showChurchNotesTab: false,
                showMentorshipTab: false,
                showCoursesTab: false,
                showEventsTab: true,
                showLiveStreamTab: false,
                maxMembersPublic: 200
            )

        case .familyGroup:
            return AmenSpaceTypeConfig(
                type: type,
                showPrayerTab: true,
                showChurchNotesTab: false,
                showMentorshipTab: false,
                showCoursesTab: false,
                showEventsTab: true,
                showLiveStreamTab: false,
                maxMembersPublic: 30
            )

        case .friendGroup:
            return AmenSpaceTypeConfig(
                type: type,
                showPrayerTab: true,
                showChurchNotesTab: false,
                showMentorshipTab: false,
                showCoursesTab: false,
                showEventsTab: true,
                showLiveStreamTab: false,
                maxMembersPublic: 50
            )

        case .businessTeam:
            return AmenSpaceTypeConfig(
                type: type,
                showPrayerTab: true,
                showChurchNotesTab: false,
                showMentorshipTab: false,
                showCoursesTab: false,
                showEventsTab: true,
                showLiveStreamTab: false,
                maxMembersPublic: 200
            )

        case .worshipTeam:
            return AmenSpaceTypeConfig(
                type: type,
                showPrayerTab: true,
                showChurchNotesTab: false,
                showMentorshipTab: false,
                showCoursesTab: false,
                showEventsTab: true,
                showLiveStreamTab: true,
                maxMembersPublic: 100
            )

        case .volunteerTeam:
            return AmenSpaceTypeConfig(
                type: type,
                showPrayerTab: true,
                showChurchNotesTab: false,
                showMentorshipTab: false,
                showCoursesTab: false,
                showEventsTab: true,
                showLiveStreamTab: false,
                maxMembersPublic: 500
            )
        }
    }
    // swiftlint:enable function_body_length cyclomatic_complexity
}
