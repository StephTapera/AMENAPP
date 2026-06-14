// BereanAgentPluginDrawerView.swift
// AMEN — Berean Agent Surface (BAS) Wave 2, Lane C
//
// @ Plugin Drawer — slides up as a glass sheet when the user taps @ in the composer.
// Design §2: Liquid Glass (.glassEffect), warm paper bg, tan surface,
// wine-red accent (one element per screen), 24pt top corners, soft shadow.
// All animations gated by @Environment(\.accessibilityReduceMotion).
// NO glass-on-glass. SF system font. Fully accessible. Dynamic Type.
//
// REGISTRY-DRIVEN: Renders from BASPluginID.allCases via BASPluginRegistry.shared.
// Adding a new BASPluginID case adds a row with ZERO changes to this view file.
//
// Lane rule: ONLY writes to BereanAgent/. No outside-lane references.
// Type prefix: BAS* for all new types in this file.

import SwiftUI

// MARK: - BereanAgentPluginDrawerView

/// Glass sheet that slides up above the keyboard when the user taps @.
/// Registry-driven: rows come from BASPluginRegistry.shared.plugins,
/// filtered by the user's search text.
struct BereanAgentPluginDrawerView: View {

    // MARK: Init

    let onPluginSelected: (BASPluginID) -> Void
    let onDismiss: () -> Void

    init(
        onPluginSelected: @escaping (BASPluginID) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.onPluginSelected = onPluginSelected
        self.onDismiss = onDismiss
    }

    // MARK: State

    @State private var searchText: String = ""

    // MARK: Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Observed directly so private-mode changes update the row availability chips.
    @State private var broker = BASPermissionBroker.shared
    @State private var registry = BASPluginRegistry.shared

    // MARK: Computed

    private var filteredPlugins: [BASPlugin] {
        let all = registry.plugins
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return all
        }
        let query = searchText.lowercased()
        return all.filter { $0.id.displayName.lowercased().contains(query) }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            dragIndicator
                .padding(.top, 8)
                .padding(.bottom, 12)

            searchBar
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            pluginList
        }
        .glassEffect(in: .rect(cornerRadius: 24))
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: -4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Plugin selection drawer")
    }

    // MARK: Drag Indicator

    private var dragIndicator: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color.basInk.opacity(0.2))
            .frame(width: 36, height: 5)
            .accessibilityHidden(true)
    }

    // MARK: Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.basInk.opacity(0.45))
                .accessibilityHidden(true)

            TextField("Search tools…", text: $searchText)
                .font(.body)
                .foregroundStyle(Color.basInk)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel("Search tools")
                .accessibilityHint("Filter the list of available plugins")

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.basInk.opacity(0.4))
                }
                .accessibilityLabel("Clear search")
                .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.basTan.opacity(0.55))
        )
        .animation(
            reduceMotion ? nil : Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8)),
            value: searchText.isEmpty
        )
    }

    // MARK: Plugin List

    private var pluginList: some View {
        Group {
            if filteredPlugins.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredPlugins) { plugin in
                            BASPluginDrawerRow(
                                plugin: plugin,
                                isPrivateModeActive: broker.isPrivateModeActive,
                                reduceMotion: reduceMotion,
                                onSelect: {
                                    onPluginSelected(plugin.id)
                                    onDismiss()
                                }
                            )

                            // Divider between rows — not after last
                            if plugin.id != filteredPlugins.last?.id {
                                Divider()
                                    .overlay(Color.basInk.opacity(0.08))
                                    .padding(.leading, 56)
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.basInk.opacity(0.25))
                .accessibilityHidden(true)

            Text("No tools match \"\(searchText)\".")
                .font(.subheadline)
                .foregroundStyle(Color.basInk.opacity(0.5))

            Text("Try 'bible', 'prayer', or 'research'.")
                .font(.footnote)
                .foregroundStyle(Color.basInk.opacity(0.35))
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
        .padding(.vertical, 32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No tools match \"\(searchText)\". Try 'bible', 'prayer', or 'research'.")
    }
}

// MARK: - BASPluginDrawerRow

/// Single 48pt row in the plugin drawer.
private struct BASPluginDrawerRow: View {

    let plugin: BASPlugin
    let isPrivateModeActive: Bool
    let reduceMotion: Bool
    let onSelect: () -> Void

