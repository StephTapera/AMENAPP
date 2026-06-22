// AmenCreatorSpaceHeroView.swift
// AMEN ConnectSpaces — Reusable Liquid Glass hero for any Space or Creator profile.
//
// Design constraints:
//   - Glass ONLY on the bottom action-bar strip and individual CTA pill buttons.
//   - Background is matte (gradient or AsyncImage + dark overlay). No glass on glass.
//   - Pulsing LIVE dot skipped when reduceMotion is true.
//   - Every interactive element meets a 44×44 pt minimum tap target.
//   - No force-unwraps anywhere in this file.

import SwiftUI

// MARK: - LIVE pulse dot

private struct LivePulseDot: View {
    let reduceMotion: Bool
    @State private var pulseOpacity: Double = 1.0

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                // Outer glow ring
                Circle()
                    .fill(Color.red.opacity(reduceMotion ? 0 : 0.35))
                    .frame(width: 12, height: 12)
                    .opacity(pulseOpacity)
                // Solid core dot
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)
            }
            Text("LIVE")
                .font(.systemScaled(10, weight: .black))
                .kerning(0.8)
                .foregroundStyle(Color.red)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: 0.9)
                .repeatForever(autoreverses: true)
            ) {
                pulseOpacity = 0.2
            }
        }
        .accessibilityLabel("Live now")
    }
}

// MARK: - Glass CTA pill button

private struct HeroCTAButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.systemScaled(13, weight: .semibold))
                Text(label)
                    .font(.systemScaled(13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color(hex: "D9A441").opacity(0.55), lineWidth: 0.75)
                    }
            }
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(label)
    }
}

// MARK: - Type badge chip

private struct SpaceTypeBadge: View {
    let spaceType: AmenCreatorSpaceType

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: spaceType.systemIcon)
                .font(.systemScaled(10, weight: .semibold))
            Text(spaceType.displayName)
                .font(.systemScaled(11, weight: .semibold))
        }
        .foregroundStyle(Color.white.opacity(0.75))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.10))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.5)
                }
        }
    }
}

// MARK: - Hero background (gradient fallback)

private struct TypeGradientBackground: View {
    let spaceType: AmenCreatorSpaceType

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: spaceType.accentColor.opacity(0.80), location: 0.0),
                    .init(color: spaceType.accentColor.opacity(0.40), location: 0.45),
                    .init(color: Color(hex: "070607"),                 location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(hex: "D9A441").opacity(0.15),
                    Color.clear
                ],
                center: UnitPoint(x: 0.72, y: 0.20),
                startRadius: 0,
                endRadius: 160
            )
        }
    }
}

// MARK: - Cover image background

private struct CoverImageBackground: View {
    let url: URL
    let accentColor: Color

