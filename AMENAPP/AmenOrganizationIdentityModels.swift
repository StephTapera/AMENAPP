import SwiftUI
import Foundation

enum AmenOrganizationType: String, CaseIterable, Codable, Identifiable {
    case church
    case school
    case university
    case campusGroup
    case business
    case nonprofit
    case ministry
    case bibleStudy
    case creatorCommunity
    case communityGroup

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .church: return "Church"
        case .school: return "School"
        case .university: return "University"
        case .campusGroup: return "Campus Group"
        case .business: return "Business"
        case .nonprofit: return "Nonprofit"
        case .ministry: return "Ministry"
        case .bibleStudy: return "Bible Study"
        case .creatorCommunity: return "Creator Community"
        case .communityGroup: return "Community Group"
        }
    }

    var contextualType: AmenContextualOrganizationType {
        switch self {
        case .church: return .church
        case .school: return .school
        case .university: return .university
        case .campusGroup: return .campusGroup
        case .business: return .business
        case .nonprofit: return .nonprofit
        case .ministry: return .ministry
        case .bibleStudy: return .bibleStudy
        case .creatorCommunity: return .creatorCommunity
        case .communityGroup: return .communityGroup
        }
    }

    var defaultModules: [AmenOrganizationProfileModuleID] {
        switch self {
        case .church:
            return [.heroBanner, .identityHeader, .spacesPreview, .eventsPreview, .smartNotesPreview, .mediaPreview, .claimCTA, .safetyTransparency]
        case .school, .university, .campusGroup:
            return [.heroBanner, .identityHeader, .spacesPreview, .eventsPreview, .schoolNotesPreview, .claimCTA, .safetyTransparency]
        case .business:
            return [.heroBanner, .identityHeader, .spacesPreview, .eventsPreview, .adminTools, .claimCTA, .safetyTransparency]
        case .nonprofit, .ministry, .bibleStudy, .creatorCommunity, .communityGroup:
            return [.heroBanner, .identityHeader, .spacesPreview, .eventsPreview, .smartNotesPreview, .claimCTA, .safetyTransparency]
        }
    }
}

enum AmenOrganizationSource: String, CaseIterable, Codable, Identifiable {
    case ncesCCD
    case ncesPSS
    case ipeds
    case irsBMF
    case censusGeocoder
    case osmStaticExtract
    case googlePlaces
    case userCreated
    case partnerImport

    var id: String { rawValue }

    var canBeBulkStored: Bool {
        switch self {
        case .ncesCCD, .ncesPSS, .ipeds, .irsBMF, .censusGeocoder, .osmStaticExtract, .userCreated, .partnerImport:
            return true
        case .googlePlaces:
            return false
        }
    }
}

enum AmenOrganizationClaimStatus: String, CaseIterable, Codable, Identifiable {
    case unclaimed
    case pending
    case claimed
    case verified
    case rejected

    var id: String { rawValue }

    var allowsOfficialControls: Bool {
        self == .claimed || self == .verified
    }
}

enum AmenOrganizationBillingPlan: String, CaseIterable, Codable, Identifiable {
    case free
    case plus
    case pro

    var id: String { rawValue }

    var unlockedModules: Set<AmenOrganizationProfileModuleID> {
        switch self {
        case .free:
            return [.heroBanner, .identityHeader, .spacesPreview, .eventsPreview, .claimCTA, .safetyTransparency]
        case .plus:
            return [.heroBanner, .identityHeader, .spacesPreview, .eventsPreview, .schoolNotesPreview, .smartNotesPreview, .mediaPreview, .claimCTA, .safetyTransparency, .adminTools]
        case .pro:
            return Set(AmenOrganizationProfileModuleID.allCases)
        }
    }
}

enum AmenOrganizationProfileModuleID: String, CaseIterable, Codable, Identifiable, Hashable {
    case heroBanner
    case identityHeader
    case spacesPreview
    case eventsPreview
    case smartNotesPreview
    case schoolNotesPreview
    case mediaPreview
    case adminTools
    case safetyTransparency
    case claimCTA
    case privateFitReason

    var id: String { rawValue }
}

struct AmenOrganizationAddress: Codable, Hashable {
    var line1: String?
    var city: String?
    var state: String?
    var zip: String?
    var latitude: Double?
    var longitude: Double?
}

struct AmenOrganizationBilling: Codable, Hashable {
    var stripeCustomerId: String?
    var subscriptionId: String?
    var tier: AmenOrganizationBillingPlan
    var status: String
}

