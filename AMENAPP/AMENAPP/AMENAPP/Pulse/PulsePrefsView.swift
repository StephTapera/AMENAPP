//
//  PulsePrefsView.swift
//  AMEN — Amen Pulse (Customize)
//
//  The user-owned settings sheet for Amen Pulse. Presented from the surface via
//  `.sheet(isPresented:)`. Pulse is a *bounded* daily surface, not a feed — so this
//  screen lets a person shape WHAT they care about and WHERE Pulse looks, and only
//  ever lets them ask for LESS (never more). No streaks, no guilt, no "don't miss out."
//
//  Binds to the frozen contracts in PulseModels.swift and PulseService.swift. It does
//  NOT redefine any of those types. `Color(hex:)` is defined globally.
//

import SwiftUI

struct PulsePrefsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var prefs: PulsePrefs = .default
    @State private var isLoading = true

    /// Fail-closed minor signal. `currentUserTier` defaults to `.teen` (minor) until age
    /// assurance resolves, so the Local row stays hidden unless the account is a known adult.
    @ObservedObject private var ageService = AgeAssuranceService.shared
    private var isMinor: Bool { ageService.currentUserTier.isMinor }

    init() {}

    // The cap the user is steering. Defaults to the config maximum until prefs load.
    private var capBinding: Binding<Int> {
        Binding(
            get: { min(prefs.maxCards ?? PulseConfig.defaultMaxCards, PulseConfig.defaultMaxCards) },
            set: { prefs.maxCards = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                Form {
                    styleSection
                    interestsSection
                    sourcesSection
                    capSection
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Customize Pulse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(); dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .task { await load() }
        }
    }

    // MARK: - 1. Style

    private var styleSection: some View {
        Section {
            Picker("Pulse style", selection: $prefs.style) {
                ForEach(PulseStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: prefs.style) { _, _ in save() }
        } header: {
            sectionHeader("Style")
        } footer: {
            sectionFooter("Sets the spirit of your morning — what Pulse leans toward when it has a choice.")
        }
    }

    // MARK: - 2. Interests

    private var interestsSection: some View {
        Section {
            FlowChips(
                items: PulsePrefs.interestCatalog,
                isSelected: { prefs.interests.contains($0) },
                label: { $0.capitalized },
                onToggle: { toggleInterest($0) }
            )
            .padding(.vertical, 4)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        } header: {
            sectionHeader("What you care about")
        } footer: {
            sectionFooter("Pulse pays a little more attention to these. Choose as few or as many as you like.")
        }
    }

    private func toggleInterest(_ interest: String) {
        if let idx = prefs.interests.firstIndex(of: interest) {
            prefs.interests.remove(at: idx)
        } else {
            prefs.interests.append(interest)
        }
        save()
    }

    // MARK: - 3. Sources

    private var sourcesSection: some View {
        Section {
            sourceToggle("Friends", systemImage: "person.2.fill", value: $prefs.sources.friends)
            sourceToggle("Church", systemImage: "building.columns.fill", value: $prefs.sources.church)
            sourceToggle("Spaces", systemImage: "square.stack.3d.up.fill", value: $prefs.sources.spaces)
            sourceToggle("Following", systemImage: "heart.fill", value: $prefs.sources.following)
            sourceToggle("Global", systemImage: "globe", value: $prefs.sources.global)

            // Local is location-derived and structurally adult-only: the row is absent for
            // minor accounts (server enforces minor-safety on cards regardless).
            if !isMinor {
                VStack(alignment: .leading, spacing: 4) {
                    sourceToggle("Local", systemImage: "location.fill", value: $prefs.sources.local)
                    Text("Adult accounts only")
                        .font(.system(size: 12.5))
                        .foregroundColor(Color(hex: "8A8A8E"))
                        .padding(.leading, 30)
                }
            }
        } header: {
            sectionHeader("Where Pulse looks")
        } footer: {
            sectionFooter("Turn off anywhere you’d rather Pulse stay out of. You can change this any time.")
        }
    }

    private func sourceToggle(_ title: String, systemImage: String, value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            Label {
                Text(title).font(.system(size: 16, weight: .regular))
            } icon: {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(.label))
            }
        }
        .tint(Color(.label))
        .onChange(of: value.wrappedValue) { _, _ in save() }
    }

    // MARK: - 4. How much

    private var capSection: some View {
        Section {
            Stepper(value: capBinding,
                    in: PulseConfig.minUserCards...PulseConfig.defaultMaxCards) {
                Text("Show up to \(capBinding.wrappedValue) cards a day.")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(Color(.label))
            }
            .onChange(of: capBinding.wrappedValue) { _, _ in save() }
        } header: {
            sectionHeader("How much")
        } footer: {
            sectionFooter("Pulse is designed to end — fewer is always allowed, never more.")
        }
    }

    // MARK: - Section chrome

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 13, weight: .semibold))
            .tracking(0.4)
            .foregroundColor(Color(hex: "8A8A8E"))
    }

    private func sectionFooter(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundColor(Color(hex: "8A8A8E"))
    }

    // MARK: - Persistence

    private func load() async {
        do {
            let loaded = try await PulseService.shared.loadPrefs()
            prefs = loaded
        } catch {
            prefs = .default   // never crash; sane default on error
        }
        isLoading = false
    }

    private func save() {
        // Clamp defensively: the user may only LOWER the cap, never raise it.
        if let cap = prefs.maxCards {
            prefs.maxCards = min(max(cap, PulseConfig.minUserCards), PulseConfig.defaultMaxCards)
        }
        let snapshot = prefs
        Task { try? await PulseService.shared.savePrefs(snapshot) }
    }
}

// MARK: - Wrapping chip layout (multi-select)

private struct FlowChips: View {
    let items: [String]
    let isSelected: (String) -> Bool
    let label: (String) -> String
    let onToggle: (String) -> Void

    var body: some View {
        PulseFlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(items, id: \.self) { item in
                let selected = isSelected(item)
                Button {
                    onToggle(item)
                } label: {
                    Text(label(item))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(selected ? .white : Color(.label))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(selected ? Color(.label).opacity(0.86) : Color(.secondarySystemGroupedBackground))
                                .background(Capsule().fill(.ultraThinMaterial))
                        )
                        .overlay(Capsule().stroke(Color.white.opacity(selected ? 0 : 0.7), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
    }
}

// MARK: - Simple wrapping layout

private struct PulseFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + lineSpacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: maxWidth == .infinity ? totalWidth : maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.minX + maxWidth {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#if DEBUG
#Preview("Pulse Prefs") {
    PulsePrefsView()
}
#endif
