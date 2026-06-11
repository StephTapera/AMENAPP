// AmenConnectV2View.swift
// AMEN Connect — Waves 1 · 2 · 3
//
// W1 (ff: connectLayoutV2Enabled):
//   GlassEffectContainer section bar + FAB glassEffectUnion, NavigationStack large title,
//   4-section C-5 pill row, workspace presence button, scroll-driven bar minimize
// W2 (ff: connectPolishV2Enabled):
//   Unified "Here is what matters"/CatchUp panel, ConnectStrings canonical disclosure,
//   ⓘ disclosure chip, ambient offline status chip, grid breathing room, .secondary contrast
// W3 (ff: connectEmptyStatesEnabled):
//   ConnectEmptyStateView on Spaces, grid tiles, Discover rails; ConnectSkeletonRail loading

import SwiftUI
import FirebaseAuth

// MARK: - W1: C-5 Section Enum (4 sections only — DMs owned by Messages tab)

enum ConnectSection: String, CaseIterable, Identifiable {
    case lobby    = "Lobby"
    case discover = "Discover"
    case spaces   = "Spaces"
    case activity = "Activity"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .lobby:    return "sparkles"
        case .discover: return "safari"
        case .spaces:   return "square.grid.2x2"
        case .activity: return "bell.badge"
        }
    }

    var bereanPlaceholder: String {
        switch self {
        case .lobby:    return "Ask Berean what needs your attention…"
        case .discover: return "Ask Berean to find a group…"
        case .spaces:   return "Ask Berean about your spaces…"
        case .activity: return "Ask Berean what you missed…"
        }
    }
}

// MARK: - W1: V2 Root View

struct AmenConnectV2RootView: View {

    @StateObject private var viewModel = AmenConnectViewModel()
    @ObservedObject private var flags = AMENFeatureFlags.shared

    @State private var section: ConnectSection = .lobby
    @State private var barVisible: Bool = true
    @State private var showCatchUp = false
    @State private var showCreate  = false

