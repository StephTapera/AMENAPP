// AmenChurchProfileView.swift
// AMEN Community OS — Church OS (Phase 3 / Agent A8)
//
// Main church profile: full-bleed photo hero + Liquid Glass action pills + segmented tabs.
// Co-exists with AmenChurchHubView (Spiritual OS media hub); this is the canonical
// Community OS profile surface.
//
// Tabs: Today's Services / Community / Notes / Events / Volunteer
//
// Design rules (C3):
//   - Page background: Color(uiColor: .systemGroupedBackground)
//   - Photo hero: large image, bottom gradient scrim, white text
//   - Action pills: Liquid Glass (.ultraThinMaterial + strokeBorder)
//   - Content cards: white + shadow(radius:16) + cornerRadius(20, style:.continuous)
//   - Accents: Color.accentColor only
//   - memberCount / followersCount: NEVER displayed
//   - Feature-gated by community_os_church_os_enabled (default false)

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - AmenChurchProfileView

struct AmenChurchProfileView: View {

    let churchId: String

    @AppStorage("community_os_church_os_enabled")
    private var featureEnabled: Bool = false

    @StateObject private var service = AmenChurchService()

    @State private var selectedTab = 0
    @State private var showVisitReadiness = false
    @State private var visitReadiness: VisitReadiness?
    @State private var isTogglingFollow = false
    @State private var isFollowing = false
    @State private var showGivingConfirmation = false
    @State private var showNewNote = false

    private let tabs = ["Today", "Community", "Notes", "Events", "Volunteer"]

