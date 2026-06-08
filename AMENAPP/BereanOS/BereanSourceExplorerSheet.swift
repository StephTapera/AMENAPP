// BereanSourceExplorerSheet.swift
// AMENAPP
//
// Bottom sheet that explores the sources backing a Berean AI answer.
// Tabs: Sources (all) | Scripture (filtered).
// Conflict section shown when detectConflicts returns non-empty pairs.

import SwiftUI

struct BereanSourceExplorerSheet: View {

    let sources: [BereanSourceEntry]
    let answerExcerpt: String

    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: SourceTab = .sources

    private let service = BereanSourceExplorerService.shared

    // MARK: - Computed

    private var conflictPairs: [(BereanSourceEntry, BereanSourceEntry)] {
        service.detectConflicts(sources)
    }

    private var scriptureSources: [BereanSourceEntry] {
        sources.filter { $0.sourceType == .scripture }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerStrip
                tabPicker
                Divider()
                tabContent
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.systemScaled(15, weight: .semibold))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
    }

    // MARK: - Header strip (Liquid Glass material)

    private var headerStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Answer excerpt
            Text(answerExcerpt)
                .font(.systemScaled(14, weight: .regular))
                .italic()
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // Confidence badge summary
            HStack(spacing: 8) {
                confidenceBadge(
                    icon: "doc.text.magnifyingglass",
                    text: "\(sources.count) source\(sources.count == 1 ? "" : "s")"
                )
                if !conflictPairs.isEmpty {
                    confidenceBadge(
                        icon: "exclamationmark.triangle.fill",
                        text: "\(conflictPairs.count) conflict\(conflictPairs.count == 1 ? "" : "s") detected",
                        color: .red
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }

    // MARK: - Tab picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(SourceTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text(tab.title)
                            .font(.systemScaled(14, weight: selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                        Rectangle()
                            .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .sources:
            sourcesTabView
        case .scripture:
            scriptureTabView
        }
    }

    // Sources tab — all sources + conflict section
    private var sourcesTabView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if sources.isEmpty {
                    emptyState(icon: "doc.text.magnifyingglass", message: "No sources found for this result.")
                } else {
                    ForEach(sources) { source in
                        BereanSourceRowView(source: source)
                            .padding(.horizontal, 16)
                        Divider().padding(.leading, 64)
                    }
                }

                // Conflict section
                if !conflictPairs.isEmpty {
                    conflictSection
                }
            }
            .padding(.bottom, 32)
        }
    }

    // Scripture tab — only .scripture type sources
    private var scriptureTabView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if scriptureSources.isEmpty {
                    emptyState(icon: "book.closed.fill", message: "No scripture references found.")
                } else {
                    ForEach(scriptureSources) { source in
                        BereanSourceRowView(source: source)
                            .padding(.horizontal, 16)
                        Divider().padding(.leading, 64)
                    }
                }
            }
            .padding(.bottom, 32)
        }
    }

    // MARK: - Conflict section

    private var conflictSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Conflicting Sources", systemImage: "exclamationmark.triangle.fill")
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(.red)
                .padding(.top, 16)
                .padding(.horizontal, 16)

            ForEach(Array(conflictPairs.enumerated()), id: \.offset) { _, pair in
                conflictPairCard(a: pair.0, b: pair.1)
            }
        }
        .padding(.bottom, 8)
    }

    private func conflictPairCard(a: BereanSourceEntry, b: BereanSourceEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("These two sources present conflicting information:")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 8) {
                conflictSourceLabel(a)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption)
                    .foregroundStyle(.red)
                conflictSourceLabel(b)
            }
        }
        .padding(12)
        .background(Color.red.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
    }

    private func conflictSourceLabel(_ source: BereanSourceEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(source.sourceType.displayName, systemImage: source.sourceType.systemIcon)
                .font(.systemScaled(10, weight: .semibold))
                .foregroundStyle(.red)
            Text(source.title)
                .font(.systemScaled(12, weight: .regular))
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private func confidenceBadge(icon: String, text: String, color: Color = .secondary) -> some View {
        Label(text, systemImage: icon)
            .font(.systemScaled(11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.systemScaled(32))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
        .padding(.horizontal, 32)
    }
}

// MARK: - SourceTab

private enum SourceTab: CaseIterable {
    case sources, scripture

    var title: String {
        switch self {
        case .sources: return "Sources"
        case .scripture: return "Scripture"
        }
    }
}

// MARK: - Preview

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        BereanSourceExplorerSheet(
            sources: [
                BereanSourceEntry(
                    id: "1",
                    url: "https://example.com",
                    title: "The Historical Jesus",
                    author: "N.T. Wright",
                    publishedAt: nil,
                    sourceType: .peerReviewed,
                    qualityScore: 0.91,
                    excerpt: "The evidence for Jesus' historical existence is overwhelming.",
                    conflictsWithSourceIds: ["2"],
                    verifiedAt: Date()
                ),
                BereanSourceEntry(
                    id: "2",
                    url: nil,
                    title: "Community Note: Skeptical perspective",
                    author: nil,
                    publishedAt: nil,
                    sourceType: .communityNote,
                    qualityScore: 0.35,
                    excerpt: "Some historians dispute the primary sources.",
                    conflictsWithSourceIds: ["1"],
                    verifiedAt: nil
                ),
                BereanSourceEntry(
                    id: "3",
                    url: nil,
                    title: "John 1:1",
                    author: nil,
                    publishedAt: nil,
                    sourceType: .scripture,
                    qualityScore: 1.0,
                    excerpt: "In the beginning was the Word, and the Word was with God.",
                    conflictsWithSourceIds: [],
                    verifiedAt: nil
                ),
            ],
            answerExcerpt: "Jesus of Nazareth is one of the most documented figures in ancient history, attested by multiple independent sources."
        )
    }
}
