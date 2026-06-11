// OperatingManualView.swift
// AMEN Universal Migration & Context System — Wave 5 (manual-projection)
//
// The Personal Operating Manual is a PROJECTION over ContextStore facets — never
// a separate store and never a denormalized copy. It reads the owner's live facets
// from ContextStoreService.shared.facets and COMPUTES, in-view, a shareable
// "how to work with me" summary across communication style, working style,
// learning style, strengths, growth areas, and priorities.
//
// It carries its OWN share-visibility control. That control is a presentation
// filter only: it changes which sections are included when the owner copies the
// manual to share it. It never writes facets, never changes a facet's stored
// visibility, and never grants any data — sharing is a COPY action (UIPasteboard).
//
// Gated on contextSystemEnabled && contextExportEnabled. Nothing user-visible
// otherwise. No spiritual ranking anywhere in this projection.

import SwiftUI
import UIKit

struct OperatingManualView: View {
    @StateObject private var flags = AMENFeatureFlags.shared
    @StateObject private var store = ContextStoreService.shared

    /// The manual's OWN share-visibility floor. Sections whose facets are all below
    /// this visibility are excluded from a copy/share. This is a projection filter —
    /// it does NOT mutate any facet's stored visibility.
    @State private var shareFloor: Visibility = .friends
    @State private var copiedConfirmation = false