    var body: some View {
        Group {
            if featureEnabled {
                profileContent
            } else {
                unavailablePlaceholder
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadAll() }
    }

    // MARK: - Unavailable placeholder

    private var unavailablePlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.columns")
                .font(.largeTitle)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
            Text("Church profiles are off")
                .font(.headline)
                .foregroundStyle(Color(uiColor: .label))
            Text("Enable Church OS in feature flags to load profile, service, notes, event, and volunteer data.")
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Main content

    private var profileContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroSection
                actionPillRow
                tabBar
                tabContent.padding(.top, 4)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Hero (320 pt)

    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { geo in
                Group {
                    if let urlStr = service.church?.coverImageUrl,
                       let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFill()
                                    .frame(width: geo.size.width, height: 320)
                                    .clipped()
                            } else {
                                heroFallback
                            }
                        }
                    } else {
                        heroFallback
                    }
                }
                .frame(width: geo.size.width, height: 320)
            }
            .frame(height: 320)

            // Bottom scrim
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.72)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(height: 320)

            // Text overlay
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                if service.isLoading && service.church == nil {
                    ProgressView().tint(.white).frame(height: 60).accessibilityHidden(true)
                } else if let church = service.church {
                    heroTextBlock(church: church)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(height: 320)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(service.church.map { "Church: \($0.name)" } ?? "Loading church")
    }

    private var heroFallback: some View {
        Color(uiColor: .secondarySystemBackground)
            .overlay(
                Image(systemName: "building.columns.fill")
                    .font(.systemScaled(60))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            )
    }

    @ViewBuilder
    private func heroTextBlock(church: ChurchOSProfile) -> some View {
        if let logoStr = church.logoUrl, let url = URL(string: logoStr) {
            AsyncImage(url: url) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFill()
                } else {
                    Color(uiColor: .secondarySystemBackground)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.40), lineWidth: 1.5)
            )
            .padding(.bottom, 8)
        }

        HStack(spacing: 8) {
            Text(church.name)
                .font(.systemScaled(26, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
            if church.isVerified {
                Image(systemName: "checkmark.seal.fill")
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Verified church")
            }
        }

        if let denomination = church.denomination {
            Text(denomination)
                .font(.systemScaled(14))
                .foregroundStyle(Color.white.opacity(0.78))
                .padding(.top, 2)
        }

        if let primary = church.campuses.first(where: { $0.isPrimary }) ?? church.campuses.first,
           !primary.city.isEmpty {
            Text("\(primary.city), \(primary.state)")
                .font(.systemScaled(12))
                .foregroundStyle(Color.white.opacity(0.55))
                .padding(.top, 2)
        }
    }

    // MARK: - Action Pill Row (Liquid Glass)

    private var actionPillRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                actionPill(
                    label: isFollowing ? "Following" : "Follow",
                    icon:  isFollowing ? "checkmark" : "plus",
                    tint:  isFollowing ? Color.accentColor : Color(uiColor: .label)
                ) { Task { await toggleFollow() } }
                .disabled(isTogglingFollow)

                actionPill(label: "Pray", icon: "hands.and.sparkles",
                           tint: Color(uiColor: .label)) {}

                actionPill(label: "Visit", icon: "mappin.and.ellipse",
                           tint: Color(uiColor: .label)) {
                    Task { await loadVisitReadiness() }
                    showVisitReadiness = true
                }

                if service.church?.givingEnabled == true {
                    actionPill(label: "Give", icon: "heart.circle",
                               tint: Color(uiColor: .label)) {
                        showGivingConfirmation = true
                    }
                    .confirmationDialog("Give to this church",
                                        isPresented: $showGivingConfirmation) {
                        if let ref = service.church?.givingPlatformRef,
                           let url = URL(string: ref) {
                            Button("Open Giving Page") { UIApplication.shared.open(url) }
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(Color(uiColor: .systemBackground))
        .sheet(isPresented: $showVisitReadiness) {
            if let vr = visitReadiness {
                ChurchVisitReadinessSheet(readiness: vr)
            }
        }
        .sheet(isPresented: $showNewNote) {
            ChurchNotesView()
        }
    }

    private func actionPill(label: String, icon: String, tint: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background {
                    Capsule(style: .continuous).fill(.ultraThinMaterial)
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(Color(uiColor: .separator).opacity(0.40),
                                              lineWidth: 0.75)
                        }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        VStack(spacing: 0) {
            Divider()
            Picker("Section", selection: $selectedTab) {
                ForEach(tabs.indices, id: \.self) { i in
                    Text(tabs[i]).tag(i)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
        }
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case 0: todayTab
        case 1: communityTab
        case 2: notesTab
        case 3: eventsTab
        case 4: volunteerTab
        default: EmptyView()
        }
    }

    // MARK: Tab 0: Today's Services

    private var todayTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            let services = service.church?.serviceTimesToday ?? []
            if services.isEmpty {
                tabEmptyState(icon: "calendar.badge.clock",
                              title: "No services today",
                              message: "Check back for upcoming service times.")
            } else {
                ForEach(services) { time in
                    ChurchAmenServiceTimeCard(serviceTime: time)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }

    // MARK: Tab 1: Community

    private var communityTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let church = service.church {
                ChurchObjectHub(churchId: church.id, churchName: church.name)
            } else {
                tabEmptyState(icon: "person.3",
                              title: "Community is off",
                              message: "Prayer requests and discussions will appear here.")
            }
        }
        .padding(.bottom, 32)
    }

    // MARK: Tab 2: Notes

    private var notesTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            if service.church?.churchNotesEnabled == true {
                HStack {
                    Text("Sermon Notes")
                        .font(.headline)
                        .foregroundStyle(Color(uiColor: .label))
                    Spacer()
                    Button("New Note") { showNewNote = true }
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("Create new sermon note")
                }
                .padding(.horizontal, 16)

                tabEmptyState(icon: "note.text",
                              title: "No notes yet",
                              message: "Start capturing what God is speaking to you.")
            } else {
                tabEmptyState(icon: "note.text",
                              title: "Church Notes unavailable",
                              message: "This church has not enabled sermon notes.")
            }
        }
        .padding(.bottom, 32)
    }

    // MARK: Tab 3: Events

    private var eventsTab: some View {
        VStack {
            tabEmptyState(icon: "calendar",
                          title: "No upcoming events",
                          message: "Events will appear here when scheduled.")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }

    // MARK: Tab 4: Volunteer

    private var volunteerTab: some View {
        VStack {
            tabEmptyState(icon: "heart.circle",
                          title: "No volunteer openings",
                          message: "Opportunities to serve will appear here.")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }

    private func tabEmptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.systemScaled(36))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
            Text(title)
                .font(.headline)
                .foregroundStyle(Color(uiColor: .label))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message)")
    }

    // MARK: - Data loading

    private func loadAll() async {
        do {
            try await service.fetchChurch(id: churchId)
            if let uid = Auth.auth().currentUser?.uid {
                await checkFollowStatus(userId: uid)
            }
        } catch {
            service.error = error.localizedDescription
        }
    }

    private func checkFollowStatus(userId: String) async {
        let doc = try? await Firestore.firestore()
            .collection("churchFollowers")
            .document(userId)
            .collection("churches")
            .document(churchId)
            .getDocument()
        let deleted = doc?.data()?["isDeleted"] as? Bool ?? true
        isFollowing = doc?.exists == true && !deleted
    }

    private func toggleFollow() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isTogglingFollow = true
        defer { isTogglingFollow = false }
        do {
            if isFollowing {
                try await service.unfollowChurch(churchId: churchId, userId: uid)
                isFollowing = false
            } else {
                try await service.followChurch(churchId: churchId, userId: uid)
                isFollowing = true
            }
        } catch {
            // Optimistic state preserved; silent failure acceptable per UX spec
        }
    }

    private func loadVisitReadiness() async {
        visitReadiness = try? await service.getVisitReadiness(churchId: churchId)
    }
}

