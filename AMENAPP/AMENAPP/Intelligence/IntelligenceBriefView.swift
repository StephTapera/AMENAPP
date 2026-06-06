import SwiftUI

// MARK: - Skeleton Loader

private struct IntelligenceSkeletonCard: View {
    @State private var shimmer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .frame(width: 72, height: 18)
                Spacer()
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .frame(width: 90, height: 14)
            }
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .frame(maxWidth: .infinity)
                .frame(height: 20)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .frame(width: 200, height: 14)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .frame(width: 160, height: 14)
        }
        .padding(16)
        .foregroundStyle(
            LinearGradient(
                colors: shimmer
                    ? [Color.primary.opacity(0.08), Color.primary.opacity(0.04)]
                    : [Color.primary.opacity(0.04), Color.primary.opacity(0.08)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                shimmer = true
            }
        }
        .accessibilityLabel("Loading card")
        .accessibilityHidden(true)
    }
}

// MARK: - Empty State

private struct IntelligenceEmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "hands.sparkles")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)

            Text("Nothing Needs Attention Right Now")
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text("You're caught up. Keep praying, keep showing up.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            // Prayer Pulse card
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "cross.circle.fill")
                        .foregroundStyle(.purple)
                    Text("Prayer Pulse")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                Text("\"Be still, and know that I am God.\"")
                    .font(.footnote)
                    .italic()
                    .foregroundStyle(.secondary)

                Text("— Psalm 46:10")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .livingGlassMaterial(tint: Color.purple.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous))
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Error State

private struct IntelligenceBriefErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Something Went Wrong")
                .font(.title3)
                .fontWeight(.semibold)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button(action: onRetry) {
                Text("Try Again")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry loading your brief")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

// MARK: - Offline Banner

private struct IntelligenceOfflineBanner: View {
    let lastRefreshed: Date?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let refreshed = lastRefreshed {
                Text("Refreshed \(Self.relativeFormatter.localizedString(for: refreshed, relativeTo: Date()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Showing cached brief")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .accessibilityLabel("Offline. \(lastRefreshed.map { "Last refreshed \(Self.relativeFormatter.localizedString(for: $0, relativeTo: Date()))" } ?? "Showing cached brief")")
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
}

// MARK: - Sensitive State

private struct IntelligenceSensitiveStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.circle")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)

            Text("Sensitive Content")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Your brief contains sensitive items. Each card will ask for your consent before revealing details.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Main Brief View

struct IntelligenceBriefView: View {
    @StateObject private var viewModel = IntelligenceBriefViewModel()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                background

                VStack(spacing: 0) {
                    // Offline stale banner sits at the top below nav
                    if case .offlineStale = viewModel.state {
                        IntelligenceOfflineBanner(lastRefreshed: viewModel.lastRefreshed)
                    }

                    briefContent
                }
            }
            .navigationTitle("What Needs Your Attention")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.state == .loading {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
            }
            .task { await viewModel.loadBrief() }
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var background: some View {
        Color.clear
            .background(.ultraThinMaterial)
            .ignoresSafeArea()
    }

    // MARK: - Content Switch

    @ViewBuilder
    private var briefContent: some View {
        switch viewModel.state {
        case .loading:
            loadingView
        case .populated:
            populatedView
        case .empty:
            ScrollView {
                IntelligenceEmptyStateView()
                    .padding(.bottom, 32)
            }
        case .error(let message):
            ScrollView {
                IntelligenceBriefErrorView(message: message) {
                    Task { await viewModel.loadBrief() }
                }
                .padding(.bottom, 32)
            }
        case .offlineStale:
            // Serve the stale brief with banner already shown above
            populatedView
        case .sensitive:
            ScrollView {
                VStack(spacing: 0) {
                    IntelligenceSensitiveStateView()
                    cardListView
                }
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    IntelligenceSkeletonCard()
                        .padding(.horizontal, 18)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Populated

    private var populatedView: some View {
        // Finite brief — ScrollView with all cards (max 7). No "load more".
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                cardListView
            }
            .padding(.bottom, 32)
        }
        .refreshable {
            // Pull-to-refresh re-renders the SAME brief (formation invariant: no new ranking)
            await viewModel.refreshBrief()
        }
    }

    // MARK: - Grouped Card List

    private var cardListView: some View {
        // Group cards by tier in canonical order: SPIRITUAL, COMMUNITY, FAMILY, LOCAL, GLOBAL
        let grouped = Dictionary(grouping: viewModel.cards, by: \.tier)
        let orderedTiers = IntelligenceTier.allCases.filter { grouped[$0] != nil }

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(orderedTiers, id: \.self) { tier in
                if let tierCards = grouped[tier], !tierCards.isEmpty {
                    IntelligenceTierHeaderView(tier: tier)

                    VStack(spacing: 12) {
                        ForEach(tierCards) { card in
                            IntelligenceCardView(card: card) { action in
                                viewModel.handleAction(action, on: card)
                            }
                            .padding(.horizontal, 18)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
    }
}