    var body: some View {
        Group {
            if flags.contextSystemEnabled && flags.contextExportEnabled {
                content
            } else {
                ContextUnavailableNotice()
            }
        }
        .navigationTitle("Operating Manual")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                intro
                shareControl

                let sections = computedSections
                if sections.isEmpty {
                    emptyState
                } else {
                    ForEach(sections) { section in
                        OperatingManualSectionCard(
                            section: section,
                            includedInShare: section.minVisibility.rank >= shareFloor.rank
                        )
                    }
                }

                shareButton(sections: sections)
                footnote
            }
            .padding(20)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .task { await loadIfNeeded() }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HOW TO WORK WITH ME")
                .font(.caption2.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Text("A short, shareable summary computed from your Passport — your communication style, how you work and learn, your strengths, where you're growing, and what you're focused on now.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("This is a live projection of your facets. It is never stored separately, and nothing here is ranked.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var shareControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Share visibility")
                .font(.subheadline.weight(.semibold))
            Text("Choose how much to include when you copy this manual. Only sections at or above this level are copied.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ManualShareVisibilityControl(selection: $shareFloor)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(PassportCardSurface(reduceTransparency: false))
    }

    private func shareButton(sections: [OperatingManualSection]) -> some View {
        let included = sections.filter { $0.minVisibility.rank >= shareFloor.rank }
        return VStack(spacing: 8) {
            Button {
                copyManual(included)
            } label: {
                Label(copiedConfirmation ? "Copied to clipboard" : "Copy manual to share",
                      systemImage: copiedConfirmation ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(included.isEmpty)
            .accessibilityLabel(included.isEmpty
                ? "Nothing to copy at this visibility level"
                : "Copy manual to clipboard, \(included.count) sections")

            if included.isEmpty {
                Text("No sections meet the current share level. Lower the level or add more to your Passport.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 4)
    }

    private var footnote: some View {
        Text("Copying creates a snapshot of text you can paste anywhere. It does not give anyone access to your Passport, and it never changes who can see your facets.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text("Not enough yet for a manual.")
                .font(.headline)
            Text("Add a few things about how you communicate, work, and learn to generate your Operating Manual.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Loading

    private func loadIfNeeded() async {
        guard store.facets.isEmpty, !store.isLoading else { return }
        try? await store.loadFacets()
    }

    // MARK: - Projection (computed in-view; NO second store)

    /// The categories the Operating Manual projects over. Strictly Tier-C, server-
    /// readable categories — relationships/family/health (Tier P) are NEVER part of
    /// a shareable operating manual.
    private var computedSections: [OperatingManualSection] {
        OperatingManualProjection.sections(from: store.facets)
    }

    // MARK: - Copy (share == copy action, never a data grant)

    private func copyManual(_ sections: [OperatingManualSection]) {
        guard !sections.isEmpty else { return }
        UIPasteboard.general.string = OperatingManualProjection.plainText(sections)
        withAnimation(Motion.adaptive(Motion.springPress)) { copiedConfirmation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(Motion.adaptive(Motion.springPress)) { copiedConfirmation = false }
        }
    }
}

// MARK: - Projection model + computation (pure functions over facets)

/// One computed section of the Operating Manual. Derived live from facets; never
/// stored. `minVisibility` is the MOST-private visibility among the facets that
/// fed the section, so the share floor can include/exclude it conservatively.
struct OperatingManualSection: Identifiable {
    let id: String           // stable section key
    let title: String
    let systemImage: String
    let lines: [String]
    let minVisibility: Visibility
}

/// Pure projection logic. No persistence, no networking, no ranking.
enum OperatingManualProjection {

    /// Map each Operating-Manual section to the facet categories it draws from.
    /// Only Tier-C categories appear — a shareable manual never includes Tier-P
    /// (relationships / family / health) facets.
    private static let layout: [(id: String, title: String, image: String, categories: [FacetCategory])] = [
        ("communication", "How I communicate", "bubble.left.and.bubble.right", [.communication]),
        ("working",       "How I work",        "briefcase",                    [.work, .current_focus]),
        ("learning",      "How I learn",       "book",                         [.learning]),
        ("strengths",     "My strengths",      "star",                         [.skills]),
        ("growth",        "Where I'm growing", "leaf",                         [.values]),
        ("priorities",    "What I'm focused on", "target",                     [.goals]),
    ]

    static func sections(from facets: [ContextFacet]) -> [OperatingManualSection] {
        layout.compactMap { entry in
            let relevant = facets.filter { entry.categories.contains($0.category) }
            guard !relevant.isEmpty else { return nil }

            let lines = relevant.map { facet -> String in
                let summary = facet.value.displaySummary.trimmingCharacters(in: .whitespacesAndNewlines)
                return summary.isEmpty ? facet.label : "\(facet.label): \(summary)"
            }
            guard !lines.isEmpty else { return nil }

            // The section's share-visibility floor is the most private facet in it.
            let minVis = relevant
                .map(\.visibility)
                .min(by: { $0.rank < $1.rank }) ?? .privateVisibility

            return OperatingManualSection(
                id: entry.id,
                title: entry.title,
                systemImage: entry.image,
                lines: lines,
                minVisibility: minVis
            )
        }
    }

    /// Plain-text rendering for the copy/share action.
    static func plainText(_ sections: [OperatingManualSection]) -> String {
        var out = "My Operating Manual\n"
        out += "(How to work with me — shared by me, from AMEN)\n"
        for section in sections {
            out += "\n\(section.title)\n"
            for line in section.lines { out += "• \(line)\n" }
        }
        return out
    }
}

// MARK: - Visibility ranking helper (presentation only; not stored)

extension Visibility {
    /// A presentation-only ordering from most private (0) to most public (4).
    /// Used solely to compare against the manual's share floor. Never persisted.
    var rank: Int {
        switch self {
        case .privateVisibility: return 0
        case .friends:           return 1
        case .groups:            return 2
        case .church:            return 3
        case .publicVisibility:  return 4
        }
    }
}

// MARK: - Section card (single-layer glass; no glass-on-glass)

struct OperatingManualSectionCard: View {
    let section: OperatingManualSection
    let includedInShare: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: section.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(section.title).font(.headline)
                Spacer()
                if includedInShare {
                    Label("In share", systemImage: "checkmark.circle")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.green)
                        .accessibilityLabel("Included when you copy")
                } else {
                    Label("Excluded", systemImage: "minus.circle")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("Excluded at the current share level")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        Text(line)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(includedInShare ? 1 : 0.55)
        .modifier(PassportCardSurface(reduceTransparency: reduceTransparency))
    }
}

// MARK: - Share visibility control (segmented; presentation filter only)

struct ManualShareVisibilityControl: View {
    @Binding var selection: Visibility

    private let options: [Visibility] = [.friends, .groups, .church, .publicVisibility]

    var body: some View {
        Picker("Share visibility", selection: $selection) {
            ForEach(options, id: \.self) { vis in
                Text(label(vis)).tag(vis)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityHint("Filters which sections are included when you copy the manual.")
    }

    private func label(_ v: Visibility) -> String {
        switch v {
        case .privateVisibility: return "Private"
        case .friends:           return "Friends"
        case .groups:            return "Groups"
        case .church:            return "Church"
        case .publicVisibility:  return "Public"
        }
    }
}
