// AmenActionPill.swift
// AMEN App — Community OS
//
// A18: The universal Liquid Glass action pill.
// Canonical floating action UI — all intent-driven affordances surface through this component.
// Design spec: C3-design-tokens.md § 8 (Toolbar / Action Pill pattern)
//
// Rules enforced:
//   • System semantic colors only — no amenGold, no hex, no dark backgrounds
//   • Single accent: Color.accentColor for interactive primary only
//   • AmenShadow.floating spec: black 10% opacity, radius 32, y 10
//   • All animations respect accessibilityReduceMotion
//   • All backgrounds respect accessibilityReduceTransparency
//   • Minimum 44×44pt touch targets on all buttons

import SwiftUI

// MARK: - AmenPillAction

/// A single action entry in an AmenActionPill.
/// `intent` holds the C2 AmenIntent raw value string; `systemImage` is the SF Symbol name.
struct AmenPillAction: Identifiable {
    let id: String
    let intent: String        // AmenIntent raw value (e.g. "discuss", "pray", "share")
    let systemImage: String   // SF Symbol name — monochrome line glyph
    let label: String         // VoiceOver accessibility label
    let isEnabled: Bool
    let action: () -> Void

    init(
        id: String = UUID().uuidString,
        intent: String,
        systemImage: String,
        label: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.intent = intent
        self.systemImage = systemImage
        self.label = label
        self.isEnabled = isEnabled
        self.action = action
    }
}

// MARK: - AmenActionPill

/// The canonical universal action pill (A18).
///
/// Layout: [secondary icon] [secondary icon] … [| separator] [● primary action]
/// All contained in a white Capsule with AmenShadow.floating.
///
/// Usage:
/// ```swift
/// AmenActionPill(
///     actions: [discussAction, prayAction, shareAction],
///     primaryAction: saveAction
/// )
/// ```
struct AmenActionPill: View {

    /// Secondary actions shown as monochrome line icons left of the separator.
    let actions: [AmenPillAction]

    /// Optional circular primary action button on the right end.
    let primaryAction: AmenPillAction?

    /// Maximum secondary actions visible before collapsing to a "more" button.
    var maxVisibleActions: Int = 4

    // MARK: Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: Internal state

    @State private var pressedId: String? = nil
    @State private var showOverflow: Bool = false

    // MARK: Computed

    private var visibleActions: [AmenPillAction] {
        Array(actions.prefix(maxVisibleActions))
    }

    private var overflowActions: [AmenPillAction] {
        guard actions.count > maxVisibleActions else { return [] }
        return Array(actions.dropFirst(maxVisibleActions))
    }

    private var hasOverflow: Bool { !overflowActions.isEmpty }

    // MARK: Body

    var body: some View {
        HStack(spacing: 0) {
            secondarySection
            if primaryAction != nil {
                separatorDivider
                primarySection
            }
        }
        .background(pillBackground)
        .clipShape(Capsule(style: .continuous))
        .shadow(
            color: .black.opacity(0.10),
            radius: 32,
            x: 0,
            y: 10
        )
        .accessibilityElement(children: .contain)
        .popover(isPresented: $showOverflow) {
            overflowMenu
        }
    }

    // MARK: - Secondary Section

