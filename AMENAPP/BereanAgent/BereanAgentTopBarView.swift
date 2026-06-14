// BereanAgentTopBarView.swift
// AMEN — Berean Agent Surface (BAS) Wave 1, Lane B
//
// Adaptive top bar that re-skins per active BASComposerMode.
// Design §2: Liquid Glass background, warm paper bg, wine-red accent (one element),
// 24pt corners, soft shadow. SF system font for UI; serif ONLY for Berean wordmark.
// All animations gated by @Environment(\.accessibilityReduceMotion).
//
// CRITICAL: This file does NOT import or reference BereanAgentComposerView.
//           Mode is received via a Binding — full decoupling enforced.
//
// Lane rule: ONLY writes to BereanAgent/. No outside-lane references.
// Type prefix: BAS* for all new types in this file.

import SwiftUI

// MARK: - BASTopBarAccessoryProvider (local conformance helper)
//
// Protocol is declared in BereanAgentContracts.swift (C-4).
// Concrete accessory structs below conform to it.

// MARK: - BASTopBarStudyAccessory

/// Translation-version pill row shown in .study mode.
/// ESV / NIV / KJV / BSB — tappable stubs (selection state is cosmetic in Wave 1).
struct BASTopBarStudyAccessory: BASTopBarAccessoryProvider {

    @Binding var selectedTranslation: String

    let accessibilityLabel: String = "Bible translation selector"

    private let translations = ["ESV", "NIV", "KJV", "BSB"]

    @ViewBuilder func accessoryContent() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(translations, id: \.self) { t in
                    Button {
                        selectedTranslation = t
                    } label: {
                        Text(t)
                            .font(.caption.weight(selectedTranslation == t ? .semibold : .regular))
                            .foregroundStyle(
                                selectedTranslation == t ? Color.white : Color.basInk.opacity(0.75)
                            )
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(selectedTranslation == t
                                          ? Color.basWineRed
                                          : Color.basTan.opacity(0.65))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(t) translation\(selectedTranslation == t ? ", selected" : "")")
                    .accessibilityHint(selectedTranslation == t ? "" : "Switches Bible translation to \(t)")
                    .accessibilityAddTraits(selectedTranslation == t ? [.isSelected, .isButton] : .isButton)
                }
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - BASTopBarPrivateAccessory

/// Lock icon + "Private" label shown in .pray mode.
struct BASTopBarPrivateAccessory: BASTopBarAccessoryProvider {

    let accessibilityLabel: String = "Private prayer mode"

    @ViewBuilder func accessoryContent() -> some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.basWineRed)
            Text("Private")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.basInk.opacity(0.75))
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - BASTopBarSafetyAccessory

/// Shield icon + safety status label shown in .post mode.
/// "Safety: Passing" (green) or "Review needed" (amber).
struct BASTopBarSafetyAccessory: BASTopBarAccessoryProvider {

    /// Wave 1 stub: safety always "Passing". Wave 2+ will wire real audit results.
    var isPassing: Bool = true

    let accessibilityLabel: String = "Post safety status"

    @ViewBuilder func accessoryContent() -> some View {
        HStack(spacing: 5) {
            Image(systemName: isPassing ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(isPassing ? Color.green : Color.orange)
            Text(isPassing ? "Safety: Passing" : "Review needed")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.basInk.opacity(0.75))
        }
        .accessibilityLabel(isPassing
                            ? "Safety check passing"
                            : "Safety review needed")
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - BASTopBarAgentAccessory

/// Animated dots + "Berean is working…" shown in .agent mode.
/// Dots animation is gated by the reduceMotion flag passed from the parent.
/// Uses Timer.publish + onReceive — safe for SwiftUI struct lifecycle.
struct BASTopBarAgentAccessory: BASTopBarAccessoryProvider {

    let accessibilityLabel: String = "Berean agent working"
    let reduceMotion: Bool

    @State private var dotPhase: Int = 0

    private let dotTimer = Timer.publish(every: 0.45, on: .main, in: .common).autoconnect()

    @ViewBuilder func accessoryContent() -> some View {
        HStack(spacing: 5) {
            if reduceMotion {
                // Static indicator for reduced-motion preference
                Image(systemName: "ellipsis")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.basInk.opacity(0.6))
            } else {
                // Animated three-dot loader
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Color.basInk.opacity(dotPhase == i ? 0.85 : 0.25))
                            .frame(width: 5, height: 5)
                            .scaleEffect(dotPhase == i ? 1.2 : 0.9)
                            .animation(
                                Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8))
                                    .delay(Double(i) * 0.15),
                                value: dotPhase
                            )
                    }
                }
                .onReceive(dotTimer) { _ in
                    dotPhase = (dotPhase + 1) % 3
                }
            }

            Text("Berean is working\u{2026}")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.basInk.opacity(0.65))
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - BereanAgentTopBarView

