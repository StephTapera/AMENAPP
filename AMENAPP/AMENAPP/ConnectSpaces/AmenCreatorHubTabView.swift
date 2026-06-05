// AmenCreatorHubTabView.swift
// AMEN ConnectSpaces — Creator Hub tab: earnings snapshot, space management,
// quick actions, verification banner, and legal resource links.
//
// Glass rule: section cards use .ultraThinMaterial chrome; body text, prayer
//             content, and document bodies stay matte. No glass-on-glass.
// Host-only intent: shown to all users; non-verified users see "Become a Creator"
//             prompt but can still browse the resources section.
// Written: 2026-06-03

import SwiftUI
import FirebaseAuth

// MARK: - Stub space model for Creator Hub

private struct CreatorHubSpace: Identifiable {
    let id: String
    let name: String
    let type: AmenCreatorSpaceType
    let memberCount: Int
}

private let stubCreatorSpaces: [CreatorHubSpace] = [
    CreatorHubSpace(id: "my-space-1", name: "Faith & Hustle Podcast",  type: .podcast,    memberCount: 312),
    CreatorHubSpace(id: "my-space-2", name: "Men's Discipleship Circle", type: .smallGroup, memberCount: 47)
]

// MARK: - Quick action model

private struct CreatorQuickAction: Identifiable {
    let id: String
    let icon: String
    let label: String
}

private let quickActions: [CreatorQuickAction] = [
    CreatorQuickAction(id: "event",       icon: "calendar.badge.plus",   label: "New Event"),
    CreatorQuickAction(id: "broadcast",   icon: "dot.radiowaves.right",  label: "Broadcast"),
    CreatorQuickAction(id: "gift",        icon: "gift.fill",             label: "Gift Membership"),
    CreatorQuickAction(id: "discovery",   icon: "slider.horizontal.3",  label: "Discovery Settings")
]

// MARK: - Creator Hub Tab View

struct AmenCreatorHubTabView: View {

    var userId: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Sheet presentation state
    @State private var showEventComposer: Bool = false
    @State private var showBroadcast: Bool = false
    @State private var showGiftMembership: Bool = false
    @State private var showDiscoverySettings: Bool = false

    // Navigation destination state
    @State private var earningsDashboardTarget: CreatorHubSpace? = nil
    @State private var managerTarget: CreatorHubSpace? = nil

    // Verification alert
    @State private var showVerificationAlert: Bool = false

    // Legal sheet state
    @State private var legalDocumentTarget: AmenLegalDocumentType? = nil

