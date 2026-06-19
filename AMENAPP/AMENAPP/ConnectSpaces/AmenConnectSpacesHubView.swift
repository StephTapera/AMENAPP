// AmenConnectSpacesHubView.swift
// AMEN Connect + Spaces — Top-level hub
//
// Entry point routed from the main tab bar (tab 6 — "Spaces").
// Three-tab layout: My Spaces | Discover | Creator Hub.
// Custom glass pill tab bar at top; no system TabView tab bar.
// Glass ONLY on section-header bars and card backgrounds.
// All scripture / message bodies remain matte.

import SwiftUI
import FirebaseAuth
import FirebaseAnalytics
import FirebaseFirestore

// MARK: - Live space model (My Spaces tab)

private struct ConnectSpace: Identifiable {
    let id: String
    let name: String
    let description: String
    let spaceType: String
    let memberCount: Int
    let isPrivate: Bool
}

private let previewVideos: [AmenConnectSpacesConnectVideo] = [
    AmenConnectSpacesConnectVideo(
        id: "video-1",
        provenance: AmenConnectSpacesVideoProvenance(
            humanRecorded: true,
            aiEdited: false,
            aiGenerated: false,
            synthVoice: false,
            synthFace: false,
            deepfakeRisk: 0.0,
            verifiedOriginal: true
        ),
        teacherId: "pastor_james",
        transcriptRef: "transcripts/v1",
        claims: [],
        scriptureRefs: [],
        sponsored: false,
        createdAt: Date(),
        updatedAt: Date()
    ),
    AmenConnectSpacesConnectVideo(
        id: "video-2",
        provenance: AmenConnectSpacesVideoProvenance(
            humanRecorded: true,
            aiEdited: false,
            aiGenerated: false,
            synthVoice: false,
            synthFace: false,
            deepfakeRisk: 0.0,
            verifiedOriginal: true
        ),
        teacherId: "pastor_anna",
        transcriptRef: "transcripts/v2",
        claims: [],
        scriptureRefs: [],
        sponsored: false,
        createdAt: Date(),
        updatedAt: Date()
    )
]

// MARK: - Room type icon helper

private func roomTypeIcon(_ type: AmenConnectSpacesRoomType) -> String {
    switch type {
    case .smallGroup:      return "person.3"
    case .prayer:          return "hands.sparkles"
    case .worship:         return "music.note"
    case .missions:        return "globe.americas"
    case .staff:           return "briefcase"
    case .cohort:          return "square.grid.2x2"
    case .accountability:  return "shield.lefthalf.filled"
    }
}

// MARK: - Tab definitions

private let tabLabels = ["My Spaces", "Discover", "Creator Hub", "Hub"]
private let tabIcons  = ["person.3", "safari", "sparkles", "tray.full"]

// MARK: - Hub View

