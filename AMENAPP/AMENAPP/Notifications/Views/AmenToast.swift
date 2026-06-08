// AmenToast.swift
// AMENAPP — Notifications/Views
//
// Compact bottom-pill notification shown on REPEAT actions.
// Slides up from the bottom edge with a spring; respects reduce-motion.
//
// Prop contract (Agent C must match exactly):
//   action:      AmenAction        — drives icon + accessibility copy
//   title:       String            — primary line (e.g. "You said Amen")
//   subtitle:    String            — secondary line (e.g. "Jordan will be encouraged")
//   undoWindow:  TimeInterval      — give=6.0, others=4.2
//   onUndo:      () -> Void        — undo handler
//
// Dependencies:
//   GlassMaterial.swift  — glassSurface(cornerRadius:), NotifGlassTokens
//   ActionBadge.swift    — ActionBadge, AmenAction.systemImageName
//   CountdownRing.swift  — CountdownRing

import SwiftUI

// MARK: - AmenToast

struct AmenToast: View {

    let action: AmenAction
    let title: String
    let subtitle: String
    let undoWindow: TimeInterval
    let onUndo: () -> Void

    @State private var appeared      = false
    @State private var undoRemaining: TimeInterval
    @State private var isPaused      = false

    private let countdownTimer = Timer
        .publish(every: 0.05, on: .main, in: .common)
        .autoconnect()

    @Environment(\.accessibilityReduceMotion)       private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        action: AmenAction,
        title: String,
        subtitle: String,
        undoWindow: TimeInterval,
        onUndo: @escaping () -> Void
    ) {
        self.action = action
        self.title = title
        self.subtitle = subtitle
        self.undoWindow = undoWindow
        self.onUndo = onUndo
        self._undoRemaining = State(initialValue: undoWindow)
    }

    // MARK: Body

    var body: some View {
        toastPill
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .offset(y: appeared ? 0 : 80)
            .opacity(appeared ? 1 : 0)
            .onAppear { animateEntrance() }
            .onReceive(countdownTimer) { _ in tickCountdown() }
    }

    // MARK: Pill layout

    private var toastPill: some View {
        HStack(spacing: 12) {

            // Leading action icon chip
            actionIconChip

            // Title + subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.systemScaled(12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Undo button with countdown ring
            undoButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassSurface(cornerRadius: 32)
        // Pause countdown on hold / long press
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPaused = true }
                .onEnded   { _ in isPaused = false }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(action.accessibilityLabel): \(title). \(subtitle). Undo available for \(Int(undoRemaining)) seconds.")
        .accessibilityAction(named: "Undo") { onUndo() }
    }

    // MARK: Icon chip

    private var actionIconChip: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 28, height: 28)

            Image(systemName: action.systemImageName)
                .font(.systemScaled(13, weight: .semibold))
                .foregroundStyle(Color(uiColor: .systemBackground))
        }
        .overlay {
            Circle()
                .strokeBorder(Color.white.opacity(0.30), lineWidth: 1)
        }
        .shadow(color: Color.accentColor.opacity(0.30), radius: 4, x: 0, y: 2)
    }

    // MARK: Undo button

    private var undoButton: some View {
        Button(action: onUndo) {
            HStack(spacing: 5) {
                CountdownRing(total: undoWindow, remaining: undoRemaining)

                Text("Undo")
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.65))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(reduceTransparency ? 0.18 : 0.10))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Undo, \(Int(undoRemaining)) seconds remaining")
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
        guard !isPaused, undoRemaining > 0 else { return }
        undoRemaining = max(0, undoRemaining - 0.05)
    }
}

// MARK: - Preview

#Preview("AmenToast — all actions") {
    ZStack(alignment: .bottom) {
        Color(.systemGroupedBackground).ignoresSafeArea()

        ScrollView {
            VStack(spacing: 16) {
                ForEach(AmenAction.allCases, id: \.rawValue) { action in
                    AmenToast(
                        action: action,
                        title: toastTitle(for: action),
                        subtitle: toastSubtitle(for: action),
                        undoWindow: action == .give ? 6.0 : 4.2,
                        onUndo: {}
                    )
                }
            }
            .padding(.vertical, 40)
        }
    }
}

#Preview("AmenToast — reduceMotion") {
    ZStack(alignment: .bottom) {
        Color(.systemGroupedBackground).ignoresSafeArea()
        AmenToast(
            action: .amen,
            title: "You said Amen",
            subtitle: "Jordan will be encouraged",
            undoWindow: 4.2,
            onUndo: {}
        )
    }
}

#Preview("AmenToast — reduceTransparency") {
    ZStack(alignment: .bottom) {
        Color.purple.ignoresSafeArea()
        AmenToast(
            action: .give,
            title: "Thank you",
            subtitle: "Your generosity blesses Marcus",
            undoWindow: 6.0,
            onUndo: {}
        )
    }
}

// MARK: - Preview helpers

private func toastTitle(for action: AmenAction) -> String {
    switch action {
    case .amen:   return "You said Amen"
    case .repost: return "You reposted this"
    case .save:   return "Saved for later"
    case .join:   return "You joined"
    case .give:   return "Thank you"
    }
}

private func toastSubtitle(for action: AmenAction) -> String {
    switch action {
    case .amen:   return "Jordan will be encouraged"
    case .repost: return "Visible on your profile now"
    case .save:   return "Find it in your Saved tab"
    case .join:   return "You're now part of this community"
    case .give:   return "Your generosity blesses Marcus"
    }
}