    private var firstSpaceId: String {
        stubCreatorSpaces.first?.id ?? "my-space-1"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                earningsSnapshotCard
                mySpacesSection
                quickActionsRow
                verificationBanner
                creatorResourcesSection
                Spacer(minLength: 100)
            }
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        // MARK: Sheets
        .sheet(isPresented: $showEventComposer) {
            AmenSmartEventComposerView()
        }
        .sheet(isPresented: $showBroadcast) {
            AmenEventBroadcastView()
        }
        .sheet(isPresented: $showGiftMembership) {
            AmenGiftMembershipView()
        }
        .sheet(isPresented: $showDiscoverySettings) {
            discoverySettingsPlaceholder
        }
        .sheet(item: $legalDocumentTarget) { docType in
            NavigationStack {
                AmenCreatorLegalOS(
                    documentType: docType,
                    userId: userId,
                    requiresAcceptance: false,
                    onAccepted: nil,
                    onDismiss: { legalDocumentTarget = nil }
                )
            }
        }
        .sheet(item: $earningsDashboardTarget) { space in
            NavigationStack {
                AmenCreatorEarningsDashboard(
                    spaceId: space.id,
                    hostUserId: userId
                )
            }
        }
        .sheet(item: $managerTarget) { space in
            AmenCommunityAIManagerView(
                spaceId: space.id,
                spaceName: space.name
            )
        }
        .alert("Verification Submitted", isPresented: $showVerificationAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your verification application has been submitted. We'll review it and follow up via email.")
        }
    }

    // MARK: - 1. Earnings Snapshot Card

    private var earningsSnapshotCard: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Header row
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(hex: "D9A441").opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: "banknote.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "D9A441"))
                }
                .accessibilityHidden(true)

                Text("Earnings")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .textCase(.uppercase)
                    .kerning(0.7)
                    .accessibilityAddTraits(.isHeader)

                Spacer()
            }

            // This Month number
            VStack(alignment: .leading, spacing: 2) {
                Text("This Month")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .textCase(.uppercase)
                    .kerning(0.5)
                Text("$247")
                    .font(.system(size: 38, weight: .black))
                    .foregroundStyle(Color(hex: "D9A441"))
                    .accessibilityLabel("This month earnings: $247")
            }

            Divider().overlay(Color.white.opacity(0.10))

            // Pending payout row
            HStack(spacing: 8) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pending Payout")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.45))
                    Text("$189")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.white)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Pending payout: $189")

                Spacer()

                // View Full Dashboard button
                Button {
                    if let first = stubCreatorSpaces.first {
                        earningsDashboardTarget = first
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("View Full Dashboard")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Color(hex: "D9A441"))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View full earnings dashboard")
                .frame(minHeight: 44)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(hex: "D9A441").opacity(0.35), lineWidth: 1)
                }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - 2. My Spaces Section

    private var mySpacesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionPill(title: "My Spaces", accent: Color(hex: "D9A441"))

            VStack(spacing: 10) {
                ForEach(stubCreatorSpaces) { space in
                    spaceManagementCard(space: space)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func spaceManagementCard(_ space: CreatorHubSpace) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Name + type badge row
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Circle()
                                .strokeBorder(space.type.accentColor.opacity(0.35), lineWidth: 0.5)
                        }
                        .frame(width: 40, height: 40)
                    Image(systemName: space.type.systemIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(space.type.accentColor)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(space.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        // Type badge
                        Text(space.type.displayName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(space.type.accentColor.opacity(0.85))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(space.type.accentColor.opacity(0.12))
                            }

                        // Member count (muted, private metric)
                        Image(systemName: "person.2")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.35))
                            .accessibilityHidden(true)
                        Text("\(space.memberCount)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.35))
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(space.name), \(space.type.displayName), \(space.memberCount) members")

                Spacer()
            }

            // Action buttons row
            HStack(spacing: 8) {
                // Manage button
                Button {
                    managerTarget = space
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Manage")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color(hex: "6E4BB5"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color(hex: "6E4BB5").opacity(0.14))
                            .overlay {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(Color(hex: "6E4BB5").opacity(0.40), lineWidth: 0.5)
                            }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Manage \(space.name)")
                .frame(minHeight: 44)

                // Earnings button
                Button {
                    earningsDashboardTarget = space
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "banknote")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Earnings")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color(hex: "D9A441"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color(hex: "D9A441").opacity(0.12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(Color(hex: "D9A441").opacity(0.35), lineWidth: 0.5)
                            }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View earnings for \(space.name)")
                .frame(minHeight: 44)
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                }
        }
    }

    // MARK: - 3. Quick Actions Row

    private var quickActionsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionPill(title: "Quick Actions", accent: Color(hex: "6E4BB5"))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(quickActions) { action in
                        quickActionChip(action)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }

    private func quickActionChip(_ action: CreatorQuickAction) -> some View {
        Button {
            handleCreatorQuickAction(action.id)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: action.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: "D9A441"))
                Text(action.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.80))
                    .lineLimit(1)
            }
            .frame(minWidth: 80, minHeight: 44)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.label)
    }

    private func handleCreatorQuickAction(_ id: String) {
        switch id {
        case "event":
            showEventComposer = true
        case "broadcast":
            showBroadcast = true
        case "gift":
            showGiftMembership = true
        case "discovery":
            showDiscoverySettings = true
        default:
            break
        }
    }

    // MARK: - 4. Verification Banner

    private var verificationBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(hex: "D9A441").opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(hex: "D9A441"))
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Become a Verified Creator")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)

                    Text("Get verified to unlock premium features.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.60))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)
            }

            Button {
                showVerificationAlert = true
            } label: {
                Text("Apply")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: "070607"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(hex: "D9A441"))
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Apply for creator verification")
            .frame(minHeight: 44)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(hex: "D9A441").opacity(0.35), lineWidth: 1)
                }
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Become a Verified Creator. Get verified to unlock premium features.")
    }

    // MARK: - 5. Creator Resources Section

    private var creatorResourcesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionPill(title: "Creator Resources", accent: Color.white.opacity(0.45))

            VStack(spacing: 8) {
                legalResourceCard(
                    title: "Community Standards",
                    docType: .communityStandards
                )
                legalResourceCard(
                    title: "Revenue Share Terms",
                    docType: .revenueShareTerms
                )
                legalResourceCard(
                    title: "Creator Agreement",
                    docType: .creatorAgreement
                )
            }
            .padding(.horizontal, 16)
        }
    }

    private func legalResourceCard(title: String, docType: AmenLegalDocumentType) -> some View {
        Button {
            legalDocumentTarget = docType
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .frame(width: 24)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))

                Spacer()

                // Version badge
                Text("v\(docType.version)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.07))
                    }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.25))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), version \(docType.version)")
        .accessibilityHint("Tap to read \(title)")
        .frame(minHeight: 44)
    }

    // MARK: - Discovery Settings Placeholder Sheet

    private var discoverySettingsPlaceholder: some View {
        NavigationStack {
            ZStack {
                Color(hex: "070607").ignoresSafeArea()

                VStack(spacing: 16) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(Color(hex: "D9A441").opacity(0.60))
                        .accessibilityHidden(true)

                    Text("Discovery Settings")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.white)

                    Text("Control how your spaces appear in discovery results.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    // TODO: Wire real discovery settings endpoint when available
                    Text("Coming soon")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: "D9A441").opacity(0.70))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background {
                            Capsule(style: .continuous)
                                .fill(Color(hex: "D9A441").opacity(0.12))
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Discovery Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { showDiscoverySettings = false }
                        .foregroundStyle(Color(hex: "D9A441"))
                }
            }
        }
    }

    // MARK: - Shared: Section pill header

    @ViewBuilder
    private func sectionPill(title: String, accent: Color) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .kerning(1.1)
            .foregroundStyle(accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(accent.opacity(0.25), lineWidth: 0.5)
                    }
            }
            .padding(.horizontal, 16)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(title)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ZStack {
        Color(hex: "070607").ignoresSafeArea()
        AmenCreatorHubTabView(userId: "preview-user")
    }
    .preferredColorScheme(.dark)
}
#endif