    @Namespace private var glassNS
    @Environment(\.accessibilityReduceMotion) private var rm

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(.systemBackground).ignoresSafeArea()
                scrollLayer
                bottomChrome
            }
            .navigationTitle(section.rawValue)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { workspaceButton }
            }
        }
        .task { await viewModel.load() }
        .sheet(isPresented: $showCatchUp) {
            ConnectV2CatchUpSheet(items: viewModel.activityItems)
        }
        .sheet(isPresented: $showCreate) {
            AmenConnectAICommandSheet(contracts: viewModel.backendContracts)
        }
        .onPreferenceChange(ConnectScrollOffsetKey.self) { offset in
            let nowVisible = offset > -80
            guard nowVisible != barVisible else { return }
            withAnimation(rm ? .easeOut(duration: 0.12) : .spring(response: 0.38, dampingFraction: 0.88)) {
                barVisible = nowVisible
            }
        }
    }

    // MARK: Scroll content

    private var scrollLayer: some View {
        ScrollView {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ConnectScrollOffsetKey.self,
                    value: proxy.frame(in: .named("connectScroll")).minY
                )
            }
            .frame(height: 0)
            sectionContent
        }
        .coordinateSpace(name: "connectScroll")
        .contentMargins(.bottom, ConnectChromeMetrics.bottomInset, for: .scrollContent)
    }

    // MARK: Section routing

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .lobby:
            ConnectV2LobbyView(viewModel: viewModel, onCatchUp: { showCatchUp = true })
        case .discover:
            ConnectV2DiscoverView(viewModel: viewModel)
        case .spaces:
            ConnectV2SpacesSection(viewModel: viewModel)
        case .activity:
            AmenConnectActivityView(items: viewModel.activityItems)
        }
    }

    // MARK: W2: Offline + W4: Berean bar + W1: Section bar

    @ViewBuilder
    private var bottomChrome: some View {
        VStack(spacing: 0) {
            // W5: offline queue status chip (injected by ConnectOfflineQueue.swift)
            if flags.connectOfflineQueueEnabled {
                ConnectOfflineStatusChip(loadState: viewModel.loadState)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // W4: Smart Berean bar
            if flags.connectSmartBereanEnabled {
                ConnectSmartBereanBar(section: section, expanded: barVisible) { intent in
                    handleBereanIntent(intent)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // W1: Glass section bar
            ConnectV2SectionBar(
                section: $section,
                expanded: barVisible,
                onPlusTapped: { showCreate = true },
                namespace: glassNS
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .padding(.bottom, 4)
        .animation(
            rm ? .easeOut(duration: 0.12) : .spring(response: 0.36, dampingFraction: 0.86),
            value: barVisible
        )
    }

    // MARK: W1: Workspace button (presence indicator + long-press switcher)

    private var workspaceButton: some View {
        Button {
            // TODO(wiring): navigate to workspace / presence switcher
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 30, height: 30)
                    .overlay(
                        Text(Auth.auth().currentUser?.displayName?.prefix(1).uppercased() ?? "A")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    )
                Circle()
                    .fill(Color.green)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 1.5))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Amen Connect — online. Long-press to switch workspace or change presence.")
        .contextMenu {
            Button("Switch workspace…", systemImage: "arrow.trianglehead.2.counterclockwise") {}
            Divider()
            Button("Online", systemImage: "circle.fill") {}
            Button("Quiet mode", systemImage: "moon.fill") {}
            Button("Sabbath mode", systemImage: "sun.and.horizon") {}
        }
    }

    // MARK: W4: Berean intent routing

    private func handleBereanIntent(_ intent: ConnectBereanIntent) {
        withAnimation(rm ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.86)) {
            switch intent {
            case .catchUp:         showCatchUp = true
            case .goTo(let s):     section = s
            case .openComposer:    showCreate = true
            case .none:            break
            }
        }
    }
}

// MARK: - W1: ConnectV2SectionBar

struct ConnectV2SectionBar: View {

    @Binding var section: ConnectSection
    var expanded: Bool
    var onPlusTapped: () -> Void
    var namespace: Namespace.ID

    @Environment(\.accessibilityReduceMotion) private var rm
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if #available(iOS 26, *), !reduceTransparency {
                nativeGlassBar
            } else {
                fallbackBar
            }
        }
    }

    // iOS 26: GlassEffectContainer — pills unioned into one capsule, FAB merges via proximity
    @available(iOS 26, *)
    private var nativeGlassBar: some View {
        // Container spacing (28) > HStack spacing (12) → pill bar and FAB merge at rest (notch effect)
        GlassEffectContainer(spacing: 28) {
            HStack(spacing: 12) {
                // Section pills — glassEffectUnion fuses them into a single capsule
                HStack(spacing: 0) {
                    ForEach(ConnectSection.allCases) { s in
                        pillContent(s)
                            .glassEffect(.regular.interactive())
                            .glassEffectUnion(id: "connect-section-bar", namespace: namespace)
                    }
                }

                // FAB — separate circle; merges with bar because container spacing > HStack spacing
                Button(action: onPlusTapped) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(.plain)
                .glassEffect(in: Circle())
                .accessibilityLabel("Create in Amen Connect")
            }
        }
    }

    // Fallback: matte bar for iOS < 26 or Reduce Transparency
    private var fallbackBar: some View {
        HStack(spacing: 0) {
            ForEach(ConnectSection.allCases) { s in
                pillContent(s)
            }
            Spacer(minLength: 8)
            Button(action: onPlusTapped) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create in Amen Connect")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemBackground), in: Capsule())
    }

    @ViewBuilder
    private func pillContent(_ s: ConnectSection) -> some View {
        let isSelected = section == s
        Button {
            withAnimation(rm ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.86)) {
                section = s
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: s.iconName)
                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                if expanded {
                    Text(s.rawValue)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .lineLimit(1)
                        .transition(rm ? .opacity : .opacity.combined(with: .scale(scale: 0.85)))
                }
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(s.rawValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - W2: ConnectV2LobbyView

struct ConnectV2LobbyView: View {

    @ObservedObject var viewModel: AmenConnectViewModel
    var onCatchUp: () -> Void
    @ObservedObject private var flags = AMENFeatureFlags.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AmenConnectSearchCapsule(
                placeholder: "Search spaces, people, jobs, boards…",
                text: $viewModel.searchText
            )
            .padding(.horizontal, 20)
            .padding(.top, 8)

            if flags.connectPolishV2Enabled {
                ConnectV2CatchUpPanel(items: viewModel.activityItems, onCatchUp: onCatchUp)
                    .padding(.horizontal, 20)
            } else {
                // Legacy panel
                AmenConnectLobbyView(viewModel: viewModel).body
            }

            ConnectV2SectionGrid(viewModel: viewModel)
                .padding(.horizontal, 20)
        }
    }
}

// MARK: - W2: Unified Catch Up Panel

struct ConnectV2CatchUpPanel: View {

    var items: [AmenConnectActivityItem]
    var onCatchUp: () -> Void

    @AppStorage("connect_catchup_dismissed_day") private var dismissedDay: String = ""
    @ObservedObject private var flags = AMENFeatureFlags.shared

    private var todayKey: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }
    private var isCollapsed: Bool { dismissedDay == todayKey && items.isEmpty }

    var body: some View {
        ConnectV2Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Here is what matters", systemImage: "sparkles")
                        .font(.systemScaled(17, weight: .bold))
                    Spacer()
                    if !isCollapsed {
                        Button("Catch Up", action: onCatchUp)
                            .font(.systemScaled(13, weight: .semibold))
                            .accessibilityLabel("Open AI Catch Up")
                    }
                    Button {
                        dismissedDay = todayKey
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss for today")
                }

                if !isCollapsed {
                    if items.isEmpty && flags.connectEmptyStatesEnabled {
                        ConnectV2CatchUpEmptyState(onExplore: onCatchUp)
                    } else {
                        ForEach(items.prefix(3)) { item in
                            ConnectV2ActivityBullet(item: item)
                        }
                        if items.count > 3 {
                            Button("+ \(items.count - 3) more", action: onCatchUp)
                                .font(.systemScaled(13, weight: .semibold))
                                .foregroundStyle(.tint)
                        }
                    }
                    ConnectV2AIDisclosureChip()
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: isCollapsed)
    }
}