struct AmenConnectSpacesHubView: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var flags = AMENFeatureFlags.shared
    @State private var showCreateSpace = false
    @State private var selectedTab: Int = 0
    @State private var showYouMenu: Bool = false
    @State private var showPresencePicker: Bool = false
    @State private var showVolunteerHub: Bool = false
    // Smart Volunteer Board entry — standalone flag module (default OFF), independent of AMENFeatureFlags.
    @ObservedObject private var volunteerFlags = VolunteerFlagService.shared

    // My Spaces — live Firestore state
    @State private var mySpaces: [ConnectSpace] = []
    @State private var isLoadingSpaces: Bool = false
    @State private var spacesLoadError: String? = nil

    private var currentUserId: String {
        Auth.auth().currentUser?.uid ?? ""
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Matte background — never glass on the page canvas
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    topTabBar
                    tabContent
                }
            }
            .navigationTitle("Spaces & Connect")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                            selectedTab = 2
                        }
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.systemScaled(16, weight: .semibold))
                    }
                    .accessibilityLabel("Open Creator Hub")
                }

                if flags.connectYouMenuEnabled {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showYouMenu = true
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: "6E4BB5").opacity(0.20))
                                    .frame(width: 30, height: 30)
                                Text(Auth.auth().currentUser?.displayName?.prefix(1).uppercased() ?? "U")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color(hex: "6E4BB5"))
                            }
                        }
                        .accessibilityLabel("Your profile and presence")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreateSpace = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.systemScaled(16, weight: .semibold))
                    }
                    .accessibilityLabel("Create a new Space")
                }

                if volunteerFlags.isEnabled(.scheduling) {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showVolunteerHub = true
                        } label: {
                            Image(systemName: "calendar.badge.checkmark")
                                .font(.systemScaled(16, weight: .semibold))
                        }
                        .accessibilityLabel("Volunteer scheduling")
                    }
                }
            }
            .sheet(isPresented: $showCreateSpace, onDismiss: { Task { await loadMySpaces() } }) {
                AmenCreateSpaceEnhancedSheet(
                    userId: currentUserId,
                    onDismiss: { showCreateSpace = false },
                    onCreated: { _ in showCreateSpace = false }
                )
            }
            .sheet(isPresented: $showYouMenu) {
                AmenYouMenuSheet(showPresencePicker: $showPresencePicker)
            }
            .sheet(isPresented: $showPresencePicker) {
                AmenSpiritualPresencePickerView()
            }
            .sheet(isPresented: $showVolunteerHub) {
                VolunteerHubView(currentUserId: currentUserId)
            }
            .onAppear {
                Analytics.logEvent("spaces_hub_viewed", parameters: [:])
                Task { await loadMySpaces() }
            }
        }
    }

    // MARK: - Custom glass pill tab bar

    private var topTabBar: some View {
        HStack(spacing: 0) {
            ForEach(tabLabels.indices, id: \.self) { index in
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        selectedTab = index
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tabIcons[index])
                            .font(.systemScaled(12, weight: selectedTab == index ? .bold : .medium))
                        Text(tabLabels[index])
                            .font(.systemScaled(13, weight: selectedTab == index ? .bold : .medium))
                    }
                    .foregroundStyle(
                        selectedTab == index
                            ? Color(hex: "D9A441")
                            : Color.secondary
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tabLabels[index])
                .accessibilityAddTraits(selectedTab == index ? [.isSelected] : [])
            }
        }
        .amenGlassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Tab content switcher

    @ViewBuilder
    private var tabContent: some View {
        ZStack {
            if selectedTab == 0 {
                mySpacesTab
                    .transition(.opacity)
            } else if selectedTab == 1 {
                AmenSpaceDiscoveryView()
                    .transition(.opacity)
            } else if selectedTab == 2 {
                AmenCreatorHubTabView(userId: currentUserId)
                    .transition(.opacity)
            } else if flags.connectHubEnabled {
                AmenHubFeedView(isEmbedded: true)
                    .transition(.opacity)
            } else {
                mySpacesTab
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: selectedTab)
    }

    // MARK: - Tab 0: My Spaces

    private var mySpacesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // MARK: Ministry Spaces section
                sectionHeader(
                    title: "Ministry Spaces",
                    foreground: Color(hex: "D9A441")
                )

                if isLoadingSpaces {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, 32)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                } else if let error = spacesLoadError {
                    Text(error)
                        .font(.systemScaled(13))
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 24)
                } else if mySpaces.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.3")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(Color(hex: "D9A441").opacity(0.60))
                        Text("No spaces yet")
                            .font(.systemScaled(15, weight: .semibold))
                            .foregroundStyle(Color.primary)
                        Text("Create your first space to gather your community.")
                            .font(.systemScaled(13))
                            .foregroundStyle(Color.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            showCreateSpace = true
                        } label: {
                            Text("Create your first space")
                                .font(.systemScaled(14, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background {
                                    Capsule(style: .continuous)
                                        .fill(Color(hex: "D9A441"))
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Create your first space")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 24)
                } else {
                    VStack(spacing: 12) {
                        ForEach(mySpaces) { space in
                            // A-014: Space cards in My Spaces are tappable — push to detail view.
                            NavigationLink(destination: AmenSpaceDetailView(
                                space: AmenConnectSpacesSpace(
                                    id: space.id,
                                    name: space.name,
                                    type: AmenConnectSpacesRoomType(rawValue: space.spaceType) ?? .smallGroup,
                                    memberIds: Array(repeating: "", count: space.memberCount),
                                    careSensitivity: space.isPrivate,
                                    createdBy: currentUserId,
                                    createdAt: Date(),
                                    updatedAt: Date()
                                ),
                                events: [],
                                tiers: [],
                                hostProfile: nil
                            )) {
                                LiveSpaceCardRow(space: space)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // MARK: Connect Teaching section
                sectionHeader(
                    title: "Connect — Teaching",
                    foreground: Color(hex: "6E4BB5")
                )

                VStack(spacing: 12) {
                    ForEach(previewVideos) { video in
                        NavigationLink(destination: AmenConnectPlayerView(video: video)) {
                            VideoCardRow(video: video)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Teaching by \(video.teacherId), tap to play")
                    }
                }
                .padding(.horizontal, 16)

                // Bottom breathing room above floating tab bar
                Spacer(minLength: 100)
            }
            .padding(.top, 16)
        }
    }

    // MARK: - Section header bar (glass pill)

    @ViewBuilder
    private func sectionHeader(title: String, foreground: Color) -> some View {
        Text(title.uppercased())
            .font(.systemScaled(11, weight: .bold))
            .kerning(1.2)
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .amenGlassEffect(in: Capsule())
            .padding(.horizontal, 16)
    }

    // MARK: - Firestore loader — My Spaces

    @MainActor
    private func loadMySpaces() async {
        guard !currentUserId.isEmpty else { return }
        isLoadingSpaces = true
        spacesLoadError = nil
        do {
            let db = Firestore.firestore()

            // A-013: Query both created spaces AND joined spaces via spaceMemberships.
            // Step 1 — spaces where this user is the creator.
            async let createdSnapshot = db
                .collection("spaces")
                .whereField("creatorUid", isEqualTo: currentUserId)
                .order(by: "createdAt", descending: true)
                .getDocuments()

            // Step 2 — space IDs from the memberships sub-collection.
            async let membershipSnapshot = db
                .collection("spaceMemberships")
                .whereField("userId", isEqualTo: currentUserId)
                .getDocuments()

            let (created, memberships) = try await (createdSnapshot, membershipSnapshot)

            // Gather all unique space IDs (joined spaces not already in created set).
            var seenIds = Set(created.documents.map { $0.documentID })
            let joinedSpaceIds = memberships.documents.compactMap { doc -> String? in
                guard let spaceId = doc.data()["spaceId"] as? String,
                      !seenIds.contains(spaceId) else { return nil }
                return spaceId
            }

            // Helper to map a Firestore data dict + document ID to ConnectSpace.
            func toConnectSpace(id: String, data: [String: Any]) -> ConnectSpace? {
                guard let name = data["name"] as? String else { return nil }
                return ConnectSpace(
                    id: id,
                    name: name,
                    description: data["description"] as? String ?? "",
                    spaceType: data["spaceType"] as? String ?? "",
                    memberCount: data["memberCount"] as? Int ?? 0,
                    isPrivate: data["isPrivate"] as? Bool ?? false
                )
            }

            var result: [ConnectSpace] = created.documents.compactMap { toConnectSpace(id: $0.documentID, data: $0.data()) }

            // Step 3 — fetch each joined space document individually (avoids Firestore "in" 30-item limit).
            if !joinedSpaceIds.isEmpty {
                for spaceId in joinedSpaceIds {
                    seenIds.insert(spaceId)
                    let doc = try await db.collection("spaces").document(spaceId).getDocument()
                    if doc.exists, let data = doc.data(), let space = toConnectSpace(id: doc.documentID, data: data) {
                        result.append(space)
                    }
                }
            }

            mySpaces = result
        } catch {
            spacesLoadError = "Couldn't load your spaces. Pull down to retry."
        }
        isLoadingSpaces = false
    }
}

// MARK: - Live space card row (real Firestore data)

private func liveSpaceTypeIcon(_ spaceType: String) -> String {
    switch spaceType {
    case "smallGroup":       return "person.3"
    case "prayer", "bibleStudy": return "hands.sparkles"
    case "worship":          return "music.note"
    case "church":           return "building.columns"
    case "campusMinistry":   return "graduationcap"
    case "missions":         return "globe.americas"
    case "podcast":          return "mic"
    case "bookClub":         return "books.vertical"
    case "mensMinistry", "mensMinistrry": return "figure.strengthtraining.traditional"
    case "womensMinistry":   return "figure.mind.and.body"
    default:                 return "person.3"
    }
}

private struct LiveSpaceCardRow: View {
    let space: ConnectSpace

    var body: some View {
        HStack(spacing: 14) {

            // Space type icon in a glass circle
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Circle()
                            .strokeBorder(Color(hex: "D9A441").opacity(0.30), lineWidth: 0.5)
                    }
                    .frame(width: 44, height: 44)

                Image(systemName: liveSpaceTypeIcon(space.spaceType))
                    .font(.systemScaled(18, weight: .semibold))
                    .foregroundStyle(Color(hex: "D9A441"))
            }

            // Name + member count
            VStack(alignment: .leading, spacing: 4) {
                Text(space.name)
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 4) {
                    Image(systemName: "person.2")
                        .font(.systemScaled(11, weight: .regular))
                        .foregroundStyle(Color.secondary)
                    Text("\(space.memberCount) member\(space.memberCount == 1 ? "" : "s")")
                        .font(.systemScaled(12))
                        .foregroundStyle(Color.secondary)

                    if space.isPrivate {
                        Image(systemName: "lock.fill")
                            .font(.systemScaled(10))
                            .foregroundStyle(Color(hex: "D9A441").opacity(0.70))
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.systemScaled(12, weight: .semibold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(.separator).opacity(0.22), lineWidth: 0.5)
                }
        }
        .accessibilityLabel("\(space.name), \(space.memberCount) member\(space.memberCount == 1 ? "" : "s")\(space.isPrivate ? ", private" : "")")
    }
}

// MARK: - Space card row (used by AmenMinistryRoomShellView navigation links)

private struct SpaceCardRow: View {
    let space: AmenConnectSpacesSpace

    var body: some View {
        HStack(spacing: 14) {

            // Room type icon in a glass circle
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Circle()
                            .strokeBorder(Color(hex: "D9A441").opacity(0.30), lineWidth: 0.5)
                    }
                    .frame(width: 44, height: 44)

                Image(systemName: roomTypeIcon(space.type))
                    .font(.systemScaled(18, weight: .semibold))
                    .foregroundStyle(Color(hex: "D9A441"))
            }

            // Name + member count
            VStack(alignment: .leading, spacing: 4) {
                Text(space.name)
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 4) {
                    Image(systemName: "person.2")
                        .font(.systemScaled(11, weight: .regular))
                        .foregroundStyle(Color.secondary)
                    Text("\(space.memberIds.count) members")
                        .font(.systemScaled(12))
                        .foregroundStyle(Color.secondary)

                    if space.careSensitivity {
                        // Privacy indicator for sensitive rooms
                        Image(systemName: "lock.fill")
                            .font(.systemScaled(10))
                            .foregroundStyle(Color(hex: "D9A441").opacity(0.70))
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.systemScaled(12, weight: .semibold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(.separator).opacity(0.22), lineWidth: 0.5)
                }
        }
        .accessibilityLabel("\(space.name), \(space.memberIds.count) member\(space.memberIds.count == 1 ? "" : "s")\(space.careSensitivity ? ", private" : "")")
    }
}

// MARK: - Video card row

private struct VideoCardRow: View {
    let video: AmenConnectSpacesConnectVideo

    var body: some View {
        HStack(spacing: 14) {

            // Play icon in a glass circle
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Circle()
                            .strokeBorder(Color(hex: "6E4BB5").opacity(0.30), lineWidth: 0.5)
                    }
                    .frame(width: 44, height: 44)

                Image(systemName: "play.fill")
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundStyle(Color(hex: "6E4BB5"))
                    .offset(x: 1) // optical center correction for play triangle
            }

            // Teacher name + provenance badge
            VStack(alignment: .leading, spacing: 6) {
                Text("Teaching by \(video.teacherId)")
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)

                // Non-removable provenance badge (Aegis: syntheticMediaLabelsNonRemovable)
                AmenSyntheticMediaLabelView(provenance: video.provenance)
                    .scaleEffect(0.90, anchor: .leading)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.systemScaled(12, weight: .semibold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(.separator).opacity(0.22), lineWidth: 0.5)
                }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    AmenConnectSpacesHubView()
}
#endif