/// Adaptive top bar for the Berean Agent Surface.
/// Receives `activeMode` as a Binding — it does NOT reference BereanAgentComposerView.
struct BereanAgentTopBarView: View {

    // MARK: Input

    @Binding var activeMode: BASComposerMode

    // MARK: State — accessory sub-state kept here for stable @State ownership

    /// Translation selection owned by the top bar so @State is stable across re-renders.
    @State private var studyTranslation: String = "ESV"

    // MARK: Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Observed directly so lock icon stays in sync with permission changes.
    @State private var broker = BASPermissionBroker.shared

    // MARK: Body

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 12) {
                wordmark

                Spacer(minLength: 8)

                accessoryArea
                    .animation(
                        reduceMotion ? nil : Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8)),
                        value: activeMode
                    )

                Spacer(minLength: 8)

                if broker.isPrivateModeActive {
                    privateLockIcon
                        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(in: .rect(cornerRadius: 24))
            .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 4)
        }
        .padding(.horizontal, 16)
    }

    // MARK: Wordmark

    private var wordmark: some View {
        HStack(spacing: 6) {
            Text("Berean")
                .font(.system(.body, design: .serif).weight(.semibold))
                .foregroundStyle(Color.basInk)
                .accessibilityAddTraits(.isHeader)

            Image(systemName: "hands.sparkles")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.basWineRed)
                .accessibilityHidden(true)
        }
        .accessibilityLabel("Berean")
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Accessory Area

    @ViewBuilder
    private var accessoryArea: some View {
        switch activeMode {
        case .study:
            BASTopBarStudyAccessory(selectedTranslation: $studyTranslation)
                .accessoryContent()

        case .pray:
            BASTopBarPrivateAccessory()
                .accessoryContent()

        case .post:
            BASTopBarSafetyAccessory()
                .accessoryContent()

        case .agent:
            BASTopBarAgentAccessory(reduceMotion: reduceMotion)
                .accessoryContent()

        default:
            EmptyView()
        }
    }

    // MARK: Private Lock Icon

    private var privateLockIcon: some View {
        Image(systemName: "lock.fill")
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.basInk.opacity(0.55))
            .accessibilityLabel("Private mode active")
            .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("TopBar — Ask") {
    @Previewable @State var mode: BASComposerMode = .ask
    VStack(spacing: 16) {
        BereanAgentTopBarView(activeMode: $mode)
        Picker("Mode", selection: $mode) {
            ForEach(BASComposerMode.allCases) { m in
                Text(m.displayName).tag(m)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }
    .padding(.top)
    .background(Color.basWarmPaper)
}

#Preview("TopBar — Study") {
    @Previewable @State var mode: BASComposerMode = .study
    BereanAgentTopBarView(activeMode: $mode)
        .padding(.top)
        .background(Color.basWarmPaper)
}

#Preview("TopBar — Agent") {
    @Previewable @State var mode: BASComposerMode = .agent
    BereanAgentTopBarView(activeMode: $mode)
        .padding(.top)
        .background(Color.basWarmPaper)
}
#endif
