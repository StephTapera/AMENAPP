// AmenNotificationCard.swift
// AMENAPP — Notifications/Views
//
// Full educational glass card shown the FIRST TIME a user takes an action.
// On repeat the compact AmenToast is shown instead.
//
// Prop contract (Agent C must match exactly):
//   action:      AmenAction                       — drives icon + copy
//   actorName:   String                           — displayed in body
//   toneColors:  (Color, Color)                   — avatar gradient (primary, accent)
//   onLearnMore: () -> Void                       — inline "Learn more" tap
//   onPrimary:   () -> Void                       — "Got it" / "Amen" etc.
//   onUndo:      () -> Void                       — ghost Undo button
//   undoWindow:  TimeInterval                     — give=6.0, others=4.2
//
// Dependencies:
//   GlassMaterial.swift  — glassSurface(cornerRadius:)
//   ActionBadge.swift    — ActionBadge, AmenAction helpers
//   CountdownRing.swift  — CountdownRing

import SwiftUI

// MARK: - AmenNotificationCard

struct AmenNotificationCard: View {

    let action: AmenAction
    let actorName: String
    let toneColors: (Color, Color)
    let onLearnMore: () -> Void
    let onPrimary: () -> Void
    let onUndo: () -> Void
    let undoWindow: TimeInterval

    @State private var appeared = false
    @State private var undoRemaining: TimeInterval
    @State private var undoPaused = false

    // Countdown timer — fires every 0.05 s for smooth ring drain
    private let countdownTimer = Timer
        .publish(every: 0.05, on: .main, in: .common)
        .autoconnect()

    @Environment(\.accessibilityReduceMotion)       private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        action: AmenAction,
        actorName: String,
        toneColors: (Color, Color),
        onLearnMore: @escaping () -> Void,
        onPrimary: @escaping () -> Void,
        onUndo: @escaping () -> Void,
        undoWindow: TimeInterval
    ) {
        self.action = action
        self.actorName = actorName
        self.toneColors = toneColors
        self.onLearnMore = onLearnMore
        self.onPrimary = onPrimary
        self.onUndo = onUndo
        self.undoWindow = undoWindow
        self._undoRemaining = State(initialValue: undoWindow)
    }

    // MARK: Body

    var body: some View {
        cardContent
            .frame(maxWidth: 340)
            .glassSurface(cornerRadius: 24)
            .offset(y: appeared ? 0 : 40)
            .opacity(appeared ? 1 : 0)
            .onAppear { animateEntrance() }
            .onReceive(countdownTimer) { _ in tickCountdown() }
    }

    // MARK: Card content

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Top row: avatar + badge
            HStack(alignment: .top, spacing: 14) {
                avatarStack
                Spacer()
            }
            .padding(.top, 20)
            .padding(.horizontal, 20)

            // Title
            // PURGED: Font.custom("CormorantGaramond-SemiBold", size: 22) → SF Pro per C3 design contract
            Text(titleText)
                .font(.system(.title2, design: .default).weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.top, 14)
                .padding(.horizontal, 20)

            // Body
            bodyText
                .padding(.top, 6)
                .padding(.horizontal, 20)

            // Buttons
            buttonRow
                .padding(.top, 20)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
    }

    // MARK: Avatar + badge

    private var avatarStack: some View {
        ZStack(alignment: .bottomTrailing) {
            // Avatar circle
            Circle()
                .fill(
                    LinearGradient(
                        colors: [toneColors.0, toneColors.1],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 56, height: 56)
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                }
                .shadow(color: toneColors.0.opacity(0.35), radius: 8, x: 0, y: 4)

            // Action badge — overlaps bottom-right of avatar
            ActionBadge(action: action)
                .offset(x: 6, y: 6)
        }
        .accessibilityLabel("\(actorName), \(action.accessibilityLabel)")
    }

    // MARK: Title

    private var titleText: String {
        switch action {
        case .amen:   return "You said Amen"
        case .repost: return "You reposted this"
        case .save:   return "Saved for later"
        case .join:   return "You joined"
        case .give:   return "Thank you"
        }
    }

    // MARK: Body text with "Learn more" tappable link

    private var bodyText: some View {
        Text("\(bodyLeading) \(Text("Learn more").foregroundStyle(Color.accentColor)) about how this works.")
            .foregroundStyle(.primary.opacity(0.75))
            .font(.systemScaled(15))
            .lineSpacing(3)
            .onTapGesture(perform: onLearnMore)
    }

    private var bodyLeading: String {
        switch action {
        case .amen:   return "Your Amen goes to \(actorName) as encouragement."
        case .repost: return "This post will appear on your profile."
        case .save:   return "Find this in your Saved tab anytime."
        case .join:   return "You're now part of this community."
        case .give:   return "Your generosity blesses \(actorName)."
        }
    }

    // MARK: Buttons

    private var buttonRow: some View {
        HStack(spacing: 12) {
            // Primary pill
            Button(action: onPrimary) {
                Text(action.primaryButtonTitle)
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 13)
                    .background(
                        Capsule()
                            .fill(Color.accentColor)
                    )
                    .shadow(
                        color: Color.accentColor.opacity(0.35),
                        radius: 8, x: 0, y: 3
                    )
            }
            .buttonStyle(CardButtonStyle())
            .accessibilityLabel(action.primaryButtonTitle)

            Spacer()

            // Ghost Undo
            Button(action: onUndo) {
                HStack(spacing: 6) {
                    CountdownRing(total: undoWindow, remaining: undoRemaining)
                    Text("Undo")
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.60))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Undo \(action.accessibilityLabel), \(Int(undoRemaining)) seconds remaining")
        }
    }

    // MARK: Entrance animation

    private func animateEntrance() {
        if reduceMotion {
            appeared = true
        } else {
            withAnimation(
                .interpolatingSpring(stiffness: 340, damping: 28)
            ) {
                appeared = true
            }
        }
    }

    // MARK: Countdown

    private func tickCountdown() {
        guard !undoPaused, undoRemaining > 0 else { return }
        undoRemaining = max(0, undoRemaining - 0.05)
    }
}

