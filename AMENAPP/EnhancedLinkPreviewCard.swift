//
//  EnhancedLinkPreviewCard.swift
//  AMENAPP
//
//  Smart link preview card for the post feed.
//  - Category-aware display variants (Bible, Church, News, Video, Podcast, Event, Warning)
//  - Compressed pressed-state animation
//  - Skeleton loading state when metadata is nil
//  - Routes via SmartLinkClassifier.openMode to the correct destination
//  - Safety interstitial for suspicious or warned links
//

import SwiftUI

struct EnhancedLinkPreviewCard: View {
    let url: URL
    let metadata: LinkPreviewMetadata?

    @State private var showBrowser = false
    @State private var showSafetyWarning = false
    @State private var safetyWarningMessage = ""
    @State private var isPressed = false

    private var category: LinkCategory {
        SmartLinkClassifier.classify(url)
    }

    private var domain: String {
        SmartLinkClassifier.displayDomain(for: url)
    }

    var body: some View {
        Button {
            handleTap()
        } label: {
            cardContent
                .scaleEffect(isPressed ? 0.97 : 1.0)
                .shadow(
                    color: .black.opacity(isPressed ? 0.10 : 0.04),
                    radius: isPressed ? 12 : 8,
                    y: isPressed ? 5 : 3
                )
                .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        // In-app browser sheet
        .sheet(isPresented: $showBrowser) {
            InAppBrowserView(
                url: url,
                title: metadata?.title,
                domain: domain,
                category: category
            )
            .ignoresSafeArea()
        }
        // Safety interstitial
        .sheet(isPresented: $showSafetyWarning) {
            LinkSafetyInterstitialSheet(
                url: url,
                message: safetyWarningMessage
            ) { didProceed in
                showSafetyWarning = false
                if didProceed {
                    UIApplication.shared.open(url)
                }
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Tap Routing

    private func handleTap() {
        isPressed = false
        let mode = SmartLinkClassifier.openMode(for: url)

        switch mode {
        case .inAppBrowser:
            showBrowser = true

        case .scriptureViewer:
            // Bible links: open in-app browser — native scripture viewer
            // is a future enhancement gated by a separate feature flag.
            showBrowser = true

        case .mapsOrEventAction:
            // Fall through to in-app browser for now;
            // a native event action sheet is a future UI change requiring approval.
            showBrowser = true

        case .externalApp, .externalSafariFallback:
            UIApplication.shared.open(url)

        case .nativeInternal:
            // Internal deep links are handled by the feed's existing NotificationDeepLinkRouter.
            UIApplication.shared.open(url)

        case .safetyInterstitial(let message):
            safetyWarningMessage = message
            showSafetyWarning = true
        }
    }

    // MARK: - Affiliate Detection

    /// True when the URL is an Amazon affiliate link (host contains amazon. and has a `tag` query param).
    private var isAffiliateLink: Bool {
        guard let host = url.host?.lowercased(), host.contains("amazon.") else { return false }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return items.contains { $0.name == "tag" }
    }

    // MARK: - Card Content

    @ViewBuilder
    private var cardContent: some View {
        if metadata == nil {
            skeletonCard
        } else {
            VStack(alignment: .leading, spacing: 4) {
                richCard
                // FTC required: clear affiliate disclosure before user taps the link.
                if isAffiliateLink {
                    Text(AffiliateConfig.disclosure)
                        .font(AMENFont.regular(10))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .accessibilityLabel("Affiliate disclosure: \(AffiliateConfig.disclosure)")
                }
            }
        }
    }

    // MARK: - Skeleton Loading State

    private var skeletonCard: some View {
        HStack(spacing: 12) {
            // Leading shimmer block (thumbnail placeholder)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.05))
                .frame(width: 64, height: 64)
                .shimmering()

            VStack(alignment: .leading, spacing: 6) {
                // Domain shimmer
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.black.opacity(0.05))
                    .frame(width: 90, height: 10)
                    .shimmering()

                // Title shimmer
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.black.opacity(0.06))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 13)
                    .shimmering()

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.black.opacity(0.04))
                    .frame(width: 140, height: 13)
                    .shimmering()
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .cardShell(cornerRadius: 14)
    }

    // MARK: - Rich Card

    private var richCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero image (only shown if we have a thumbnail and it's not a compact layout)
            if let imageURL = metadata?.imageURL, shouldShowHeroImage {
                CachedAsyncImage(
                    url: imageURL,
                    size: CGSize(width: 400, height: 200)
                ) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(height: 148)
                        .clipped()
                } placeholder: {
                    Rectangle()
                        .fill(Color.black.opacity(0.04))
                        .frame(height: 148)
                        .overlay(
                            Image(systemName: category.icon)
                                .font(.systemScaled(22))
                                .foregroundStyle(.black.opacity(0.12))
                        )
                }
            }

            HStack(alignment: .top, spacing: 10) {
                // Compact thumbnail for non-hero layouts
                if !shouldShowHeroImage, let imageURL = metadata?.imageURL {
                    CachedAsyncImage(
                        url: imageURL,
                        size: CGSize(width: 120, height: 120)
                    ) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.05))
                            .frame(width: 60, height: 60)
                            .overlay(
                                Image(systemName: category.icon)
                                    .font(.systemScaled(18))
                                    .foregroundStyle(.black.opacity(0.15))
                            )
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    // Category badge + domain row
                    HStack(spacing: 6) {
                        if category.showsBadge {
                            categoryBadge
                        }

                        Text(domain)
                            .font(AMENFont.regular(11))
                            .foregroundStyle(.black.opacity(0.40))
                            .lineLimit(1)

                        Spacer()

                        Image(systemName: "arrow.up.right")
                            .font(.systemScaled(10, weight: .semibold))
                            .foregroundStyle(.black.opacity(0.25))
                    }

                    // Title
                    if let title = metadata?.title, !title.isEmpty {
                        Text(title)
                            .font(AMENFont.semiBold(15))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Description (only shown in hero layout)
                    if shouldShowHeroImage, let desc = metadata?.description, !desc.isEmpty {
                        Text(desc)
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.black.opacity(0.55))
                            .lineLimit(2)
                    }
                }
            }
            .padding(12)
        }
        .cardShell(cornerRadius: 14)
    }

    // MARK: - Category Badge

    private var categoryBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: category.icon)
                .font(.systemScaled(9, weight: .bold))
            if category == .unsafe {
                Text("Warning")
                    .font(AMENFont.semiBold(10))
            }
        }
        .foregroundStyle(badgeForeground)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(badgeBackground)
        )
    }

    private var badgeForeground: Color {
        category == .unsafe ? .white : .black
    }

    private var badgeBackground: Color {
        switch category {
        case .unsafe:   return .red
        case .bible:    return Color.black.opacity(0.10)
        case .church:   return Color.black.opacity(0.08)
        case .news:     return Color.black.opacity(0.07)
        default:        return Color.black.opacity(0.06)
        }
    }

    /// Show a large hero image for articles/church; compact thumbnail for others.
    private var shouldShowHeroImage: Bool {
        guard metadata?.imageURL != nil else { return false }
        switch category {
        case .news, .church, .general: return true
        default: return false
        }
    }
}

