// WhatNeedsAttentionView.swift — AMEN Living Intelligence
// Main "What Needs Your Attention" feed. Six fully-rendered UI states:
//   .loading, .populated, .empty, .error, .offline, .sensitive
//
// Design rules (enforced here):
//   - NO infinite scroll — brief is finite; show all cards in one pass
//   - Pull-to-refresh calls viewModel.refresh() which does NOT re-fetch from network
//   - NO fabricated cards in the empty state
//   - NO count-based solidarity language anywhere

import SwiftUI

// MARK: - Main View

struct WhatNeedsAttentionView: View {
    @StateObject private var viewModel = WhatNeedsAttentionViewModel()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.clear
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()

                stateContent
            }
            .navigationTitle("What Needs Your Attention")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if case .loading = viewModel.state {
                        ProgressView()
                            .scaleEffect(0.85)
                            .accessibilityLabel("Loading your brief")
                    }
                }
            }
            .task { await viewModel.load() }
        }
    }

    // MARK: - State Switch

    @ViewBuilder
    private var stateContent: some View {
        switch viewModel.state {
        case .loading:
            IntelligenceLoadingView()

        case .populated(let brief):
            BriefContentView(brief: brief) { action, cardId in
                Task { await viewModel.handleAction(action, cardId: cardId) }
            }
            // Pull-to-refresh: re-renders same brief, NO new network fetch
            .refreshable {
                await viewModel.refresh()
            }

        case .empty:
            ScrollView {
                EmptyIntelligenceView()
                    .padding(.bottom, 32)
            }

        case .error(let message):
            ScrollView {
                IntelligenceErrorView(message: message) {
                    Task { await viewModel.load() }
                }
                .padding(.bottom, 32)
            }

        case .offline(let stale):
            OfflineIntelligenceView(stale: stale) { action, cardId in
                Task { await viewModel.handleAction(action, cardId: cardId) }
            }
            .refreshable {
                await viewModel.load()
            }

        case .sensitive:
            SensitiveIntelligenceView {
                viewModel.showSensitiveContent = true
                Task { await viewModel.refresh() }
            }
        }
    }
}

// MARK: - BriefContentView

struct BriefContentView: View {
    let brief: IntelligenceBrief
    let onAction: (CardAction, String) -> Void

    /// Cards grouped by Tier in canonical order: SPIRITUAL → COMMUNITY → FAMILY → LOCAL → GLOBAL
    private var groupedByTier: [(Tier, [IntelligenceCard])] {
        let grouped = Dictionary(grouping: brief.cards, by: \.tier)
        return Tier.allCases.compactMap { tier in
            guard let cards = grouped[tier], !cards.isEmpty else { return nil }
            return (tier, cards)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Tier sections
                ForEach(groupedByTier, id: \.0) { tier, cards in
                    tierSection(tier: tier, cards: cards)
                }

                // Brief footer: expiry info
                briefFooter
            }
            .padding(.bottom, 32)
        }
    }

    // MARK: - Tier Section

    private func tierSection(tier: Tier, cards: [IntelligenceCard]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            IntelligenceTierHeaderView(tier: tier)

            VStack(spacing: 12) {
                ForEach(cards) { card in
                    IntelligenceCardView(card: card) { action in
                        onAction(action, card.id)
                    }
                    .padding(.horizontal, 18)
                }
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - Brief Footer

    private var briefFooter: some View {
        let expiresDate = Date(timeIntervalSince1970: brief.expiresAt / 1000)
        let hoursRemaining = max(0, expiresDate.timeIntervalSinceNow / 3600)
        let label: String
        if hoursRemaining < 1 {
            label = "Brief expires soon"
        } else {
            let h = Int(hoursRemaining)
            label = "Brief expires in \(h) hour\(h == 1 ? "" : "s")"
        }

        return Text(label)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .accessibilityLabel(label)
    }
}

// MARK: - IntelligenceLoadingView

struct IntelligenceLoadingView: View {
    @State private var shimmer = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    skeletonCard
                        .padding(.horizontal, 18)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
    }

    private var skeletonCard: some View {
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
        .accessibilityHidden(true)
    }
}

// MARK: - EmptyIntelligenceView

struct EmptyIntelligenceView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "hands.sparkles")
                .font(.systemScaled(52))
                .foregroundStyle(.secondary)

            Text("Your community is quiet right now.")
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text("Keep praying, keep showing up. Check back tomorrow.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            // Prayer Pulse card + scripture prompt
            // CTA navigates to BereanStudyHomeView
            NavigationLink {
                BereanStudyHomeView()
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "cross.circle.fill")
                            .foregroundStyle(.purple)
                            .accessibilityHidden(true)
                        Text("Prayer Pulse")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    }

                    Text("\"Be still, and know that I am God.\"")
                        .font(.footnote)
                        .italic()
                        .foregroundStyle(.secondary)

                    Text("— Psalm 46:10")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Text("Start a Berean study or prayer →")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 2)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                        .strokeBorder(Color.purple.opacity(0.18), lineWidth: 0.75)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .accessibilityLabel("Open Prayer Pulse and Berean study")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - IntelligenceErrorView

struct IntelligenceErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.systemScaled(48))
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

// MARK: - OfflineIntelligenceView

struct OfflineIntelligenceView: View {
    let stale: IntelligenceBrief?
    let onAction: (CardAction, String) -> Void

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Amber stale banner
            staleBanner

            if let brief = stale {
                BriefContentView(brief: brief, onAction: onAction)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        Image(systemName: "wifi.slash")
                            .font(.systemScaled(48))
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)

                        Text("You're Offline")
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text("No cached brief is available. Connect to the internet to load your brief.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
            }
        }
    }

    private var staleBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.caption)
                .foregroundStyle(.primary)

            if let brief = stale {
                let date = Date(timeIntervalSince1970: brief.generatedAt / 1000)
                Text("Last updated \(Self.relativeFormatter.localizedString(for: date, relativeTo: Date()))")
                    .font(.caption)
                    .foregroundStyle(.primary)
            } else {
                Text("Showing cached brief")
                    .font(.caption)
                    .foregroundStyle(.primary)
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.18))
        .accessibilityLabel(
            stale.map {
                let date = Date(timeIntervalSince1970: $0.generatedAt / 1000)
                return "Offline. Last updated \(Self.relativeFormatter.localizedString(for: date, relativeTo: Date()))"
            } ?? "Offline. Showing cached brief"
        )
    }
}

// MARK: - SensitiveIntelligenceView

struct SensitiveIntelligenceView: View {
    let onReveal: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "heart.circle")
                    .font(.systemScaled(52))
                    .foregroundStyle(.secondary)
                    .padding(.top, 40)

                Text("Your brief involves a local tragedy.")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Text("Some of the content in your brief addresses a sensitive situation in your community. We want to engage with care and lament — not scroll past.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Button(action: onReveal) {
                    Text("I want to engage with this")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.75)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("I want to engage with this sensitive content")

                Text("You can dismiss this brief and return later if now isn't the right time.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 40)
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Loading") {
    WhatNeedsAttentionView()
}
#endif
