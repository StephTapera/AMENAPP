// AmenGatheringsHomeView.swift
// AMENAPP — Amen Gatherings Discovery Feed
//
// White canvas. Large page title. Liquid Glass filter pills.
// Floating "Create Gathering" CTA. Skeleton loading states.

import SwiftUI

struct AmenGatheringsHomeView: View {
    @StateObject private var vm = AmenGatheringsHomeViewModel()
    @State private var showCreateFlow = false
    @State private var selectedGathering: AmenGatheringFeedCard?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let flags = AMENFeatureFlags.shared

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                feedScrollView
                if flags.gatheringCreationEnabled {
                    createFloatingButton
                }
            }
            .navigationTitle("Gatherings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showCreateFlow) {
                AmenGatheringCreateFlow()
            }
            .onChange(of: showCreateFlow) { _, isShowing in
                if !isShowing {
                    Task { await vm.load() }
                }
            }
            .sheet(item: $selectedGathering) { card in
                AmenGatheringDetailSheetWrapper(gatheringId: card.gatheringId)
            }
            .sheet(isPresented: $vm.showCalendar) {
                AmenGatheringCalendarView()
            }
            .sheet(isPresented: $vm.showSearch) {
                GatheringsSearchSheet(gatherings: vm.allGatherings) {
                    vm.showSearch = false
                }
            }
            .task { await vm.load() }
        }
    }

    // MARK: - Feed Scroll

    private var feedScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                categoryFilterRow
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                AmenSpaceBannerRail(surface: .events, title: "Featured Gatherings")
                    .padding(.bottom, 16)

                if vm.isLoading {
                    skeletonSection
                } else if vm.isEmpty {
                    emptyState
                } else {
                    feedSections
                }
            }
            .padding(.bottom, 100)
        }
        .refreshable { await vm.load() }
    }

    // MARK: - Category Filter Chips

    private var categoryFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AmenGatheringType.allCases, id: \.self) { type in
                    GatheringFilterChip(
                        label: type.displayName,
                        icon: type.systemImage,
                        isSelected: vm.selectedType == type
                    ) {
                        vm.toggleFilter(type)
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Feed Sections

    @ViewBuilder
    private var feedSections: some View {
        if !vm.trending.isEmpty {
            feedSection(title: "Near You", cards: vm.trending, variant: .hero)
        }
        if !vm.thisWeek.isEmpty {
            feedSection(title: "This Week", cards: vm.thisWeek, variant: .compact)
        }
        if !vm.fromChurches.isEmpty {
            feedSection(title: "From Churches You Follow", cards: vm.fromChurches, variant: .compact)
        }
        if !vm.prayerAndWorship.isEmpty {
            feedSection(title: "Prayer & Worship", cards: vm.prayerAndWorship, variant: .hero)
        }
        if !vm.volunteer.isEmpty {
            feedSection(title: "Volunteer Opportunities", cards: vm.volunteer, variant: .compact)
        }
        if !vm.yourUpcoming.isEmpty {
            feedSection(title: "Your Upcoming Gatherings", cards: vm.yourUpcoming, variant: .compact)
        }
    }

    private enum CardVariant { case hero, compact }

    private func feedSection(title: String, cards: [AmenGatheringFeedCard], variant: CardVariant) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            AmenGatheringsSectionHeader(title: title)
                .padding(.horizontal, 16)

            switch variant {
            case .hero:
                heroRail(cards: cards)
            case .compact:
                compactList(cards: cards)
            }
        }
        .padding(.bottom, 20)
    }

    private func heroRail(cards: [AmenGatheringFeedCard]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(cards) { card in
                    AmenGatheringHeroCard(card: card) { selectedGathering = card }
                        .frame(width: 300, height: 220)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func compactList(cards: [AmenGatheringFeedCard]) -> some View {
        VStack(spacing: 8) {
            ForEach(cards) { card in
                AmenGatheringCompactCard(card: card) { selectedGathering = card }
                    .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Skeleton

    private var skeletonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Near You")
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        AmenGatheringSkeletonCard()
                            .frame(width: 300)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 20)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.3.sequence")
                .font(.system(size: 52, weight: .ultraLight))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("No Gatherings Found")
                    .font(.title3.weight(.semibold))
                Text("Be the first to invite your community to gather in prayer, worship, or fellowship.")
                    .font(.subheadline)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if flags.gatheringCreationEnabled {
                Button {
                    showCreateFlow = true
                } label: {
                    Label("Create a Gathering", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 44)
                        .background(AmenTheme.Colors.amenGold)
                        .clipShape(Capsule(style: .continuous))
                }
                .accessibilityLabel("Create a gathering")
            }
        }
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Floating Create Button

    private var createFloatingButton: some View {
        VStack {
            Spacer()
            Button {
                showCreateFlow = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Create Gathering")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Color.black)
                .padding(.horizontal, 20)
                .frame(minHeight: 50)
                .background(AmenTheme.Colors.amenGold)
                .clipShape(Capsule(style: .continuous))
                .shadow(color: AmenTheme.Colors.shadowCard, radius: 12, x: 0, y: 6)
            }
            .accessibilityLabel("Create a new gathering")
            .padding(.bottom, 24)
        }
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 12) {
                Button { vm.toggleCalendar() } label: {
                    Image(systemName: vm.showCalendar ? "list.bullet" : "calendar")
                        .accessibilityLabel(vm.showCalendar ? "Switch to list view" : "Switch to calendar view")
                }
                Button { vm.showSearch = true } label: {
                    Image(systemName: "magnifyingglass")
                        .accessibilityLabel("Search gatherings")
                }
            }
        }
    }
}