    // MARK: Computed — scope status

    /// Effective scope accounting for private mode override.
    private var effectiveScope: BASScopeMode {
        isPrivateModeActive ? .never_ : plugin.currentScope
    }

    private var isUnavailable: Bool {
        effectiveScope == .never_ || effectiveScope == .privateMode
    }

    // MARK: Chip config

    private var scopeLabel: String {
        if isPrivateModeActive { return "Unavailable" }
        switch plugin.currentScope {
        case .readOnly:            return "Read Only"
        case .askEveryTime:        return "Ask"
        case .never_, .privateMode: return "Unavailable"
        case .importantActionsOnly: return "Ask"
        }
    }

    private var chipForeground: Color {
        if isPrivateModeActive || plugin.currentScope == .never_ || plugin.currentScope == .privateMode {
            return Color.basInk.opacity(0.45)
        }
        switch plugin.currentScope {
        case .readOnly:            return Color(hex: "1A6B35")   // green ink
        case .askEveryTime, .importantActionsOnly: return Color(hex: "7A5200") // amber ink
        default:                   return Color.basInk.opacity(0.45)
        }
    }

    private var chipBackground: Color {
        if isPrivateModeActive || plugin.currentScope == .never_ || plugin.currentScope == .privateMode {
            return Color.basInk.opacity(0.08)
        }
        switch plugin.currentScope {
        case .readOnly:            return Color(hex: "D6F0E0")   // soft green
        case .askEveryTime, .importantActionsOnly: return Color(hex: "FFF0CC") // soft amber
        default:                   return Color.basInk.opacity(0.08)
        }
    }

    // MARK: Accessibility strings

    private var accessibilityRowLabel: String {
        "\(plugin.id.displayName), \(scopeLabel)"
    }

    private var accessibilityHint: String? {
        isUnavailable ? "This tool is unavailable in the current privacy mode." : nil
    }

    // MARK: Body

    var body: some View {
        Button {
            guard !isUnavailable else { return }
            onSelect()
        } label: {
            rowContent
        }
        .disabled(isUnavailable)
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityRowLabel)
        .accessibilityHint(accessibilityHint ?? "")
        .animation(
            reduceMotion ? nil : Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8)),
            value: isUnavailable
        )
    }

    // MARK: Row Content

    private var rowContent: some View {
        HStack(spacing: 12) {
            // Plugin icon — wine-red when selected/available, muted when unavailable
            Image(systemName: plugin.id.iconToken)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(
                    isUnavailable
                        ? Color.basInk.opacity(0.25)
                        : Color.basWineRed
                )
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            // Name + scope description
            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.id.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        isUnavailable ? Color.basInk.opacity(0.35) : Color.basInk
                    )

                Text(scopeDescription(for: plugin.id.requiredScope))
                    .font(.footnote)
                    .foregroundStyle(Color.basInk.opacity(0.45))
            }

            Spacer(minLength: 8)

            // Scope status chip
            scopeChip
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }

    // MARK: Scope Chip

    private var scopeChip: some View {
        Text(scopeLabel)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(chipForeground)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(chipBackground)
            )
    }

    // MARK: Scope Description

    private func scopeDescription(for scope: BASScopeMode) -> String {
        switch scope {
        case .readOnly:             return "Reads data only — never writes"
        case .askEveryTime:         return "Asks permission before each action"
        case .importantActionsOnly: return "Asks only for significant actions"
        case .never_:               return "Not available"
        case .privateMode:          return "Unavailable in private mode"
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Plugin Drawer") {
    ZStack(alignment: .bottom) {
        Color.basWarmPaper.ignoresSafeArea()

        BereanAgentPluginDrawerView(
            onPluginSelected: { id in
                print("Selected plugin: \(id.displayName)")
            },
            onDismiss: {
                print("Drawer dismissed")
            }
        )
        .frame(maxHeight: 500)
    }
}

#Preview("Plugin Drawer — search active") {
    ZStack(alignment: .bottom) {
        Color.basWarmPaper.ignoresSafeArea()

        BereanAgentPluginDrawerView(
            onPluginSelected: { _ in },
            onDismiss: {}
        )
        .frame(maxHeight: 500)
    }
}
#endif
