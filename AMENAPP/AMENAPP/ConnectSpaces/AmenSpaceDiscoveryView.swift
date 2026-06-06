// AmenSpaceDiscoveryView.swift
// AMEN ConnectSpaces — Interest-based community discovery.
//
// Design constraints:
//   - NO follower counts, NO vanity metrics, NO "trending"/"popular" labels.
//   - Results are ONLY filter-driven — no random recommendations surfaced.
//   - Glass ONLY on cards, chips, and section headers. Page canvas stays matte.
//   - Skeleton shimmer respects reduceMotion.
//   - All CF calls go through Functions.functions().httpsCallable("discoverSpaces").
//   - DiscoveredSpace is defined inline; do not import a separate model file.

import SwiftUI
import FirebaseFunctions

// MARK: - Discovered space model

struct DiscoveredSpace: Identifiable, Codable {
    let id: String
    let name: String
    let tagline: String
    let spaceType: String
    let memberCount: Int
    let isVerified: Bool
    let coverImageURL: String?
}

// MARK: - View state

private enum DiscoveryLoadState {
    case idle
    case loading
    case loaded([DiscoveredSpace])
    case empty
    case failed(String)
}

// MARK: - Interest chip data

private struct SpaceDiscoveryInterestChip: Identifiable {
    let id: String
    let label: String
}

private let allInterests: [SpaceDiscoveryInterestChip] = [
    .init(id: "faith",           label: "Faith"),
    .init(id: "prayer",          label: "Prayer"),
    .init(id: "bibleStudy",      label: "Bible Study"),
    .init(id: "worship",         label: "Worship"),
    .init(id: "discipleship",    label: "Discipleship"),
    .init(id: "marriage",        label: "Marriage"),
    .init(id: "recovery",        label: "Recovery"),
    .init(id: "anxiety",         label: "Anxiety"),
    .init(id: "mensMinistry",    label: "Men's Ministry"),
    .init(id: "womensMinistry",  label: "Women's Ministry"),
    .init(id: "youth",           label: "Youth"),
    .init(id: "missions",        label: "Missions"),
    .init(id: "business",        label: "Business"),
    .init(id: "fitness",         label: "Fitness"),
    .init(id: "books",           label: "Books"),
    .init(id: "music",           label: "Music"),
    .init(id: "school",          label: "School"),
    .init(id: "podcasts",        label: "Podcasts")
]

private struct TypeFilter: Identifiable {
    let id: String
    let label: String
    let icon: String
    let spaceType: AmenCreatorSpaceType
}

private let quickTypeFilters: [TypeFilter] = [
    .init(id: "church",   label: "Church",    icon: "building.columns",    spaceType: .church),
    .init(id: "podcast",  label: "Podcast",   icon: "mic.fill",            spaceType: .podcast),
    .init(id: "mentor",   label: "Mentor",    icon: "person.badge.key.fill", spaceType: .mentor),
    .init(id: "bookclub", label: "Book Club", icon: "book.closed.fill",    spaceType: .bookClub),
    .init(id: "recovery", label: "Recovery",  icon: "heart.circle.fill",   spaceType: .recoverySupport)
]

// MARK: - Shimmer modifier

private struct ShimmerModifier: ViewModifier {
    let reduceMotion: Bool
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(0.5)
        } else {
            content
                .overlay(
                    LinearGradient(
                        stops: [
                            .init(color: .clear,                      location: phase - 0.35),
                            .init(color: .white.opacity(0.06),        location: phase),
                            .init(color: .clear,                      location: phase + 0.35)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .allowsHitTesting(false)
                )
                .onAppear {
                    withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                        phase = 1.7
                    }
                }
        }
    }
}

private extension View {
    func discoveryShimmer(reduceMotion: Bool) -> some View {
        modifier(ShimmerModifier(reduceMotion: reduceMotion))
    }
}

// MARK: - Skeleton card

private struct SpaceSkeletonCard: View {
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .frame(height: 14)
                    .frame(maxWidth: 180)

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 11)
                    .frame(maxWidth: 130)
            }

            Spacer()
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
        }
        .discoveryShimmer(reduceMotion: reduceMotion)
        .accessibilityHidden(true)
    }
}

// MARK: - Interest chip pill

