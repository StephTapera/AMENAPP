//
//  ResourceGlassHomeView.swift
//  AMENAPP
//
//  Wave 3 + 4 — Assembly + wiring for the white Liquid Glass Resources home.
//  Composes the Wave 2 components into the redesigned home and wires them to the
//  EXISTING navigation destinations, services, and search so nothing regresses.
//
//  Rendered by ResourcesView ONLY when AMENFeatureFlags.resourcesGlassHomeEnabled is
//  true (default OFF). When OFF, ResourcesView shows its original layout unchanged.
//

import SwiftUI
import FirebaseAuth

struct ResourceGlassHomeView: View {
    @ObservedObject private var featureFlags = AMENFeatureFlags.shared
    @ObservedObject private var supportCoordinator = SupportIntelligenceCoordinator.shared

    @State private var mediaVM = AMENResourcesHubViewModel()
    @State private var path = NavigationPath()

    @State private var selectedCategory: ResourcesView.ResourceCategory = .all
    @State private var searchText = ""
    @State private var aiSearchResults: [AISearchResult] = []
    @State private var useAISearch = false
    @State private var isSearchingWithAI = false
    @State private var aiSearchTask: Task<Void, Never>?
    @State private var supportAnalysisTask: Task<Void, Never>?

    @State private var scrollOffset: CGFloat = 0
    @State private var showChurchHub = false
    @State private var showBereanOSHub = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Hero collapses as the user scrolls (0 → 1).
    private var heroCompression: CGFloat {
        min(max((-scrollOffset - 20) / 120, 0), 1)
    }

    private let smartSuggestions = [
        "Resources on anxiety",
        "Romans 8 studies",
        "Short devotionals under 10 minutes",
        "Leadership training PDFs"
    ]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    offsetReader

