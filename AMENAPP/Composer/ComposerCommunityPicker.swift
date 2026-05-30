// ComposerCommunityPicker.swift
// AMENAPP
//
// Community / Topic tagging picker sheet for the AMEN composer.
// Presents a searchable list of Firestore communities + built-in faith topics.
// Agent F — UI-Consolidation-v1

import SwiftUI
import FirebaseFirestore

// MARK: - CommunityPickerItem

struct CommunityPickerItem: Identifiable {
    var id: String
    var name: String
    var memberCount: Int
    var type: CommunityTagType   // .community or .topic
    var iconURL: String?
    var iconName: String?        // SF Symbol name (built-in topics only)
    var isRecent: Bool = false
}

// MARK: - Built-in faith topics

private extension CommunityPickerItem {
    static let builtInTopics: [CommunityPickerItem] = [
        CommunityPickerItem(id: "prayer_topic",       name: "Prayer",          memberCount: 0, type: .topic, iconName: "hands.sparkles.fill"),
        CommunityPickerItem(id: "bible_study",        name: "Bible Study",     memberCount: 0, type: .topic, iconName: "book.fill"),
        CommunityPickerItem(id: "worship",            name: "Worship",         memberCount: 0, type: .topic, iconName: "music.note"),
        CommunityPickerItem(id: "testimony",          name: "Testimonies",     memberCount: 0, type: .topic, iconName: "star.bubble.fill"),
        CommunityPickerItem(id: "marriage",           name: "Marriage",        memberCount: 0, type: .topic, iconName: "heart.fill"),
        CommunityPickerItem(id: "faith_work",         name: "Faith & Work",    memberCount: 0, type: .topic, iconName: "briefcase.fill"),
        CommunityPickerItem(id: "discipleship",       name: "Discipleship",    memberCount: 0, type: .topic, iconName: "figure.walk"),
        CommunityPickerItem(id: "mental_wellness",    name: "Mental Wellness", memberCount: 0, type: .topic, iconName: "brain.head.profile"),
    ]
}

// MARK: - ViewModel

@MainActor
final class ComposerCommunityPickerViewModel: ObservableObject {

    @Published var searchQuery: String = ""
    @Published var recentItems: [CommunityPickerItem] = []
    @Published var communities: [CommunityPickerItem] = []
    @Published var topics: [CommunityPickerItem] = CommunityPickerItem.builtInTopics
    @Published var isLoading: Bool = false

    // Filtered results shown when searchQuery is non-empty
    @Published var filteredResults: [CommunityPickerItem] = []

    private let db = Firestore.firestore()
    private let recentDefaultsKey = "recentCommunities"
    private let maxRecent = 5

    // MARK: Load initial

    func loadInitial() async {
        isLoading = true
        defer { isLoading = false }

        loadRecentsFromDefaults()

        do {
            let snapshot = try await db.collection("communities")
                .limit(to: 20)
                .getDocuments()

            let items: [CommunityPickerItem] = snapshot.documents.compactMap { doc in
                let data = doc.data()
                guard let name = data["name"] as? String else { return nil }
                let memberCount = data["memberCount"] as? Int ?? 0
                return CommunityPickerItem(
                    id: doc.documentID,
                    name: name,
                    memberCount: memberCount,
                    type: .community
                )
            }
            communities = items
        } catch {
            // Silently fail — built-in topics are always available
        }
    }

    // MARK: Search

    func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            filteredResults = []
            return
        }

        let lower = trimmed.lowercased()

        // Local filter first (instant)
        var results: [CommunityPickerItem] = []

        let localCommunities = communities.filter { $0.name.lowercased().contains(lower) }
        let localTopics = CommunityPickerItem.builtInTopics.filter { $0.name.lowercased().contains(lower) }
        results = localCommunities + localTopics

        filteredResults = results

        // Firestore query for queries longer than 3 chars
        guard trimmed.count > 3 else { return }

        do {
            // Prefix range query (Firestore doesn't support LIKE — use range)
            let end = trimmed + "\u{f8ff}"
            let snapshot = try await db.collection("communities")
                .whereField("name", isGreaterThanOrEqualTo: trimmed)
                .whereField("name", isLessThanOrEqualTo: end)
                .limit(to: 10)
                .getDocuments()

            let remoteItems: [CommunityPickerItem] = snapshot.documents.compactMap { doc in
                let data = doc.data()
                guard let name = data["name"] as? String else { return nil }
                // Skip duplicates already in results
                if results.contains(where: { $0.id == doc.documentID }) { return nil }
                let memberCount = data["memberCount"] as? Int ?? 0
                return CommunityPickerItem(
                    id: doc.documentID,
                    name: name,
                    memberCount: memberCount,
                    type: .community
                )
            }

            // Merge: local results first, then remote additions
            filteredResults = results + remoteItems
        } catch {
            // Keep local results on error
        }
    }

    // MARK: Recent items

    func saveRecent(_ item: CommunityPickerItem) {
        var recents = loadRawRecents()
        // Remove duplicate
        recents.removeAll { $0.id == item.id }
        // Prepend
        var updated = item
        updated.isRecent = true
        recents.insert(updated, at: 0)
        // Cap at maxRecent
        if recents.count > maxRecent {
            recents = Array(recents.prefix(maxRecent))
        }
        persistRecents(recents)
        recentItems = recents
    }

    private func loadRecentsFromDefaults() {
        recentItems = loadRawRecents()
    }

    private func loadRawRecents() -> [CommunityPickerItem] {
        guard
            let data = UserDefaults.standard.data(forKey: recentDefaultsKey),
            let decoded = try? JSONDecoder().decode([CommunityPickerItemCodable].self, from: data)
        else { return [] }
        return decoded.map { $0.toItem() }
    }

    private func persistRecents(_ items: [CommunityPickerItem]) {
        let codable = items.map { CommunityPickerItemCodable(from: $0) }
        if let data = try? JSONEncoder().encode(codable) {
            UserDefaults.standard.set(data, forKey: recentDefaultsKey)
        }
    }
}