private struct SpaceDiscoveryInterestChipPill: View {
    let chip: SpaceDiscoveryInterestChip
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(chip.label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color(hex: "D9A441") : Color.white.opacity(0.80))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    Capsule(style: .continuous)
                        .fill(
                            isSelected
                                ? Color(hex: "D9A441").opacity(0.15)
                                : Color.white.opacity(0.07)
                        )
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    isSelected
                                        ? Color(hex: "D9A441").opacity(0.70)
                                        : Color.white.opacity(0.12),
                                    lineWidth: isSelected ? 1.0 : 0.5
                                )
                        }
                }
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel(chip.label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Type filter chip

private struct TypeFilterChip: View {
    let filter: TypeFilter
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: filter.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(filter.label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(
                isSelected
                    ? filter.spaceType.accentColor
                    : Color.white.opacity(0.65)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        isSelected
                            ? filter.spaceType.accentColor.opacity(0.15)
                            : Color.white.opacity(0.06)
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                isSelected
                                    ? filter.spaceType.accentColor.opacity(0.60)
                                    : Color.white.opacity(0.10),
                                lineWidth: isSelected ? 0.75 : 0.5
                            )
                    }
            }
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel(filter.label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Discovery space card

private struct DiscoverySpaceCard: View {
    let space: DiscoveredSpace

    private var resolvedType: AmenCreatorSpaceType? {
        AmenCreatorSpaceType(rawValue: space.spaceType)
    }

    private var typeIcon: String {
        resolvedType?.systemIcon ?? "person.3.fill"
    }

    private var typeLabel: String {
        resolvedType?.displayName ?? space.spaceType
    }

    private var accentColor: Color {
        resolvedType?.accentColor ?? Color(hex: "6E4BB5")
    }

    private var memberCountCaption: String {
        if space.memberCount >= 1000 {
            return String(format: "%.1fK members", Double(space.memberCount) / 1000)
        }
        return "\(space.memberCount) members"
    }

    var body: some View {
        HStack(spacing: 14) {

            // Type icon in glass circle
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Circle()
                            .strokeBorder(accentColor.opacity(0.35), lineWidth: 0.5)
                    }
                    .frame(width: 48, height: 48)

                Image(systemName: typeIcon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accentColor)
            }

            // Text stack
            VStack(alignment: .leading, spacing: 5) {

                // Name + verified
                HStack(spacing: 6) {
                    Text(space.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if space.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color(hex: "D9A441"))
                            .accessibilityLabel("Verified")
                    }
                }

                // Tagline
                Text(space.tagline)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.60))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                // Type badge + member count (very muted)
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Image(systemName: typeIcon)
                            .font(.system(size: 9, weight: .semibold))
                        Text(typeLabel)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(accentColor.opacity(0.80))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background {
                        Capsule(style: .continuous)
                            .fill(accentColor.opacity(0.10))
                    }

                    Text(memberCountCaption)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.30))
                }
            }

            Spacer(minLength: 4)

            // Learn more chevron
            HStack(spacing: 3) {
                Text("Learn More")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.45))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.30))
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(space.name), \(typeLabel)\(space.isVerified ? ", verified" : ""), \(space.tagline)"
        )
        .accessibilityHint("Tap to learn more about this community")
    }
}

// MARK: - Coming Soon card (location proximity)

private struct ComingSoonProximityCard: View {
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Circle()
                            .strokeBorder(Color(hex: "245B8F").opacity(0.35), lineWidth: 0.5)
                    }
                    .frame(width: 44, height: 44)

                Image(systemName: "location.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: "245B8F"))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Communities Near You")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Coming Soon — location-based discovery is on the way.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.50))
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(hex: "245B8F").opacity(0.20), lineWidth: 0.5)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Communities Near You — Coming Soon")
    }
}

// MARK: - Main view

struct AmenSpaceDiscoveryView: View {

    @State private var selectedInterests: Set<String> = []
    @State private var selectedTypes: Set<String> = []
    @State private var loadState: DiscoveryLoadState = .idle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Computed filter arrays for CF call

    private var interestParams: [String] {
        Array(selectedInterests)
    }

