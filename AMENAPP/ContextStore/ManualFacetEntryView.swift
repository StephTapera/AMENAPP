// ManualFacetEntryView.swift
// AMEN Universal Migration & Context System — Wave 1 (passport-ui)
//
// Chip-based pickers (interests / values / communities), free-text (goals /
// current_focus), and a communication-style selector. Each editable facet has
// its own visibility control, defaulting to .privateVisibility. On save we build
// real ContextFacet values via StructuredFacetValue and the canonical tier table.
//
// Persistence is another agent's responsibility (ContextStoreService). This view
// keeps ephemeral @State so it compiles standalone; the save path is marked
// TODO(store).

import SwiftUI
import FirebaseAuth

struct ManualFacetEntryView: View {
    @StateObject private var flags = AMENFeatureFlags.shared
    @Environment(\.dismiss) private var dismiss

    // Chip selections
    @State private var interests: Set<String> = []
    @State private var values: Set<String> = []
    @State private var communities: Set<String> = []

    // Free text
    @State private var goalsText: String = ""
    @State private var currentFocusText: String = ""

    // Communication style
    @State private var preferredTone: String? = nil
    @State private var conversationStyles: Set<String> = []

    // Per-facet visibility (default private). Keyed by FacetCategory.
    @State private var visibility: [FacetCategory: Visibility] = [
        .interests: .privateVisibility,
        .values: .privateVisibility,
        .communities: .privateVisibility,
        .goals: .privateVisibility,
        .current_focus: .privateVisibility,
        .communication: .privateVisibility
    ]

    @State private var didSave = false

    private let interestOptions  = ["Theology", "Music", "Reading", "Fitness", "Cooking", "Coding", "Art", "Outdoors"]
    private let valueOptions      = ["Honesty", "Service", "Family", "Patience", "Generosity", "Humility"]
    private let communityOptions  = ["Local church", "Small group", "Volunteers", "Students", "Parents", "Creators"]
    private let toneOptions        = ["Direct", "Warm", "Reflective", "Playful"]
    private let conversationOptions = ["Async", "Long-form", "Voice", "In person"]

    var body: some View {
        Group {
            if flags.contextSystemEnabled && flags.contextManualEntryEnabled {
                content
            } else {
                ContextUnavailableNotice()
            }
        }
        .navigationTitle("About you")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Pick what fits. Skip anything. Each item has its own visibility — the default is private.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                chipSection(
                    title: "Interests",
                    options: interestOptions,
                    selection: $interests,
                    category: .interests
                )
                chipSection(
                    title: "Values",
                    options: valueOptions,
                    selection: $values,
                    category: .values
                )
                chipSection(
                    title: "Communities",
                    options: communityOptions,
                    selection: $communities,
                    category: .communities
                )

                freeTextSection(
                    title: "Goals",
                    placeholder: "What are you working toward?",
                    text: $goalsText,
                    category: .goals
                )
                // Wave 4: turn the entered goal into a real Commitment Object (flag-gated,
                // Tier-C only). Reuses the Action Intelligence creation path via CommitmentBridge.
                if let goalFacet = pendingGoalsFacet {
                    ContextMakeCommitmentButton(facet: goalFacet)
                }
                freeTextSection(
                    title: "Current focus",
                    placeholder: "What's on your mind these days?",
                    text: $currentFocusText,
                    category: .current_focus
                )

                communicationSection

                AmenLiquidGlassPillButton(
                    title: didSave ? "Saved" : "Save to my Passport",
                    systemImage: didSave ? "checkmark" : "tray.and.arrow.down",
                    isLoading: false,
                    isDisabled: !hasAnything
                ) { save() }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
            .padding(20)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    // MARK: Sections

    private func chipSection(
        title: String,
        options: [String],
        selection: Binding<Set<String>>,
        category: FacetCategory
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            FacetChipFlow(options: options, selection: selection)
            VisibilityControl(
                visibility: Binding(
                    get: { visibility[category] ?? .privateVisibility },
                    set: { visibility[category] = $0 }
                )
            )
        }
    }