// MARK: - ChurchAmenServiceTimeCard

private struct ChurchAmenServiceTimeCard: View {
    let serviceTime: AmenServiceTime

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "clock")
                .font(.systemScaled(18))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.10))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(serviceTime.startTime)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .label))

                HStack(spacing: 6) {
                    Text(serviceTime.location)
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    Text(serviceTime.serviceStyle.displayName)
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }

                if serviceTime.isOnline {
                    Label("Online available", systemImage: "globe")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                }
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 3)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Service at \(serviceTime.startTime), \(serviceTime.location), " +
            "\(serviceTime.serviceStyle.displayName) style." +
            (serviceTime.isOnline ? " Online streaming available." : "")
        )
    }
}

// MARK: - ChurchVisitReadinessSheet

private struct ChurchVisitReadinessSheet: View {
    let readiness: VisitReadiness
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let service = readiness.serviceTimeToday {
                        card(title: "Today's Service") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(service.startTime)
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(Color(uiColor: .label))
                                Text(service.location)
                                    .font(.subheadline)
                                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                            }
                        }
                    }

                    if !readiness.firstTimerTips.isEmpty {
                        card(title: "First-Timer Tips") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(readiness.firstTimerTips, id: \.self) { tip in
                                    Label(tip, systemImage: "checkmark.circle.fill")
                                        .font(.subheadline)
                                        .foregroundStyle(Color(uiColor: .label))
                                        .accessibilityLabel(tip)
                                }
                            }
                        }
                    }

                    if let parking = readiness.parkingInfo {
                        card(title: "Parking") {
                            Text(parking)
                                .font(.subheadline)
                                .foregroundStyle(Color(uiColor: .secondaryLabel))
                        }
                    }

                    card(title: "Childcare") {
                        Label(
                            readiness.childcareAvailable
                                ? "Childcare available"
                                : "No childcare listed — contact the church",
                            systemImage: readiness.childcareAvailable
                                ? "checkmark.circle.fill"
                                : "info.circle"
                        )
                        .font(.subheadline)
                        .foregroundStyle(Color(uiColor: .label))
                    }

                    if let a11y = readiness.accessibilityInfo {
                        card(title: "Accessibility") {
                            Text(a11y)
                                .font(.subheadline)
                                .foregroundStyle(Color(uiColor: .secondaryLabel))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Plan Your Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Close visit readiness sheet")
                }
            }
        }
    }

    private func card<Content: View>(title: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .textCase(.uppercase)
                .kerning(0.5)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
        )
    }
}

// MARK: - Preview

#Preview("Church Profile") {
    NavigationStack {
        AmenChurchProfileView(churchId: "preview_church_01")
    }
    .onAppear {
        UserDefaults.standard.set(true, forKey: "community_os_church_os_enabled")
    }
}
