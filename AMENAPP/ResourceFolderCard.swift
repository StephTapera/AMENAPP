// ResourceFolderCard.swift
// AMENAPP
//
// Premium folder-style banner card for resource category navigation.
// Design language: soft glass folder with layered document depth,
// warm ambient glow, and Apple-native spring press response.
// Inspired by folder-as-icon metaphor — tactile, spatial, premium.

import SwiftUI

// MARK: - ResourceFolderCard

/// Full-width banner folder card.
/// Replaces WellnessCard for section entries in ResourcesView.
struct ResourceFolderCard: View {

    let icon: String
    let title: String
    let subtitle: String
    let chips: [String]          // 2–3 short keyword chips shown as document labels
    let accentColor: Color
    let folderColor: Color       // slightly darker — the folder back
    let paperColor: Color        // lighter — the peeking content layers

    // Lift animation state driven by FolderPressEffect
    var isPressed: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {

            // ── Folder back (slightly taller, peeks above lip) ──────────────
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(folderColor)
                .frame(height: 108)
                .overlay(alignment: .top) {
                    // Folder tab nub — top-left pill
                    Capsule()
                        .fill(folderColor.mix(with: .black, by: 0.08))
                        .frame(width: 64, height: 14)
                        .offset(x: -62, y: -7)
                }

            // ── Peeking content layers (paper sheets) ───────────────────────
            paperLayers

            // ── Folder body (front face) ─────────────────────────────────────
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: accentColor.mix(with: .white, by: 0.18), location: 0),
                            .init(color: accentColor.mix(with: .black, by: 0.04), location: 1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 92)
                // subtle inner top highlight — glass sheen
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.22), .clear],
                                startPoint: .top,
                                endPoint: .init(x: 0.5, y: 0.45)
                            )
                        )
                        .frame(height: 92)
                }
                // outer stroke for glass edge definition
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.35), accentColor.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .overlay {
                    HStack(spacing: 0) {
                        // ── Icon badge + title/subtitle ───────────────────
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(.white.opacity(0.18))
                                    .frame(width: 44, height: 44)
                                Image(systemName: icon)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(title)
                                    .font(.custom("OpenSans-Bold", size: 17))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                                Text(subtitle)
                                    .font(.custom("OpenSans-Regular", size: 11))
                                    .foregroundStyle(.white.opacity(0.80))
                                    .lineLimit(1)
                            }
                        }
                        .padding(.leading, 18)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.trailing, 18)
                    }
                }

        }
        .frame(maxWidth: .infinity)
        .frame(height: 108)
        // Ambient glow beneath the card
        .shadow(color: accentColor.opacity(isPressed ? 0.10 : 0.22), radius: isPressed ? 6 : 16, x: 0, y: isPressed ? 2 : 8)
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        // Press: compress slightly; release: float up
        .scaleEffect(isPressed ? 0.975 : 1.0)
        .offset(y: isPressed ? 1 : 0)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: isPressed)
    }

    // MARK: - Paper layers peeking out of the folder top

    private var paperLayers: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: -8) {
                // Back paper — rotated slightly left
                paperSheet(
                    label: chips.count > 1 ? chips[1] : "",
                    rotation: -4,
                    xOffset: 8
                )
                // Middle paper
                paperSheet(
                    label: chips.count > 0 ? chips[0] : "",
                    rotation: 1.5,
                    xOffset: 0
                )
                // Front paper — slightly right
                paperSheet(
                    label: chips.count > 2 ? chips[2] : "",
                    rotation: 5,
                    xOffset: -6
                )
            }
            .frame(height: 42)
            .padding(.trailing, 20)
            // Papers sit above folder body, anchored just above the lip line
            Spacer().frame(height: 74)
        }
        .frame(height: 108, alignment: .top)
        .padding(.top, 2)
    }

    private func paperSheet(label: String, rotation: Double, xOffset: CGFloat) -> some View {
        ZStack(alignment: .center) {
            // Sheet body
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [paperColor, paperColor.mix(with: .gray, by: 0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    // Ruled line detail on the sheet
                    VStack(spacing: 5) {
                        ForEach(0..<3, id: \.self) { _ in
                            Capsule()
                                .fill(Color(.systemGray4).opacity(0.5))
                                .frame(height: 1.5)
                        }
                    }
                    .padding(.horizontal, 5)
                    .padding(.top, 8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color(.systemGray4).opacity(0.3), lineWidth: 0.5)
                )

            // Label chip at bottom of sheet
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(accentColor.mix(with: .black, by: 0.1))
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(accentColor.opacity(0.12), in: Capsule())
                    .offset(y: 14)
            }
        }
        .frame(width: 46, height: 52)
        .rotationEffect(.degrees(rotation))
        .offset(x: xOffset, y: 0)
    }
}

