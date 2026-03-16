//
//  AMENMediaReactionBar.swift
//  AMENAPP
//
//  Faith-based reaction bar for the media viewer overlay.
//  Amen, Pray, Fire, Bless, Share — with glow effects and spring animations.
//

import SwiftUI

// MARK: - Reaction Model

enum AMENReaction: String, CaseIterable {
    case amen      = "hands.sparkles.fill"
    case pray      = "figure.stand"
    case fire      = "flame.fill"
    case bless     = "cross.circle.fill"
    case dove      = "bird.fill"

    var label: String {
        switch self {
        case .amen:  return "Amen"
        case .pray:  return "Pray"
        case .fire:  return "Fire"
        case .bless: return "Bless"
        case .dove:  return "Share"
        }
    }

    var activeColor: Color {
        switch self {
        case .amen:  return Color(red: 0.96, green: 0.78, blue: 0.26)   // Gold
        case .pray:  return Color(red: 0.65, green: 0.55, blue: 0.98)   // Violet
        case .fire:  return Color(red: 0.98, green: 0.57, blue: 0.24)   // Amber-orange
        case .bless: return Color(red: 0.38, green: 0.65, blue: 0.98)   // Sky blue
        case .dove:  return Color(red: 0.20, green: 0.83, blue: 0.60)   // Emerald
        }
    }
}

// MARK: - Reaction Button

struct AMENReactionButton: View {
    let reaction: AMENReaction
    @Binding var count: Int
    @Binding var isActive: Bool

    @State private var bouncing = false

    var body: some View {
        Button {
            triggerReaction()
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    // Glow ring when active
                    if isActive {
                        Circle()
                            .fill(reaction.activeColor.opacity(0.2))
                            .frame(width: 50, height: 50)
                            .blur(radius: 6)
                    }

                    // Icon background
                    Circle()
                        .fill(
                            isActive
                                ? AnyShapeStyle(reaction.activeColor.opacity(0.18))
                                : AnyShapeStyle(Color.white.opacity(0.07))
                        )
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    isActive
                                        ? reaction.activeColor.opacity(0.5)
                                        : Color.white.opacity(0.12),
                                    lineWidth: 1
                                )
                        )

                    Image(systemName: reaction.rawValue)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(
                            isActive
                                ? reaction.activeColor
                                : Color.white.opacity(0.55)
                        )
                        .scaleEffect(bouncing ? 1.35 : 1.0)
                }
                .scaleEffect(bouncing ? 1.1 : 1.0)

                // Count label
                Text(count > 0 ? "\(count)" : reaction.label)
                    .font(.system(size: 10, weight: count > 0 ? .bold : .regular))
                    .foregroundStyle(
                        isActive
                            ? reaction.activeColor
                            : Color.white.opacity(0.4)
                    )
                    .contentTransition(.numericText())
            }
        }
        .buttonStyle(.plain)
    }

    private func triggerReaction() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
            bouncing = true
            isActive.toggle()
            count += isActive ? 1 : -1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                bouncing = false
            }
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

// MARK: - Full Reaction Bar

struct AMENMediaReactionBar: View {
    @State private var reactionCounts: [AMENReaction: Int] = [
        .amen: 24, .pray: 11, .fire: 8, .bless: 5, .dove: 3,
    ]
    @State private var activeReactions: [AMENReaction: Bool] = [
        .amen: false, .pray: false, .fire: false, .bless: false, .dove: false,
    ]
    @State private var barVisible = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AMENReaction.allCases, id: \.self) { reaction in
                AMENReactionButton(
                    reaction: reaction,
                    count: Binding(
                        get: { reactionCounts[reaction] ?? 0 },
                        set: { reactionCounts[reaction] = $0 }
                    ),
                    isActive: Binding(
                        get: { activeReactions[reaction] ?? false },
                        set: { activeReactions[reaction] = $0 }
                    )
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.55),
                                Color(red: 0.05, green: 0.05, blue: 0.10).opacity(0.75),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.15),
                                Color.white.opacity(0.03),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
        )
        .padding(.horizontal, 20)
        .offset(y: barVisible ? 0 : 60)
        .opacity(barVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72).delay(0.15)) {
                barVisible = true
            }
        }
    }
}

// MARK: - Media Viewer Integration

struct AMENMediaViewer: View {
    let mediaImage: Image
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            mediaImage
                .resizable()
                .scaledToFit()
                .ignoresSafeArea()

            // Gradient scrim at bottom
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(height: 200)
                .ignoresSafeArea()
            }

            // Reaction bar pinned to bottom
            VStack {
                Spacer()
                AMENMediaReactionBar()
                    .padding(.bottom, 36)
            }

            // Dismiss button
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.15), in: Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }
}
