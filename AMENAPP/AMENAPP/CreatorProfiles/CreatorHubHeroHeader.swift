// CreatorHubHeroHeader.swift
// AMEN — Creator Profiles (ministry hubs) — Wave 3
//
// Full-bleed Creator Hub hero. Extends the existing `.creator` hero concept
// (HeroSurfaceAdapter.fromUser) for ministry hubs: hero media, verified badge,
// role labels, a server-derived status badge (Live / Next event / Prayer / Resource),
// and a row of quick-action glass buttons.
//
// MEDIA-GATE: hero media renders ONLY when moderation == .approved (isServable);
// otherwise a brand gradient is shown. The client never renders unapproved media.
//
// Conventions: white bg under content; legibility gradient over media; black/white text
// driven by media overlay; AmenTheme.Colors.* + Color(hex:) tokens; no glass-on-glass
// (quick-action buttons are glass over MEDIA, not over a glass parent); Dynamic Type;
// VoiceOver labels on every interactive element; reduce-motion disables Live pulse.

import SwiftUI

// MARK: - Quick actions

enum CreatorHubQuickAction: String, CaseIterable, Identifiable {
    case follow, message, pray, support, share
    var id: String { rawValue }

    var title: String {
        switch self {
        case .follow:  return "Follow"
        case .message: return "Message"
        case .pray:    return "Pray"
        case .support: return "Support"
        case .share:   return "Share"
        }
    }

    var systemImage: String {
        switch self {
        case .follow:  return "plus.circle"
        case .message: return "bubble.left"
        case .pray:    return "hands.sparkles"
        case .support: return "heart"
        case .share:   return "square.and.arrow.up"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .follow:  return "Follow this ministry to receive updates"
        case .message: return "Send a message"
        case .pray:    return "Open the prayer board"
        case .support: return "Support this ministry"
        case .share:   return "Share this profile"
        }
    }
}

// MARK: - Hero header

struct CreatorHubHeroHeader: View {
    let profile: CreatorHubProfile
    let heroState: CreatorHubHeroState
    /// Donations are gated — Support is hidden unless this is true.
    var supportEnabled: Bool = false
    /// 0 (expanded) … 1 (fully collapsed). Drives shrink + fade as the screen scrolls.
    var collapseProgress: Double = 0
    var onAction: (CreatorHubQuickAction) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clampedCollapse: Double { min(max(collapseProgress, 0), 1) }

    private var heroHeight: CGFloat {
        let expanded: CGFloat = 360
        let collapsed: CGFloat = 140
        return expanded - (expanded - collapsed) * clampedCollapse
    }

    /// Quick actions shown — Support omitted unless donations are enabled.
    private var actions: [CreatorHubQuickAction] {
        CreatorHubQuickAction.allCases.filter { $0 != .support || supportEnabled }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            heroBackground
            legibilityGradient
            heroContent
                .opacity(1 - clampedCollapse * 0.85)
        }
        .frame(height: heroHeight)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    // MARK: Background (MEDIA-GATE enforced)

    @ViewBuilder
    private var heroBackground: some View {
        if let media = profile.heroMedia,
           media.isServable,
           media.kind == .image,
           let url = URL(string: media.storagePath) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    brandGradient
                case .empty:
                    brandGradient.overlay { ProgressView().tint(.white) }
                @unknown default:
                    brandGradient
                }
            }
            .accessibilityHidden(true)
        } else {
            brandGradient
        }
    }

    /// Brand gradient fallback (used when media is missing or not approved).
    private var brandGradient: some View {
        LinearGradient(
            colors: [
                Color(hex: "1B1B1F"),
                Color(hex: "2A2730"),
                AmenTheme.Colors.amenGold.opacity(0.30),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Dark legibility scrim so white text stays readable over any media.
    private var legibilityGradient: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.0),
                Color.black.opacity(0.20),
                Color.black.opacity(0.60),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .accessibilityHidden(true)
    }

    // MARK: Foreground content

    private var heroContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusBadge

            HStack(spacing: 6) {
                Text(profile.displayName)
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if profile.verified {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(AmenTheme.Colors.amenGold)
                        .accessibilityLabel("Verified")
                }
            }
            .accessibilityElement(children: .combine)

            if !profile.roleLabels.isEmpty {
                Text(profile.roleLabels.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }

            quickActionRow
                .padding(.top, 4)
        }
        .padding(20)
    }

    // MARK: Status badge (derived from heroState)

    @ViewBuilder
    private var statusBadge: some View {
        switch heroState {
        case .live:
            badge(icon: "dot.radiowaves.left.and.right", text: "Live now", tint: Color(hex: "E0394B"), pulsing: true)
        case .nextEvent(let event):
            badge(icon: "calendar", text: "Next: \(event.title)", tint: AmenTheme.Colors.amenGold, pulsing: false)
        case .latestTeaching(let teaching):
            badge(icon: "play.circle", text: teaching.title, tint: AmenTheme.Colors.statusInfo, pulsing: false)
        case .prayer(let openRequests):
            badge(icon: "hands.sparkles", text: "\(openRequests) prayer requests", tint: AmenTheme.Colors.statusSuccess, pulsing: false)
        case .resource(let resource):
            badge(icon: "doc.text", text: resource.title, tint: AmenTheme.Colors.amenGold, pulsing: false)
        case .idle:
            EmptyView()
        }
    }

    private func badge(icon: String, text: String, tint: Color, pulsing: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .imageScale(.small)
                .modifier(PulseModifier(active: pulsing && !reduceMotion))
            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule().fill(tint.opacity(0.92))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }

    // MARK: Quick action row (glass over MEDIA — not over a glass parent)

    private var quickActionRow: some View {
        HStack(spacing: 10) {
            ForEach(actions) { action in
                Button {
                    onAction(action)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: action.systemImage)
                            .imageScale(.small)
                        Text(action.title)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule().strokeBorder(Color.white.opacity(0.30), lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(action.title)
                .accessibilityHint(action.accessibilityHint)
            }
        }
    }
}

// MARK: - Pulse (reduce-motion aware)

private struct PulseModifier: ViewModifier {
    let active: Bool
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(active && pulse ? 1.25 : 1.0)
            .opacity(active && pulse ? 0.55 : 1.0)
            .onAppear {
                guard active else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

// MARK: - HeroSurface extension (extends the .creator kind, per product decision)

#if canImport(AdaptiveHeroEngine)
import AdaptiveHeroEngine

extension HeroSurface {
    /// Map a CreatorHubProfile into a `.creator` HeroSurface so ministry hubs reuse the
    /// existing adaptive hero engine. Mirrors `HeroSurface.fromUser` field-for-field.
    static func creatorHubSurface(
        _ profile: CreatorHubProfile,
        relationship: ViewerRelationship = .stranger
    ) -> HeroSurface {
        let heroURL = profile.heroMedia
            .filter { $0.isServable }
            .flatMap { URL(string: $0.storagePath) }

        return HeroSurface(
            id: profile.id,
            kind: .creator,
            visibility: .publicAll,
            viewerRelationship: relationship,
            title: LocalizedStringKey(profile.displayName),
            subtitle: profile.roleLabels.isEmpty
                ? nil
                : LocalizedStringKey(profile.roleLabels.joined(separator: " · ")),
            hero: HeroImageRef(url: heroURL, cacheKey: "creatorHub_\(profile.id)"),
            avatar: HeroImageRef(url: heroURL, cacheKey: "creatorHubAvatar_\(profile.id)"),
            badges: [],
            trust: profile.verified ? .knownInCommunity : .unverified,
            faithTags: [],
            location: nil,
            modules: []
        )
    }
}
#endif