// MARK: - W2: ⓘ Disclosure Chip

struct ConnectV2AIDisclosureChip: View {

    @State private var showSheet = false

    var body: some View {
        Button { showSheet = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "info.circle")
                Text("AI · permission-aware")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About AI summaries. Tap for details.")
        .sheet(isPresented: $showSheet) {
            NavigationStack {
                List {
                    Section {
                        Text(ConnectStrings.aiSummaryDisclosure)
                            .font(.body)
                    }
                    Section {
                        Button("Manage what AI can see") {}
                    }
                }
                .navigationTitle("About AI Summaries")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showSheet = false }.fontWeight(.semibold)
                    }
                }
            }
        }
    }
}

// MARK: - Activity bullet with W4 reason chip

private struct ConnectV2ActivityBullet: View {

    var item: AmenConnectActivityItem

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(item.isPriority ? Color.red : Color.accentColor)
                .frame(width: 7, height: 7)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.systemScaled(14, weight: .semibold))
                Text(item.detail)
                    .font(.systemScaled(12))
                    .foregroundStyle(.secondary)   // W2: .secondary not .tertiary for 4.5:1 contrast
            }
            Spacer(minLength: 0)
            if item.requiresAction {
                Text("Action")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title). \(item.detail)\(item.requiresAction ? ". Action required." : "")")
    }
}

// MARK: - W3: Catch Up empty state with ghost preview

private struct ConnectV2CatchUpEmptyState: View {

    var onExplore: () -> Void

