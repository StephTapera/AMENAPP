// ConnectWave0UIContracts.swift
// AMEN Connect — Wave 0 Frozen UI Contracts
//
// FROZEN 2026-06-10. Do not edit without Lead Orchestrator authorization.
// See CONTRACTS.md for the full decision record.
//
// Contains:
//   C-1  ConnectChromeMetrics
//   C-2  ConnectStrings.aiSummaryDisclosure
//   C-3  ConnectEmptyStateView + ConnectCTAConfig
//   C-4  SkeletonCard + SkeletonRail

import SwiftUI

// MARK: - C-1: Bottom Chrome Inset

/// Single source of truth for floating Connect chrome heights.
/// Every ScrollView in the Connect module must consume `bottomInset`
/// via .safeAreaInset(edge: .bottom) or .contentMargins(.bottom, ...).
enum ConnectChromeMetrics {
    static let tabBarHeight: CGFloat = 49
    static let bereanPillHeight: CGFloat = 50
    static let breathingMargin: CGFloat = 16
    /// Total bottom inset consumed by floating Connect chrome (115 pt).
    static var bottomInset: CGFloat { tabBarHeight + bereanPillHeight + breathingMargin }
}

// MARK: - C-2: Canonical AI Disclosure

/// Canonical AI disclosure string for all Connect AI surfaces.
/// This is the only permitted disclosure text — delete any divergent variants.
enum ConnectStrings {
    static let aiSummaryDisclosure: String = NSLocalizedString(
        "connect.ai.disclosure",
        value: "AI summaries include only content you can access. Private, paid, confidential, youth-protected, deleted, and admin-excluded content is never included.",
        comment: "Standard AI permission boundary disclosure shown on all Connect AI surfaces"
    )
}

// MARK: - C-3: ConnectEmptyStateView

struct ConnectCTAConfig {
    let label: String
    let systemImage: String?
    let action: () -> Void

    init(_ label: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.action = action
    }
}

/// Canonical empty-state component for all Connect surfaces.
/// CTA buttons use native Liquid Glass (.amenGlassEffect). Entrance respects Reduce Motion.
/// Never place this component on top of another glass surface (C-5 glass-on-glass rule).
struct ConnectEmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let primaryCTA: ConnectCTAConfig
    var secondaryCTA: ConnectCTAConfig? = nil
    var ghostPreview: AnyView? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {
                Image(systemName: icon)
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ctaStack

                if let ghostPreview {
                    ghostPreview
                        .frame(maxWidth: .infinity)
                        .frame(height: 96)
                        .clipped()
                        .overlay(
                            LinearGradient(
                                colors: [.clear, Color(.systemBackground).opacity(0.88)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .cornerRadius(12)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 40)
        }
        .frame(maxWidth: .infinity)
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.94)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : AmenMotion.cardSpring) {
                appeared = true
            }
        }
    }

    @ViewBuilder
    private var ctaStack: some View {
        VStack(spacing: 10) {
            ctaButton(primaryCTA, isPrimary: true)
            if let secondary = secondaryCTA {
                ctaButton(secondary, isPrimary: false)
            }
        }
    }

    @ViewBuilder
    private func ctaButton(_ config: ConnectCTAConfig, isPrimary: Bool) -> some View {
        Button(action: config.action) {
            HStack(spacing: 6) {
                if let image = config.systemImage {
                    Image(systemName: image)
                        .font(.subheadline.weight(.semibold))
                }
                Text(config.label)
                    .font(.subheadline.weight(isPrimary ? .semibold : .medium))
            }
            .foregroundStyle(isPrimary ? Color.primary : Color.secondary)
            .padding(.horizontal, isPrimary ? 24 : 18)
            .padding(.vertical, isPrimary ? 13 : 11)
            .frame(minWidth: 44, minHeight: 44)
            .amenGlassEffect(in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(config.label)
    }
}

// MARK: - C-4: SkeletonCard + SkeletonRail

/// Single shimmer card placeholder. Shimmer respects Reduce Motion.
struct SkeletonCard: View {
    var cornerRadius: CGFloat = 16
    var aspectRatio: CGFloat = 1.4

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerPhase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(.systemGray5))
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay(shimmerLayer)
            .accessibilityLabel("Loading")
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    .linear(duration: 1.4)
                    .repeatForever(autoreverses: false)
                ) {
                    shimmerPhase = 1
                }
            }
    }

    @ViewBuilder
    private var shimmerLayer: some View {
        if !reduceMotion {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color.white.opacity(0.38), location: 0.5),
                    .init(color: .clear, location: 1)
                ],
                startPoint: UnitPoint(x: shimmerPhase - 0.3, y: 0.5),
                endPoint: UnitPoint(x: shimmerPhase + 0.3, y: 0.5)
            )
            .blendMode(.plusLighter)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .allowsHitTesting(false)
        }
    }
}

/// Horizontal rail of shimmer cards. Used for Discover section loading states.
struct SkeletonRail: View {
    var cardCount: Int = 3
    var cardWidth: CGFloat = 180
    var cardAspectRatio: CGFloat = 1.3
    var spacing: CGFloat = 12

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                ForEach(0..<cardCount, id: \.self) { _ in
                    SkeletonCard(aspectRatio: cardAspectRatio)
                        .frame(width: cardWidth)
                }
            }
            .padding(.horizontal, 20)
        }
        .disabled(true)
        .accessibilityLabel("Loading content")
    }
}

// MARK: - C-5 Navigation Note (see CONTRACTS.md for full decision)
// Connect pill row: Lobby | Discover | Spaces | Activity  (4 sections)
// DMs: owned by Messages bottom tab — removed from Connect pill row
// Bottom tabs: Home | Search | Messages | Resources | Profile
