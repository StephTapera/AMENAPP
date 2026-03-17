// ChristianMediaBannerView.swift
// AMENAPP
//
// Premium Christian Media discovery banner.
// Visual language: an open media tray/sleeve with layered editorial
// content cards fanning out — a curated content pocket that invites
// exploration of sermons, podcasts, worship, and devotionals.
//
// Reference interpretation:
// - The envelope holder → a soft pearl/neutral media tray
// - The photo cards peeking out → styled media-type cards (scenic/tinted)
// - The front white card → clean editorial content summary card
// - The "36" badge → a curated media count indicator
// - Timestamp metadata → "Curated for you" + content categories

import SwiftUI

// MARK: - Environment Key for press state

private struct MediaBannerPressedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var mediaBannerIsPressed: Bool {
        get { self[MediaBannerPressedKey.self] }
        set { self[MediaBannerPressedKey.self] = newValue }
    }
}

// MARK: - Design Tokens

private enum CMDesign {
    // Palette
    static let tray       = Color(red: 0.92, green: 0.91, blue: 0.895)   // warm pearl
    static let trayEdge   = Color(red: 0.86, green: 0.85, blue: 0.84)    // slightly darker edge
    static let cardWhite  = Color(red: 0.995, green: 0.994, blue: 0.990) // off-white editorial card
    static let deepInk    = Color(red: 0.10, green: 0.10, blue: 0.11)    // headline ink
    static let softInk    = Color(red: 0.48, green: 0.46, blue: 0.46)    // secondary text

    // Media card accent fills (cinematic tints — like scenic photo cards)
    static let cardA = Color(red: 0.32, green: 0.40, blue: 0.52)  // slate dusk — sermon/teaching
    static let cardB = Color(red: 0.42, green: 0.34, blue: 0.28)  // warm amber — worship/music

    // Count badge
    static let badgeAccent = Color(red: 0.52, green: 0.18, blue: 0.80)  // purple — matches brand

    // Geometry
    static let trayRadius: CGFloat   = 26
    static let cardRadius: CGFloat   = 14
    static let bannerHeight: CGFloat = 160
}

// MARK: - ChristianMediaBannerView

struct ChristianMediaBannerView: View {
    /// Drives the fan-in stagger on appear
    @State private var appeared = false
    /// Drives press depth feedback — set by MediaBannerPressStyle via environment
    @Environment(\.mediaBannerIsPressed) private var isPressed

    var body: some View {
        ZStack(alignment: .bottom) {
            // Layer 0: media tray sleeve (the "envelope holder")
            mediaTray

            // Layer 1: back media cards peeking above tray lip
            LayeredMediaPreviewStack(appeared: appeared)
                .frame(height: CMDesign.bannerHeight)
                .allowsHitTesting(false)

            // Layer 2: front editorial card (the main white card in reference)
            editorialCard
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
                .offset(y: isPressed ? 1 : 0)
                .animation(.spring(response: 0.3, dampingFraction: 0.76), value: isPressed)
        }
        .frame(maxWidth: .infinity)
        .frame(height: CMDesign.bannerHeight)
        .scaleEffect(isPressed ? 0.975 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isPressed)
        .onAppear {
            withAnimation(.spring(response: 0.72, dampingFraction: 0.82).delay(0.08)) {
                appeared = true
            }
        }
    }

    // MARK: Media Tray (envelope body)

    private var mediaTray: some View {
        ZStack {
            // Tray body — the open sleeve
            RoundedRectangle(cornerRadius: CMDesign.trayRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: CMDesign.tray, location: 0),
                            .init(color: CMDesign.trayEdge, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    // Subtle inner highlight on top edge
                    RoundedRectangle(cornerRadius: CMDesign.trayRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.55), .clear],
                                startPoint: .top,
                                endPoint: .init(x: 0.5, y: 0.22)
                            )
                        )
                )
                .overlay(
                    // Refined stroke for tactile edge definition
                    RoundedRectangle(cornerRadius: CMDesign.trayRadius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.70), CMDesign.trayEdge.opacity(0.60)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.0
                        )
                )

            // Bottom metadata strip — "Today, curated for you"
            VStack {
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(CMDesign.softInk.opacity(0.7))
                    Text("Curated for you  ·  Sermons, Music, Podcasts")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(CMDesign.softInk.opacity(0.75))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: CMDesign.bannerHeight)
        // Tray depth shadows
        .shadow(color: Color(red: 0.52, green: 0.18, blue: 0.80).opacity(0.10), radius: 18, x: 0, y: 8)
        .shadow(color: .black.opacity(0.07), radius: 5, x: 0, y: 3)
    }

    // MARK: Editorial Front Card

    /// The foreground white card — like the letter pulled forward in the reference.
    /// Contains the content title, descriptor, and media count badge.
    private var editorialCard: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                // Category label — "From:" equivalent
                Text("Christian Media")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CMDesign.badgeAccent)
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .padding(.bottom, 6)

                // Primary headline
                Text("Watch, listen,\nreflect.")
                    .font(.system(size: 22, weight: .bold, design: .default))
                    .foregroundStyle(CMDesign.deepInk)
                    .lineSpacing(2)
                    .padding(.bottom, 7)

                // Supporting descriptor
                Text("Sermons, worship, podcasts & devotionals")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(CMDesign.softInk)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: CMDesign.cardRadius, style: .continuous)
                    .fill(CMDesign.cardWhite)
                    .shadow(color: .black.opacity(0.09), radius: 12, x: 0, y: 4)
                    .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
            )
            .overlay(
                // Hairline border for definition
                RoundedRectangle(cornerRadius: CMDesign.cardRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.055), lineWidth: 0.75)
            )

            // Media count badge (the "36" in reference)
            MediaCountBadge(count: 60)
                .offset(x: -14, y: -12)
        }
    }
}

