// BereanMemoryBrowserView.swift
// AMENAPP
// Browse, search, and delete saved Berean AI insights (memory entries).

import SwiftUI

struct BereanMemoryBrowserView: View {
    @ObservedObject private var service = BereanMemoryService.shared
    @State private var searchText = ""
    @State private var showDeleteConfirm: BereanInsight? = nil

    private var filtered: [BereanInsight] {
        guard !searchText.isEmpty else { return service.insights }
        let q = searchText.lowercased()
        return service.insights.filter {
            $0.text.lowercased().contains(q)
            || $0.linkedVerses.joined(separator: " ").lowercased().contains(q)
            || $0.tags.joined(separator: " ").lowercased().contains(q)
        }
    }

    var body: some View {
        Group {
            if service.isLoading && service.insights.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Saved Insights" : "No Results",
                    systemImage: "brain",
                    description: Text(searchText.isEmpty
                        ? "Long-press any Berean response and tap \"Save to Memory\" to save insights here."
                        : "Try a different search term.")
                )
            } else {
                List {
                    ForEach(filtered) { insight in
                        BereanInsightRow(insight: insight) {
                            showDeleteConfirm = insight
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Berean Memory")
        .searchable(text: $searchText, prompt: "Search insights, verses, tags")
        .task { service.startObserving() }
        .onDisappear { service.stopObserving() }
        .confirmationDialog(
            "Delete this insight?",
            isPresented: Binding(
                get: { showDeleteConfirm != nil },
                set: { if !$0 { showDeleteConfirm = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let insight = showDeleteConfirm {
                    Task { try? await service.delete(entryId: insight.id) }
                }
                showDeleteConfirm = nil
            }
            Button("Cancel", role: .cancel) { showDeleteConfirm = nil }
        }
    }
}

// MARK: - Row

private struct BereanInsightRow: View {
    let insight: BereanInsight
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(insight.text)
                .font(.body)
                .lineLimit(3)

            HStack(spacing: 8) {
                if !insight.linkedVerses.isEmpty {
                    Label(insight.linkedVerses.first ?? "", systemImage: "book")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(insight.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if !insight.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(insight.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.accentColor.opacity(0.10)))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
