//
//  FollowButton.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//

import SwiftUI

/// A reusable follow/unfollow button component
struct SocialFollowButton: View {
    let userId: String
    let username: String
    
    @State private var isFollowing = false
    @State private var isLoading = false
    
    private let followService = FollowService.shared
    
    var body: some View {
        Button {
            handleFollowToggle()
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: isFollowing ? .gray : .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: isFollowing ? "person.fill.checkmark" : "person.fill.badge.plus")
                        .font(.systemScaled(14, weight: .semibold))
                }
                
                Text(isFollowing ? "Following" : "Follow")
                    .font(AMENFont.bold(14))
            }
            .foregroundStyle(isFollowing ? Color.gray : Color.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Group {
                    if isFollowing {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white.opacity(0.2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.amenGold)
                    }
                }
            )
        }
        .disabled(isLoading)
        .accessibilityHint(isFollowing ? "Unfollows this person" : "Follow or send a follow request")
        .task {
            await checkFollowStatus()
        }
    }
    
    private func checkFollowStatus() async {
        isFollowing = await followService.isFollowing(userId: userId)
    }
    
    private func handleFollowToggle() {
        // P0 FIX: Prevent duplicate follow operations from rapid taps
        guard !isLoading else {
            dlog("⚠️ Follow action already in progress")
            return
        }
        
        isLoading = true
        
        Task {
            do {
                if isFollowing {
                    try await followService.unfollowUser(userId: userId)
                } else {
                    try await followService.followUser(userId: userId)
                }
                
                await MainActor.run {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                        isFollowing.toggle()
                    }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    dlog("❌ Follow/Unfollow error: \(error)")
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black
        SocialFollowButton(userId: "sample-user-id", username: "johndoe")
    }
}

// MARK: - AnimatedFollowButton

/// Animated follow button with shimmer, checkmark spring, and particle burst.
/// Usage: AnimatedFollowButton(isFollowing: $isFollowing, isInProgress: $isInProgress) { toggleFollow() }
struct AnimatedFollowButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isFollowing: Bool
    @Binding var isInProgress: Bool
    let onToggle: () -> Void

    @State private var isPressed      = false
    @State private var showParticles  = false
    @State private var checkScale     = CGFloat(0.4)
    @State private var checkOpacity   = CGFloat(0)
    @State private var shimmerOffset  = CGFloat(-1)
    @State private var labelOpacity   = CGFloat(1)
    @State private var labelOffset    = CGFloat(0)

    private let accentColor = Color(red: 0.9, green: 0.45, blue: 0.12) // warm orange

    var body: some View {
        Button(action: handleTap) {
            ZStack {
                // Surface
                Group {
                    if isFollowing {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                LinearGradient(
                                    colors: [.white.opacity(0.5), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .center
                                )
                                .clipShape(Capsule())
                            )
                            .overlay(
                                Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 0.5)
                            )
                    } else {
                        Capsule().fill(Color.black)
                    }
                }
                .animation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.75), value: isFollowing)

                // Shimmer
                LinearGradient(
                    colors: [.clear, .white.opacity(0.35), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 60)
                .clipShape(Capsule())
                .offset(x: shimmerOffset * 160)
                .allowsHitTesting(false)

                // Label
                HStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .strokeBorder(isFollowing ? Color.black.opacity(0.5) : .clear, lineWidth: 1.5)
                            .frame(width: 16, height: 16)
                        Image(systemName: "checkmark")
                            .font(.systemScaled(8, weight: .bold))
                            .foregroundStyle(.black.opacity(0.6))
                    }
                    .scaleEffect(checkScale)
                    .opacity(checkOpacity)

                    if isInProgress {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(isFollowing ? Color.primary : Color.white)
                    } else {
                        Text(isFollowing ? "Following" : "Follow")
                            .font(.systemScaled(14, weight: .bold))
                            .foregroundStyle(isFollowing ? Color.primary : Color.white)
                            .opacity(labelOpacity)
                            .offset(y: labelOffset)
                            .animation(reduceMotion ? .none : .spring(response: 0.3), value: isFollowing)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(reduceMotion ? .none : .spring(response: 0.25, dampingFraction: 0.6), value: isPressed)
        }
        .buttonStyle(FollowPressStyle(isPressed: $isPressed))
        .overlay(FollowParticleBurst(trigger: showParticles, color: accentColor))
        .disabled(isInProgress)
    }

    private func handleTap() {
        guard !isInProgress else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        shimmerOffset = -1
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) { shimmerOffset = 1.5 }

        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.12)) {
            labelOpacity = 0
            labelOffset  = isFollowing ? 4 : -4
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            onToggle()
            labelOffset = isFollowing ? -4 : 4
            withAnimation(Motion.adaptive(.spring(response: 0.3))) {
                labelOpacity = 1
                labelOffset  = 0
            }
            if !isFollowing { // was false, now toggling to true
                withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.55))) {
                    checkScale   = 1.0
                    checkOpacity = 1.0
                }
                showParticles = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { showParticles = true }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                checkScale   = 0.4
                checkOpacity = 0
            }
        }
    }
}

private struct FollowPressStyle: ButtonStyle {
    @Binding var isPressed: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, v in isPressed = v }
    }
}

private struct FollowParticleBurst: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let trigger: Bool
    let color: Color
    private let count = 8
    private let angles: [Double] = (0..<8).map { Double($0) / 8.0 * .pi * 2 }
    private let sizes: [CGFloat] = [3, 4, 3, 5, 3, 4, 3, 5]

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill([color, Color.blue.opacity(0.7), Color.green.opacity(0.7), Color.white][i % 4])
                    .frame(width: sizes[i], height: sizes[i])
                    .offset(
                        x: trigger ? cos(angles[i]) * 22 : 0,
                        y: trigger ? sin(angles[i]) * 22 : 0
                    )
                    .opacity(trigger ? 0 : 0)
                    .animation(
                        (!reduceMotion && trigger) ? .spring(response: 0.4, dampingFraction: 0.6).delay(Double(i) * 0.02) : .none,
                        value: trigger
                    )
            }
        }
        .allowsHitTesting(false)
    }
}