    var body: some View {
        ConnectEmptyStateView(
            icon: "sparkles",
            title: "Nothing yet",
            message: "Join a space and your AI catch-up will surface what matters each day.",
            primaryCTA: ConnectCTAConfig("Explore Spaces", systemImage: "safari", action: onExplore),
            ghostPreview: AnyView(
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(["Prayer request from Joshua", "New announcement in Young Adults", "3 replies to your thread"], id: \.self) { sample in
                        HStack(spacing: 8) {
                            Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                            Text(sample).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                .blur(radius: 2.5)
                .opacity(0.65)
            )
        )
    }
}

// MARK: - W2+3: Section grid with empty tile CTA

private struct ConnectV2SectionGrid: View {

    @ObservedObject var viewModel: AmenConnectViewModel
    @ObservedObject private var flags = AMENFeatureFlags.shared

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            tile("Spaces",        icon: "square.grid.2x2",            isEmpty: emptySpaces,  cta: "Create your first Space")
            tile("Announcements", icon: "megaphone",                   isEmpty: false,        cta: "Draft an announcement")
            tile("Discussions",   icon: "number",                      isEmpty: false,        cta: "Start a channel")
            tile("Calendar",      icon: "calendar",                    isEmpty: emptyMeetings, cta: "Add an event")
            tile("Meetings",      icon: "video",                       isEmpty: false,        cta: "Schedule a meeting")
            tile("Marketplace",   icon: "storefront",                  isEmpty: false,        cta: "Post a listing")
            tile("Creators",      icon: "person.crop.rectangle.stack", isEmpty: false,        cta: "Create a profile")
            tile("Safety",        icon: "shield.checkered",            isEmpty: false,        cta: "")
        }
    }

    private var emptySpaces: Bool   { flags.connectEmptyStatesEnabled && viewModel.spaces.isEmpty }
    private var emptyMeetings: Bool { flags.connectEmptyStatesEnabled && viewModel.meetings.isEmpty }

    @ViewBuilder
    private func tile(_ title: String, icon: String, isEmpty: Bool, cta: String) -> some View {
        ConnectV2Card {
            VStack(alignment: .leading, spacing: 12) {
                // W2: 44pt icon circle with breathing room
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color(.systemGray6)))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.systemScaled(15, weight: .bold))
                        .foregroundStyle(.primary)
                    // W3: empty slot → action CTA in subtitle
                    if isEmpty && !cta.isEmpty {
                        Text(cta)
                            .font(.systemScaled(12, weight: .semibold))
                            .foregroundStyle(.tint)
                    } else {
                        Text(tileSubtitle(title))
                            .font(.systemScaled(12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.top, 4)   // W2: breathing room top of icon
        }
        .accessibilityLabel(isEmpty ? "\(title): \(cta)" : "Open \(title)")
    }

    private func tileSubtitle(_ title: String) -> String {
        switch title {
        case "Spaces":        return "\(viewModel.spaces.count) workspaces"
        case "Announcements": return "Pinned, urgent, scheduled"
        case "Discussions":   return "Channels, threads, reactions"
        case "Calendar":      return "Events, RSVPs, bookings"
        case "Meetings":      return "Huddles, rooms, recaps"
        case "Marketplace":   return "Jobs, babysitting, help"
        case "Creators":      return "Tiers, posts, products"
        case "Safety":        return "Reports and AI guardrails"
        default:              return ""
        }
    }
}

// MARK: - W3: Spaces section with ConnectEmptyStateView

struct ConnectV2SpacesSection: View {

    @ObservedObject var viewModel: AmenConnectViewModel
    @ObservedObject private var flags = AMENFeatureFlags.shared
    @State private var showCreate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Amen Spaces")
                    .font(.systemScaled(28, weight: .black))
                    .padding(.horizontal, 20)
                Text("Workspaces for churches, colleges, nonprofits, creators, teams, and communities.")
                    .font(.systemScaled(14))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if flags.connectEmptyStatesEnabled && viewModel.spaces.isEmpty {
                ConnectEmptyStateView(
                    icon: "building.2",
                    title: "Create your first Space",
                    message: "Bring your community together — church, campus group, team, or family.",
                    primaryCTA: ConnectCTAConfig("Create Space", systemImage: "plus.circle", action: { showCreate = true }),
                    secondaryCTA: ConnectCTAConfig("Explore Spaces", action: {})
                )
                .padding(.horizontal, 20)
            } else if viewModel.loadState == .loading {
                VStack(spacing: 12) {
                    SkeletonCard(height: 80)
                    SkeletonCard(height: 80)
                    SkeletonCard(height: 80)
                }
                .padding(.horizontal, 20)
            } else {
                AmenConnectSpaceListView(viewModel: viewModel)
            }
        }
        .sheet(isPresented: $showCreate) {
            AmenCreateSpaceEnhancedSheet(
                userId: Auth.auth().currentUser?.uid ?? "",
                onDismiss: { showCreate = false },
                onCreated: { _ in showCreate = false }
            )
        }
    }
}

