// AmenDiscoveryRailsView.swift
// AMEN App — Spiritual OS / Community Discovery
//
// Apple TV / Netflix-style horizontal discovery rails.
// Section title + "See All" header above a horizontal LazyHStack of tappable cards.
//
// Design rules:
//   • NO glass on cards — Color(.secondarySystemBackground) only.
//   • NO glass on section headers.
//   • Glass is permitted only on overlaid action controls (not rendered here).
//   • Section title text uses Color.amenBlack — no decorative gold.
//   • Shimmer uses AmenTheme.Colors.shimmerBase / shimmerHighlight.
//
// Usage:
//   AmenDiscoveryRailsView(userId: currentUserId) { item in
//       // navigate to item
//   }

import SwiftUI
import FirebaseAuth
import FirebaseFunctions

// MARK: - AmenDiscoveryRailsView

struct AmenDiscoveryRailsView: View {

    // MARK: Inputs

    let userId: String
    let onItemTap: (DiscoveryRailItem) -> Void
    var onSeeAll: ((DiscoveryRailType) -> Void)? = nil

    // MARK: Feature flags

    @AppStorage("amen_discovery_rails_enabled") private var isEnabled = true
    @AppStorage("amen_hero_cards_enabled") private var heroCardsEnabled = true

    // MARK: State

    @State private var viewModel = AmenDiscoveryRailsViewModel()
    @StateObject private var entitlements = AmenAccountEntitlementService.shared
    @State private var showDiscoveryAgent = false
    @State private var showAgentPaywall = false

    // MARK: Body

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 32) {
                // Hero card carousel — Church, Space, Event, Prayer, Sermon
                if heroCardsEnabled {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Featured")
                            .font(.title3.bold())
                            .foregroundStyle(Color.amenBlack)
                            .padding(.horizontal, 18)
                        AmenDiscoveryHeroCarousel()
                    }
                }

                // Personal Discovery Agent card — Amen+ gated
                PersonalDiscoveryAgentCard(
                    hasAccess: entitlements.hasAccess(to: .personalDiscoveryAgent),
                    onTap: {
                        if entitlements.hasAccess(to: .personalDiscoveryAgent) {
                            showDiscoveryAgent = true
                        } else {
                            showAgentPaywall = true
                        }
                    }
                )
                .padding(.horizontal, 18)

                if viewModel.isLoading && viewModel.rails.isEmpty {
                    loadingPlaceholder
                } else if viewModel.rails.isEmpty {
                    emptyState
                } else {
                    ForEach(viewModel.rails) { rail in
                        AmenDiscoveryRailSection(
                            rail: rail,
                            onItemTap: onItemTap,
                            onSeeAll: onSeeAll
                        )
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .task {
            guard isEnabled else { return }
            await viewModel.load(userId: userId)
            await entitlements.refreshIfNeeded()
        }
        .sheet(isPresented: $showDiscoveryAgent) {
            AmenPersonalDiscoveryAgentSheet(isPresented: $showDiscoveryAgent)
        }
        .amenPaywall(
            isPresented: $showAgentPaywall,
            requiredTier: .amenPlus,
            feature: "Personal Discovery Agent"
        )
    }

    // MARK: - Loading placeholder — 3 shimmer rails

    private var loadingPlaceholder: some View {
        VStack(alignment: .leading, spacing: 32) {
            ForEach(0..<3, id: \.self) { _ in
                shimmerRail
            }
        }
        .accessibilityHidden(true)
    }

    private var shimmerRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header skeleton
            HStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(AmenTheme.Colors.shimmerBase)
                    .frame(width: 160, height: 14)
                    .amenSkeleton()
                Spacer()
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(AmenTheme.Colors.shimmerBase)
                    .frame(width: 48, height: 12)
                    .amenSkeleton()
            }
            .padding(.horizontal, 18)

            // Card skeletons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<5, id: \.self) { _ in
                        shimmerCard
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private var shimmerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AmenTheme.Colors.shimmerBase)
                .frame(width: 160, height: 120)
                .amenSkeleton()

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(AmenTheme.Colors.shimmerBase)
                .frame(width: 120, height: 12)
                .amenSkeleton()

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(AmenTheme.Colors.shimmerBase)
                .frame(width: 80, height: 10)
                .amenSkeleton()
        }
        .frame(width: 160)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.amenSlate.opacity(0.5))
            Text("Discovering your community...")
                .font(.subheadline)
                .foregroundStyle(Color.amenSlate)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Discovering your community — content loading")
    }
}

// MARK: - AmenDiscoveryRailSection

struct AmenDiscoveryRailSection: View {

    let rail: DiscoveryRail
    let onItemTap: (DiscoveryRailItem) -> Void
    var onSeeAll: ((DiscoveryRailType) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader
            itemScrollRow
        }
    }

    // MARK: Section header

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: rail.type.iconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.amenBlack)
                .accessibilityHidden(true)

            Text(rail.type.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.amenBlack)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button {
                onSeeAll?(rail.type)
            } label: {
                Text("See All")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("See all \(rail.type.title)")
            .accessibilityHint("Opens the full list for this section")
        }
        .padding(.horizontal, 18)
    }

    // MARK: Horizontal scroll row

    private var itemScrollRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(rail.items) { item in
                    AmenDiscoveryRailCard(item: item)
                        .onTapGesture {
                            onItemTap(item)
                        }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 4)  // prevent shadow clipping at edges
        }
    }
}

