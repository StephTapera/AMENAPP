// BereanComposerTray.swift
// AMENAPP
//
// Capability-first glass tray that floats above the Berean composer input bar.
// Adapts to what the user is typing: quick-start suggestions when empty,
// scripture lookup chips when a reference is detected, reasoning chips when
// a question is forming, and an inline mode picker (all 5 modes) plus an
// expandable capabilities panel — all without presenting any sheet.
//
// Agent H — BereanUI Rebuild, 2026-05-27

import SwiftUI

// MARK: - Draft Intent

/// Describes what Berean has inferred from the current draft text.
/// Parent is responsible for classifying the draft and passing this in.
enum BereanDraftIntent: Equatable {
    case empty
    case question
    case scriptureRef(String)
    case prayer
    case modeKeyword(BereanPersonalityMode)
}

// MARK: - Capabilities Panel Model

private struct BereanCapability: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
}

private let bereanCapabilities: [BereanCapability] = [
    BereanCapability(icon: "book.pages.fill",            title: "Scripture Lookup",        detail: "Look up any verse or passage by reference."),
    BereanCapability(icon: "hands.sparkles.fill",         title: "Prayer Companion",        detail: "Guided prayer, reflection, and Scripture anchors."),
    BereanCapability(icon: "magnifyingglass.circle.fill", title: "Deep Study",              detail: "Structured exposition with cross-references."),
    BereanCapability(icon: "checkmark.seal.fill",         title: "Citation Verification",   detail: "Checks that quotes are accurate to their source."),
    BereanCapability(icon: "mic.fill",                    title: "Voice Mode",              detail: "Speak your question or prayer hands-free."),
    BereanCapability(icon: "brain.head.profile",          title: "Memory",                  detail: "Remembers context across your sessions."),
    BereanCapability(icon: "note.text.badge.plus",        title: "Save to Notes",           detail: "Saves Berean's response to your Church Notes."),
    BereanCapability(icon: "arrow.triangle.branch",       title: "Cross-reference",         detail: "Finds related passages across the whole Bible."),
    BereanCapability(icon: "character.magnify",           title: "Word Study",              detail: "Original Greek and Hebrew word meanings."),
]

// MARK: - BereanComposerTray

/// The glass tray that sits above the composer input bar.
/// VStack(spacing: 8) this above BereanComposerBar / BereanCompactComposerBar.
struct BereanComposerTray: View {

    // MARK: Interface

    @Binding var draftText: String
    let draftIntent: BereanDraftIntent
    let selectedMode: BereanPersonalityMode
    var onModeChange: (BereanPersonalityMode) -> Void
    var onChipTap: (String) -> Void      // fills draftText with suggested starter text
    var onActionTap: (BereanLiquidAction.ActionType) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: Private state

    @State private var showModePicker = false
    @State private var showCapabilities = false
    @State private var scriptureGoldPulse = false
    @State private var modeChipPressedID: BereanPersonalityMode? = nil
    /// Stored task reference so `startGoldPulse()` can cancel the previous loop
    /// before starting a new one (P-07: unbounded concurrent task fix).
    @State private var goldPulseTask: Task<Void, Never>? = nil

    // The five primary modes surfaced inline (matches the spec "all 5 modes").
    private let primaryModes: [BereanPersonalityMode] = [
        .askBerean,
        .scriptureStudy,
        .prayerCompanion,
        .deepStudy,
        .discernment
    ]

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top suggestion / detection row
            intentRow