// MARK: - Codable bridge for UserDefaults persistence

private struct CommunityPickerItemCodable: Codable {
    var id: String
    var name: String
    var memberCount: Int
    var typeRaw: String
    var iconURL: String?
    var iconName: String?

    init(from item: CommunityPickerItem) {
        self.id = item.id
        self.name = item.name
        self.memberCount = item.memberCount
        self.typeRaw = item.type.rawValue
        self.iconURL = item.iconURL
        self.iconName = item.iconName
    }

    func toItem() -> CommunityPickerItem {
        CommunityPickerItem(
            id: id,
            name: name,
            memberCount: memberCount,
            type: CommunityTagType(rawValue: typeRaw) ?? .topic,
            iconURL: iconURL,
            iconName: iconName,
            isRecent: true
        )
    }
}

// MARK: - ComposerCommunityPickerView

struct ComposerCommunityPickerView: View {

    @Binding var draft: ComposerDraft
    @Binding var isPresented: Bool

    @StateObject private var viewModel = ComposerCommunityPickerViewModel()
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                AmenTheme.Colors.backgroundGrouped
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Drag indicator
                    dragIndicator

                    // Header
                    headerTitle

                    // Search bar
                    searchBar
                        .padding(.horizontal, AmenLayout.horizontalInset)
                        .padding(.bottom, 12)

                    // Current tag chip (if any)
                    if draft.taggedCommunity != nil {
                        currentTagChip
                            .padding(.horizontal, AmenLayout.horizontalInset)
                            .padding(.bottom, 8)
                    }

