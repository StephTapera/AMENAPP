// CommunityDiscoveryFeedView.swift
// AMENAPP — DiscoveryOS
// Discovery feed with hero cards, curated sections, and dynamic hubs.

import SwiftUI

struct CommunityDiscoveryFeedView: View {
    @State private var items: [DiscoveryItem] = DiscoveryItem.previews
    @State private var searchText = ""
    @State private var selectedFilter: DiscoveryFilter = .all
    @State private var seeAllTitle: String = ""
    @State private var seeAllItems: [DiscoveryItem] = []
    @State private var showSeeAll = false

    enum DiscoveryFilter: String, CaseIterable {
        case all, spaces, mentors, churches, studies, events
        var label: String { rawValue.capitalized }
    }

    private var filtered: [DiscoveryItem] {
        let byType: [DiscoveryItem] = {
            guard selectedFilter != .all else { return items }
            let target: DiscoveryItem.DiscoveryItemType? = {
                switch selectedFilter {
                case .spaces:   return .space
                case .mentors:  return .mentor
                case .churches: return .church
                case .studies:  return .study
                case .events:   return .event
                default:        return nil
                }
            }()
            return items.filter { $0.type == target }
        }()

        if searchText.isEmpty { return byType }
        return byType.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.subtitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Filter pills
                filterRow

                // Featured hero
                if let featured = filtered.first {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader(title: "Featured", subtitle: "Handpicked for you", items: filtered)
                        DiscoveryHeroCard(item: featured, onJoin: { _ in }, onTap: { _ in })
                            .padding(.horizontal, 16)
                    }
                }

                // Spaces section
                let spaces = filtered.filter { $0.type == .space }
                if !spaces.isEmpty {
                    horizontalSection(title: "Active Spaces", items: spaces)
                }

                // Studies section
                let studies = filtered.filter { $0.type == .study }
                if !studies.isEmpty {
                    horizontalSection(title: "Bible Studies", items: studies)
                }

                // Mentors section
                let mentors = filtered.filter { $0.type == .mentor }
                if !mentors.isEmpty {
                    horizontalSection(title: "Available Mentors", items: mentors)
                }

                // All
                if !filtered.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader(title: "All Results", subtitle: "\(filtered.count) found", items: filtered)
                        LazyVStack(spacing: 12) {
                            ForEach(filtered) { item in
                                DiscoveryHeroCard(item: item, onJoin: { _ in }, onTap: { _ in })
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .navigationTitle("Discover")
        .searchable(text: $searchText, prompt: "Spaces, studies, mentors…")
        .sheet(isPresented: $showSeeAll) {
            DiscoverySeeAllSheet(title: seeAllTitle, items: seeAllItems)
        }
    }

    // MARK: - Sub-views

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DiscoveryFilter.allCases, id: \.self) { filter in
                    Button {
                        withAnimation(.spring(response: 0.28)) { selectedFilter = filter }
                    } label: {
                        Text(filter.label)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .foregroundStyle(selectedFilter == filter ? .white : .primary)
                            .background(
                                selectedFilter == filter ? Color.accentColor : Color(.secondarySystemBackground),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(filter.label)
                    .accessibilityAddTraits(selectedFilter == filter ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func sectionHeader(title: String, subtitle: String, items: [DiscoveryItem] = []) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("See All") {
                seeAllTitle = title
                seeAllItems = items.isEmpty ? filtered : items
                showSeeAll = true
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func horizontalSection(title: String, items: [DiscoveryItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: title, subtitle: "\(items.count) available", items: items)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        DiscoveryHeroCard(item: item, onJoin: { _ in }, onTap: { _ in })
                            .frame(width: 280)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - See All Sheet

private struct DiscoverySeeAllSheet: View {
    let title: String
    let items: [DiscoveryItem]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CommunityDiscoveryFeedView()
    }
}
