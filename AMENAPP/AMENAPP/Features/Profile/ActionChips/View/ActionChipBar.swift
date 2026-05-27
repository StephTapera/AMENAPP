import SwiftUI

// MARK: - ActionChipBar

/// Horizontal scrolling row of capsule action buttons rendered below the
/// profile header bio. Chips are pre-resolved by `ActionChipBarViewModel`;
/// this view is purely presentational.
///
/// Usage:
/// ```swift
/// ActionChipBar(chips: viewModel.resolvedChips, targetUserId: userId) { route in
///     navigator.handle(route)
/// }
/// ```
public struct ActionChipBar: View {

    // MARK: Public Interface

    public let chips: [any ActionChip]
    public let targetUserId: String
    public let onRoute: (ActionChipRoute) -> Void

    // MARK: Init

    public init(
        chips: [any ActionChip],
        targetUserId: String,
        onRoute: @escaping (ActionChipRoute) -> Void
    ) {
        self.chips = chips
        self.targetUserId = targetUserId
        self.onRoute = onRoute
    }

    // MARK: Body

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(chips, id: \.id) { chip in
                    ActionChipButton(chip: chip, targetUserId: targetUserId, onRoute: onRoute)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - ActionChipButton

/// Individual capsule button for a single chip.
private struct ActionChipButton: View {

    let chip: any ActionChip
    let targetUserId: String
    let onRoute: (ActionChipRoute) -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            onRoute(chip.routeAction(for: targetUserId))
        } label: {
            chipLabel
        }
        .buttonStyle(ChipButtonStyle(isPressed: $isPressed))
        .accessibilityLabel(chip.label)
        .accessibilityHint("Activates \(chip.label) action")
    }

    private var chipLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: chip.systemImage)
                .font(.subheadline.weight(.medium))
            Text(chip.label)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 40)
        .background(chipBackground)
        .clipShape(Capsule())
        .overlay(chipBorder)
    }

    private var chipBackground: some View {
        ZStack {
            Capsule()
                .fill(.ultraThinMaterial)
            Capsule()
                .fill(Color.white.opacity(0.15))
        }
    }

    private var chipBorder: some View {
        Capsule()
            .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5)
    }
}

// MARK: - ChipButtonStyle

/// Custom button style that applies a spring scale-down on press.
private struct ChipButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(
                .spring(response: 0.4, dampingFraction: 0.75),
                value: configuration.isPressed
            )
            .onChange(of: configuration.isPressed) { _, newValue in
                isPressed = newValue
            }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("ActionChipBar — creator church") {
    let chips: [any ActionChip] = [
        PrayChip(),
        MessageChip(),
        SendVerseChip(),
        GiveChip(),
        SubscribeChip()
    ]
    ZStack {
        Color.gray.ignoresSafeArea()
        ActionChipBar(chips: chips, targetUserId: "preview_user") { route in
            print("Routed: \(route)")
        }
    }
}

#Preview("ActionChipBar — own profile (empty)") {
    ZStack {
        Color.gray.ignoresSafeArea()
        ActionChipBar(chips: [], targetUserId: "self") { _ in }
    }
}
#endif
