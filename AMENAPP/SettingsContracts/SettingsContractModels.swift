import Foundation

typealias TranslationID = String
typealias ContextID = String

struct AppearancePrefs: Codable, Equatable {
    var mode: AppearanceMode
    var accent: AccentColor
    var glassIntensity: Double
    var reduceTransparency: Bool

    static let defaultValue = AppearancePrefs(
        mode: .system,
        accent: .default,
        glassIntensity: 0.65,
        reduceTransparency: false
    )
}

struct GeneralPrefs: Codable, Equatable {
    var appLanguage: LanguageCode
    var scriptureTranslation: TranslationID
    var autoCorrect: Bool
    var hapticFeedback: Bool
    var autocomplete: Bool
    var trendingSearches: Bool
    var webSearchAllowed: Bool
    var aiAutoSwitch: Bool
    var proLevel: ProLevel
    var accessibilityMode: Bool
    var reduceMotion: Bool
    var increaseContrast: Bool
    var dyslexiaFont: Bool
    var voiceInput: Bool
    var textToSpeech: Bool

    static let defaultValue = GeneralPrefs(
        appLanguage: "en",
        scriptureTranslation: "WEB",
        autoCorrect: true,
        hapticFeedback: true,
        autocomplete: true,
        trendingSearches: false,
        webSearchAllowed: false,
        aiAutoSwitch: false,
        proLevel: .standard,
        accessibilityMode: false,
        reduceMotion: false,
        increaseContrast: false,
        dyslexiaFont: false,
        voiceInput: false,
        textToSpeech: false
    )
}

struct SecuritySettings: Codable, Equatable {
    var passkeysEnrolled: [PasskeyRef]
    var totpEnabled: Bool
    var smsEnabled: Bool
    var lockdownMode: Bool
    var requireFaceIDForApp: Bool
    var suspiciousLoginAlerts: Bool
    var recoveryEmail: String?
    var recoveryPhone: String?

    static let defaultValue = SecuritySettings(
        passkeysEnrolled: [],
        totpEnabled: false,
        smsEnabled: false,
        lockdownMode: false,
        requireFaceIDForApp: true,
        suspiciousLoginAlerts: true,
        recoveryEmail: nil,
        recoveryPhone: nil
    )
}

struct PasskeyRef: Codable, Identifiable, Equatable {
    var id: String
    var displayName: String
    var addedAt: Date
    var lastUsedAt: Date?
}

struct SessionInfo: Codable, Identifiable, Equatable {
    var id: String
    var deviceName: String
    var platform: String
    var lastActiveAt: Date
    var ipCity: String?
    var isCurrent: Bool
    var isTrusted: Bool
}

struct SettingsTrustedContact: Codable, Identifiable, Equatable {
    var id: String
    var displayName: String
    var contactMethod: SettingsTrustedContactMethod
    var status: SettingsTrustedContactStatus
    var addedAt: Date
}

struct SettingsTrustedContactMethod: Codable, Equatable {
    var kind: ContactMethodKind
    var maskedValue: String
}

struct FamilyLink: Codable, Identifiable, Equatable {
    var id: String
    var role: FamilyRole
    var counterpartUidMasked: String
    var status: FamilyLinkStatus
    var ageBand: AgeBand
    var createdAt: Date
}

struct ParentalControls: Codable, Equatable {
    var contentLimitLevel: ContentLimitLevel
    var dmRestriction: InteractionRestriction
    var commentRestriction: InteractionRestriction
    var groupVisibility: GroupVisibility
    var aiSafetyLevel: AISafetyLevel
    var screenTimeReminders: Bool
    var prayerVisibility: SettingsPrayerVisibility

    static let minorDefault = ParentalControls(
        contentLimitLevel: .teen,
        dmRestriction: .approvedConnectionsOnly,
        commentRestriction: .followersOnly,
        groupVisibility: .guardianApproved,
        aiSafetyLevel: .high,
        screenTimeReminders: true,
        prayerVisibility: .privateByDefault
    )
}

struct NotificationPrefs: Codable, Equatable {
    var categories: [SettingsNotificationCategory: ChannelChoice]

    static let defaultValue = NotificationPrefs(categories: Dictionary(
        uniqueKeysWithValues: SettingsNotificationCategory.allCases.map { category in
            let minimum = category.minimumAllowedChoice
            return (category, minimum ?? .quiet)
        }
    ))
}

struct BereanAIControls: Codable, Equatable {
    var scriptureCrossCheck: Bool
    var translation: TranslationID
    var denominationContext: ContextID?
    var showSources: Bool
    var explainUncertainty: Bool
    var pastoralTone: TonePreset
    var activePreset: BereanPreset
    var originalLanguageMode: Bool

