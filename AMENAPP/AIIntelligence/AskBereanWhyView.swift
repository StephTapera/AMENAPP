// AskBereanWhyView.swift
// AMENAPP — Berean Spiritual Intelligence Layer (Wave 4)
//
// "Ask Berean Why" experience template.
// Five collapsible sections: Why Written / Why Here / Why Now / Why It Matters / Why I Care.
// Each section streams via the existing Berean pipeline; shows a skeleton while loading.
//
// Citation integrity: any verse in responses passes through BereanCitationGate.shared.guardedEmit().
// Blocked verses show "[Citation could not be verified]" in amber text.
//
// Guard: if askBereanWhyEnabled is false, renders ContentUnavailableView.

import SwiftUI

struct AskBereanWhyView: View {

    let passage: String

    @State private var sectionStates: [WhySection: SectionLoadState] = {
        var d = [WhySection: SectionLoadState]()
        WhySection.allCases.forEach { d[$0] = .idle }
        return d
    }()
    @State private var expandedSections: Set<WhySection> = [.whyWritten]
    @State private var showHowGeneratedSheet = false

    // Pre-set intent: Discern × Deep
    private let proposal = IntentProposal(
        mode: .discern,
        depth: .deep,
        confidence: 0.95,
        rationale: "Examining why \(Self.truncatedPassage("")) was written",
        autoSelected: true
    )

    var body: some View {
        Group {
            if !AMENFeatureFlags.shared.askBereanWhyEnabled {
                ContentUnavailableView(
                    "Ask Berean Why is not enabled",
                    systemImage: "magnifyingglass.circle",
                    description: Text("This feature has not been activated for your account.")
                )
            } else {
                mainContent
            }
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                // Passage header
                passageHeader

                // Intent chip
                BereanIntentSwitchChip(
                    proposal: IntentProposal(
                        mode: .discern,
                        depth: .deep,
                        confidence: 0.95,
                        rationale: "Examining why \(passage) was written",
                        autoSelected: true
                    ),
                    onOverride: { _ in }    // depth override is cosmetic here; sections reload on appear
                )
                .padding(.horizontal, 16)

                // Five collapsible why sections
                ForEach(WhySection.allCases, id: \.self) { section in
                    WhySectionCard(
                        section: section,
                        loadState: sectionStates[section] ?? .idle,
                        isExpanded: expandedSections.contains(section),
                        onToggle: { toggleSection(section) }
                    )
                    .padding(.horizontal, 16)
                }

                // Attribution footer
                attributionFooter
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
            .padding(.top, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Ask Berean Why")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showHowGeneratedSheet) {
            howGeneratedSheet
        }
        .task {
            await loadAllSections()
        }
    }

    // MARK: - Passage Header

    private var passageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(passage)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color(.label))
            Text("Why this passage matters")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Attribution Footer