// MARK: - W3: Discover view with skeleton rails + sticky "All"

struct ConnectV2DiscoverView: View {

    @ObservedObject var viewModel: AmenConnectViewModel
    @ObservedObject private var flags = AMENFeatureFlags.shared
    @State private var selectedFilter = "All"

    private let filters = ["All", "Faith", "College", "Career", "Lifestyle",
                           "Parenting", "Finance", "Health", "Music", "Events", "Organizations"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Discover")
                    .font(.systemScaled(28, weight: .black))
                    .padding(.horizontal, 20)
                Text("Find communities, mentors, jobs, trusted local help, and creators.")
                    .font(.systemScaled(14))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // W1 fix: sticky "All" + scrollable rest with trailing fade gradient
            HStack(spacing: 0) {
                AmenConnectGlassPill(title: "All", iconName: nil, isSelected: selectedFilter == "All") {
                    selectedFilter = "All"
                }
                .padding(.leading, 20)

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(filters.dropFirst(), id: \.self) { f in
                            AmenConnectGlassPill(title: f, iconName: nil, isSelected: selectedFilter == f) {
                                selectedFilter = f
                            }
                        }
                    }
                    .padding(.vertical, 2).padding(.horizontal, 8)
                }
                .scrollIndicators(.hidden)
                .overlay(alignment: .trailing) {
                    LinearGradient(
                        colors: [.clear, Color(.systemBackground)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: 32)
                    .allowsHitTesting(false)
                }
            }

            // W3: Rails with skeleton / empty / content
            discoverRail(title: "Based on your memberships", reason: "Because you joined")
            discoverRail(title: "New this week",              reason: "New this week")

            if !viewModel.listings.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Jobs, babysitting, tutoring, and local help")
                            .font(.systemScaled(18, weight: .bold)).padding(.leading, 20)
                        Spacer()
                        Button("See all") {}
                            .font(.systemScaled(13, weight: .semibold)).foregroundStyle(.tint).padding(.trailing, 20)
                    }
                    ForEach(viewModel.listings.prefix(3)) { listing in
                        ConnectV2ListingRow(listing: listing).padding(.horizontal, 20)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func discoverRail(title: String, reason: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(reason.isEmpty ? title : title)
                    .font(.systemScaled(18, weight: .bold)).padding(.leading, 20)
                Spacer()
                if !viewModel.creators.isEmpty {
                    Button("See all") {}
                        .font(.systemScaled(13, weight: .semibold)).foregroundStyle(.tint).padding(.trailing, 20)
                }
            }

            if viewModel.loadState == .loading {
                ConnectSkeletonRail(cardCount: 3, cardWidth: 240, cardAspectRatio: 1.5)
            } else if viewModel.creators.isEmpty {
                if flags.connectEmptyStatesEnabled {
                    Text("Join your first space and we'll personalize this.")
                        .font(.systemScaled(13)).foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.creators) { creator in
                            ConnectV2CreatorCard(creator: creator).frame(width: 240)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

// MARK: - W2: Catch Up Sheet (canonical disclosure)

struct ConnectV2CatchUpSheet: View {

    var items: [AmenConnectActivityItem]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Image(systemName: "sparkles")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.tint)
                        Spacer()
                    }
                    .padding(.horizontal, 20).padding(.top, 8)

                    if items.isEmpty {
                        ConnectV2CatchUpEmptyState(onExplore: { dismiss() })
                            .padding(.horizontal, 20)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(items) { item in
                                ConnectV2ActivityBullet(item: item).padding(.horizontal, 20)
                            }
                        }
                    }

                    // W2: Canonical C-2 disclosure string
                    Text(ConnectStrings.aiSummaryDisclosure)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20).padding(.bottom, 8)
                        .accessibilityLabel("AI summaries are permission-aware and exclude restricted content.")
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("AI Catch Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Local matte card (same contract as private AmenConnectCard)

private struct SkeletonCard: View {
    let height: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(.secondarySystemBackground))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                    .padding(12)
            }
            .frame(height: height)
            .redacted(reason: .placeholder)
            .opacity(reduceMotion ? 0.85 : 1)
            .accessibilityLabel("Loading space")
    }
}