    static let defaultValue = BereanAIControls(
        scriptureCrossCheck: true,
        translation: "WEB",
        denominationContext: nil,
        showSources: true,
        explainUncertainty: true,
        pastoralTone: .warm,
        activePreset: .study,
        originalLanguageMode: false
    )
}

struct AmenSafetyPrefs: Codable, Equatable {
    var safeCommentingMode: Bool
    var contextBeforeComment: Bool
    var watchReadBeforeComment: Bool

    static let defaultValue = AmenSafetyPrefs(
        safeCommentingMode: true,
        contextBeforeComment: true,
        watchReadBeforeComment: true
    )
}

struct StorageBreakdown: Codable, Equatable {
    var total: Int64
    var documents: Int64
    var images: Int64
    var audioNotes: Int64
    var videoCache: Int64
    var bibleDownloads: Int64
    var sermonDownloads: Int64
    var aiMemoryCache: Int64

    static let empty = StorageBreakdown(
        total: 0,
        documents: 0,
        images: 0,
        audioNotes: 0,
        videoCache: 0,
        bibleDownloads: 0,
        sermonDownloads: 0,
        aiMemoryCache: 0
    )
}

struct IssueReport: Codable, Identifiable, Equatable {
    var id: String
    var category: IssueReportCategory
    var body: String
    var includeScreenshot: Bool
    var includeLogs: Bool
    var status: IssueReportStatus
    var createdAt: Date

    static let maxBodyCharacterCount = 2_000
}

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
}

enum AccentColor: String, Codable, CaseIterable, Identifiable {
    case `default`
    case blue
    case green
    case yellow
    case pink
    case orange
    case purple
    case black
    case tan
    case wineRed

    var id: String { rawValue }
}

enum ProLevel: String, Codable, CaseIterable, Identifiable {
    case standard
    case plus
    case creator
    case church

    var id: String { rawValue }
}

enum SettingsNotificationCategory: String, Codable, CaseIterable, Identifiable {
    case prayerReminders
    case bibleReadingPlan
    case groupChats
    case replies
    case mentions
    case sermonTeaching
    case churchAnnouncements
    case eventReminders
    case amenPulseDailyDigest
    case creatorUpdates
    case safetyAlerts
    case accountSecurity
    case marketing
    case productTips
    case usageSummaries

    var id: String { rawValue }

    var minimumAllowedChoice: ChannelChoice? {
        switch self {
        case .safetyAlerts, .accountSecurity:
            return .quiet
        default:
            return nil
        }
    }
}

enum ChannelChoice: String, Codable, CaseIterable, Identifiable {
    case off
    case push
    case email
    case pushAndEmail
    case quiet
    case digestOnly

    var id: String { rawValue }
}

enum TonePreset: String, Codable, CaseIterable, Identifiable {
    case concise
    case warm
    case scholarly
    case pastoralButNotAuthoritative

    var id: String { rawValue }
}

enum BereanPreset: String, Codable, CaseIterable, Identifiable {
    case study
    case prayer
    case debate
    case originalLanguage

    var id: String { rawValue }
}

enum ContentLimitLevel: String, Codable, CaseIterable, Identifiable {
    case child
    case teen
    case standard
    case mature

    var id: String { rawValue }
}

enum AISafetyLevel: String, Codable, CaseIterable, Identifiable {
    case high
    case balanced
    case adultStandard

    var id: String { rawValue }
}

enum SettingsTrustedContactStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case confirmed
    case removed

    var id: String { rawValue }
}

enum ContactMethodKind: String, Codable, CaseIterable, Identifiable {
    case email
    case phone

    var id: String { rawValue }
}

enum FamilyRole: String, Codable, CaseIterable, Identifiable {
    case guardian
    case minor

    var id: String { rawValue }
}

enum FamilyLinkStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case active
    case removed

    var id: String { rawValue }
}

enum AgeBand: String, Codable, CaseIterable, Identifiable {
    case under13
    case thirteenTo15
    case sixteenTo17
    case adult

    var id: String { rawValue }
}

enum InteractionRestriction: String, Codable, CaseIterable, Identifiable {
    case disabled
    case approvedConnectionsOnly
    case followersOnly
    case everyone

    var id: String { rawValue }
}

enum GroupVisibility: String, Codable, CaseIterable, Identifiable {
    case hidden
    case guardianApproved
    case publicAllowed

    var id: String { rawValue }
}

enum SettingsPrayerVisibility: String, Codable, CaseIterable, Identifiable {
    case privateByDefault
    case sharedWithGuardianConsent
    case userControlled

    var id: String { rawValue }
}

enum IssueReportCategory: String, Codable, CaseIterable, Identifiable {
    case bug
    case safety
    case account
    case payment
    case content
    case prayer
    case group
    case aiAnswer

    var id: String { rawValue }
}

enum IssueReportStatus: String, Codable, CaseIterable, Identifiable {
    case submitted
    case reviewed
    case resolved

    var id: String { rawValue }
}