// MARK: - LayeredMediaPreviewStack

/// Three cards fan-staggered above the tray lip — the photo cards in the reference.
/// Back two are cinematic scene cards; front-most is implicit (the editorial card sits on top).
struct LayeredMediaPreviewStack: View {
    let appeared: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            // Card C — furthest back, left lean
            mediaPreviewCard(
                style: .teachingScene,
                rotation: -7.5,
                xOffset: -36,
                yOffset: appeared ? -74 : -30,
                delay: 0.0
            )

            // Card B — middle, slight right
            mediaPreviewCard(
                style: .worshipScene,
                rotation: 4.0,
                xOffset: 28,
                yOffset: appeared ? -80 : -30,
                delay: 0.06
            )
        }
        // anchor to bottom of frame so cards appear to emerge from the tray opening
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.horizontal, 20)
    }

    private enum CardStyle {
        case teachingScene   // Slate/cool — sermon / Bible teaching
        case worshipScene    // Warm amber — worship / music
    }

    private func mediaPreviewCard(
        style: CardStyle,
        rotation: Double,
        xOffset: CGFloat,
        yOffset: CGFloat,
        delay: Double
    ) -> some View {
        let fill: AnyShapeStyle
        let iconName: String
        let label: String

        switch style {
        case .teachingScene:
            fill = AnyShapeStyle(
                LinearGradient(
                    stops: [
                        .init(color: CMDesign.cardA, location: 0),
                        .init(color: CMDesign.cardA.opacity(0.78), location: 1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            iconName = "book.pages.fill"
            label = "Sermons"
        case .worshipScene:
            fill = AnyShapeStyle(
                LinearGradient(
                    stops: [
                        .init(color: CMDesign.cardB, location: 0),
                        .init(color: CMDesign.cardB.opacity(0.78), location: 1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            iconName = "music.note"
            label = "Worship"
        }

        return ZStack(alignment: .bottomLeading) {
            // Card face
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(fill)
                // Subtle inner top highlight — light entering from above
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.18), .clear],
                                startPoint: .top,
                                endPoint: .init(x: 0.5, y: 0.4)
                            )
                        )
                }
                // Simulated scenic texture lines (minimal, tasteful)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(0..<4, id: \.self) { i in
                            Capsule()
                                .fill(.white.opacity(i == 0 ? 0.12 : 0.06))
                                .frame(width: i == 0 ? 52 : CGFloat(28 + i * 6), height: 2)
                        }
                    }
                    .padding(.top, 12)
                    .padding(.leading, 10)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.20), lineWidth: 0.75)
                )

            // Label chip at bottom of card
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 8, weight: .medium))
                Text(label)
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.88))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Capsule().fill(.black.opacity(0.22)))
            .padding(8)
        }
        .frame(width: 80, height: 100)
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
        .rotationEffect(.degrees(rotation))
        .offset(x: xOffset, y: yOffset)
        .animation(.spring(response: 0.66, dampingFraction: 0.80).delay(delay), value: appeared)
    }
}

// MARK: - MediaCountBadge

/// The subtle "60+" media count chip — adapted from the "36" count in the reference.
struct MediaCountBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "play.rectangle.on.rectangle.fill")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(CMDesign.badgeAccent.opacity(0.75))
            Text("\(count)+ resources")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(CMDesign.softInk)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(CMDesign.badgeAccent.opacity(0.08))
                .overlay(
                    Capsule()
                        .stroke(CMDesign.badgeAccent.opacity(0.18), lineWidth: 0.75)
                )
        )
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color(red: 0.97, green: 0.96, blue: 0.95)
            .ignoresSafeArea()
        VStack {
            ChristianMediaBannerView()
                .padding(.horizontal, 20)
        }
    }
}