    private func freeTextSection(
        title: String,
        placeholder: String,
        text: Binding<String>,
        category: FacetCategory
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            TextEditor(text: text)
                .frame(minHeight: 72)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: AmenGlassMetrics.cornerRadiusSmall, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text(placeholder)
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel(title)
            VisibilityControl(
                visibility: Binding(
                    get: { visibility[category] ?? .privateVisibility },
                    set: { visibility[category] = $0 }
                )
            )
        }
    }

    private var communicationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Communication style").font(.headline)

            Text("Preferred tone")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            FacetSingleSelect(options: toneOptions, selection: $preferredTone)

            Text("How you like to converse")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            FacetChipFlow(options: conversationOptions, selection: $conversationStyles)

            VisibilityControl(
                visibility: Binding(
                    get: { visibility[.communication] ?? .privateVisibility },
                    set: { visibility[.communication] = $0 }
                )
            )
        }
    }

    // MARK: Save

    /// The Tier-C `.goals` facet implied by the current goals text, or nil if empty.
    /// Used to offer the "make a commitment" affordance before the full Passport save.
    private var pendingGoalsFacet: ContextFacet? {
        let goals = goalsText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goals.isEmpty else { return nil }
        let uid = Auth.auth().currentUser?.uid ?? ""
        let now = Date()
        let key = "goals.manual"
        return ContextFacet(
            id: UUID(),
            userId: uid,
            category: .goals,
            key: key,
            label: "Goals",
            value: .text(goals),
            visibility: visibility[.goals] ?? .privateVisibility,
            tier: ContextTierTable.tier(for: .goals, key: key),
            provenance: manualProvenance(at: now),
            createdAt: now,
            updatedAt: now,
            schemaVersion: 1
        )
    }

    private var hasAnything: Bool {
        !interests.isEmpty || !values.isEmpty || !communities.isEmpty
        || !goalsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !currentFocusText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || preferredTone != nil || !conversationStyles.isEmpty
    }

    private func save() {
        let facets = buildFacets()
        guard !facets.isEmpty else { return }

        // Persist through ContextStoreService: approval-before-write, tier
        // enforcement, and Aegis C59 receipt verification all happen in saveFacet.
        Task {
            for facet in facets {
                do {
                    try await ContextStoreService.shared.saveFacet(facet)
                } catch {
                    // A single facet failing a guard must not silently drop the rest;
                    // surface it but keep going (per-facet independence).
                    print("[ManualFacetEntry] saveFacet failed for \(facet.key): \(error)")
                }
            }
            await MainActor.run {
                withAnimation(Motion.adaptive(Motion.popToggle)) { didSave = true }
            }
        }
    }

    /// Builds canonical ContextFacet values. Tier is always derived from the table.
    private func buildFacets() -> [ContextFacet] {
        let uid = Auth.auth().currentUser?.uid ?? ""
        let now = Date()
        var out: [ContextFacet] = []

        func make(
            category: FacetCategory,
            key: String,
            label: String,
            value: StructuredFacetValue
        ) -> ContextFacet {
            ContextFacet(
                id: UUID(),
                userId: uid,
                category: category,
                key: key,
                label: label,
                value: value,
                visibility: visibility[category] ?? .privateVisibility,
                tier: ContextTierTable.tier(for: category, key: key),
                provenance: manualProvenance(at: now),
                createdAt: now,
                updatedAt: now,
                schemaVersion: 1
            )
        }

        if !interests.isEmpty {
            out.append(make(category: .interests, key: "interests.manual",
                            label: "Interests", value: .list(interests.sorted())))
        }
        if !values.isEmpty {
            out.append(make(category: .values, key: "values.manual",
                            label: "Values", value: .list(values.sorted())))
        }
        if !communities.isEmpty {
            out.append(make(category: .communities, key: "communities.manual",
                            label: "Communities", value: .list(communities.sorted())))
        }
        let goals = goalsText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !goals.isEmpty {
            out.append(make(category: .goals, key: "goals.manual",
                            label: "Goals", value: .text(goals)))
        }
        let focus = currentFocusText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !focus.isEmpty {
            out.append(make(category: .current_focus, key: "current_focus.manual",
                            label: "Current focus", value: .text(focus)))
        }
        if preferredTone != nil || !conversationStyles.isEmpty {
            let style = CommunicationStyleValue(
                preferredTone: preferredTone,
                conversationStyles: conversationStyles.sorted(),
                frustratingBehaviors: [],
                meaningfulContentTypes: []
            )
            out.append(make(category: .communication, key: "communication.style",
                            label: "Communication style", value: .communicationStyle(style)))
        }
        return out
    }

    private func manualProvenance(at date: Date) -> Provenance {
        // Manual entry is user-authored: approved + no AI extraction.
        // sanitizationPassId is non-empty per Aegis C59 (no LLM path, but the
        // contract forbids persisting an empty receipt id).
        Provenance(
            source: .manual,
            sourceLabel: nil,
            extractedAt: nil,
            confidence: nil,
            userApproved: true,
            userEdited: false,
            sanitizationPassId: "manual-\(UUID().uuidString)"
        )
    }
}