// MARK: - CardButtonStyle (subtle press scale)

private struct CardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.96 : 1))
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.08)
                    : .spring(response: 0.22, dampingFraction: 0.78),
                value: configuration.isPressed
            )
    }
}

// MARK: - Preview

#Preview("AmenNotificationCard — all actions") {
    ScrollView {
        VStack(spacing: 24) {
            ForEach(AmenAction.allCases, id: \.rawValue) { action in
                AmenNotificationCard(
                    action: action,
                    actorName: "Jordan",
                    toneColors: (Color.accentColor, Color.accentColor.opacity(0.7)),
                    onLearnMore: {},
                    onPrimary: {},
                    onUndo: {},
                    undoWindow: action == .give ? 6.0 : 4.2
                )
            }
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground).ignoresSafeArea())
}

#Preview("AmenNotificationCard — reduceMotion") {
    AmenNotificationCard(
        action: .amen,
        actorName: "Jordan",
        toneColors: (Color.accentColor, Color.accentColor.opacity(0.7)),
        onLearnMore: {},
        onPrimary: {},
        onUndo: {},
        undoWindow: 4.2
    )
    .padding()
    .background(Color(.systemGroupedBackground).ignoresSafeArea())
}

#Preview("AmenNotificationCard — reduceTransparency") {
    AmenNotificationCard(
        action: .give,
        actorName: "Marcus",
        toneColors: (Color.accentColor, Color.accentColor.opacity(0.6)),
        onLearnMore: {},
        onPrimary: {},
        onUndo: {},
        undoWindow: 6.0
    )
    .padding()
    .background(Color.purple.ignoresSafeArea())
}
