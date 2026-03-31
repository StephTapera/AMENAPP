//
//  AMENAccountTypeSystem.swift
//  AMENAPP
//
//  Central architecture layer for account-type differentiation.
//  This file contains: SmartEngagementSignals, AccountCapabilities,
//  AccountTypeConfiguration, AccountTypeConfigurationFactory,
//  AccountTypeConfigurationService, AccountTypeBadgeView,
//  VerificationStatusBadgeView.
//
//  All simple enums/models (ChurchRelationshipType, VisibilityLevel,
//  VerificationStatus, ChurchRole, RolePermissions, ChurchAffiliationSummary,
//  ChurchServiceTime, ChurchAddress, ProfileModuleKind, ProfileActionKind,
//  ComposerPresetKind, SettingsSectionKind, SetupChecklistItemKind,
//  AccountType, UserAccount, ChurchMembership, ChurchProfile, BusinessProfile)
//  are defined in their individual standalone files.
//
//  IMPORTANT: `AMENAccountType` enum lives in AMENAccountTypeOnboardingView.swift.
//  This file references it but does NOT redefine it.
//
//  Design system:
//  - White background, black text
//  - Liquid Glass: .ultraThinMaterial + Color.white.opacity(0.55) overlay
//                  + Color(white: 0.88).opacity(0.5) strokeBorder 0.5pt
//                  + shadow black 0.06 radius 12
//  - Spring: .spring(response: 0.35, dampingFraction: 0.82)
//  - Typography: AMENFont.bold / .semiBold / .regular
//
//  Pure SwiftUI + Foundation — NO Firebase imports.
//  All persisted models conform to Codable.
//

import SwiftUI
import Foundation
import Combine

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SmartEngagementSignals
// ─────────────────────────────────────────────────────────────────────────────

/// Non-vanity engagement metrics — shown as human labels, not raw counts.
struct SmartEngagementSignals: Codable {
    var encouragedCount:          Int
    var savedToNotesCount:        Int
    var prayerfulResponseCount:   Int
    var discussionHealthScore:    Double   // 0.0 – 1.0
    var sharedCount:              Int