                    if searchText.isEmpty {
                        homeSections
                    } else {
                        searchResultsSection
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 96)
            }
            .coordinateSpace(name: "rgScroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                if reduceMotion { scrollOffset = value }
                else { withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.85)) { scrollOffset = value } }
            }
            .background(backgroundCanvas)
            .navigationBarHidden(true)
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await mediaVM.load() }
            .task { await mediaVM.load() }
            .onDisappear {
                aiSearchTask?.cancel(); aiSearchTask = nil
                supportAnalysisTask?.cancel(); supportAnalysisTask = nil
            }
            .onChange(of: searchText) { _, q in handleSupportSearchChange(q) }
            .navigationDestination(for: AMENMediaEntry.self) { entry in
                AMENResourceDetailView(entry: entry)
            }
            .sheet(isPresented: $showBereanOSHub) { BereanOSHubView() }
            .sheet(isPresented: $showChurchHub) { FindChurchView() }
        }
    }

    // MARK: - Canvas

    private var backgroundCanvas: some View {
        LinearGradient(colors: [RGInk.canvasTop, RGInk.canvasBottom],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    private var offsetReader: some View {
        GeometryReader { geo in
            Color.clear.preference(key: ScrollOffsetPreferenceKey.self,
                                   value: geo.frame(in: .named("rgScroll")).minY)
        }
        .frame(height: 0)
    }

    // MARK: - Home sections

    @ViewBuilder
    private var homeSections: some View {
        primarySections      // ≤10 children per builder closure
        secondarySections
    }

    @ViewBuilder
    private var primarySections: some View {
        // Search bar (glass) + smart suggestions
        ResourceSearchGlassBar(
            text: $searchText,
            isSearching: isSearchingWithAI,
            suggestions: smartSuggestions,
            onSubmit: performAISearch,
            onSuggestion: { suggestion in searchText = suggestion; performAISearch() }
        )

        // Filter pills
        ResourceFilterPillBar(selection: $selectedCategory)

        // 1 — Today's hero + summary
        if let hero = heroContent {
            ResourceHeroBanner(content: hero, compactProgress: heroCompression) {
                open(hero.primary)
            }
        }
        SmartDailySummaryCard(summary: dailySummary)

        // Crisis-first safety (reuses existing disaster + support intelligence)
        if selectedCategory == .all || selectedCategory == .crisis {
            DisasterResourcesSection()
        }
        supportForYouSection

        // 2 — Continue
        if !continueItems.isEmpty, showsLearning {
            VStack(alignment: .leading, spacing: 4) {
                ResourceSectionHeader(title: "Continue", subtitle: "Pick up where you left off")
                ContinueResourceCarousel(items: continueItems) { open($0) }
            }
        }

        // 3 — Recommended with "Why this?"
        if !recommendedItems.isEmpty, showsLearning {
            VStack(alignment: .leading, spacing: 12) {
                ResourceSectionHeader(title: "Recommended For You", subtitle: "Calm picks for your season")
                VStack(spacing: 12) {
                    ForEach(recommendedItems) { item in
                        Button { open(item) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ResourceCompactRow(item: item, showDivider: false)
                                if let reason = item.recommendationReason {
                                    ResourceRecommendationReasonPill(reason: reason)
                                }
                            }
                            .padding(14)
                            .background(RGInk.card, in: RoundedRectangle(cornerRadius: RGInk.cardCorner, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: RGInk.cardCorner, style: .continuous)
                                .strokeBorder(RGInk.hairline, lineWidth: 1))
                        }
                        .buttonStyle(ResourceCardPressStyle())
                    }
                }
                .padding(.horizontal, 20)
            }
        }

    }

    @ViewBuilder
    private var secondarySections: some View {
        // 4 — From Your Church / Organization
        if selectedCategory == .all || selectedCategory == .tools || selectedCategory == .community {
            churchSection
        }

        // Connect
        if selectedCategory == .all || selectedCategory == .community {
            VStack(alignment: .leading, spacing: 12) {
                ResourceSectionHeader(title: "Connect", subtitle: "Acts 2:42")
                NavigationLink(destination: AMENConnectView()) { AMENConnectBanner() }
                    .buttonStyle(ResourceCardPressStyle())
                    .padding(.horizontal, 20)
            }
        }

        // 5 — Resource Bundles
        if showsLearning {
            VStack(alignment: .leading, spacing: 12) {
                ResourceSectionHeader(title: "Resource Bundles", subtitle: "Study kits & group packs")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(placeholderBundles) { bundle in
                            ResourceBundleStackCard(bundle: bundle) { open(bundle.previewItem) }
                                .frame(width: 260)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }

        // 6 — Support & Wellness (preserves existing detail destinations)
        if selectedCategory == .all || selectedCategory == .crisis || selectedCategory == .mentalHealth {
            supportWellnessSection
        }

        // 7 — Faith & Learning
        if showsLearning {
            faithLearningSection
        }
    }

    private var showsLearning: Bool {
        selectedCategory == .all || selectedCategory == .learning || selectedCategory == .community
    }

    // MARK: - Church section

    private var churchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ResourceSectionHeader(title: "From Your Church", subtitle: "Your faith home")
            HStack(spacing: 12) {
                NavigationLink(destination: ChurchNotesView()) {
                    glassEntryCard(icon: "note.text", tint: RGInk.tan,
                                   title: "Church Notes", subtitle: "Sermons, highlights & insights")
                }
                .buttonStyle(ResourceCardPressStyle())
                NavigationLink(destination: FindChurchView()) {
                    glassEntryCard(icon: "mappin.and.ellipse", tint: Color(hex: "10B981"),
                                   title: "Find a Church", subtitle: "Discover churches near you")
                }
                .buttonStyle(ResourceCardPressStyle())
            }
            .padding(.horizontal, 20)
        }
    }

    private func glassEntryCard(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.16))
                    .frame(width: 38, height: 38)
                Image(systemName: icon).font(.system(size: 16, weight: .medium)).foregroundStyle(tint)
            }
            Text(title).font(AMENFont.semiBold(14)).foregroundStyle(.primary)
            Text(subtitle).font(AMENFont.regular(11)).foregroundStyle(.secondary).lineLimit(2)
            Spacer(minLength: 0)
            HStack(spacing: 3) {
                Text("Open").font(AMENFont.semiBold(11)).foregroundStyle(tint)
                Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold)).foregroundStyle(tint)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .leading)
        .background(RGInk.card, in: RoundedRectangle(cornerRadius: RGInk.cardCorner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: RGInk.cardCorner, style: .continuous)
            .strokeBorder(RGInk.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(title). \(subtitle)"))
    }

    // MARK: - Support & Wellness

    private var supportWellnessSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ResourceSectionHeader(title: "Support & Wellness")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                NavigationLink(destination: CrisisResourcesDetailView()) {
                    FolderSquareCard(icon: "phone.fill", title: "Crisis Resources",
                                     accentColor: Color(red: 0.82, green: 0.18, blue: 0.20),
                                     folderColor: Color(red: 0.72, green: 0.13, blue: 0.16),
                                     paperColor: Color(red: 1.0, green: 0.95, blue: 0.95))
                }
                .buttonStyle(ResourceCardPressStyle())
                NavigationLink(destination: MentalHealthDetailView()) {
                    FolderSquareCard(icon: "heart.text.square.fill", title: "Mental Health",
                                     accentColor: Color(red: 0.18, green: 0.60, blue: 0.36),
                                     folderColor: Color(red: 0.12, green: 0.48, blue: 0.28),
                                     paperColor: Color(red: 0.93, green: 0.99, blue: 0.95))
                }
                .buttonStyle(ResourceCardPressStyle())
                NavigationLink(destination: GivingNonprofitsDetailView()) {
                    FolderSquareCard(icon: "heart.circle.fill", title: "Giving",
                                     accentColor: Color(red: 0.15, green: 0.42, blue: 0.84),
                                     folderColor: Color(red: 0.10, green: 0.32, blue: 0.72),
                                     paperColor: Color(red: 0.93, green: 0.96, blue: 1.0))
                }
                .buttonStyle(ResourceCardPressStyle())
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Faith & Learning

    private var faithLearningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ResourceSectionHeader(title: "Faith & Learning")
            VStack(spacing: 10) {
                NavigationLink(destination: WalkWithChristView()) {
                    ResourceCompactRow(
                        item: ResourceGlassItem(id: "walk", title: "Walk With Christ",
                                                subtitle: "Discipleship journey & devotionals",
                                                systemIcon: "figure.walk", accent: Color(hex: "10B981"),
                                                type: .devotional),
                        showDivider: false
                    )
                    .padding(.horizontal, 14)
                    .background(RGInk.card, in: RoundedRectangle(cornerRadius: RGInk.rowCorner, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: RGInk.rowCorner, style: .continuous)
                        .strokeBorder(RGInk.hairline, lineWidth: 1))
                }
                .buttonStyle(ResourceCardPressStyle())

                Button { showBereanOSHub = true } label: {
                    ResourceCompactRow(
                        item: ResourceGlassItem(id: "berean", title: "Berean OS",
                                                subtitle: "Wisdom research, debates & mentorship",
                                                systemIcon: "brain.head.profile", accent: .purple,
                                                type: .guide),
                        showDivider: false
                    )
                    .padding(.horizontal, 14)
                    .background(RGInk.card, in: RoundedRectangle(cornerRadius: RGInk.rowCorner, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: RGInk.rowCorner, style: .continuous)
                        .strokeBorder(RGInk.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Support intelligence "For You" (reuses SupportIntelligenceCoordinator)

    @ViewBuilder
    private var supportForYouSection: some View {
        let actions = Array(supportCoordinator.currentProfile.suggestedActions.prefix(3))
        if featureFlags.resourcesIntelligenceEnabled, !actions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ResourceSectionHeader(title: "For You", subtitle: "Quietly shaped by your care context")
                VStack(spacing: 10) {
                    ForEach(actions) { action in
                        NavigationLink { supportDestination(for: action) } label: {
                            ResourceCompactRow(
                                item: ResourceGlassItem(id: action.id, title: action.title,
                                                        subtitle: "Open calm, private support",
                                                        systemIcon: "heart.text.square.fill",
                                                        accent: RGInk.tan, type: .guide),
                                showDivider: false
                            )
                            .padding(14)
                            .background(RGInk.card, in: RoundedRectangle(cornerRadius: RGInk.cardCorner, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: RGInk.cardCorner, style: .continuous)
                                .strokeBorder(RGInk.hairline, lineWidth: 1))
                        }
                        .buttonStyle(ResourceCardPressStyle())
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    @ViewBuilder
    private func supportDestination(for action: SupportAction) -> some View {
        switch action.type {
        case .openFindChurch, .shareWithPastorOrCareTeam:
            FindChurchView()
        case .openNonprofitResources:
            GivingNonprofitsDetailView()
        case .openBerean:
            BereanLandingView()
        case .messageTrustedContact:
            TrustedCircleView()
        default:
            MentalHealthDetailView()
        }
    }

    // MARK: - Search results

    @ViewBuilder
    private var searchResultsSection: some View {
        ResourceSearchGlassBar(
            text: $searchText, isSearching: isSearchingWithAI, suggestions: [],
            onSubmit: performAISearch, onSuggestion: { _ in }
        )
        let results = searchFilteredResources
        VStack(alignment: .leading, spacing: 12) {
            ResourceSectionHeader(
                title: useAISearch ? "AI Search Results" : "Search Results",
                subtitle: "\(results.count) found"
            )
            if results.isEmpty {
                Text("No results found. Try adjusting your search.")
                    .font(AMENFont.regular(14)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, resource in
                        let item = enrichedResult(resource, index: index)
                        Button { open(item) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ResourceCompactRow(item: item, showDivider: false)
                                if let reason = item.recommendationReason {
                                    ResourceRecommendationReasonPill(reason: reason)
                                }
                            }
                            .padding(14)
                            .background(RGInk.card, in: RoundedRectangle(cornerRadius: RGInk.cardCorner, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: RGInk.cardCorner, style: .continuous)
                                .strokeBorder(RGInk.hairline, lineWidth: 1))
                        }
                        .buttonStyle(ResourceCardPressStyle())
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func enrichedResult(_ resource: ResourceItem, index: Int) -> ResourceGlassItem {
        var item = ResourceGlassAdapters.item(from: resource)
        if useAISearch, index < aiSearchResults.count {
            item.recommendationReason = aiSearchResults[index].reason
        }
        return item
    }

    private var searchFilteredResources: [ResourceItem] {
        if useAISearch && !aiSearchResults.isEmpty {
            return aiSearchResults.map { $0.resource }
        }
        return allResources.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText) ||
            $0.category.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Derived content

    private var heroContent: ResourceHeroContent? {
        if let sermon = mediaVM.featuredSermons.first {
            var item = ResourceGlassAdapters.item(from: sermon)
            item.sourceType = .recommended
            return ResourceHeroContent(
                eyebrow: "Recommended for your season",
                title: sermon.title,
                subtitle: sermon.speaker,
                chips: [timeOfDayChip, sermon.topic.isEmpty ? "For you" : sermon.topic].filter { !$0.isEmpty },
                imageRef: sermon.thumbnailURL,
                accent: RGInk.tan,
                reason: item.recommendationReason,
                primary: item
            )
        }
        // Graceful fallback to a known learning resource
        if let r = allResources.first(where: { $0.category == "Learning" }) {
            let item = ResourceGlassAdapters.item(from: r)
            return ResourceHeroContent(
                eyebrow: "Recommended for your season",
                title: r.title, subtitle: r.description,
                chips: [timeOfDayChip, "For you"],
                accent: RGInk.tan, primary: item
            )
        }
        return nil
    }

    private var dailySummary: ResourceDailySummary {
        let name = (Auth.auth().currentUser?.displayName?.components(separatedBy: " ").first).flatMap { $0.isEmpty ? nil : $0 } ?? "friend"
        let studies = mediaVM.featuredSermons.count
        let podcasts = mediaVM.featuredPodcasts.count
        var stats: [ResourceCountChip] = []
        if studies > 0 { stats.append(.init(value: "\(studies)", label: studies == 1 ? "study" : "studies")) }
        if podcasts > 0 { stats.append(.init(value: "\(podcasts)", label: "saved")) }
        stats.append(.init(value: "\(allResources.count)", label: "resources"))
        let line: String = {
            if studies > 0 || podcasts > 0 {
                return "You have \(studies) \(studies == 1 ? "study" : "studies") and \(podcasts) saved \(podcasts == 1 ? "sermon" : "sermons") waiting, plus new resources from your community."
            }
            return "A calm set of studies, devotionals, and resources is ready whenever you are."
        }()
        return ResourceDailySummary(greeting: "\(timeOfDayGreeting), \(name).", line: line, stats: stats)
    }

    private var continueItems: [ResourceGlassItem] {
        let sermons = mediaVM.featuredSermons.prefix(5).map { ResourceGlassAdapters.item(from: $0) }
        let podcasts = mediaVM.featuredPodcasts.prefix(3).map { ResourceGlassAdapters.item(from: $0) }
        return Array(sermons) + Array(podcasts)
    }

    private var recommendedItems: [ResourceGlassItem] {
        mediaVM.featuredSermons.dropFirst().prefix(3).map { sermon in
            var item = ResourceGlassAdapters.item(from: sermon)
            if item.recommendationReason == nil { item.recommendationReason = "Because it fits your recent reflections" }
            return item
        }
    }

    private var placeholderBundles: [ResourceGlassBundle] {
        // §8: no bundle model exists yet → graceful placeholders from known content concepts.
        [
            ResourceGlassBundle(id: "b_study", title: "30-Day Psalms Kit", subtitle: "Praise & Lament",
                                systemIcon: "book.closed.fill", accent: RGInk.tan,
                                counts: [.init(value: "4", label: "PDFs"), .init(value: "12", label: "Notes")],
                                isOfficial: true, previewCount: 8),
            ResourceGlassBundle(id: "b_group", title: "Small-Group Pack", subtitle: "Gospel Survey",
                                systemIcon: "person.3.fill", accent: Color(hex: "10B981"),
                                counts: [.init(value: "6", label: "Lessons"), .init(value: "18", label: "Questions")],
                                previewCount: 6),
            ResourceGlassBundle(id: "b_notes", title: "Sermon Notes Set", subtitle: "This Series",
                                systemIcon: "note.text", accent: RGInk.wine,
                                counts: [.init(value: "5", label: "Notes"), .init(value: "3", label: "Videos")],
                                previewCount: 5)
        ]
    }

    // MARK: - Greeting helpers

    private var timeOfDayGreeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }
    private var timeOfDayChip: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<12: return "Morning"
        case 12..<17: return "Afternoon"
        default: return "Evening"
        }
    }

    // MARK: - Navigation

    private func open(_ item: ResourceGlassItem?) {
        guard let item else { return }
        if let entry = item.mediaEntry { path.append(entry) }
    }

    // MARK: - Search (mirrors ResourcesView.performAISearch)

    private func performAISearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        aiSearchTask?.cancel()
        aiSearchTask = Task {
            await MainActor.run { isSearchingWithAI = true }
            do {
                let results = try await AIResourceSearchService.shared.searchWithAI(query: query, allResources: allResources)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.3)) {
                        aiSearchResults = results; useAISearch = true; isSearchingWithAI = false
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.3)) { useAISearch = false; isSearchingWithAI = false }
                }
            }
        }
    }

    private func handleSupportSearchChange(_ query: String) {
        supportAnalysisTask?.cancel()
        guard featureFlags.resourcesIntelligenceEnabled else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return }
        supportAnalysisTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            _ = await supportCoordinator.analyze(text: trimmed, surface: .search)
        }
    }
}

// Small helper so bundle literal stays readable.
private extension ResourceGlassBundle {
    /// Placeholder bundles have no openable item yet (§8 — bundle model missing).
    var previewItem: ResourceGlassItem? { nil }
}