    var body: some View {
        ZStack(alignment: .bottom) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    TypeGradientBackground(
                        spaceType: .church    // fallback; accent passed separately
                    )
                case .empty:
                    Color(hex: "070607")
                        .overlay(
                            ProgressView()
                                .tint(Color.white.opacity(0.5))
                        )
                @unknown default:
                    Color(hex: "070607")
                }
            }

            // Bottom gradient fade — covers bottom 60% toward app background
            LinearGradient(
                stops: [
                    .init(color: Color.clear,          location: 0.0),
                    .init(color: Color(hex: "070607").opacity(0.55), location: 0.40),
                    .init(color: Color(hex: "070607"),               location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - Main view

struct AmenCreatorSpaceHeroView: View {
    let spaceName: String
    let spaceType: AmenCreatorSpaceType
    let tagline: String
    let memberCount: Int
    let isLiveNow: Bool
    let isVerified: Bool
    let coverImageURL: String?
    let onJoin: (() -> Void)?
    let onWatch: (() -> Void)?
    let onPray: (() -> Void)?
    let onMessage: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Formatted member count (private, non-prominent)

    private var memberCountText: String {
        if memberCount >= 1_000_000 {
            return String(format: "%.1fM members", Double(memberCount) / 1_000_000)
        } else if memberCount >= 1000 {
            return String(format: "%.1fK members", Double(memberCount) / 1000)
        } else {
            return "\(memberCount) members"
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {

            // MARK: Background layer
            Group {
                if let rawURL = coverImageURL, let url = URL(string: rawURL) {
                    CoverImageBackground(url: url, accentColor: spaceType.accentColor)
                } else {
                    TypeGradientBackground(spaceType: spaceType)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            // MARK: Bottom content strip (glass base)
            VStack(alignment: .leading, spacing: 0) {

                // Action buttons — float above the text strip
                HStack(spacing: 8) {
                    Spacer()

                    if let watch = onWatch, isLiveNow {
                        HeroCTAButton(icon: "play.fill", label: "Watch", action: watch)
                    }
                    if let pray = onPray {
                        HeroCTAButton(icon: "hands.sparkles.fill", label: "Pray", action: pray)
                    }
                    if let message = onMessage {
                        HeroCTAButton(icon: "message.fill", label: "Message", action: message)
                    }
                    if let join = onJoin {
                        HeroCTAButton(icon: "plus.circle.fill", label: "Join", action: join)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

                // Text info section with thinMaterial background
                VStack(alignment: .leading, spacing: 6) {

                    // Row 1: space name + LIVE dot
                    HStack(alignment: .center, spacing: 10) {
                        Text(spaceName)
                            .font(.systemScaled(24, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)

                        if isLiveNow {
                            LivePulseDot(reduceMotion: reduceMotion)
                        }
                    }

                    // Row 2: type badge + verified badge
                    HStack(spacing: 6) {
                        SpaceTypeBadge(spaceType: spaceType)

                        if isVerified {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.systemScaled(11, weight: .bold))
                                Text("Verified")
                                    .font(.systemScaled(11, weight: .semibold))
                            }
                            .foregroundStyle(Color(hex: "D9A441"))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(Color(hex: "D9A441").opacity(0.15))
                                    .overlay {
                                        Capsule(style: .continuous)
                                            .strokeBorder(Color(hex: "D9A441").opacity(0.40), lineWidth: 0.5)
                                    }
                            }
                            .accessibilityLabel("Verified community")
                        }
                    }

                    // Row 3: tagline
                    if !tagline.isEmpty {
                        Text(tagline)
                            .font(.systemScaled(13, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.65))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial)
            }
        }
        .frame(height: 240)
        .clipped()
        .ignoresSafeArea(edges: .top)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Church — Cover Image — Live") {
    ZStack {
        Color(hex: "070607").ignoresSafeArea()
        VStack(spacing: 0) {
            AmenCreatorSpaceHeroView(
                spaceName: "Elevation Church",
                spaceType: .church,
                tagline: "We exist to see people far from God raised to life in Christ.",
                memberCount: 18_400,
                isLiveNow: true,
                isVerified: true,
                coverImageURL: nil,
                onJoin: {},
                onWatch: {},
                onPray: {},
                onMessage: {}
            )
            Spacer()
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Podcast — No Cover — Not Live") {
    ZStack {
        Color(hex: "070607").ignoresSafeArea()
        VStack(spacing: 0) {
            AmenCreatorSpaceHeroView(
                spaceName: "The Bible Project Podcast",
                spaceType: .podcast,
                tagline: "Exploring the biblical narrative together.",
                memberCount: 3_200,
                isLiveNow: false,
                isVerified: false,
                coverImageURL: nil,
                onJoin: {},
                onWatch: nil,
                onPray: nil,
                onMessage: nil
            )
            Spacer()
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Recovery Support — Sensitive") {
    ZStack {
        Color(hex: "070607").ignoresSafeArea()
        VStack(spacing: 0) {
            AmenCreatorSpaceHeroView(
                spaceName: "Walking in Freedom",
                spaceType: .recoverySupport,
                tagline: "A safe community for healing and restoration.",
                memberCount: 84,
                isLiveNow: false,
                isVerified: false,
                coverImageURL: nil,
                onJoin: {},
                onWatch: nil,
                onPray: {},
                onMessage: {}
            )
            Spacer()
        }
    }
    .preferredColorScheme(.dark)
}
#endif
