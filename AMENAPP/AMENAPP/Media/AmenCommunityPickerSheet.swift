import SwiftUI

// MARK: - Community Models

private struct AmenCommunityItem: Identifiable {
    let id: String
    let title: String
    let memberCount: String
    let isRecent: Bool
}

private let sampleCommunities: [AmenCommunityItem] = [
    AmenCommunityItem(id: "design-threads",    title: "Design Threads",      memberCount: "81.7K", isRecent: true),
    AmenCommunityItem(id: "inpublic",          title: "In Public",           memberCount: "12.4K", isRecent: true),
    AmenCommunityItem(id: "tech-threads",      title: "Tech Threads",        memberCount: "94.3K", isRecent: false),
    AmenCommunityItem(id: "design-threads-2",  title: "Design Threads",      memberCount: "81.7K", isRecent: false),
    AmenCommunityItem(id: "marriage-threads",  title: "Marriage & Family",   memberCount: "26.1K", isRecent: false),
    AmenCommunityItem(id: "bible-study",       title: "Bible Study Community", memberCount: "54.2K", isRecent: false),
    AmenCommunityItem(id: "worship-prayer",    title: "Worship & Prayer",    memberCount: "38.9K", isRecent: false),
    AmenCommunityItem(id: "faith-family",      title: "Faith & Family",      memberCount: "22.1K", isRecent: false),
]

// MARK: - AmenCommunityPickerSheet

struct AmenCommunityPickerSheet: View {
    @Binding var selectedCommunityId: String?
    @Binding var selectedTopicIds: [String]
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?

    private var recentItems: [AmenCommunityItem] {
        sampleCommunities.filter { $0.isRecent }
    }

    private var communityItems: [AmenCommunityItem] {
        let all = sampleCommunities.filter { !$0.isRecent }
        guard !debouncedQuery.isEmpty else { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(debouncedQuery) }
    }

    private var filteredRecents: [AmenCommunityItem] {
        guard !debouncedQuery.isEmpty else { return recentItems }
        return recentItems.filter { $0.title.localizedCaseInsensitiveContains(debouncedQuery) }
    }

    var body: some View {
        VStack(spacing: 0) {
            grabberHandle
            searchBar
            Divider()
                .foregroundStyle(AmenTheme.Colors.separatorSubtle)
            communityList
        }
        .background(AmenTheme.Colors.backgroundPrimary)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(24)
    }

    // MARK: Sub-views

    private var grabberHandle: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(AmenTheme.Colors.separator)
            .frame(width: 36, height: 4)
            .padding(.top, 10)
            .padding(.bottom, 14)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .font(.system(size: 15))
            TextField("Search topics", text: $searchText)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .font(.subheadline)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: searchText) { _, newValue in
                    debounceTask?.cancel()
                    debounceTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        guard !Task.isCancelled else { return }
                        debouncedQuery = newValue
                    }
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AmenTheme.Colors.surfaceInput)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var communityList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                let hasAnyResults = !filteredRecents.isEmpty || !communityItems.isEmpty
                if !hasAnyResults {
                    emptyState
                } else {
                    if !filteredRecents.isEmpty {
                        sectionHeader("Recent")
                        ForEach(filteredRecents) { item in
                            AmenCommunityRowView(
                                item: item,
                                isSelected: selectedCommunityId == item.id || selectedTopicIds.contains(item.id),
                                onTap: { handleTap(item) }
                            )
                        }
                    }
                    if !communityItems.isEmpty {
                        sectionHeader("Communities")
                        ForEach(communityItems) { item in
                            AmenCommunityRowView(
                                item: item,
                                isSelected: selectedCommunityId == item.id || selectedTopicIds.contains(item.id),
                                onTap: { handleTap(item) }
                            )
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func sectionHeader(_ label: String) -> some View {
        Text(label)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(AmenTheme.Colors.textPrimary)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.3")
                .font(.system(size: 36))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
            Text("No results")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: Selection Logic

    private func handleTap(_ item: AmenCommunityItem) {
        if item.id == selectedCommunityId {
            selectedCommunityId = nil
        } else if selectedTopicIds.contains(item.id) {
            selectedTopicIds.removeAll { $0 == item.id }
        } else {
            selectedCommunityId = item.id
        }
    }
}

// MARK: - AmenCommunityRowView

private struct AmenCommunityRowView: View {
    let item: AmenCommunityItem
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                arrowIcon
                itemInfo
                Spacer(minLength: 0)
                if isSelected {
                    checkmark
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.97 : 1))
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.75), value: isPressed)
        ._onButtonGesture(pressing: { isPressed = $0 }, perform: {})
    }

    private var arrowIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AmenTheme.Colors.amenBlue.opacity(0.12))
                .frame(width: 36, height: 36)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.amenBlue)
        }
        .accessibilityHidden(true)
    }

    private var itemInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .lineLimit(1)
            Text("\(item.memberCount) members")
                .font(.caption)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
    }

    private var checkmark: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AmenTheme.Colors.amenGold)
            .accessibilityLabel("Selected")
    }
}
