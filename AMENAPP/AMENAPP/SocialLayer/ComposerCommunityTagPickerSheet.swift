// ComposerCommunityTagPickerSheet.swift
// AMENAPP — SocialLayer
//
// INTEGRATION NOTE (Phase 4 — CreatePostView wiring):
//   1. Add `@State private var selectedTag: CommunityTag? = nil` to CreatePostView.
//   2. Add `@State private var showTagPicker = false` to CreatePostView.
//   3. In the composer toolbar, add a button:
//        Button { showTagPicker = true } label: {
//            Label("Tag", systemImage: "tag.fill")
//                .font(.system(size: 15, weight: .medium))
//                .foregroundStyle(selectedTag != nil ? AmenTheme.Colors.amenPurple : AmenTheme.Colors.textSecondary)
//        }
//   4. Sheet attachment:
//        .sheet(isPresented: $showTagPicker) {
//            ComposerCommunityTagPickerSheet(selectedTag: $selectedTag) {
//                showTagPicker = false
//            }
//        }
//   5. Pass `selectedTag` into the draft: `draft.taggedCommunity = selectedTag`
//      (ComposerDraft.taggedCommunity is already declared in ComposerContract.swift)
//   6. Optionally render a dismiss-able tag chip below the text field when `selectedTag != nil`.

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - TagPickerItem (private, sheet-internal)

private struct TagPickerItem: Identifiable, Equatable {
    let id: String
    let name: String
    let isCommunity: Bool      // true → .community, false → .topic

    var communityTag: CommunityTag {
        CommunityTag(id: id, name: name, type: isCommunity ? .community : .topic)
    }

    var icon: String { isCommunity ? "person.3.fill" : "tag.fill" }
}

// MARK: - RecentsStore (UserDefaults JSON persistence)

private enum RecentsStore {
    private static let key = "composerCommunityTagRecents_v1"
    private static let maxCount = 5

    static func load() -> [CommunityTag] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let tags = try? JSONDecoder().decode([CommunityTag].self, from: data)
        else { return [] }
        return tags
    }

    static func save(_ tags: [CommunityTag]) {
        guard let data = try? JSONEncoder().encode(tags) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func push(_ tag: CommunityTag) {
        var current = load().filter { $0.id != tag.id }
        current.insert(tag, at: 0)
        save(Array(current.prefix(maxCount)))
    }
}

// MARK: - ComposerCommunityTagPickerSheet

struct ComposerCommunityTagPickerSheet: View {
    @Binding var selectedTag: CommunityTag?
    var onDone: () -> Void

    // MARK: State
    @State private var searchText: String = ""
    @State private var debouncedQuery: String = ""
    @State private var debounceTask: Task<Void, Never>?

    @State private var searchResults: [TagPickerItem] = []
    @State private var mySpaces: [TagPickerItem] = []
    @State private var recents: [CommunityTag] = []
    @State private var isLoadingSearch = false
    @State private var isLoadingSpaces = false

    // MARK: Static curated topics
    private static let curatedTopics: [TagPickerItem] = [
        TagPickerItem(id: "topic_scripture_study",   name: "Scripture Study",   isCommunity: false),
        TagPickerItem(id: "topic_prayer",            name: "Prayer",            isCommunity: false),
        TagPickerItem(id: "topic_worship",           name: "Worship",           isCommunity: false),
        TagPickerItem(id: "topic_theology",          name: "Theology",          isCommunity: false),
        TagPickerItem(id: "topic_marriage_family",   name: "Marriage & Family", isCommunity: false),
        TagPickerItem(id: "topic_youth",             name: "Youth",             isCommunity: false),
        TagPickerItem(id: "topic_missions",          name: "Missions",          isCommunity: false),
        TagPickerItem(id: "topic_apologetics",       name: "Apologetics",       isCommunity: false),
    ]

    // MARK: Derived
    private var filteredCuratedTopics: [TagPickerItem] {
        guard !debouncedQuery.isEmpty else { return Self.curatedTopics }
        return Self.curatedTopics.filter {
            $0.name.localizedCaseInsensitiveContains(debouncedQuery)
        }
    }

    private var filteredMySpaces: [TagPickerItem] {
        guard !debouncedQuery.isEmpty else { return mySpaces }
        return mySpaces.filter {
            $0.name.localizedCaseInsensitiveContains(debouncedQuery)
        }
    }