                    // Content
                    if viewModel.searchQuery.isEmpty {
                        emptyQueryContent
                    } else {
                        searchResultsList
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)  // custom indicator above
        .task { await viewModel.loadInitial() }
        .onChange(of: viewModel.searchQuery) { _, newValue in
            Task { await viewModel.search(newValue) }
        }
    }

    // MARK: Subviews

    private var dragIndicator: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(AmenTheme.Colors.textTertiary)
            .frame(width: 36, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private var headerTitle: some View {
        HStack {
            Text("+ Community or topic")
                .font(.headline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Spacer()
            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
                    .frame(width: AmenLayout.minTapTarget, height: AmenLayout.minTapTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, AmenLayout.horizontalInset)
        .padding(.bottom, 12)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .font(.callout)

            TextField("Search communities and topics", text: $viewModel.searchQuery)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .accessibilityLabel("Search communities and topics")

            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .amenGlassInputBar(cornerRadius: AmenTheme.CornerRadius.pill)
    }

    private var currentTagChip: some View {
        HStack(spacing: 6) {
            if let tag = draft.taggedCommunity {
                HStack(spacing: 6) {
                    Image(systemName: tag.type == .community ? "building.columns.fill" : "tag.fill")
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.amenBlue)

                    Text(tag.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)

                    Button {
                        withAnimation(Motion.adaptive(Motion.springRelease)) {
                            draft.taggedCommunity = nil
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(tag.name) tag")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(AmenTheme.Colors.amenBlue.opacity(0.12))
                        .overlay(
                            Capsule()
                                .strokeBorder(AmenTheme.Colors.amenBlue.opacity(0.30), lineWidth: 0.75)
                        )
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Tagged: \(tag.name). Tap X to remove.")
            }

            Spacer()
        }
    }

    // MARK: Empty query content (Recent + Communities + Topics sections)

    private var emptyQueryContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {

                // Recent section
                if !viewModel.recentItems.isEmpty {
                    sectionHeader("Recent")
                    recentChipsRow
                        .padding(.bottom, 8)
                }

                // Communities section
                if viewModel.isLoading {
                    loadingRow
                } else if !viewModel.communities.isEmpty {
                    sectionHeader("Communities")
                    ForEach(viewModel.communities) { item in
                        communityRow(item)
                    }
                }

                // Topics section
                sectionHeader("Topics")
                ForEach(CommunityPickerItem.builtInTopics) { item in
                    communityRow(item)
                }

                Spacer(minLength: 32)
            }
            .padding(.top, 4)
        }
    }

    // MARK: Search results list

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if viewModel.isLoading {
                    loadingRow
                } else if viewModel.filteredResults.isEmpty {
                    emptyResultsView
                } else {
                    ForEach(viewModel.filteredResults) { item in
                        communityRow(item)
                    }
                }
                Spacer(minLength: 32)
            }
            .padding(.top, 4)
        }
    }

    // MARK: Section header

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(AmenTheme.Colors.textTertiary)
            .padding(.horizontal, AmenLayout.horizontalInset)
            .padding(.top, 16)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Recent chips horizontal row

    private var recentChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.recentItems) { item in
                    recentChip(item)
                }
            }
            .padding(.horizontal, AmenLayout.horizontalInset)
            .padding(.vertical, 4)
        }
        .accessibilityLabel("Recent communities and topics")
    }

    private func recentChip(_ item: CommunityPickerItem) -> some View {
        Button {
            selectItem(item)
        } label: {
            HStack(spacing: 5) {
                itemIconView(item, size: 14)
                Text(item.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(AmenTheme.Colors.surfaceChip)
                    .overlay(
                        Capsule()
                            .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.75)
                    )
            )
        }
        .buttonStyle(AmenPressStyle(scale: 0.96))
        .accessibilityLabel("\(item.name), \(item.memberCount) members, \(item.type.rawValue)")
    }

    // MARK: Community / topic row

    private func communityRow(_ item: CommunityPickerItem) -> some View {
        let isSelected = draft.taggedCommunity?.id == item.id

        return Button {
            selectItem(item)
        } label: {
            HStack(spacing: 12) {
                // Icon circle
                itemIconView(item, size: 20)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(iconBackground(for: item))
                    )

                // Name + member count
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .lineLimit(1)

                    if item.type == .community && item.memberCount > 0 {
                        Text(memberCountLabel(item.memberCount))
                            .font(.caption)
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                    } else {
                        Text(item.type == .topic ? "Topic" : "Community")
                            .font(.caption)
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                    }
                }

                Spacer()

                // Checkmark if selected
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(AmenTheme.Colors.amenBlue)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, AmenLayout.horizontalInset)
            .padding(.vertical, 10)
            .background(
                isSelected
                    ? AmenTheme.Colors.amenBlue.opacity(0.06)
                    : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(AmenPressStyle(scale: 0.98))
        .accessibilityLabel("\(item.name), \(item.memberCount) members, \(item.type.rawValue)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .amenSeparatorBottom()
        .animation(Motion.adaptive(Motion.springRelease), value: isSelected)
    }

    // MARK: Loading row

    private var loadingRow: some View {
        HStack {
            ProgressView()
                .tint(AmenTheme.Colors.textSecondary)
            Text("Loading communities…")
                .font(.callout)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityLabel("Loading communities")
    }

    // MARK: Empty results

    private var emptyResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(AmenTheme.Colors.textTertiary)

            Text("No results for "\(viewModel.searchQuery)"")
                .font(.callout)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, AmenLayout.horizontalInset)
        .accessibilityLabel("No results found for \(viewModel.searchQuery)")
    }

    // MARK: Helpers

    @ViewBuilder
    private func itemIconView(_ item: CommunityPickerItem, size: CGFloat) -> some View {
        if let symbolName = item.iconName {
            Image(systemName: symbolName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(iconTint(for: item))
        } else if let urlString = item.iconURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                case .failure, .empty:
                    fallbackIcon(item: item, size: size)
                @unknown default:
                    fallbackIcon(item: item, size: size)
                }
            }
            .frame(width: size + 4, height: size + 4)
        } else {
            fallbackIcon(item: item, size: size)
        }
    }

    private func fallbackIcon(item: CommunityPickerItem, size: CGFloat) -> some View {
        Image(systemName: item.type == .community ? "building.columns.fill" : "tag.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(iconTint(for: item))
    }

    private func iconTint(for item: CommunityPickerItem) -> Color {
        switch item.type {
        case .community: return AmenTheme.Colors.amenPurple
        case .topic:     return AmenTheme.Colors.amenBlue
        }
    }

    private func iconBackground(for item: CommunityPickerItem) -> Color {
        switch item.type {
        case .community: return AmenTheme.Colors.amenPurple.opacity(0.12)
        case .topic:     return AmenTheme.Colors.amenBlue.opacity(0.12)
        }
    }

    private func memberCountLabel(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM members", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fk members", Double(count) / 1_000)
        } else if count == 1 {
            return "1 member"
        } else {
            return "\(count) members"
        }
    }

    // MARK: Select action

    private func selectItem(_ item: CommunityPickerItem) {
        withAnimation(Motion.adaptive(Motion.popToggle)) {
            draft.taggedCommunity = CommunityTag(
                id: item.id,
                name: item.name,
                type: item.type
            )
        }
        viewModel.saveRecent(item)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            isPresented = false
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Community Picker") {
    @Previewable @State var draft = ComposerDraft()
    @Previewable @State var isPresented = true
    Color.gray.opacity(0.2)
        .sheet(isPresented: $isPresented) {
            ComposerCommunityPickerView(draft: $draft, isPresented: $isPresented)
        }
}
#endif