// MARK: - FolderSquareCard
// Compact square folder — used in 3-column grids.
// Icon is the visual anchor; name sits at the bottom of the folder face.
// Same folder metaphor as ResourceFolderCard but square and icon-first.

struct FolderSquareCard: View {
    let icon: String
    let title: String
    let accentColor: Color
    let folderColor: Color
    let paperColor: Color

    var body: some View {
        ZStack(alignment: .bottom) {

            // ── Folder back ──────────────────────────────────────────────────
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(folderColor)
                .frame(width: nil, height: nil) // fills parent
                .overlay(alignment: .topLeading) {
                    // Tab nub
                    Capsule()
                        .fill(folderColor.mix(with: .black, by: 0.10))
                        .frame(width: 20, height: 6)
                        .offset(x: 8, y: -3)
                }

            // ── 2 peeking paper sheets (top-right area) ──────────────────────
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: -4) {
                    Spacer()
                    squarePaperSheet(rotation: -5)
                    squarePaperSheet(rotation: 4)
                        .padding(.trailing, 10)
                }
                .frame(height: 16)
                Spacer()
            }
            .padding(.top, 6)

            // ── Folder front face ─────────────────────────────────────────────
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: accentColor.mix(with: .white, by: 0.20), location: 0),
                            .init(color: accentColor.mix(with: .black, by: 0.06), location: 1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                // Glass sheen
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.25), .clear],
                                startPoint: .top,
                                endPoint: .init(x: 0.5, y: 0.5)
                            )
                        )
                }
                // Edge highlight
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.40), accentColor.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                // Icon — centered, prominent
                .overlay(alignment: .center) {
                    VStack(spacing: 4) {
                        // Icon badge
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.18))
                                .frame(width: 26, height: 26)
                            Image(systemName: icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        // Title below icon
                        Text(title)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 6)
                }
                // shrinks slightly from bottom so the back folder peeks at top
                .padding(.top, 14)
        }
        .aspectRatio(1.0, contentMode: .fit)   // square
        .shadow(color: accentColor.opacity(0.22), radius: 14, x: 0, y: 6)
        .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 2)
    }

    private func squarePaperSheet(rotation: Double) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(paperColor)
            .overlay(
                VStack(spacing: 4) {
                    ForEach(0..<2, id: \.self) { _ in
                        Capsule()
                            .fill(Color(.systemGray4).opacity(0.45))
                            .frame(height: 1.5)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color(.systemGray4).opacity(0.25), lineWidth: 0.5)
            )
            .frame(width: 16, height: 20)
            .rotationEffect(.degrees(rotation))
    }
}

// MARK: - FolderPressEffect ButtonStyle

/// ButtonStyle that drives the `isPressed` state into a ResourceFolderCard.
/// Usage:  Button { ... } label: { ResourceFolderCard(..., isPressed: config.isPressed) }
///         .buttonStyle(FolderPressEffect())
struct FolderPressEffect: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.folderIsPressed, configuration.isPressed)
            .animation(.spring(response: 0.28, dampingFraction: 0.70), value: configuration.isPressed)
    }
}

// MARK: - Environment key for press state propagation

private struct FolderIsPressedKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var folderIsPressed: Bool {
        get { self[FolderIsPressedKey.self] }
        set { self[FolderIsPressedKey.self] = newValue }
    }
}

// MARK: - Convenience: Color mixing helper (pure Swift, no UIKit)

extension Color {
    /// Linearly interpolate toward `other` by `fraction` (0 = self, 1 = other).
    func mix(with other: Color, by fraction: Double) -> Color {
        let f = max(0, min(1, fraction))
        return Color(
            red:   lerp(component(\.red),   other.component(\.red),   f),
            green: lerp(component(\.green), other.component(\.green), f),
            blue:  lerp(component(\.blue),  other.component(\.blue),  f),
            opacity: lerp(component(\.opacity), other.component(\.opacity), f)
        )
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    private func component(_ kp: KeyPath<(red: Double, green: Double, blue: Double, opacity: Double), Double>) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        let tuple = (red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a))
        return tuple[keyPath: kp]
    }
}