    @ViewBuilder
    private var secondarySection: some View {
        HStack(spacing: 20) {
            ForEach(visibleActions) { pillAction in
                secondaryButton(for: pillAction)
            }
            if hasOverflow {
                overflowButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func secondaryButton(for pillAction: AmenPillAction) -> some View {
        Button {
            guard pillAction.isEnabled else { return }
            triggerHaptic()
            withAnimation(springOrEaseOut) {
                pressedId = pillAction.id
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(springOrEaseOut) { pressedId = nil }
                pillAction.action()
            }
        } label: {
            Image(systemName: pillAction.systemImage)
                .font(.systemScaled(17, weight: .regular))
                .foregroundStyle(
                    pillAction.isEnabled
                        ? Color(uiColor: .secondaryLabel)
                        : Color(uiColor: .tertiaryLabel)
                )
                .frame(width: 44, height: 44)
                .scaleEffect(pressedId == pillAction.id ? 0.88 : 1.0)
                .animation(springOrEaseOut, value: pressedId)
        }
        .buttonStyle(.plain)
        .disabled(!pillAction.isEnabled)
        .accessibilityLabel(pillAction.label)
        .accessibilityHint(
            pillAction.isEnabled
                ? "Tap to \(pillAction.label.lowercased())"
                : "Not available"
        )
        .accessibilityAddTraits(pillAction.isEnabled ? [] : .isStaticText)
    }

    private var overflowButton: some View {
        Button {
            showOverflow = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.systemScaled(17, weight: .regular))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More actions")
        .accessibilityHint("Shows \(overflowActions.count) additional actions")
    }

    // MARK: - Separator

    private var separatorDivider: some View {
        Rectangle()
            .fill(Color(uiColor: .separator))
            .frame(width: 0.5, height: 24)
    }

    // MARK: - Primary Section

    @ViewBuilder
    private var primarySection: some View {
        if let primary = primaryAction {
            Button {
                guard primary.isEnabled else { return }
                triggerHaptic()
                withAnimation(springOrEaseOut) { pressedId = primary.id }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(springOrEaseOut) { pressedId = nil }
                    primary.action()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            primary.isEnabled
                                ? Color.accentColor
                                : Color(uiColor: .tertiarySystemFill)
                        )
                        .frame(width: 44, height: 44)
                    Image(systemName: primary.systemImage)
                        .font(.systemScaled(17, weight: .semibold))
                        .foregroundStyle(
                            primary.isEnabled
                                ? Color.white
                                : Color(uiColor: .tertiaryLabel)
                        )
                }
                .scaleEffect(pressedId == primary.id ? 0.88 : 1.0)
                .animation(springOrEaseOut, value: pressedId)
            }
            .buttonStyle(.plain)
            .disabled(!primary.isEnabled)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .accessibilityLabel(primary.label)
            .accessibilityHint(
                primary.isEnabled
                    ? "Tap to \(primary.label.lowercased())"
                    : "Not available"
            )
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var pillBackground: some View {
        if reduceTransparency {
            Color(uiColor: .systemBackground)
        } else {
            Color.white
        }
    }

    // MARK: - Overflow Menu

    private var overflowMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(overflowActions) { pillAction in
                Button {
                    showOverflow = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        pillAction.action()
                    }
                } label: {
                    Label(pillAction.label, systemImage: pillAction.systemImage)
                        .font(.body)
                        .foregroundStyle(
                            pillAction.isEnabled
                                ? Color(uiColor: .label)
                                : Color(uiColor: .tertiaryLabel)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .disabled(!pillAction.isEnabled)
                .accessibilityLabel(pillAction.label)
            }
        }
        .padding(.vertical, 4)
        .presentationCompactAdaptation(.popover)
    }

    // MARK: - Helpers

    private var springOrEaseOut: Animation {
        reduceMotion
            ? .easeOut(duration: 0.12)
            : .spring(response: 0.24, dampingFraction: 0.84)
    }

    private func triggerHaptic() {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
}

// MARK: - Preview

#Preview("Action Pill — standard") {
    VStack(spacing: 32) {
        // Standard pill with primary
        AmenActionPill(
            actions: [
                AmenPillAction(intent: "discuss", systemImage: "bubble.left.and.bubble.right",
                               label: "Discuss") { print("discuss") },
                AmenPillAction(intent: "pray", systemImage: "hands.and.sparkles",
                               label: "Pray") { print("pray") },
                AmenPillAction(intent: "share", systemImage: "square.and.arrow.up",
                               label: "Share") { print("share") }
            ],
            primaryAction: AmenPillAction(
                intent: "study", systemImage: "book.pages", label: "Study"
            ) { print("study") }
        )

        // Overflow pill (>4 actions)
        AmenActionPill(
            actions: [
                AmenPillAction(intent: "discuss", systemImage: "bubble.left.and.bubble.right",
                               label: "Discuss") { print("discuss") },
                AmenPillAction(intent: "pray", systemImage: "hands.and.sparkles",
                               label: "Pray") { print("pray") },
                AmenPillAction(intent: "share", systemImage: "square.and.arrow.up",
                               label: "Share") { print("share") },
                AmenPillAction(intent: "ask", systemImage: "questionmark.bubble",
                               label: "Ask a Question") { print("ask") },
                AmenPillAction(intent: "study", systemImage: "book.pages",
                               label: "Study") { print("study") }
            ],
            primaryAction: AmenPillAction(
                intent: "announce", systemImage: "megaphone", label: "Announce"
            ) { print("announce") },
            maxVisibleActions: 3
        )

        // Secondary-only, one disabled
        AmenActionPill(
            actions: [
                AmenPillAction(intent: "discuss", systemImage: "bubble.left.and.bubble.right",
                               label: "Discuss", isEnabled: false) { }
            ],
            primaryAction: nil
        )
    }
    .padding(24)
    .background(Color(uiColor: .systemGroupedBackground))
}