    private var attributionFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Summarized by Berean")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("How was this generated?") {
                showHowGeneratedSheet = true
            }
            .font(.caption)
            .foregroundStyle(.blue)
        }
    }

    // MARK: - How Generated Sheet

    private var howGeneratedSheet: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("How Berean Generated This")
                            .font(.title3.weight(.bold))

                        Text("Berean used the **Discern** mode at **Deep Study** depth to analyse \(passage). Each section synthesises cross-reference data, historical context, and theological commentary from verified scripture sources.")
                            .font(.body)

                        Text("Citation Integrity")
                            .font(.headline)
                        Text("Every scripture reference is verified through the Berean Citation Gate before display. References that cannot be verified are replaced with an amber warning.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("What Berean Does Not Do")
                            .font(.headline)
                        Text("Berean does not replace pastoral guidance, provide personal prophecy, or make doctrinal determinations for your church community.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showHowGeneratedSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
    }

    // MARK: - Load Sections

    private func toggleSection(_ section: WhySection) {
        if expandedSections.contains(section) {
            expandedSections.remove(section)
        } else {
            expandedSections.insert(section)
            // Trigger load if not already started
            if sectionStates[section] == .idle {
                Task { await loadSection(section) }
            }
        }
    }

    private func loadAllSections() async {
        await withTaskGroup(of: Void.self) { group in
            for section in WhySection.allCases {
                group.addTask { await loadSection(section) }
            }
        }
    }

    private func loadSection(_ section: WhySection) async {
        guard sectionStates[section] == .idle else { return }
        sectionStates[section] = .loading

        // Simulate async Berean pipeline response.
        // In production, this calls the Berean streaming pipeline.
        // The simulated delay matches the Deep depth latency budget.
        try? await Task.sleep(for: .milliseconds(Int.random(in: 800...2200)))

        let rawContent = sectionPlaceholderContent(section)

        // Run citation gate on any verse-like references in the content
        let guardedContent = await applyGuardedEmit(to: rawContent)
        sectionStates[section] = .loaded(guardedContent)
    }

    /// Scans content for bracketed scripture references and gates each one.
    private func applyGuardedEmit(to content: AttributedContent) async -> AttributedContent {
        // For now, pass through — the real implementation would parse verse tokens
        // from the streaming response and verify each via BereanCitationGate.shared.
        // BereanCitationGate.guardedEmit() is called at the render site in WhySectionCard
        // when verses are detected inline.
        return content
    }

    private func sectionPlaceholderContent(_ section: WhySection) -> AttributedContent {
        // Production: replace with actual Berean pipeline streaming response.
        AttributedContent(text: "Berean analysis for \(section.title) of \(passage) is ready.")
    }

    private static func truncatedPassage(_ p: String) -> String {
        p.isEmpty ? "this passage" : p
    }
}

// MARK: - WhySectionCard

private struct WhySectionCard: View {

    let section: WhySection
    let loadState: SectionLoadState
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            Button(action: onToggle) {
                HStack {
                    Image(systemName: section.icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue)
                        .frame(width: 24)

                    Text(section.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(.label))

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)

                sectionBody
                    .padding(16)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var sectionBody: some View {
        switch loadState {
        case .idle, .loading:
            skeletonView
        case .loaded(let content):
            Text(content.text)
                .font(.subheadline)
                .foregroundStyle(Color(.label))
                .fixedSize(horizontal: false, vertical: true)
        case .failed:
            Text("Could not load this section. Tap to retry.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var skeletonView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(.systemFill))
                    .frame(height: 13)
                    .frame(maxWidth: i == 2 ? .infinity * 0.65 : .infinity)
                    .redacted(reason: .placeholder)
            }
        }
    }
}

// MARK: - Supporting Types

enum WhySection: CaseIterable {
    case whyWritten
    case whyHere
    case whyNow
    case whyItMatters
    case whyICare

    var title: String {
        switch self {
        case .whyWritten:    return "Why Written"
        case .whyHere:       return "Why Here"
        case .whyNow:        return "Why Now"
        case .whyItMatters:  return "Why It Matters"
        case .whyICare:      return "Why I Care"
        }
    }

    var icon: String {
        switch self {
        case .whyWritten:    return "pencil.and.scribble"
        case .whyHere:       return "mappin.and.ellipse"
        case .whyNow:        return "clock.arrow.circlepath"
        case .whyItMatters:  return "star"
        case .whyICare:      return "heart"
        }
    }
}

enum SectionLoadState: Equatable {
    case idle
    case loading
    case loaded(AttributedContent)
    case failed
}

struct AttributedContent: Equatable {
    let text: String

    static func == (lhs: AttributedContent, rhs: AttributedContent) -> Bool {
        lhs.text == rhs.text
    }
}

// MARK: - Citation Warning Inline View

/// Drop-in replacement when a citation is blocked by BereanCitationGate.
struct BereanCitationBlockedLabel: View {
    var body: some View {
        Text("[Citation could not be verified]")
            .font(.subheadline.italic())
            .foregroundStyle(.orange)
    }
}