            // Mode picker row — toggled by "+" area; always visible when intent is .empty or showModePicker
            if showModePicker || draftIntent == .empty {
                modePickerRow
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .move(edge: .bottom))
                    )
            }

            // Expandable capabilities panel
            if showCapabilities {
                capabilitiesPanel
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .move(edge: .top))
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(trayBackground)
        .animation(reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.78), value: draftIntent)
        .animation(reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.78), value: showModePicker)
        .animation(reduceMotion ? .none : .spring(response: 0.42, dampingFraction: 0.82), value: showCapabilities)
        .onChange(of: draftIntent) { _, _ in
            goldPulseTask?.cancel()
            goldPulseTask = nil
        }
    }

    // MARK: - Tray Background

    @ViewBuilder
    private var trayBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(BereanColor.glassFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.70),
                                    Color.white.opacity(0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                )
                .shadow(color: BereanColor.shadowColor.opacity(0.08), radius: 12, x: 0, y: 4)
        }
    }

    // MARK: - Intent Row

    @ViewBuilder
    private var intentRow: some View {
        if draftIntent == .empty {
            // Focus-trigger: vertical glass rows matching the disambiguation card pattern
            quickStartFocusRows
        } else {
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        switch draftIntent {
                        case .empty:
                            EmptyView()
                        case .scriptureRef(let ref):
                            scriptureDetectedChip(ref: ref)
                            otherQuickStartChips(excluding: .scriptureStudy)
                        case .question:
                            reasoningReadyChip
                            activeModePill
                        case .prayer:
                            prayerReadyChip
                            activeModePill
                        case .modeKeyword(let mode):
                            modeKeywordChips(highlightedMode: mode)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    capabilitiesToggleButton
                    modePickerToggleButton
                }
            }
        }
    }

    // MARK: - Focus Trigger Rows (empty state)

    private var quickStartFocusRows: some View {
        VStack(spacing: 0) {
            focusRow(icon: "sparkles",       text: "Ask a question",   hint: "Get scripture-grounded answers") { onChipTap("Ask a question") }
            Divider().padding(.leading, 50)
            focusRow(icon: "book.pages.fill", text: "Study scripture",  hint: "Look up any verse or passage")   { onChipTap("Study scripture") }
            Divider().padding(.leading, 50)
            focusRow(icon: "hands.sparkles",  text: "Pray together",    hint: "Guided prayer and reflection")   { onChipTap("Pray together") }
        }
    }

    private func focusRow(icon: String, text: String, hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AmenTheme.Colors.amenBlue)
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(text)
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(BereanColor.textPrimary)
                    Text(hint)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(BereanColor.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 4)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
        .accessibilityHint(hint)
    }

    // MARK: Quick-start chips (empty state)

    private var quickStartChips: some View {
        Group {
            quickChip(icon: "sparkles",        text: "Ask a question",   fill: .empty)
            quickChip(icon: "book.pages.fill",  text: "Study scripture",  fill: .empty)
            quickChip(icon: "hands.sparkles",   text: "Pray together",    fill: .empty)
        }
    }

    /// Returns the two chips that are NOT related to the given mode (for use in scripture detected state).
    @ViewBuilder
    private func otherQuickStartChips(excluding mode: BereanPersonalityMode) -> some View {
        if mode != .prayerCompanion {
            quickChip(icon: "hands.sparkles", text: "Pray together", fill: .faded)
        }
        if mode != .deepStudy {
            quickChip(icon: "sparkles",       text: "Ask a question", fill: .faded)
        }
    }

    // MARK: Scripture detected chip

    @ViewBuilder
    private func scriptureDetectedChip(ref: String) -> some View {
        Button {
            onChipTap("Tell me about \(ref)")
            HapticManager.impact(style: .light)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "book.pages.fill")
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(Color.amenGold)
                Text("Lookup: \(ref)")
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(BereanColor.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minWidth: 44, minHeight: 44)
            .background(
                Capsule()
                    .fill(reduceTransparency
                          ? Color(uiColor: .secondarySystemBackground)
                          : Color.amenGold.opacity(0.10))
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                Color.amenGold.opacity(scriptureGoldPulse ? 0.90 : 0.50),
                                lineWidth: 1.2
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Look up \(ref)")
        .accessibilityHint("Asks Berean about \(ref)")
        .onAppear { startGoldPulse() }
        .onChange(of: ref) { _, _ in startGoldPulse() }
        .onDisappear { goldPulseTask?.cancel() }
    }

    // MARK: Reasoning ready chip

    private var reasoningReadyChip: some View {
        // Color.amenPurple is a global token defined in ChurchNotesDesignSystem.swift.
        // No private copy needed here. (DS-9: already promoted to global Color extension.)
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(AMENFont.semiBold(11))
                .foregroundStyle(Color.amenPurple)
            Text("Berean: reasoning ready")
                .font(AMENFont.medium(13))
                .foregroundStyle(Color.amenPurple)
                .lineLimit(1)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .background(
            Capsule()
                .fill(reduceTransparency
                      ? Color(uiColor: .secondarySystemBackground)
                      : Color.amenPurple.opacity(0.08))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.amenPurple.opacity(0.35), lineWidth: 0.75)
                )
        )
        .accessibilityLabel("Berean reasoning ready")
        .accessibilityAddTraits(.isStaticText)
    }

    // MARK: Prayer ready chip

    private var prayerReadyChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "hands.sparkles.fill")
                .font(AMENFont.semiBold(11))
                .foregroundStyle(Color.amenGold)
            Text("Prayer companion ready")
                .font(AMENFont.medium(13))
                .foregroundStyle(BereanColor.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .background(
            Capsule()
                .fill(reduceTransparency
                      ? Color(uiColor: .secondarySystemBackground)
                      : Color.amenGold.opacity(0.08))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.amenGold.opacity(0.40), lineWidth: 0.75)
                )
        )
        .accessibilityLabel("Prayer companion ready")
        .accessibilityAddTraits(.isStaticText)
    }

    // MARK: Active mode pill (used alongside reasoning/prayer chips)

    private var activeModePill: some View {
        HStack(spacing: 5) {
            Image(systemName: selectedMode.icon)
                .font(AMENFont.semiBold(11))
                .foregroundStyle(Color.amenGold)
            Text(selectedMode.rawValue)
                .font(AMENFont.medium(12))
                .foregroundStyle(BereanColor.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .frame(minHeight: 44)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.amenGold.opacity(0.55), lineWidth: 1.0)
                )
        )
        .accessibilityLabel("Active mode: \(selectedMode.rawValue)")
        .accessibilityAddTraits(.isStaticText)
    }

    // MARK: Mode keyword chips (glowing highlighted mode)

    @ViewBuilder
    private func modeKeywordChips(highlightedMode: BereanPersonalityMode) -> some View {
        ForEach(primaryModes, id: \.self) { mode in
            let isHighlighted = mode == highlightedMode
            Button {
                onModeChange(mode)
                HapticManager.impact(style: .light)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: mode.icon)
                        .font(AMENFont.semiBold(11))
                        .foregroundStyle(isHighlighted ? Color.white : BereanColor.textSecondary)
                    Text(mode.rawValue)
                        .font(AMENFont.medium(12))
                        .foregroundStyle(isHighlighted ? Color.white : BereanColor.textPrimary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(minHeight: 44)
                .scaleEffect(isHighlighted ? 1.05 : 1.0)
                .background(
                    Capsule()
                        .fill(isHighlighted ? Color.amenGold : (reduceTransparency ? Color(uiColor: .secondarySystemBackground) : BereanColor.glassFill))
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    isHighlighted ? Color.amenGold : BereanColor.glassBorder,
                                    lineWidth: isHighlighted ? 1.5 : 0.5
                                )
                        )
                )
            }
            .buttonStyle(.plain)
            .animation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.88), value: isHighlighted)
            .accessibilityLabel("\(mode.rawValue) mode\(isHighlighted ? ", suggested" : "")")
            .accessibilityHint("Switch to \(mode.rawValue)")
            .accessibilityAddTraits(mode == selectedMode ? .isSelected : [])
        }
    }

    // MARK: - Mode Picker Row (inline, no sheet)

    private var modePickerRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(primaryModes, id: \.self) { mode in
                    modeChip(mode)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func modeChip(_ mode: BereanPersonalityMode) -> some View {
        let isActive = selectedMode == mode

        return Button {
            withAnimation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.88)) {
                onModeChange(mode)
                modeChipPressedID = mode
            }
            HapticManager.impact(style: .light)
            // reset scale feedback
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                modeChipPressedID = nil
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: mode.icon)
                    .font(AMENFont.semiBold(11))
                    .foregroundStyle(isActive ? Color.white : BereanColor.textSecondary)
                Text(mode.rawValue)
                    .font(AMENFont.medium(13))
                    .foregroundStyle(isActive ? Color.white : BereanColor.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(height: 36)
            .background(
                Capsule()
                    .fill(isActive
                          ? AnyShapeStyle(Color.amenGold)
                          : (reduceTransparency
                             ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
                             : AnyShapeStyle(Material.ultraThinMaterial)))
                    .overlay(
                        Capsule()
                            .fill(isActive ? Color.clear : BereanColor.glassFill)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(isActive ? Color.clear : BereanColor.glassBorder, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(modeChipPressedID == mode ? 0.94 : 1.0)
        .animation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.88), value: isActive)
        .animation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.88), value: modeChipPressedID)
        .accessibilityLabel("\(mode.rawValue) mode")
        .accessibilityHint("Switch to \(mode.rawValue)")
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Capabilities Panel (inline expansion, no sheet)

    private var capabilitiesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(BereanColor.separator)
                .frame(height: 0.5)
                .padding(.horizontal, 2)
                .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(bereanCapabilities) { cap in
                    capabilityRow(cap)
                }
            }
        }
    }

    private func capabilityRow(_ cap: BereanCapability) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: cap.icon)
                .font(AMENFont.semiBold(14))
                .foregroundStyle(Color.amenGold)
                .frame(width: 22, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(cap.title)
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(BereanColor.textPrimary)
                Text(cap.detail)
                    .font(AMENFont.regular(12))
                    .foregroundStyle(BereanColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(cap.title): \(cap.detail)")
    }

    // MARK: - Control Buttons

    private var capabilitiesToggleButton: some View {
        Button {
            withAnimation(reduceMotion ? .none : .spring(response: 0.42, dampingFraction: 0.82)) {
                showCapabilities.toggle()
            }
            HapticManager.impact(style: .light)
        } label: {
            HStack(spacing: 4) {
                Text("···")
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(BereanColor.textSecondary)
            }
            .frame(width: 44, height: 36)
            .background(
                Capsule()
                    .fill(showCapabilities
                          ? AnyShapeStyle(Color.amenBlue.opacity(0.12))
                          : (reduceTransparency ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground)) : AnyShapeStyle(Material.ultraThinMaterial)))
                    .overlay(
                        Capsule()
                            .fill(showCapabilities ? Color.clear : BereanColor.glassFill)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                showCapabilities ? Color.amenBlue.opacity(0.40) : BereanColor.glassBorder,
                                lineWidth: 0.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showCapabilities ? "Hide Berean capabilities" : "What can Berean do?")
        .accessibilityHint(showCapabilities ? "Collapses the capabilities list" : "Shows all Berean capabilities inline")
    }

    private var modePickerToggleButton: some View {
        Button {
            withAnimation(reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.78)) {
                showModePicker.toggle()
            }
            HapticManager.impact(style: .light)
        } label: {
            Image(systemName: showModePicker ? "chevron.down" : selectedMode.icon)
                .font(AMENFont.semiBold(12))
                .foregroundStyle(showModePicker ? BereanColor.textSecondary : Color.amenGold)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(showModePicker
                              ? (reduceTransparency ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground)) : AnyShapeStyle(Material.ultraThinMaterial))
                              : AnyShapeStyle(Color.amenGold.opacity(0.12)))
                        .overlay(
                            Circle().fill(showModePicker ? BereanColor.glassFill : Color.clear)
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    showModePicker ? BereanColor.glassBorder : Color.amenGold.opacity(0.35),
                                    lineWidth: 0.5
                                )
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showModePicker ? "Hide mode picker" : "Switch mode (current: \(selectedMode.rawValue))")
        .accessibilityHint(showModePicker ? "Collapses mode options" : "Opens all Berean modes inline")
    }

    // MARK: - Chip Helpers

    private enum ChipFill { case empty, faded }

    private func quickChip(icon: String, text: String, fill: ChipFill) -> some View {
        Button {
            onChipTap(text)
            HapticManager.impact(style: .light)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(AMENFont.semiBold(11))
                    .foregroundStyle(fill == .faded
                                     ? BereanColor.textTertiary
                                     : BereanColor.textSecondary)
                Text(text)
                    .font(AMENFont.medium(13))
                    .foregroundStyle(fill == .faded
                                     ? BereanColor.textTertiary
                                     : BereanColor.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .opacity(fill == .faded ? 0.4 : 1.0)
            .background(
                Capsule()
                    .fill(reduceTransparency
                          ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
                          : AnyShapeStyle(Material.ultraThinMaterial))
                    .overlay(
                        Capsule().fill(BereanColor.glassFill)
                    )
                    .overlay(
                        Capsule().strokeBorder(BereanColor.glassBorder, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.88), value: fill)
        .accessibilityLabel(text)
        .accessibilityHint("Fills the composer with \"\(text)\"")
    }

    // MARK: - Animation Helpers

    private func startGoldPulse() {
        guard !reduceMotion else { return }
        // Cancel any in-flight pulse loop before starting a new one (P-07 fix:
        // prevents unbounded concurrent tasks when scripture ref changes rapidly).
        goldPulseTask?.cancel()
        scriptureGoldPulse = false
        // Drive the border opacity between two values using a repeating task so
        // the only animation curve applied to SwiftUI state is a spring.
        goldPulseTask = Task { @MainActor in
            while !Task.isCancelled {
                withAnimation(reduceMotion ? .none : .spring(response: 0.42, dampingFraction: 0.82)) {
                    scriptureGoldPulse = true
                }
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled else { break }
                withAnimation(reduceMotion ? .none : .spring(response: 0.42, dampingFraction: 0.82)) {
                    scriptureGoldPulse = false
                }
                try? await Task.sleep(for: .milliseconds(600))
            }
        }
    }
}

// MARK: - Preview

#Preview("Empty / idle") {
    @Previewable @State var draft = ""

    VStack(spacing: 8) {
        BereanComposerTray(
            draftText: $draft,
            draftIntent: .empty,
            selectedMode: .scholar,
            onModeChange: { _ in },
            onChipTap: { draft = $0 },
            onActionTap: { _ in }
        )
        .padding(.horizontal, 16)

        Spacer()
    }
    .background(Color.white)
    .ignoresSafeArea(edges: .bottom)
}

#Preview("Scripture reference detected") {
    @Previewable @State var draft = "Tell me about John 3:16"

    VStack(spacing: 8) {
        BereanComposerTray(
            draftText: $draft,
            draftIntent: .scriptureRef("John 3:16"),
            selectedMode: .scholar,
            onModeChange: { _ in },
            onChipTap: { draft = $0 },
            onActionTap: { _ in }
        )
        .padding(.horizontal, 16)

        Spacer()
    }
    .background(Color.white)
    .ignoresSafeArea(edges: .bottom)
}

#Preview("Question intent") {
    @Previewable @State var draft = "Why does God allow suffering?"

    VStack(spacing: 8) {
        BereanComposerTray(
            draftText: $draft,
            draftIntent: .question,
            selectedMode: .strategist,
            onModeChange: { _ in },
            onChipTap: { draft = $0 },
            onActionTap: { _ in }
        )
        .padding(.horizontal, 16)

        Spacer()
    }
    .background(Color.white)
    .ignoresSafeArea(edges: .bottom)
}

#Preview("Mode keyword — pray") {
    @Previewable @State var draft = "I want to pray about anxiety"

    VStack(spacing: 8) {
        BereanComposerTray(
            draftText: $draft,
            draftIntent: .modeKeyword(.shepherd),
            selectedMode: .scholar,
            onModeChange: { _ in },
            onChipTap: { draft = $0 },
            onActionTap: { _ in }
        )
        .padding(.horizontal, 16)

        Spacer()
    }
    .background(Color.white)
    .ignoresSafeArea(edges: .bottom)
}