// MARK: - Per-facet visibility control (default private)

struct VisibilityControl: View {
    @Binding var visibility: Visibility

    private let choices: [Visibility] = [.privateVisibility, .friends, .publicVisibility]

    var body: some View {
        HStack(spacing: 8) {
            Text("Who can see this:")
                .font(.caption)
                .foregroundStyle(.tertiary)
            ForEach(choices, id: \.self) { choice in
                Button {
                    withAnimation(Motion.adaptive(Motion.springPress)) { visibility = choice }
                } label: {
                    Text(label(for: choice))
                        .font(.caption.weight(visibility == choice ? .semibold : .regular))
                        .foregroundStyle(visibility == choice ? Color.primary : Color.secondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(
                                visibility == choice
                                ? Color.primary.opacity(0.10)
                                : Color.clear
                            )
                        )
                        .overlay(
                            Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.6)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Visibility \(label(for: choice))")
                .accessibilityAddTraits(visibility == choice ? .isSelected : [])
            }
        }
    }

    private func label(for v: Visibility) -> String {
        switch v {
        case .privateVisibility: return "Private"
        case .friends:           return "Friends"
        case .groups:            return "Groups"
        case .church:            return "Church"
        case .publicVisibility:  return "Public"
        }
    }
}

// MARK: - Chip flow (multi-select)

struct FacetChipFlow: View {
    let options: [String]
    @Binding var selection: Set<String>

    var body: some View {
        FacetFlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(options, id: \.self) { option in
                let isOn = selection.contains(option)
                Button {
                    withAnimation(Motion.adaptive(Motion.springPress)) {
                        if isOn { selection.remove(option) } else { selection.insert(option) }
                    }
                } label: {
                    Text(option)
                        .font(.subheadline.weight(isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? Color.accentColor : Color.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(isOn ? Color.accentColor.opacity(0.16) : Color(.secondarySystemBackground))
                        )
                        .overlay(
                            Capsule().stroke(
                                isOn ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.10),
                                lineWidth: 0.8
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

// MARK: - Single-select segment

struct FacetSingleSelect: View {
    let options: [String]
    @Binding var selection: String?

    var body: some View {
        FacetFlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(options, id: \.self) { option in
                let isOn = selection == option
                Button {
                    withAnimation(Motion.adaptive(Motion.springPress)) {
                        selection = isOn ? nil : option
                    }
                } label: {
                    Text(option)
                        .font(.subheadline.weight(isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? Color.accentColor : Color.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(isOn ? Color.accentColor.opacity(0.16) : Color(.secondarySystemBackground))
                        )
                        .overlay(
                            Capsule().stroke(
                                isOn ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.10),
                                lineWidth: 0.8
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

// MARK: - Lightweight flow layout (wraps chips, no external deps)

struct FacetFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubviews.Element]] = [[]]
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, !rows[rows.count - 1].isEmpty {
                totalHeight += rowHeight + lineSpacing
                rows.append([])
                rowWidth = 0
                rowHeight = 0
            }
            rows[rows.count - 1].append(subview)
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth == .infinity ? rowWidth : maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
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

// MARK: - Shared "unavailable" notice

struct ContextUnavailableNotice: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("This isn't available yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