    private var isSearchActive: Bool { !debouncedQuery.isEmpty }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            dragHandle
            searchBar
            Divider()
                .foregroundStyle(AmenTheme.Colors.separatorSubtle)
            content
        }
        .background(.ultraThinMaterial)
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
        .presentationCornerRadius(32)
        .presentationDragIndicator(.hidden)
        .onAppear {
            recents = RecentsStore.load()
            fetchMySpaces()
        }
        .onChange(of: debouncedQuery) { _, query in
            if !query.isEmpty {
                fetchSearchResults(query: query)
            } else {
                searchResults = []
            }
        }
    }

    // MARK: - Sub-views

    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(AmenTheme.Colors.separator)
            .frame(width: 36, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .accessibilityHidden(true)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .font(.system(size: 15, weight: .medium))
                .accessibilityHidden(true)
            TextField("Search communities or topics", text: $searchText)
                .font(AMENFont.medium(14))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel("Search communities or topics")
                .onChange(of: searchText) { _, newValue in
                    debounceTask?.cancel()
                    debounceTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        guard !Task.isCancelled else { return }
                        await MainActor.run { debouncedQuery = newValue }
                    }
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    debouncedQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                        .font(.system(size: 15))
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .liquidGlass(opacity: 0.08, blur: 12, shadowOpacity: 0.05, cornerRadius: 16)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if isSearchActive {
                    searchResultsSection
                } else {
                    if !recents.isEmpty {
                        recentsSection
                    }
                    myCommunitiesSection
                    topicsSection
                }
            }
            .padding(.bottom, 32)
        }
    }

    // MARK: Recents

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Recent")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(recents, id: \.id) { tag in
                        recentChip(tag)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    private func recentChip(_ tag: CommunityTag) -> some View {
        let isSelected = selectedTag == tag
        return Button {
            handleSelection(
                TagPickerItem(
                    id: tag.id,
                    name: tag.name,
                    isCommunity: tag.type == .community
                )
            )
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tag.type == .community ? "person.3.fill" : "tag.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : AmenTheme.Colors.amenPurple)
                Text(tag.name)
                    .font(AMENFont.medium(13))
                    .foregroundStyle(isSelected ? .white : AmenTheme.Colors.textPrimary)
                    .lineLimit(1)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? AmenTheme.Colors.amenPurple : AmenTheme.Colors.surfaceChip)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.clear : AmenTheme.Colors.borderSoft,
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(AmenPressStyle(scale: 0.96))
        .accessibilityLabel("\(tag.name), \(tag.type == .community ? "community" : "topic")\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: My Communities

    @ViewBuilder
    private var myCommunitiesSection: some View {
        sectionHeader("My Communities")
        if isLoadingSpaces {
            HStack {
                Spacer()
                ProgressView()
                    .padding(.vertical, 16)
                Spacer()
            }
        } else if filteredMySpaces.isEmpty {
            emptyMyCommunitiesState
        } else {
            ForEach(Array(filteredMySpaces.enumerated()), id: \.element.id) { index, item in
                TagPickerRow(
                    item: item,
                    isSelected: selectedTag?.id == item.id,
                    onTap: { handleSelection(item) }
                )
                .staggeredReveal(index: index, baseDelay: 0.03, maxDelay: 0.15)
            }
        }
    }

    private var emptyMyCommunitiesState: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.3")
                .font(.system(size: 22))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
            Text("Join communities to tag them")
                .font(AMENFont.medium(14))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: Topics

    @ViewBuilder
    private var topicsSection: some View {
        sectionHeader("Topics")
        ForEach(Array(filteredCuratedTopics.enumerated()), id: \.element.id) { index, item in
            TagPickerRow(
                item: item,
                isSelected: selectedTag?.id == item.id,
                onTap: { handleSelection(item) }
            )
        }
        if filteredCuratedTopics.isEmpty {
            Text("No matching topics")
                .font(AMENFont.medium(14))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
        }
    }

    // MARK: Search Results

    @ViewBuilder
    private var searchResultsSection: some View {
        if isLoadingSearch {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.vertical, 24)
        } else if searchResults.isEmpty {
            emptySearchState
        } else {
            sectionHeader("Results")
            ForEach(searchResults) { item in
                TagPickerRow(
                    item: item,
                    isSelected: selectedTag?.id == item.id,
                    onTap: { handleSelection(item) }
                )
            }
        }
    }

    private var emptySearchState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
            Text("No results for \"\(debouncedQuery)\"")
                .font(AMENFont.medium(14))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 52)
        .padding(.horizontal, 16)
    }

    // MARK: Helpers

    private func sectionHeader(_ label: String) -> some View {
        Text(label)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AmenTheme.Colors.textPrimary)
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Selection

    private func handleSelection(_ item: TagPickerItem) {
        let tag = item.communityTag
        if selectedTag?.id == tag.id {
            // Deselect: tap again to clear
            selectedTag = nil
        } else {
            selectedTag = tag
            RecentsStore.push(tag)
            recents = RecentsStore.load()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // Small delay so user sees checkmark before sheet closes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                onDone()
            }
        }
    }

    // MARK: - Data Fetching

    /// Fetches the spaces the current user is a member of.
    private func fetchMySpaces() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoadingSpaces = true

        let db = Firestore.firestore()
        // Query spaces where the current user is a member
        db.collection("spaces")
            .whereField("memberIds", arrayContains: uid)
            .limit(to: 30)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    isLoadingSpaces = false
                    guard let docs = snapshot?.documents else { return }
                    mySpaces = docs.compactMap { doc -> TagPickerItem? in
                        guard let name = doc.data()["name"] as? String else { return nil }
                        return TagPickerItem(id: doc.documentID, name: name, isCommunity: true)
                    }
                }
            }
    }

    /// Queries `topics` and `spaces` for prefix-matching name search.
    private func fetchSearchResults(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        isLoadingSearch = true
        let db = Firestore.firestore()
        let end = query + "\u{f8ff}"  // Unicode sentinel for prefix range query

        let topicsQuery = db.collection("topics")
            .whereField("name", isGreaterThanOrEqualTo: query)
            .whereField("name", isLessThanOrEqualTo: end)
            .limit(to: 10)

        let spacesQuery = db.collection("spaces")
            .whereField("name", isGreaterThanOrEqualTo: query)
            .whereField("name", isLessThanOrEqualTo: end)
            .limit(to: 10)

        Task {
            async let topicsDocs = try? topicsQuery.getDocuments().documents ?? []
            async let spacesDocs = try? spacesQuery.getDocuments().documents ?? []

            let (topics, spaces) = await (topicsDocs, spacesDocs)

            let topicItems = (topics ?? []).compactMap { doc -> TagPickerItem? in
                guard let name = doc.data()["name"] as? String else { return nil }
                return TagPickerItem(id: doc.documentID, name: name, isCommunity: false)
            }
            let spaceItems = (spaces ?? []).compactMap { doc -> TagPickerItem? in
                guard let name = doc.data()["name"] as? String else { return nil }
                return TagPickerItem(id: doc.documentID, name: name, isCommunity: true)
            }

            // Merge: spaces first, then topics; deduplicate by id
            var seen = Set<String>()
            var merged: [TagPickerItem] = []
            for item in (spaceItems + topicItems) {
                if seen.insert(item.id).inserted { merged.append(item) }
            }

            await MainActor.run {
                isLoadingSearch = false
                searchResults = merged
            }
        }
    }
}

// MARK: - TagPickerRow

private struct TagPickerRow: View {
    let item: TagPickerItem
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                iconBadge
                nameLabel
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AmenTheme.Colors.amenGold)
                        .accessibilityHidden(true)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 0)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(AmenPressStyle(scale: 0.97))
        .accessibilityLabel("\(item.name), \(item.isCommunity ? "community" : "topic")\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(reduceMotion ? nil : Motion.springPress, value: isSelected)
    }

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AmenTheme.Colors.amenPurple.opacity(0.12))
                .frame(width: 36, height: 36)
            Image(systemName: item.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.amenPurple)
        }
        .accessibilityHidden(true)
    }

    private var nameLabel: some View {
        Text(item.name)
            .font(AMENFont.medium(14))
            .foregroundStyle(AmenTheme.Colors.textPrimary)
            .lineLimit(1)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Tag Picker") {
    @Previewable @State var tag: CommunityTag? = nil

    Color.gray.opacity(0.15)
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            ComposerCommunityTagPickerSheet(selectedTag: $tag) {
                print("Done — selected: \(String(describing: tag))")
            }
        }
}
#endif
