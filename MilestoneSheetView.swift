//
//  MilestoneSheetView.swift
//  AMENAPP
//
//  5 Milestone Moment Sheets - matches Instagram/Threads design exactly
//  White bottom sheet with profile avatar + overlapping badge pill
//

import SwiftUI

// MARK: - Milestone Model
struct AMENMilestone {
    let id: String
    let badgeIcon: String          // SF Symbol name
    let badgeLabel: String         // e.g. "70.8K", "7 day streak"
    let badgeColor: Color
    let title: String
    let body: String
    let primaryLabel: String
    let secondaryLabel: String
    let primaryAction: () -> Void
    let secondaryAction: () -> Void
}

// MARK: - Sheet View
struct MilestoneSheetView: View {
    let milestone: AMENMilestone
    let profileImageURL: String?
    let onDismiss: () -> Void

    @State private var badgeScale: CGFloat = 0.4
    @State private var badgeOpacity: Double = 0
    @State private var contentOpacity: Double = 0
    @State private var contentOffset: CGFloat = 18
    @State private var countValue: Double = 0
    @State private var sparkleParticles: [SparkleParticle] = []

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 4)
                .padding(.top, 14)
                .padding(.bottom, 24)

            // Avatar + badge
            ZStack(alignment: .bottom) {
                // Profile image
                Group {
                    if let urlString = profileImageURL, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                avatarPlaceholder
                            }
                        }
                    } else {
                        avatarPlaceholder
                    }
                }
                .frame(width: 96, height: 96)
                .clipShape(Circle())

                // Badge pill — overlaps bottom of avatar
                HStack(spacing: 6) {
                    Image(systemName: milestone.badgeIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(.label))
                    Text(milestone.badgeLabel)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color(.label))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.13), radius: 10, y: 3)
                )
                .scaleEffect(badgeScale)
                .opacity(badgeOpacity)
                .offset(y: 18)

                // Sparkle particles
                ForEach(sparkleParticles) { p in
                    Circle()
                        .fill(milestone.badgeColor.opacity(0.8))
                        .frame(width: p.size, height: p.size)
                        .offset(x: p.x, y: p.y)
                        .opacity(p.opacity)
                }
            }
            .padding(.bottom, 28)

            // Title
            Text(milestone.title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color(.label))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
                .opacity(contentOpacity)
                .offset(y: contentOffset)

            // Body
            Text(milestone.body)
                .font(.system(size: 15))
                .foregroundStyle(Color(.secondaryLabel))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 28)
                .padding(.bottom, 32)
                .opacity(contentOpacity)
                .offset(y: contentOffset)

            // Primary button
            Button {
                milestone.primaryAction()
                onDismiss()
            } label: {
                Text(milestone.primaryLabel)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(.label), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(MilestoneButtonStyle())
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
            .opacity(contentOpacity)
            .offset(y: contentOffset)

            // Secondary button
            Button {
                milestone.secondaryAction()
                onDismiss()
            } label: {
                Text(milestone.secondaryLabel)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(.label))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color(.separator), lineWidth: 1)
                    )
            }
            .buttonStyle(MilestoneButtonStyle())
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
            .opacity(contentOpacity)
            .offset(y: contentOffset)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onAppear { runEntrance() }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color(.systemGray4))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color(.systemGray2))
            )
    }

    private func runEntrance() {
        // 1. Badge springs in
        withAnimation(.spring(response: 0.42, dampingFraction: 0.62).delay(0.18)) {
            badgeScale = 1.0
            badgeOpacity = 1.0
        }

        // 2. Sparkle burst at badge position
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            fireSparkles()
        }

        // 3. Content fades + slides up
        withAnimation(.spring(response: 0.48, dampingFraction: 0.75).delay(0.28)) {
            contentOpacity = 1.0
            contentOffset = 0
        }

        // 4. Haptic
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func fireSparkles() {
        sparkleParticles = (0..<10).map { i in
            let angle = Double(i) / 10.0 * 360.0
            let rad = angle * .pi / 180
            let dist = Double.random(in: 30...52)
            return SparkleParticle(
                id: i,
                x: cos(rad) * dist,
                y: sin(rad) * dist - 8,
                size: Double.random(in: 4...8),
                opacity: 1
            )
        }
        withAnimation(.easeOut(duration: 0.55)) {
            sparkleParticles = sparkleParticles.map { p in
                SparkleParticle(id: p.id, x: p.x * 1.8, y: p.y * 1.8, size: p.size * 0.4, opacity: 0)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            sparkleParticles = []
        }
    }
}

// MARK: - Sparkle Particle
struct SparkleParticle: Identifiable {
    let id: Int
    var x: Double
    var y: Double
    var size: Double
    var opacity: Double
}

// MARK: - Button Style
struct MilestoneButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