// MARK: - AmenDiscoveryRailCard

struct AmenDiscoveryRailCard: View {

    let item: DiscoveryRailItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            imageSection
            textSection
            progressSection
        }
        .frame(width: 160)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: Image area (160 x 120)

    private var imageSection: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let url = item.imageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure, .empty:
                            fallbackImageView
                        @unknown default:
                            fallbackImageView
                        }
                    }
                } else {
                    fallbackImageView
                }
            }
            .frame(width: 160, height: 120)
            .clipped()
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 12,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 12,
                    style: .continuous
                )
            )
            .overlay(alignment: .bottom) {
                // Gradient scrim for legibility
                LinearGradient(
                    colors: [.clear, .black.opacity(0.30)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0,
                        style: .continuous
                    )
                )
            }

            // Badge pill — top right of image
            if let badge = item.badgeText {
                Text(badge)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.70))
                    )
                    .padding(6)
            }
        }
        .frame(width: 160, height: 120)
    }

    // MARK: Fallback when no image

    private var fallbackImageView: some View {
        ZStack {
            Rectangle()
                .fill(Color(.tertiarySystemBackground))
            Image(systemName: fallbackIcon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.amenSlate.opacity(0.5))
        }
    }

    private var fallbackIcon: String {
        switch item.type {
        case .space:       return "bubble.left.and.bubble.right"
        case .mentor:      return "person.circle"
        case .church:      return "building.columns"
        case .event:       return "calendar"
        case .study:       return "book.closed"
        case .person:      return "person.crop.circle"
        case .churchNote:  return "doc.text"
        case .discussion:  return "quote.bubble"
        }
    }

    // MARK: Text section

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let sub = item.subtitle {
                Text(sub)
                    .font(.system(size: 12))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, item.progressFraction != nil ? 6 : 10)
    }

    // MARK: Progress bar (continueJourney items only)

    @ViewBuilder
    private var progressSection: some View {
        if let fraction = item.progressFraction {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.systemFill))
                        .frame(height: 4)

                    Rectangle()
                        .fill(Color.teal)
                        .frame(width: geo.size.width * CGFloat(max(0, min(1, fraction))), height: 4)
                }
            }
            .frame(height: 4)
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            .accessibilityLabel("\(Int(max(0, min(1, fraction)) * 100)) percent complete")
        }
    }

    // MARK: Accessibility label

    private var accessibilityLabel: String {
        var parts = [item.title]
        if let sub = item.subtitle { parts.append(sub) }
        if let badge = item.badgeText { parts.append(badge) }
        if let fraction = item.progressFraction {
            parts.append("\(Int(max(0, min(1, fraction)) * 100)) percent complete")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - PersonalDiscoveryAgentCard

private struct PersonalDiscoveryAgentCard: View {

    let hasAccess: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                HStack(alignment: .top, spacing: 14) {
                    // Left icon column
                    ZStack {
                        Circle()
                            .fill(Color(hex: "D9A441").opacity(0.15))
                            .frame(width: 48, height: 48)
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color(hex: "D9A441"))
                    }
                    .accessibilityHidden(true)

                    // Text column
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Personal Discovery Agent")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.amenBlack)
                            .multilineTextAlignment(.leading)

                        Text("Find communities, people, events, and opportunities aligned with your goals")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.amenSlate)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 10)

                        // CTA button row
                        HStack(spacing: 8) {
                            Text(hasAccess ? "Get Started" : "Try It")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(hex: "070607"))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(Color(hex: "D9A441"))
                                )

                            if !hasAccess {
                                HStack(spacing: 4) {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Color(hex: "D9A441"))
                                        .accessibilityHidden(true)
                                    Text("Amen+ required")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Color(hex: "D9A441"))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Color(hex: "D9A441").opacity(0.12))
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(Color(hex: "D9A441").opacity(0.35), lineWidth: 1)
                                        )
                                )
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color(hex: "D9A441").opacity(0.25), lineWidth: 1)
                        )
                )
                .shadow(color: Color(hex: "D9A441").opacity(0.08), radius: 12, x: 0, y: 4)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            hasAccess
                ? "Personal Discovery Agent. Find communities, people, events, and opportunities aligned with your goals. Get Started."
                : "Personal Discovery Agent. Find communities, people, events, and opportunities aligned with your goals. Requires Amen Plus. Try It."
        )
        .accessibilityHint(
            hasAccess
                ? "Opens the Personal Discovery Agent"
                : "Opens upgrade options for Amen Plus"
        )
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - DiscoveryResult model

private struct DiscoveryResult: Identifiable {
    let id: String
    let name: String
    let description: String
    let category: String // "community", "church", or "event"
}