// MARK: - Search Sheet

private struct GatheringsSearchSheet: View {
    let gatherings: [AmenGatheringFeedCard]
    let onDone: () -> Void

    @State private var searchText = ""

    private var filtered: [AmenGatheringFeedCard] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return gatherings }
        let query = searchText.lowercased()
        return gatherings.filter {
            $0.title.lowercased().contains(query) ||
            $0.hostName.lowercased().contains(query) ||
            $0.type.displayName.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { card in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                        HStack(spacing: 6) {
                            Text(card.type.displayName)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AmenTheme.Colors.amenGold)
                            Text("·")
                                .foregroundStyle(AmenTheme.Colors.textSecondary)
                            Text(card.hostName)
                                .font(.caption)
                                .foregroundStyle(AmenTheme.Colors.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(card.title), \(card.type.displayName), hosted by \(card.hostName)")
                }
            }
            .searchable(text: $searchText, prompt: "Search gatherings")
            .navigationTitle("Search Gatherings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDone() }
                }
            }
        }
    }
}

// MARK: - Filter Chip

private struct GatheringFilterChip: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    @GestureState private var isPressed = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption.weight(.medium))
                Text(label)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(isSelected ? AmenTheme.Colors.textPrimary : AmenTheme.Colors.textSecondary)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background {
                if isSelected {
                    Capsule(style: .continuous).fill(AmenTheme.Colors.amenGold.opacity(0.15))
                } else if reduceTransparency {
                    Capsule(style: .continuous).fill(Color(.systemGray6))
                } else {
                    Capsule(style: .continuous).fill(.ultraThinMaterial)
                        .overlay(Capsule(style: .continuous).fill(Color.white.opacity(0.1)))
                }
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        isSelected ? AmenTheme.Colors.amenGold.opacity(0.5) : AmenTheme.Colors.borderSoft,
                        lineWidth: isSelected ? 1.0 : 0.5
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Detail Sheet Wrapper

struct AmenGatheringDetailSheetWrapper: View {
    let gatheringId: String
    @State private var gathering: AmenGathering?
    @State private var isLoading = true
    @State private var error: AmenGatheringError?

    var body: some View {
        Group {
            if let gathering {
                AmenGatheringDetailView(gathering: gathering)
            } else if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                VStack(spacing: 16) {
                    Text(error.userFacingTitle).font(.headline)
                    Text(error.userFriendlyMessage).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding()
            }
        }
        .task {
            do {
                gathering = try await AmenGatheringService.shared.getGatheringPreview(gatheringId: gatheringId)
            } catch let e as AmenGatheringError {
                error = e
            } catch {
                self.error = .unknown(error.localizedDescription)
            }
            isLoading = false
        }
    }
}

// MARK: - View Model

@MainActor
final class AmenGatheringsHomeViewModel: ObservableObject {
    @Published var trending: [AmenGatheringFeedCard] = []
    @Published var thisWeek: [AmenGatheringFeedCard] = []
    @Published var fromChurches: [AmenGatheringFeedCard] = []
    @Published var prayerAndWorship: [AmenGatheringFeedCard] = []
    @Published var volunteer: [AmenGatheringFeedCard] = []
    @Published var yourUpcoming: [AmenGatheringFeedCard] = []
    @Published var isLoading = false
    @Published var selectedType: AmenGatheringType?
    @Published var showCalendar = false
    @Published var showSearch = false

    var isEmpty: Bool {
        trending.isEmpty && thisWeek.isEmpty && fromChurches.isEmpty &&
        prayerAndWorship.isEmpty && volunteer.isEmpty && yourUpcoming.isEmpty
    }

    var allGatherings: [AmenGatheringFeedCard] {
        (trending + thisWeek + fromChurches + prayerAndWorship + volunteer + yourUpcoming)
            .uniqued(by: \.gatheringId)
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let all = try await AmenGatheringService.shared.listGatheringsFeed(type: selectedType)
            distribute(all)
        } catch {
            // Non-fatal — show empty state
        }
    }

    func toggleFilter(_ type: AmenGatheringType) {
        selectedType = selectedType == type ? nil : type
        Task { await load() }
    }

    func toggleCalendar() {
        showCalendar.toggle()
    }

    private func distribute(_ cards: [AmenGatheringFeedCard]) {
        let now = Date()
        let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now

        trending = Array(cards.filter { $0.startAt > now }.prefix(6))
        thisWeek = Array(cards.filter { $0.startAt > now && $0.startAt <= weekEnd }.prefix(8))
        prayerAndWorship = Array(cards.filter {
            $0.type == .prayerNight || $0.type == .worshipNight
        }.prefix(6))
        volunteer = Array(cards.filter { $0.type == .volunteerOpportunity }.prefix(6))
        fromChurches = Array(cards.prefix(5))
        yourUpcoming = Array(cards.filter { $0.userRsvpStatus == .going }.prefix(5))
    }
}
