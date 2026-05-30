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

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .plus: return "Plus"
        case .pro:  return "Pro"
        }
    }

    var monthlyPrice: String {
        switch self {
        case .free: return "Free"
        case .plus: return "$29/mo"
        case .pro:  return "$79/mo"
        }
    }

    // Instance convenience — delegates to the static helper.
    var unlockedModules: Set<AmenOrganizationProfileModuleID> {
        AmenOrganizationBillingPlan.unlockedModules(for: self)
    }

    // Static helper so AmenOrganizationModulePolicy can call without an instance.
    // Per spec: Free → Plus (additive) → Pro (additive).
    static func unlockedModules(for plan: AmenOrganizationBillingPlan) -> Set<AmenOrganizationProfileModuleID> {
        switch plan {
        case .free:
            return [.heroBanner, .identityHeader, .safetyTransparency, .adminTools]
        case .plus:
            return AmenOrganizationBillingPlan.unlockedModules(for: .free)
                .union([.spacesPreview, .eventsPreview, .schoolNotesPreview, .smartNotesPreview, .giving])
        case .pro:
            return AmenOrganizationBillingPlan.unlockedModules(for: .plus)
                .union([.mediaPreview, .analytics])
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
    case giving
    case analytics

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
    var schemaVersion: Int = 1

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

// MARK: - AmenOrganizationModulePolicy

/// Server-of-truth gating logic for module visibility.
/// - Free modules always visible to any viewer.
/// - Paid modules require claimed/verified status + tier unlock.
/// - adminTools / privateFitReason only visible to the org owner.
enum AmenOrganizationModulePolicy {

    static func canRender(
        _ moduleId: AmenOrganizationProfileModuleID,
        for org: AmenOrganizationProfile,
        isOwner: Bool
    ) -> Bool {
        // 1. Owner-only modules.
        if moduleId == .adminTools && !isOwner { return false }
        if moduleId == .privateFitReason && !isOwner { return false }

        // 2. claimCTA: only for unclaimed orgs.
        if moduleId == .claimCTA { return org.claimStatus == .unclaimed }

        // 3. Always-free modules — no tier gate.
        let freeModules: Set<AmenOrganizationProfileModuleID> = [
            .heroBanner, .identityHeader, .safetyTransparency, .adminTools
        ]
        if freeModules.contains(moduleId) { return true }

        // 4. Paid modules require a claimed/verified org.
        guard org.claimStatus == .claimed || org.claimStatus == .verified else { return false }

        // 5. Check tier unlock table.
        let tier = org.billing?.tier ?? .free
        return AmenOrganizationBillingPlan.unlockedModules(for: tier).contains(moduleId)
    }

    /// Returns the lowest tier that unlocks `moduleId` — used by locked placeholder UI.
    static func requiredTier(for moduleId: AmenOrganizationProfileModuleID) -> AmenOrganizationBillingPlan {
        if AmenOrganizationBillingPlan.unlockedModules(for: .plus).contains(moduleId) { return .plus }
        return .pro
    }
}

struct AmenOrganizationProfileView: View {
    let organization: AmenOrganizationProfile
    var isOwner: Bool = false

    /// Module IDs to render — passing through policy filter, plus locked placeholders for owners.
    private var renderedModuleIDs: [AmenOrganizationProfileModuleID] {
        organization.effectiveModules.filter { moduleId in
            if AmenOrganizationModulePolicy.canRender(moduleId, for: organization, isOwner: isOwner) {
                return true
            }
            // Show locked placeholder so org owners can discover what to upgrade to.
            if isOwner,
               organization.claimStatus == .claimed || organization.claimStatus == .verified,
               moduleId != .claimCTA, moduleId != .privateFitReason {
                return true
            }
            return false
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(renderedModuleIDs, id: \.self) { moduleId in
                    if AmenOrganizationModulePolicy.canRender(moduleId, for: organization, isOwner: isOwner) {
                        AmenDefaultOrgProfileModule(id: moduleId)
                            .view(for: organization, isOwner: isOwner)
                    } else {
                        AmenOrganizationLockedModuleCard(
                            moduleId: moduleId,
                            organization: organization,
                            requiredTier: AmenOrganizationModulePolicy.requiredTier(for: moduleId)
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle(organization.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - AmenOrganizationLockedModuleCard

/// Placeholder card for tier-locked modules. Tapping opens AmenOrgUpgradeSheet.
struct AmenOrganizationLockedModuleCard: View {
    let moduleId: AmenOrganizationProfileModuleID
    let organization: AmenOrganizationProfile
    let requiredTier: AmenOrganizationBillingPlan

    @State private var showUpgradeSheet = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var lockedModuleTitle: String {
        switch moduleId {
        case .spacesPreview:     return "Spaces"
        case .eventsPreview:     return "Events"
        case .smartNotesPreview: return "Smart Notes"
        case .schoolNotesPreview: return "School Notes"
        case .mediaPreview:      return "Media"
        case .giving:            return "Giving"
        case .analytics:         return "Analytics"
        default:                 return moduleId.rawValue.capitalized
        }
    }

    private var accentColor: Color {
        requiredTier == .pro ? AmenTheme.Colors.amenPurple : AmenTheme.Colors.amenGold
    }

    var body: some View {
        Button { showUpgradeSheet = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(accentColor.opacity(0.12)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(lockedModuleTitle)
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(Color.primary)
                    Text("Upgrade to \(requiredTier.displayName) to unlock")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(Color.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.secondary)
            }
            .padding(14)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.systemBackground))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(accentColor.opacity(0.30), lineWidth: 1)
                        }
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(accentColor.opacity(0.06)) }
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(accentColor.opacity(0.30), lineWidth: 1)
                        }
                }
            }
            .shadow(color: accentColor.opacity(0.08), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(lockedModuleTitle). Locked. Requires \(requiredTier.displayName) plan.")
        .accessibilityHint("Double-tap to see upgrade options.")
        .sheet(isPresented: $showUpgradeSheet) {
            AmenOrgUpgradeSheet(organization: organization)
        }
    }
}

private struct AmenOrganizationProfileModuleCard: View {
    let moduleID: AmenOrganizationProfileModuleID
    let organization: AmenOrganizationProfile
    let isOwner: Bool

    @State private var showUpgradeSheet = false

    var body: some View {
        Group {
            switch moduleID {
            case .heroBanner:
                heroBannerCard
            case .identityHeader:
                identityHeaderCard
            case .claimCTA:
                claimCTACard
            case .spacesPreview:
                spacesPreviewCard
            case .eventsPreview:
                eventsPreviewCard
            case .schoolNotesPreview:
                schoolNotesCard
            case .smartNotesPreview:
                smartNotesCard
            case .adminTools:
                adminToolsCard
            case .safetyTransparency:
                safetyFooterCard
            case .mediaPreview:
                mediaPreviewCard
            case .privateFitReason:
                privateFitCard
            case .giving:
                givingCard
            case .analytics:
                analyticsCard
            }
        }
    }

    // MARK: - Hero Banner

    private var heroBannerCard: some View {
        ZStack(alignment: .bottomLeading) {
            if let urlString = organization.bannerConfig["imageURL"],
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        heroBannerFallback
                    }
                }
            } else {
                heroBannerFallback
            }

            // Gradient overlay
            LinearGradient(
                colors: [Color.clear, Color(.sRGBLinear, white: 0, opacity: 0.55)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(organization.name)
                    .font(AMENFont.semiBold(20))
                    .foregroundStyle(Color.white)
                    .lineLimit(2)

                // Type badge chip
                Text(organization.type.displayName.uppercased())
                    .font(AMENFont.semiBold(11))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(AmenTheme.Colors.amenGold.opacity(0.18))
                            .overlay(Capsule(style: .continuous).strokeBorder(AmenTheme.Colors.amenGold.opacity(0.45), lineWidth: 0.5))
                    )
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(UIColor.separator).opacity(0.3), lineWidth: 0.5)
        )
        .accessibilityLabel("\(organization.name) — \(organization.type.displayName) banner")
    }

    private var heroBannerFallback: some View {
        ZStack {
            AmenTheme.Colors.amenGold.opacity(0.15)
            Image(systemName: "building.2.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.amenGold.opacity(0.45))
        }
    }

    // MARK: - Identity Header

    private var identityHeaderCard: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(organization.name)
                        .font(AMENFont.semiBold(20))
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)

                    if organization.claimStatus == .verified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AmenTheme.Colors.amenGold)
                            .accessibilityLabel("Verified")
                    }
                }

                Text(organization.type.displayName)
                    .font(AMENFont.regular(13))
                    .foregroundStyle(Color.secondary)

                if let website = organization.website, !website.isEmpty,
                   let url = URL(string: website) {
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                                .font(.system(size: 11))
                            Text(website)
                                .font(AMENFont.regular(12))
                                .lineLimit(1)
                        }
                        .foregroundStyle(AmenTheme.Colors.amenBlue)
                    }
                    .accessibilityLabel("Visit website")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .orgIdentityGlassCard()
        .accessibilityElement(children: .combine)
    }

    // MARK: - Claim CTA

    private var claimCTACard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Is this your organization?")
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(Color.primary)
                Text("Claim this listing to manage your profile, add events, and connect with your community.")
                    .font(AMENFont.regular(13))
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    // Claim flow — coordinated by parent view
                } label: {
                    Text("Claim this listing")
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(Color(.systemBackground))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous).fill(AmenTheme.Colors.amenGold)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .amenGlassEffect(AmenTheme.Colors.amenGold.opacity(0.08), cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(UIColor.separator).opacity(0.3), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Spaces Preview

    private var spacesPreviewCard: some View {
        moduleRow(
            icon: "square.stack.3d.up",
            iconTint: AmenTheme.Colors.amenPurple,
            title: "Spaces",
            subtitle: "Join or create a Space connected to this organization."
        )
    }

    // MARK: - Events Preview

    private var eventsPreviewCard: some View {
        moduleRow(
            icon: "calendar",
            iconTint: AmenTheme.Colors.amenBlue,
            title: "Events",
            subtitle: "Upcoming gatherings, RSVP moments, and community activities."
        )
    }

    // MARK: - School Notes Preview

    private var schoolNotesCard: some View {
        moduleRow(
            icon: "note.text",
            iconTint: AmenTheme.Colors.amenBlue,
            title: "Study Notes",
            subtitle: "Class, chapel, cohort, and study notes using the shared Smart Notes engine."
        )
    }

    // MARK: - Smart Notes Preview

    private var smartNotesCard: some View {
        moduleRow(
            icon: "book.fill",
            iconTint: AmenTheme.Colors.amenGold,
            title: "Church Notes",
            subtitle: "Shared study, sermon, meeting, and event notes."
        )
    }

    // MARK: - Media Preview

    private var mediaPreviewCard: some View {
        moduleRow(
            icon: "play.rectangle.fill",
            iconTint: AmenTheme.Colors.amenPurple,
            title: "Media",
            subtitle: "Sermons, clips, classes, and public media."
        )
    }

    // MARK: - Admin Tools

    private var adminToolsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(AmenTheme.Colors.amenGold.opacity(0.12)))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Manage Organization")
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(Color.primary)
                    Text("Roles, moderation, banner controls, analytics, and paid workspace tools.")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.5))
            }

            if isOwner && organization.claimStatus.allowsOfficialControls {
                adminToolsBillingRow
            }
        }
        .padding(14)
        .orgIdentityGlassCard()
        .sheet(isPresented: $showUpgradeSheet) {
            AmenOrgUpgradeSheet(organization: organization)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Manage Organization")
    }

    @ViewBuilder
    private var adminToolsBillingRow: some View {
        let tier = organization.billing?.tier ?? .free
        Divider().padding(.vertical, 10)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Current Plan")
                    .font(AMENFont.regular(11))
                    .foregroundStyle(Color.secondary)
                Text("\(tier.displayName) · \(tier.monthlyPrice)")
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(Color.primary)
            }
            Spacer(minLength: 0)
            adminPlanButton(tier: tier)
        }
    }

    @ViewBuilder
    private func adminPlanButton(tier: AmenOrganizationBillingPlan) -> some View {
        let label = tier == .free ? "Upgrade Plan" : "Manage Plan"
        let fill = tier == .free ? AmenTheme.Colors.amenGold : AmenTheme.Colors.amenPurple
        Button { showUpgradeSheet = true } label: {
            Text(label)
                .font(AMENFont.semiBold(13))
                .foregroundStyle(Color(.systemBackground))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule(style: .continuous).fill(fill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Private Fit Reason

    private var privateFitCard: some View {
        moduleRow(
            icon: "wand.and.stars",
            iconTint: AmenTheme.Colors.amenPurple,
            title: "Why This May Fit You",
            subtitle: "Private AI reasoning based on your intent and public organization signals."
        )
    }

    // MARK: - Giving

    private var givingCard: some View {
        moduleRow(
            icon: "heart.fill",
            iconTint: AmenTheme.Colors.amenGold,
            title: "Giving",
            subtitle: "Support this organization through tithes, offerings, and donations."
        )
    }

    // MARK: - Analytics

    private var analyticsCard: some View {
        moduleRow(
            icon: "chart.bar.fill",
            iconTint: AmenTheme.Colors.amenBlue,
            title: "Analytics",
            subtitle: "Audience insights, content performance, and community health metrics."
        )
    }

    // MARK: - Safety Footer

    private var safetyFooterCard: some View {
        HStack(spacing: 0) {
            Spacer()
            Button("Community Guidelines") { }
                .font(AMENFont.regular(12))
                .foregroundStyle(Color.secondary)
                .buttonStyle(.plain)
            Text(" · ")
                .font(AMENFont.regular(12))
                .foregroundStyle(Color.secondary)
            Button("Report an Issue") { }
                .font(AMENFont.regular(12))
                .foregroundStyle(Color.secondary)
                .buttonStyle(.plain)
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Shared Row Helper

    private func moduleRow(icon: String, iconTint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(iconTint)
                .frame(width: 36, height: 36)
                .background(Circle().fill(iconTint.opacity(0.12)))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(Color.primary)
                Text(subtitle)
                    .font(AMENFont.regular(13))
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .orgIdentityGlassCard()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Glass Card Modifier

private extension View {
    func orgIdentityGlassCard() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(UIColor.separator).opacity(0.3), lineWidth: 0.5)
            )
    }
}

// MARK: - OrgOpsRun

struct OrgOpsRun: Identifiable, Codable {
    let id: String
    let job: String          // "nces_ccd_import", "irs_bmf_import", "algolia_sync", etc.
    let source: String
    let startedAt: Date
    var finishedAt: Date?
    var created: Int
    var updated: Int
    var skipped: Int
    var errors: [String]
    var dryRun: Bool
}
