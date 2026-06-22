// MediaDoomScrollGuard.swift
// AMENAPP
//
// Detects doom-scroll patterns and presents a gentle, human-first interruption.
// Counts media swipes per session; at the threshold it presents a pause sheet.
// Gated by `mediaDoomScrollGuardEnabled`.

import SwiftUI
import Combine

// MARK: - State Object

@MainActor
final class MediaDoomScrollGuardState: ObservableObject {

    static let shared = MediaDoomScrollGuardState()

    @Published private(set) var shouldInterrupt: Bool = false
    @Published private(set) var sessionItemCount: Int = 0

    private let interruptThreshold = 20
    private let flags = AMENFeatureFlags.shared

    private init() {}

    /// Call each time the user swipes to a new media item.
    func recordSwipe() {
        guard flags.mediaDoomScrollGuardEnabled else { return }

        sessionItemCount += 1
        dlog("[MediaDoomScrollGuard] Swipe recorded — count: \(sessionItemCount)")

        if sessionItemCount >= interruptThreshold && !shouldInterrupt {
            shouldInterrupt = true
            dlog("[MediaDoomScrollGuard] Interrupt threshold reached")
        }
    }

    /// Dismisses the interruption sheet and resets the counter for the current session pass.
    func dismiss() {
        shouldInterrupt = false
        sessionItemCount = 0
        dlog("[MediaDoomScrollGuard] Dismissed — counter reset")
    }

    /// Full reset for a brand-new session (e.g. app foreground or explicit new session).
    func reset() {
        shouldInterrupt = false
        sessionItemCount = 0
        dlog("[MediaDoomScrollGuard] Full reset")
    }
}

// MARK: - ViewModifier

struct MediaDoomScrollGuard: ViewModifier {

    @ObservedObject private var state = MediaDoomScrollGuardState.shared

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(
                get: { state.shouldInterrupt },
                set: { if !$0 { state.dismiss() } }
            )) {
                DoomScrollInterruptionSheet(
                    itemCount: state.sessionItemCount,
                    onKeepGoing: { state.dismiss() },
                    onTakeBreak: {
                        state.dismiss()
                        NotificationCenter.default.post(name: .openSelahPause, object: nil)
                    }
                )
                .presentationDetents([.medium])
                .presentationCornerRadius(24)
            }
    }
}

// MARK: - Interruption Sheet

private struct DoomScrollInterruptionSheet: View {

    let itemCount: Int
    let onKeepGoing: () -> Void
    let onTakeBreak: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Color.blue)
            }
            .padding(.top, 12)

            // Copy
            VStack(spacing: 10) {
                Text("You've been scrolling for a while")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Text("Take a breath. You've seen \(itemCount) videos. Want to keep going or take a break?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            // Actions
            VStack(spacing: 12) {
                Button(action: onTakeBreak) {
                    Text("Take a break")
                        .font(.body)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }

                Button(action: onKeepGoing) {
                    Text("Keep going")
                        .font(.body)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.ultraThinMaterial)
                        .foregroundStyle(.primary)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }
}

// MARK: - View Extension

extension View {
    /// Attaches the doom-scroll interruption overlay to any scrollable media surface.
    func doomScrollGuarded() -> some View {
        modifier(MediaDoomScrollGuard())
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let openSelahPause = Notification.Name("com.amenapp.openSelahPause")
}