struct AmenOrganizationProfile: Identifiable, Codable, Hashable {
    var id: String
    var type: AmenOrganizationType
    var name: String
    var normalizedName: String
    var description: String?
    var address: AmenOrganizationAddress
    var website: String?
    var phone: String?
    var verifiedStatus: String
    var claimStatus: AmenOrganizationClaimStatus
    var source: AmenOrganizationSource
    var sourceId: String
    var sourceUpdatedAt: Date?
    var createdAt: Date?
    var updatedAt: Date?
    var createdBy: String?
    var ownerUid: String?
    var visibility: String
    var bannerConfig: [String: String]
    var spaceDefaults: [String: String]
    var billing: AmenOrganizationBilling?
    var safetyStatus: String
    var modules: [AmenOrganizationProfileModuleID]
    var schemaVersion: Int

    var effectiveModules: [AmenOrganizationProfileModuleID] {
        modules.isEmpty ? type.defaultModules : modules
    }

    var billingPlan: AmenOrganizationBillingPlan {
        billing?.tier ?? .free
    }
}

protocol AmenOrgProfileModule {
    var id: AmenOrganizationProfileModuleID { get }
    func view(for organization: AmenOrganizationProfile, isOwner: Bool) -> AnyView
}

struct AmenDefaultOrgProfileModule: AmenOrgProfileModule {
    let id: AmenOrganizationProfileModuleID

    func view(for organization: AmenOrganizationProfile, isOwner: Bool) -> AnyView {
        AnyView(AmenOrganizationProfileModuleCard(moduleID: id, organization: organization, isOwner: isOwner))
    }
}

enum AmenOrganizationModulePolicy {
    static func canRender(_ module: AmenOrganizationProfileModuleID, for organization: AmenOrganizationProfile, isOwner: Bool) -> Bool {
        if [.adminTools, .privateFitReason].contains(module) && !isOwner {
            return false
        }
        if module == .claimCTA {
            return !organization.claimStatus.allowsOfficialControls || isOwner
        }
        let unlocked = organization.billingPlan.unlockedModules
        return unlocked.contains(module) || organization.claimStatus.allowsOfficialControls
    }
}

struct AmenOrganizationProfileView: View {
    let organization: AmenOrganizationProfile
    var isOwner: Bool = false

    private var modules: [AmenDefaultOrgProfileModule] {
        organization.effectiveModules
            .filter { AmenOrganizationModulePolicy.canRender($0, for: organization, isOwner: isOwner) }
            .map(AmenDefaultOrgProfileModule.init(id:))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(modules, id: \.id) { module in
                    module.view(for: organization, isOwner: isOwner)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(Color.white.ignoresSafeArea())
        .navigationTitle(organization.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AmenOrganizationProfileModuleCard: View {
    let moduleID: AmenOrganizationProfileModuleID
    let organization: AmenOrganizationProfile
    let isOwner: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.black.opacity(0.06)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.black)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.black.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.58)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 4)
        )
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch moduleID {
        case .heroBanner: return organization.name
        case .identityHeader: return organization.type.displayName
        case .spacesPreview: return "Spaces"
        case .eventsPreview: return "Events"
        case .smartNotesPreview: return "Smart Notes"
        case .schoolNotesPreview: return "School Notes"
        case .mediaPreview: return "Media"
        case .adminTools: return "Admin Tools"
        case .safetyTransparency: return "Safety & Transparency"
        case .claimCTA: return organization.claimStatus.allowsOfficialControls ? "Manage Claim" : "Claim or Start a Space"
        case .privateFitReason: return "Why This May Fit You"
        }
    }

    private var subtitle: String {
        switch moduleID {
        case .heroBanner: return organization.description ?? "A verified organization profile can host groups, events, notes, and community spaces."
        case .identityHeader: return "\(organization.claimStatus.rawValue.capitalized) · \(organization.source.rawValue)"
        case .spacesPreview: return "Groups and Spaces connected to this organization."
        case .eventsPreview: return "Upcoming gatherings, RSVP moments, and community activities."
        case .smartNotesPreview: return "Shared study, sermon, meeting, and event notes."
        case .schoolNotesPreview: return "Class, chapel, cohort, and study notes using the shared Smart Notes engine."
        case .mediaPreview: return "Sermons, clips, classes, and public media."
        case .adminTools: return "Roles, moderation, banner controls, analytics, and paid workspace tools."
        case .safetyTransparency: return "Source, claim state, moderation status, and report controls."
        case .claimCTA: return "Represent this organization, participate here, or start a connected community group."
        case .privateFitReason: return "Private AI reasoning based on your intent and public organization signals."
        }
    }

    private var symbolName: String {
        switch moduleID {
        case .heroBanner: return "sparkles.rectangle.stack"
        case .identityHeader: return organization.type == .school ? "graduationcap.fill" : "building.2.fill"
        case .spacesPreview: return "person.3.fill"
        case .eventsPreview: return "calendar"
        case .smartNotesPreview, .schoolNotesPreview: return "note.text"
        case .mediaPreview: return "play.rectangle.fill"
        case .adminTools: return "person.badge.key.fill"
        case .safetyTransparency: return "shield.checkered"
        case .claimCTA: return "checkmark.seal.fill"
        case .privateFitReason: return "wand.and.stars"
        }
    }
}
