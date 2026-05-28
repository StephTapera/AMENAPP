// TakeBreakPromptView.swift
// AMENAPP
//
// A soft interrupt sheet shown when the system detects binge-scroll patterns
// or when the user explicitly taps "Take Break." Calming, not alarming.
// No guilt language. Invites intentional choice.
//
// Gated by AMENFeatureFlags.shared.mediaDoomScrollGuardEnabled

import SwiftUI

// MARK: - TakeBreakReason

enum TakeBreakReason {
    case userRequested
    case rapidSkipping
    case timeElapsed(minutes: Int)
    case lateNight
    case sessionComplete
}

// MARK: - TakeBreakPromptView

struct TakeBreakPromptView: View {

    // MARK: Inputs

    let reason: TakeBreakReason
    let sessionDuration: TimeInterval
    let onTakeBreak: () -> Void
    let onContinue: () -> Void
    let onEndSession: () -> Void

    // MARK: Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Animation State

    @State private var appeared = false

    // MARK: Computed — reason-driven copy

    private var title: String {
        switch reason {
        case .userRequested:
            return "Taking a break is good"
        case .rapidSkipping:
            return "You moved quickly through several items"
        case .timeElapsed(let minutes):
            return "You\u{2019}ve been here for \(minutes) minutes"
        case .lateNight:
            return "It\u{2019}s getting late"
        case .sessionComplete:
            return "You completed your session"
        }
    }

    private var subtitle: String {
        switch reason {
        case .userRequested:
            return "Rest is part of the rhythm. Step away and return refreshed."
        case .rapidSkipping:
            return "Slowing down can help you absorb what matters. There\u{2019}s no rush."
        case .timeElapsed(let minutes):
            return minutes >= 60
                ? "That\u{2019}s over an hour of time. Even a short walk can clear your mind."
                : "A moment away is a gift to yourself. Your feed will still be here."
        case .lateNight:
            return "Rest is a spiritual practice. Your mind and body will thank you."
        case .sessionComplete:
            return "Take a moment to sit with what you\u{2019}ve just seen and heard."
        }
    }

    private var symbolName: String {
        switch reason {
        case .lateNight, .userRequested:
            return "moon.stars"
        case .rapidSkipping:
            return "wind"
        case .timeElapsed:
            return "hourglass"
        case .sessionComplete:
            return "checkmark.circle"
        }
    }

    // MARK: Body

    var body: some View {
        // Feature gate — render nothing visible when flag is OFF
        if !AMENFeatureFlags.shared.mediaDoomScrollGuardEnabled {
            // Sheet still needs a surface; pass through to continue immediately.
            Color.clear
                .onAppear { onContinue() }
        } else {
            sheetContent
                .presentationCornerRadius(28)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : (reduceMotion ? 0 : 16))
                .onAppear {
                    if reduceMotion {
                        appeared = true
                    } else {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                            appeared = true
                        }
                    }
                    AMENAnalyticsService.shared.track(
                        .feedMeaningfulInteraction(type: "take_break_prompt_shown")
                    )
                }
        }
    }

    // MARK: Sheet Content

    private var sheetContent: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Drag indicator
                dragIndicator
                    .padding(.top, 10)
                    .padding(.bottom, 28)

                // Icon + Title + Subtitle
                headerSection
                    .padding(.horizontal, 28)
                    .padding(.bottom, 36)

                // Buttons
                buttonStack
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
            }
        }
    }

    // MARK: Drag Indicator

    private var dragIndicator: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(.systemGray4))
            .frame(width: 36, height: 4)
    }

    // MARK: Header Section

    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: symbolName)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.primary)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Session duration badge — only shown when meaningful
            if sessionDuration >= 60 {
                sessionDurationBadge
            }
        }
    }

    private var sessionDurationBadge: some View {
        let minutes = max(1, Int(sessionDuration / 60))
        let label = minutes == 1 ? "1 min in session" : "\(minutes) min in session"
        return Text(label)
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color(.secondarySystemBackground))
            )
            .accessibilityLabel(label)
    }

    // MARK: Button Stack

    private var buttonStack: some View {
        VStack(spacing: 12) {
            // 1. Take a Break — black pill, most prominent
            Button(action: onTakeBreak) {
                Text("Take a Break")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(Color.black, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Take a Break")

            // 2. Continue Intentionally — white with black border
            Button(action: onContinue) {
                Text("Continue Intentionally")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(
                        Capsule()
                            .fill(Color(.systemBackground))
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.black, lineWidth: 1.5)
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Continue Intentionally")

            // 3. End Session — plain text, secondary
            Button(action: onEndSession) {
                Text("End Session")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("End Session")
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("User Requested") {
    Color(.systemGray6)
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            TakeBreakPromptView(
                reason: .userRequested,
                sessionDuration: 720,
                onTakeBreak: {},
                onContinue: {},
                onEndSession: {}
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
        }
}

#Preview("Rapid Skipping") {
    Color(.systemGray6)
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            TakeBreakPromptView(
                reason: .rapidSkipping,
                sessionDuration: 300,
                onTakeBreak: {},
                onContinue: {},
                onEndSession: {}
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
        }
}

#Preview("Time Elapsed — 23 min") {
    Color(.systemGray6)
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            TakeBreakPromptView(
                reason: .timeElapsed(minutes: 23),
                sessionDuration: 23 * 60,
                onTakeBreak: {},
                onContinue: {},
                onEndSession: {}
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
        }
}

#Preview("Late Night") {
    Color(.systemGray6)
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            TakeBreakPromptView(
                reason: .lateNight,
                sessionDuration: 1560,
                onTakeBreak: {},
                onContinue: {},
                onEndSession: {}
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
        }
}

#Preview("Session Complete") {
    Color(.systemGray6)
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            TakeBreakPromptView(
                reason: .sessionComplete,
                sessionDuration: 480,
                onTakeBreak: {},
                onContinue: {},
                onEndSession: {}
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
        }
}

#Preview("Reduce Motion") {
    Color(.systemGray6)
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            TakeBreakPromptView(
                reason: .timeElapsed(minutes: 45),
                sessionDuration: 45 * 60,
                onTakeBreak: {},
                onContinue: {},
                onEndSession: {}
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
        }
}
#endif
