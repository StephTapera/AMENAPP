// FollowBadgeView.swift
// AMENAPP
//
// Threads-style follow badge — overlaid bottom-right on the author avatar.
// + morphs to ✓ with spring, badge turns purple, ripple fires, toast floats.

import SwiftUI

struct FollowBadgeView: View {
    @Binding var isFollowed: Bool
    let onToggle: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var showRipple = false
    @State private var showToast = false

    var body: some View {
        ZStack {
            // Ripple ring
            Circle()
                .stroke(Color.purple.opacity(0.35), lineWidth: 1.5)
                .frame(width: 20, height: 20)
                .scaleEffect(showRipple ? 3.2 : 1.0)
                .opacity(showRipple ? 0 : 0.8)
                .animation(
                    showRipple ? .easeOut(duration: 0.55) : .none,
                    value: showRipple
                )

            // Badge circle
            Circle()
                .fill(isFollowed ? Color.purple : Color(uiColor: .label))
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .strokeBorder(Color(uiColor: .systemBackground), lineWidth: 2)
                )
                .overlay(
                    ZStack {
                        // Plus (un-followed state)
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .rotationEffect(.degrees(isFollowed ? 45 : 0))
                            .opacity(isFollowed ? 0 : 1)
                            .scaleEffect(isFollowed ? 0.5 : 1)

                        // Checkmark (followed state)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .opacity(isFollowed ? 1 : 0)
                            .scaleEffect(isFollowed ? 1 : 0.4)
                    }
                    .animation(.spring(response: 0.38, dampingFraction: 0.62), value: isFollowed)
                )
                .scaleEffect(scale)
                .animation(.spring(response: 0.38, dampingFraction: 0.58), value: isFollowed)
        }
        // "Following" toast above badge
        .overlay(alignment: .top) {
            if showToast {
                Text("Following")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.purple, in: Capsule())
                    .fixedSize()
                    .offset(y: -28)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        )
                    )
            }
        }
        .onTapGesture { triggerFollow() }
    }

    private func triggerFollow() {
        // 1. Spring press
        withAnimation(.spring(response: 0.2, dampingFraction: 0.45)) { scale = 0.82 }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.58).delay(0.08)) { scale = 1.0 }

        // 3. Ripple + toast only when following (before toggle flips)
        let aboutToFollow = !isFollowed
        if aboutToFollow {
            showRipple = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                withAnimation { showRipple = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { showRipple = false }
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { showToast = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation(.easeOut(duration: 0.3)) { showToast = false }
            }
        }

        // 2. Toggle state
        withAnimation(.spring(response: 0.38, dampingFraction: 0.62)) { isFollowed.toggle() }

        // 5. Haptic
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // 6. Fire parent handler
        onToggle()
    }
}