    private var typeParams: [String] {
        Array(selectedTypes)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "070607").ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {

                        // MARK: 1 — Interest filter row
                        VStack(alignment: .leading, spacing: 8) {
                            sectionLabel("What interests you?", accent: Color(hex: "D9A441"))

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(allInterests) { chip in
                                        SpaceDiscoveryInterestChipPill(
                                            chip: chip,
                                            isSelected: selectedInterests.contains(chip.id)
                                        ) {
                                            toggleInterest(chip.id)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 4)
                            }
                        }

                        // MARK: 2 — Space type filter row
                        VStack(alignment: .leading, spacing: 8) {
                            sectionLabel("Community type", accent: Color(hex: "6E4BB5"))

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(quickTypeFilters) { filter in
                                        TypeFilterChip(
                                            filter: filter,
                                            isSelected: selectedTypes.contains(filter.id)
                                        ) {
                                            toggleType(filter)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 4)
                            }
                        }

                        // MARK: 3 — Results
                        VStack(alignment: .leading, spacing: 10) {
                            switch loadState {

                            case .idle:
                                // Show prompt when no filters have been applied yet
                                idlePromptView()

                            case .loading:
                                ForEach(0..<3, id: \.self) { _ in
                                    SpaceSkeletonCard(reduceMotion: reduceMotion)
                                }
                                .padding(.horizontal, 16)

                            case .loaded(let spaces):
                                if spaces.isEmpty {
                                    emptyStateView()
                                } else {
                                    LazyVStack(spacing: 10) {
                                        ForEach(spaces) { space in
                                            DiscoverySpaceCard(space: space)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }

                            case .empty:
                                emptyStateView()

                            case .failed(let message):
                                errorStateView(message: message)
                            }
                        }

                        // MARK: 4 — Near You placeholder
                        VStack(alignment: .leading, spacing: 8) {
                            sectionLabel("Near You", accent: Color(hex: "245B8F"))

                            ComingSoonProximityCard()
                                .padding(.horizontal, 16)
                        }

                        Spacer(minLength: 100)
                    }
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Find Your Community")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                // Do not auto-load with no filters — respect intent-driven model
            }
        }
    }

    // MARK: - Section label helper

    @ViewBuilder
    private func sectionLabel(_ text: String, accent: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .kerning(1.1)
            .foregroundStyle(accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(accent.opacity(0.22), lineWidth: 0.5)
                    }
            }
            .padding(.horizontal, 16)
    }

    // MARK: - Empty state

    @ViewBuilder
    private func emptyStateView() -> some View {
        VStack(spacing: 14) {
            Image(systemName: "globe.americas")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.white.opacity(0.35))

            Text("No communities matched your interests.")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.70))
                .multilineTextAlignment(.center)

            Text("Try adjusting your filters.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No communities matched your interests. Try adjusting your filters.")
    }

    // MARK: - Idle prompt

    @ViewBuilder
    private func idlePromptView() -> some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.white.opacity(0.25))

            Text("Select an interest or community type above to find your people.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.40))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .accessibilityLabel("Select interests or community type to search for communities.")
    }

    // MARK: - Error state

    @ViewBuilder
    private func errorStateView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.white.opacity(0.40))

            Text("Couldn't load communities right now.")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.65))

            Text(message)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.35))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error loading communities: \(message)")
    }

    // MARK: - Toggle helpers

    private func toggleInterest(_ id: String) {
        withAnimation(
            reduceMotion
                ? .easeOut(duration: LiquidGlassTokens.motionFast)
                : .spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.82)
        ) {
            if selectedInterests.contains(id) {
                selectedInterests.remove(id)
            } else {
                selectedInterests.insert(id)
            }
        }
        triggerSearch()
    }

    private func toggleType(_ filter: TypeFilter) {
        withAnimation(
            reduceMotion
                ? .easeOut(duration: LiquidGlassTokens.motionFast)
                : .spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.82)
        ) {
            if selectedTypes.contains(filter.id) {
                selectedTypes.remove(filter.id)
            } else {
                selectedTypes.insert(filter.id)
            }
        }
        triggerSearch()
    }

    // MARK: - Search trigger

    private func triggerSearch() {
        guard !selectedInterests.isEmpty || !selectedTypes.isEmpty else {
            loadState = .idle
            return
        }
        Task { await fetchSpaces() }
    }

    // MARK: - CF call

    @MainActor
    private func fetchSpaces() async {
        loadState = .loading

        let payload: [String: Any] = [
            "interests": interestParams,
            "types": typeParams,
            "limit": 20
        ]

        do {
            let callable = Functions.functions().httpsCallable("discoverSpaces")
            let result = try await callable.call(payload)

            guard let data = result.data as? [[String: Any]] else {
                loadState = .empty
                return
            }

            let jsonData = try JSONSerialization.data(withJSONObject: data)
            let decoded = try JSONDecoder().decode([DiscoveredSpace].self, from: jsonData)

            loadState = decoded.isEmpty ? .empty : .loaded(decoded)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Empty filters — idle") {
    AmenSpaceDiscoveryView()
        .preferredColorScheme(.dark)
}

#Preview("Loaded results") {
    struct Preview: View {
        @State private var view = AmenSpaceDiscoveryView()

        var body: some View {
            AmenSpaceDiscoveryView()
                .preferredColorScheme(.dark)
        }
    }
    return Preview()
        .preferredColorScheme(.dark)
}
#endif