// MARK: - Safety Interstitial Sheet

private struct LinkSafetyInterstitialSheet: View {
    let url: URL
    let message: String
    let completion: (Bool) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Color.black.opacity(0.12))
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("Be Careful")
                .font(AMENFont.bold(18))
                .foregroundStyle(.primary)

            Text(message)
                .font(AMENFont.regular(14))
                .foregroundStyle(.black.opacity(0.60))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Text(SmartLinkClassifier.displayDomain(for: url))
                .font(AMENFont.regular(12))
                .foregroundStyle(.black.opacity(0.40))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.06)))

            VStack(spacing: 10) {
                Button {
                    completion(true)
                } label: {
                    Text("Open Anyway")
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black))
                }

                Button {
                    completion(false)
                } label: {
                    Text("Go Back")
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.07)))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color.white)
    }
}

// MARK: - View Helpers

private extension View {
    /// Consistent card shell used across card variants.
    func cardShell(cornerRadius: CGFloat) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Shimmer placeholder animation for skeleton loading.
    func shimmering() -> some View {
        self.modifier(ShimmerModifier())
    }
}

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: phase - 0.3),
                        .init(color: .white.opacity(0.55), location: phase),
                        .init(color: .clear, location: phase + 0.3),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1.3
                }
            }
    }
}