    /// Derived plain-language labels for public display.
    /// Raw numbers are never surfaced; only qualitative signals.
    var publicLabels: [String] {
        var labels: [String] = []
        if encouragedCount > 10 {
            labels.append("Many were encouraged")
        } else if encouragedCount > 0 {
            labels.append("Others were encouraged")
        }
        if savedToNotesCount > 5 {
            labels.append("Saved to notes by many")
        } else if savedToNotesCount > 0 {
            labels.append("Saved to notes")
        }
        if prayerfulResponseCount > 5 {
            labels.append("Generated prayerful responses")
        } else if prayerfulResponseCount > 0 {
            labels.append("Received prayerful responses")
        }
        if discussionHealthScore > 0.7 {
            labels.append("Active discussion")
        }
        if sharedCount > 20 {
            labels.append("Widely shared")
        } else if sharedCount > 5 {
            labels.append("Shared across the community")
        }
        return labels
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - AccountCapabilities
// ─────────────────────────────────────────────────────────────────────────────

/// Boolean capability flags keyed to an account type.
/// Consumed by feature gates throughout the app.
struct AccountCapabilities {
    var canPostAsOrganization:   Bool
    var canManageMembers:        Bool
    var canCreateEvents:         Bool
    var canArchiveSermons:       Bool
    var canGoLive:               Bool
    var canViewAnalytics:        Bool
    var canManageAdmins:         Bool
    var canAddServiceTimes:      Bool
    var hasVerificationFlow:     Bool
    var canFeatureOfferings:     Bool
    var canAddBusinessLinks:     Bool
    var hasAIModeration:         Bool
    var canAddChurchAffiliation: Bool
    var hasPrivacyControls:      Bool
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - AccountTypeConfiguration
// ─────────────────────────────────────────────────────────────────────────────

/// Full configuration bundle describing what an account type can do and show.
struct AccountTypeConfiguration {
    let accountType:           AMENAccountType
    let profileModules:        [ProfileModuleKind]
    let profileActions:        [ProfileActionKind]
    let composerPresets:       [ComposerPresetKind]
    let setupChecklist:        [SetupChecklistItemKind]
    let capabilities:          AccountCapabilities
    let composerPlaceholder:   String
    let discoveryTags:         [String]
    let settingsSectionLabels: [String]
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - AccountTypeConfigurationFactory
// ─────────────────────────────────────────────────────────────────────────────

/// Produces the correct `AccountTypeConfiguration` for any `AMENAccountType`.
enum AccountTypeConfigurationFactory {

    static func configuration(for type: AMENAccountType) -> AccountTypeConfiguration {
        switch type {
        case .personal: return personal
        case .church:   return church
        case .business: return business
        }
    }

    // MARK: Personal

    static var personal: AccountTypeConfiguration {
        AccountTypeConfiguration(
            accountType: .personal,
            profileModules: [
                .churchAffiliation,
                .faithJourney,
                .prayerFocus,
                .testimonyHighlight,
                .favoriteVerseTopics,
                .savedStudies
            ],
            profileActions: [
                .follow,
                .message,
                .prayWith,
                .viewTestimony
            ],
            composerPresets: [
                .reflection,
                .prayerRequest,
                .testimony,
                .gratitude,
                .scriptureSharee
            ],
            setupChecklist: [
                .addProfilePhoto,
                .writeIntro,
                .chooseScriptureTopics,
                .shareFirstReflection,
                .connectChurch,
                .startFirstPrayer
            ],
            capabilities: AccountCapabilities(
                canPostAsOrganization:   false,
                canManageMembers:        false,
                canCreateEvents:         false,
                canArchiveSermons:       false,
                canGoLive:               false,
                canViewAnalytics:        false,
                canManageAdmins:         false,
                canAddServiceTimes:      false,
                hasVerificationFlow:     false,
                canFeatureOfferings:     false,
                canAddBusinessLinks:     false,
                hasAIModeration:         false,
                canAddChurchAffiliation: true,
                hasPrivacyControls:      true
            ),
            composerPlaceholder: "Share a reflection, prayer request, gratitude, or testimony...",
            discoveryTags: ["faith journey", "prayer", "testimony", "scripture", "community"],
            settingsSectionLabels: [
                "Faith Journey Visibility",
                "Prayer Privacy",
                "Testimony Controls",
                "Church Affiliation"
            ]
        )
    }

    // MARK: Church

    static var church: AccountTypeConfiguration {
        AccountTypeConfiguration(
            accountType: .church,
            profileModules: [
                .churchVerificationBadge,
                .mutualChurchSignal,
                .serviceTimes,
                .locationDirections,
                .churchVisitCTA,
                .sermonArchive,
                .ministriesAnnouncements,
                .churchAdminTools
            ],
            profileActions: [
                .planVisit,
                .messageChurch,
                .viewEvents,
                .watchSermon,
                .prayerRequest
            ],
            composerPresets: [
                .announcement,
                .sermonRecap,
                .eventInvite,
                .ministryUpdate,
                .congregationPrayer
            ],
            setupChecklist: [
                .startVerification,
                .addServiceTimes,
                .addLocation,
                .uploadLogo,
                .createFirstAnnouncement,
                .assignStaffRoles,
                .addSermonSource
            ],
            capabilities: AccountCapabilities(
                canPostAsOrganization:   true,
                canManageMembers:        true,
                canCreateEvents:         true,
                canArchiveSermons:       true,
                canGoLive:               true,
                canViewAnalytics:        true,
                canManageAdmins:         true,
                canAddServiceTimes:      true,
                hasVerificationFlow:     true,
                canFeatureOfferings:     false,
                canAddBusinessLinks:     false,
                hasAIModeration:         true,
                canAddChurchAffiliation: false,
                hasPrivacyControls:      true
            ),
            composerPlaceholder: "Share a sermon recap, announcement, event, or ministry update...",
            discoveryTags: ["church", "service times", "sermons", "community", "events", "faith"],
            settingsSectionLabels: [
                "Verification Status",
                "Church Admins & Roles",
                "Service Times",
                "Events & Sermons",
                "Moderation"
            ]
        )
    }

    // MARK: Business

    static var business: AccountTypeConfiguration {
        AccountTypeConfiguration(
            accountType: .business,
            profileModules: [
                .businessMission,
                .businessLinks,
                .featuredOfferings,
                .opportunities,
                .partnershipTools
            ],
            profileActions: [
                .contact,
                .collaborate,
                .visitSite,
                .viewResources,
                .viewOpportunities
            ],
            composerPresets: [
                .resourceShare,
                .opportunity,
                .missionUpdate,
                .partnershipUpdate,
                .featuredOffering
            ],
            setupChecklist: [
                .addCategory,
                .addWebsite,
                .writeMissionStatement,
                .featureFirstResource,
                .configureAnalytics,
                .createFirstProfessionalPost
            ],
            capabilities: AccountCapabilities(
                canPostAsOrganization:   true,
                canManageMembers:        false,
                canCreateEvents:         true,
                canArchiveSermons:       false,
                canGoLive:               false,
                canViewAnalytics:        true,
                canManageAdmins:         true,
                canAddServiceTimes:      false,
                hasVerificationFlow:     true,
                canFeatureOfferings:     true,
                canAddBusinessLinks:     true,
                hasAIModeration:         false,
                canAddChurchAffiliation: false,
                hasPrivacyControls:      true
            ),
            composerPlaceholder: "Share a mission update, resource, opportunity, or featured offering...",
            discoveryTags: ["ministry", "resources", "mission", "faith-based", "partnerships"],
            settingsSectionLabels: [
                "Business Details",
                "Links & Contact",
                "Analytics & Insights",
                "Admin Access",
                "Partnership Tools"
            ]
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - AccountTypeConfigurationService
// ─────────────────────────────────────────────────────────────────────────────

/// Observable service that vends the active account-type configuration.
/// Reads and writes `AMENAccountType` via UserDefaults.
///
/// Usage:
///   @StateObject private var accountService = AccountTypeConfigurationService()
///   let config = accountService.currentConfiguration
///
@MainActor
final class AccountTypeConfigurationService: ObservableObject {

    // MARK: Published state

    @Published private(set) var currentType: AMENAccountType
    @Published private(set) var currentConfiguration: AccountTypeConfiguration

    // MARK: UserDefaults key

    private static let defaultsKey = "amenAccountType"

    // MARK: Init

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? ""
        let resolved = AMENAccountType(rawValue: stored) ?? .personal
        self.currentType = resolved
        self.currentConfiguration = AccountTypeConfigurationFactory.configuration(for: resolved)
    }

    // MARK: Mutation

    /// Persists the chosen account type and updates all published properties.
    func setAccountType(_ type: AMENAccountType) {
        UserDefaults.standard.set(type.rawValue, forKey: Self.defaultsKey)
        currentType = type
        currentConfiguration = AccountTypeConfigurationFactory.configuration(for: type)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Liquid Glass View Modifier (local)
// ─────────────────────────────────────────────────────────────────────────────

/// Applies the AMEN Liquid Glass style to any RoundedRectangle-backed view.
private struct LiquidGlassBackground: ViewModifier {
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
            )
    }
}

private extension View {
    func amenLiquidGlass(cornerRadius: CGFloat = 14) -> some View {
        modifier(LiquidGlassBackground(cornerRadius: cornerRadius))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - AccountTypeBadgeView
// ─────────────────────────────────────────────────────────────────────────────

/// A compact pill showing the account type and any necessary prompt,
/// rendered in the AMEN Liquid Glass style on a white background.
///
///   AccountTypeBadgeView(type: .church)
///   AccountTypeBadgeView(type: .personal)
///
struct AccountTypeBadgeView: View {

    let type: AMENAccountType

    @State private var isPressed = false

    // The secondary label shown after the bullet (e.g., "Verification required")
    private var subtitle: String? {
        switch type {
        case .personal: return nil
        case .church:   return "Verification required"
        case .business: return "Organization"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: type.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.black.opacity(0.7))

            Text(pillText)
                .font(AMENFont.semiBold(12))
                .foregroundColor(.black.opacity(0.85))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .amenLiquidGlass(cornerRadius: 20)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isPressed)
        .onTapGesture { }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
    }

    private var pillText: String {
        if let sub = subtitle {
            return "\(type.rawValue) · \(sub)"
        }
        return type.rawValue
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - VerificationStatusBadgeView
// ─────────────────────────────────────────────────────────────────────────────

/// Small inline badge showing a verification status with icon.
/// Used on church and business profiles next to the display name.
///
///   VerificationStatusBadgeView(status: .verified)
///   VerificationStatusBadgeView(status: .pending)
///
struct VerificationStatusBadgeView: View {

    let status: VerificationStatus

    private var iconColor: Color {
        switch status {
        case .unverified: return Color(white: 0.65)
        case .pending:    return Color(red: 0.95, green: 0.75, blue: 0.0)
        case .verified:   return .black
        case .rejected:   return Color(red: 0.85, green: 0.20, blue: 0.20)
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(iconColor)

            Text(status.displayLabel)
                .font(AMENFont.regular(11))
                .foregroundColor(.black.opacity(0.7))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .amenLiquidGlass(cornerRadius: 10)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Previews
// ─────────────────────────────────────────────────────────────────────────────

struct AMENAccountTypeSystem_Previews: PreviewProvider {

    static var previews: some View {
        Group {

            // Badge pills for all three account types
            VStack(spacing: 16) {
                Text("Account Type Badges")
                    .font(AMENFont.bold(17))
                    .foregroundColor(.black)

                ForEach(AMENAccountType.allCases) { type in
                    AccountTypeBadgeView(type: type)
                }
            }
            .padding(32)
            .background(Color.white)
            .previewDisplayName("AccountTypeBadgeView")

            // Verification status badges
            VStack(spacing: 16) {
                Text("Verification Status")
                    .font(AMENFont.bold(17))
                    .foregroundColor(.black)

                ForEach(
                    [VerificationStatus.unverified,
                     .pending,
                     .verified,
                     .rejected],
                    id: \.rawValue
                ) { status in
                    VerificationStatusBadgeView(status: status)
                }
            }
            .padding(32)
            .background(Color.white)
            .previewDisplayName("VerificationStatusBadgeView")

            // Configuration factory snapshot
            VStack(alignment: .leading, spacing: 12) {
                Text("Church Config Snapshot")
                    .font(AMENFont.bold(17))
                    .foregroundColor(.black)

                let config = AccountTypeConfigurationFactory.church
                Group {
                    infoRow(label: "Modules",   value: "\(config.profileModules.count)")
                    infoRow(label: "Actions",   value: "\(config.profileActions.count)")
                    infoRow(label: "Presets",   value: "\(config.composerPresets.count)")
                    infoRow(label: "Checklist", value: "\(config.setupChecklist.count)")
                    infoRow(label: "Go Live",   value: config.capabilities.canGoLive ? "Yes" : "No")
                    infoRow(label: "Verify",    value: config.capabilities.hasVerificationFlow ? "Yes" : "No")
                }
            }
            .padding(32)
            .background(Color.white)
            .previewDisplayName("Factory Snapshot — Church")
        }
        .preferredColorScheme(.light)
    }

    private static func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AMENFont.semiBold(13))
                .foregroundColor(.black.opacity(0.6))
            Spacer()
            Text(value)
                .font(AMENFont.regular(13))
                .foregroundColor(.black)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .amenLiquidGlass(cornerRadius: 10)
    }
}