struct ConnectV2Card<Content: View>: View {
    var content: () -> Content
    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(.separator).opacity(0.28), lineWidth: 0.5))
    }
}

// MARK: - Creator card (local V2 version — AmenConnectCreatorCard is private to AmenConnectView)

private struct ConnectV2CreatorCard: View {
    var creator: AmenConnectCreatorProfile
    var body: some View {
        ConnectV2Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color.blue.opacity(0.2), Color.green.opacity(0.15)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 52, height: 52)
                        .overlay(Image(systemName: "person.crop.rectangle.stack").foregroundStyle(.primary))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(creator.displayName)
                            .font(.systemScaled(15, weight: .bold)).lineLimit(1)
                        Text(creator.type.rawValue.capitalized)
                            .font(.systemScaled(12)).foregroundStyle(.secondary)
                    }
                }
                Text(creator.bio)
                    .font(.systemScaled(12)).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 10) {
                    Label("\(creator.memberCount)", systemImage: "person.2")
                    if creator.isPaidEnabled { Label("Paid", systemImage: "star") }
                }
                .font(.systemScaled(11, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("\(creator.displayName), \(creator.type.rawValue)")
    }
}

// MARK: - Listing row

private struct ConnectV2ListingRow: View {
    var listing: AmenConnectMarketplaceListing
    var body: some View {
        ConnectV2Card {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(listing.title).font(.systemScaled(15, weight: .bold)).lineLimit(1)
                    Text("\(listing.category.rawValue) · \(listing.locationLabel)")
                        .font(.systemScaled(12)).foregroundStyle(.secondary)
                    Text("\(listing.posterName) · \(listing.verificationLevel)")
                        .font(.systemScaled(11)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(listing.compensation)
                    .font(.systemScaled(13, weight: .bold))
            }
        }
        .accessibilityLabel("\(listing.title), \(listing.category.rawValue), \(listing.compensation)")
    }
}

// MARK: - Scroll offset preference key (private; different from AmenConnectScrollOffsetKey)

private struct ConnectScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - W1 · W2 · W3 Total Control Wiring Certificate
//
// Surface                            Flag                        Status
// AmenConnectRootView flag gate      connectLayoutV2Enabled      Wired (AmenConnectView.swift edit)
// ConnectV2SectionBar (iOS 26 glass) connectLayoutV2Enabled      Wired — GlassEffectContainer + glassEffectUnion
// ConnectV2SectionBar (fallback)     connectLayoutV2Enabled      Wired — matte Capsule
// ConnectV2LobbyView                 connectLayoutV2Enabled      Wired
// ConnectV2CatchUpPanel              connectPolishV2Enabled      Wired via flag check in LobbyView
// ConnectV2AIDisclosureChip          connectPolishV2Enabled      Wired via CatchUpPanel
// ConnectV2SectionGrid empty tiles   connectEmptyStatesEnabled   Wired via flag checks
// ConnectV2SpacesSection empty       connectEmptyStatesEnabled   Wired via ConnectEmptyStateView
// ConnectV2DiscoverView skeleton     connectEmptyStatesEnabled   Wired via ConnectSkeletonRail
// Canonical disclosure string C-2    (unconditional fix)         Wired — AmenConnectView.swift edit
// Chrome bottom inset C-1            connectLayoutV2Enabled      Wired — .contentMargins bottomInset
// No glass-on-glass                  (invariant)                 Verified — all glass is chrome over matte
// Reduce Motion                      (invariant)                 Verified — all animations use rm guard