// MARK: - AmenPersonalDiscoveryAgentSheet

private struct AmenPersonalDiscoveryAgentSheet: View {

    @Binding var isPresented: Bool
    @State private var goalText = ""
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var discoveryResults: [DiscoveryResult] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerBanner
                searchInputSection
                resultsSection
                Spacer(minLength: 0)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Discovery Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                    .accessibilityLabel("Dismiss Personal Discovery Agent")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Header banner

    private var headerBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(hex: "D9A441"))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("What are you looking for?")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.amenBlack)
                Text("Describe your goals and your agent will search for you")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.amenSlate)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Personal Discovery Agent. Describe your goals and your agent will search for you.")
    }

    // MARK: Search input

    private var searchInputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(
                "e.g. small groups for young professionals, ministry jobs in Atlanta...",
                text: $goalText,
                axis: .vertical
            )
            .lineLimit(3...5)
            .font(.system(size: 14))
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.amenSlate.opacity(0.20), lineWidth: 1)
                    )
            )
            .accessibilityLabel("Goal description field")
            .accessibilityHint("Describe what you are looking for")

            Button {
                Task { await runSearch() }
            } label: {
                HStack(spacing: 8) {
                    if isSearching {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                            .tint(Color(hex: "070607"))
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                    Text(isSearching ? "Searching..." : "Find for Me")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(Color(hex: "070607"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(goalText.trimmingCharacters(in: .whitespaces).isEmpty || isSearching
                              ? Color(hex: "D9A441").opacity(0.40)
                              : Color(hex: "D9A441"))
                )
            }
            .buttonStyle(.plain)
            .disabled(goalText.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
            .accessibilityLabel(isSearching ? "Searching for results" : "Find for Me")
            .accessibilityHint("Runs a personalised search based on your goal description")
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 10)
    }

    // MARK: Results area

    @ViewBuilder
    private var resultsSection: some View {
        if hasSearched {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    if discoveryResults.isEmpty {
                        emptyResultsPlaceholder
                    } else {
                        ForEach(discoveryResults) { result in
                            DiscoveryResultCard(result: result)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
        }
    }

    private var emptyResultsPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.amenSlate.opacity(0.45))
                .accessibilityHidden(true)
            Text("No results found")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.amenSlate)
                .multilineTextAlignment(.center)
            Text("Try rephrasing your goals or broadening your search.")
                .font(.system(size: 13))
                .foregroundStyle(Color.amenSlate.opacity(0.70))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No results found. Try rephrasing your goals or broadening your search.")
    }

    // MARK: Search action

    @MainActor
    private func runSearch() async {
        guard !goalText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let functions = Functions.functions()
            let result = try await functions.httpsCallable("discoverByGoals").call([
                "goals": goalText,
                "userId": Auth.auth().currentUser?.uid ?? ""
            ])
            if let data = result.data as? [String: Any] {
                var parsed: [DiscoveryResult] = []
                // communities
                for item in (data["communities"] as? [[String: Any]] ?? []) {
                    if let id = item["id"] as? String, let name = item["name"] as? String {
                        parsed.append(DiscoveryResult(
                            id: id,
                            name: name,
                            description: item["description"] as? String ?? "",
                            category: "community"
                        ))
                    }
                }
                // churches
                for item in (data["churches"] as? [[String: Any]] ?? []) {
                    if let id = item["id"] as? String, let name = item["name"] as? String {
                        parsed.append(DiscoveryResult(
                            id: id,
                            name: name,
                            description: item["description"] as? String ?? "",
                            category: "church"
                        ))
                    }
                }
                // events
                for item in (data["events"] as? [[String: Any]] ?? []) {
                    if let id = item["id"] as? String, let name = item["name"] as? String {
                        parsed.append(DiscoveryResult(
                            id: id,
                            name: name,
                            description: item["description"] as? String ?? "",
                            category: "event"
                        ))
                    }
                }
                discoveryResults = parsed
            }
            hasSearched = true
        } catch {
            // Show empty state on error so the user sees a graceful fallback.
            hasSearched = true
        }
    }
}

// MARK: - DiscoveryResultCard

private struct DiscoveryResultCard: View {
    let result: DiscoveryResult

    private var categoryIcon: String {
        switch result.category {
        case "church":     return "building.columns"
        case "event":      return "calendar"
        default:           return "bubble.left.and.bubble.right"
        }
    }

    private var categoryLabel: String {
        switch result.category {
        case "church":     return "Church"
        case "event":      return "Event"
        default:           return "Community"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Category pill row
            HStack(spacing: 6) {
                Image(systemName: categoryIcon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(hex: "070607"))
                    .accessibilityHidden(true)
                Text(categoryLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "070607"))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color(hex: "D9A441"))
            )
            .accessibilityLabel("\(categoryLabel) category")

            // Name
            Text(result.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.amenBlack)
                .fixedSize(horizontal: false, vertical: true)

            // Description
            if !result.description.isEmpty {
                Text(result.description)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.amenSlate)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(hex: "D9A441").opacity(0.20), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(categoryLabel): \(result.name). \(result.description)")
    }
}

