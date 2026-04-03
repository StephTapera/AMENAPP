//
//  BrowseCommunitiesView.swift
//  AMENAPP
//
//  Discover all communities — search, category filter, community cards.
//  Mirrors Threads Communities browse tab.
//

import SwiftUI
import FirebaseAuth

// MARK: - Browse View

struct BrowseCommunitiesView: View {
    @StateObject private var vm = ArkCommunityViewModel()
    @State private var searchText = ""
    @State private var selectedCategory: String? = nil   // nil = All
    @State private var showCreateCommunity = false
    @FocusState private var searchFocused: Bool

    private let categories: [(String, String, String)] = [   // (id, label, icon)
        ("small_group", "Small Group", "person.3.fill"),
        ("ministry",    "Ministry",    "star.fill"),
        ("recovery",    "Recovery",    "heart.fill"),
        ("study",       "Study",       "book.fill"),
        ("prayer",      "Prayer",      "hands.sparkles.fill"),
    ]

    private var filteredCommunities: [ArkCommunity] {
        var list = vm.communities
        if let cat = selectedCategory {
            list = list.filter { $0.category == cat }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            list = list.filter {
                $0.name.lowercased().contains(q) ||
                $0.description.lowercased().contains(q)
            }
        }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground))

            // Category filter chips
            categoryChips
                .padding(.bottom, 10)
                .background(Color(.secondarySystemGroupedBackground))

            Divider().opacity(0.3)

            // Community list
            communityList
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Browse Communities")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateCommunity = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.systemScaled(20))
                }
            }
        }
        .task {
            await vm.loadCommunities()
            await vm.loadUserMemberships()
        }
        .refreshable {
            await vm.loadCommunities()
            await vm.loadUserMemberships()
        }
        .sheet(isPresented: $showCreateCommunity) {
            CreateCommunitySheet()
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(searchFocused ? .primary : .secondary)
                .font(.systemScaled(15, weight: searchFocused ? .semibold : .regular))
                .animation(.easeInOut(duration: 0.15), value: searchFocused)

            TextField("Search communities…", text: $searchText)
                .font(AMENFont.regular(15))
                .focused($searchFocused)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Category Chips

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(id: nil, label: "All", icon: "square.grid.2x2.fill")
                ForEach(categories, id: \.0) { id, label, icon in
                    categoryChip(id: id, label: label, icon: icon)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
        }
    }

    private func categoryChip(id: String?, label: String, icon: String) -> some View {
        let isActive = selectedCategory == id
        let chipColor = id.flatMap { cat in
            categories.first { $0.0 == cat }.map { _ in categoryColor(for: id) }
        } ?? Color.accentColor

        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                selectedCategory = (selectedCategory == id) ? nil : id
            }
            HapticManager.impact(style: .light)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.systemScaled(11, weight: .semibold))
                Text(label)
                    .font(AMENFont.semiBold(13))
            }
            .foregroundStyle(isActive ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                isActive ? chipColor : Color(.tertiarySystemGroupedBackground),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    private func categoryColor(for id: String?) -> Color {
        switch id {
        case "small_group": return .blue
        case "ministry":    return .purple
        case "recovery":    return .orange
        case "study":       return .green
        case "prayer":      return .indigo
        default:            return .accentColor
        }
    }

    // MARK: - Community List

    private var communityList: some View {
        Group {
            if vm.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading communities…")
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredCommunities.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: searchText.isEmpty ? "person.3" : "magnifyingglass")
                        .font(.systemScaled(44))
                        .foregroundStyle(.tertiary)
                    Text(searchText.isEmpty ? "No communities yet" : "No results for \"\(searchText)\"")
                        .font(AMENFont.semiBold(16))
                        .foregroundStyle(.secondary)
                    if searchText.isEmpty {
                        Button {
                            showCreateCommunity = true
                        } label: {
                            Label("Start a Community", systemImage: "plus")
                                .font(AMENFont.semiBold(14))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.accentColor, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredCommunities) { community in
                            NavigationLink(destination: ArkCommunityDetailView(community: community)) {
                                CommunityBrowseCard(
                                    community: community,
                                    isMember: vm.userMembershipIds.contains(community.id ?? "")
                                )
                            }
                            .buttonStyle(.plain)

                            if community.id != filteredCommunities.last?.id {
                                Divider()
                                    .padding(.leading, 76)
                                    .opacity(0.25)
                            }
                        }
                    }
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
        }
    }
}

// MARK: - Community Browse Card

struct CommunityBrowseCard: View {
    let community: ArkCommunity
    let isMember: Bool

    private var categoryColor: Color {
        switch community.category {
        case "small_group": return .blue
        case "ministry":    return .purple
        case "recovery":    return .orange
        case "study":       return .green
        case "prayer":      return .indigo
        default:            return .accentColor
        }
    }

    private var categoryIcon: String {
        switch community.category {
        case "small_group": return "person.3.fill"
        case "ministry":    return "star.fill"
        case "recovery":    return "heart.fill"
        case "study":       return "book.fill"
        case "prayer":      return "hands.sparkles.fill"
        default:            return "person.3.fill"
        }
    }

    private var initials: String {
        community.name.split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map { String($0) } }
            .joined()
            .uppercased()
    }

    var body: some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.15))
                    .frame(width: 50, height: 50)
                Text(initials)
                    .font(.systemScaled(18, weight: .bold, design: .rounded))
                    .foregroundStyle(categoryColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(community.name)
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(.primary)
                    if community.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.systemScaled(12))
                            .foregroundStyle(.blue)
                    }
                }

                Text(community.description)
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Label(community.categoryDisplayName, systemImage: categoryIcon)
                        .font(AMENFont.semiBold(11))
                        .foregroundStyle(categoryColor)

                    Text("·")
                        .foregroundStyle(.tertiary)

                    Text("\(community.memberCount) members")
                        .font(AMENFont.regular(11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            // Member badge or chevron
            if isMember {
                Image(systemName: "checkmark.circle.fill")
                    .font(.systemScaled(20))
                    .foregroundStyle(categoryColor)
            } else {
                Image(systemName: "chevron.right")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Create Community Sheet

private struct CreateCommunitySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var category = "small_group"
    @State private var isPrivate = false
    @State private var covenantPrinciples: [String] = ["Love & respect", "Truth in grace", "No gossip"]
    @State private var isCreating = false
    @State private var newPrinciple = ""

    private let categories: [(String, String, String)] = [
        ("small_group", "Small Group",  "person.3.fill"),
        ("ministry",    "Ministry",     "star.fill"),
        ("recovery",    "Recovery",     "heart.fill"),
        ("study",       "Study",        "book.fill"),
        ("prayer",      "Prayer",       "hands.sparkles.fill"),
    ]

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Community Info") {
                    TextField("Name", text: $name)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.0) { id, label, icon in
                            Label(label, systemImage: icon).tag(id)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Privacy") {
                    Toggle("Private Community", isOn: $isPrivate)
                    if isPrivate {
                        Text("Members must be approved before joining.")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    ForEach(covenantPrinciples.indices, id: \.self) { i in
                        HStack {
                            Text(covenantPrinciples[i])
                                .font(AMENFont.regular(14))
                            Spacer()
                        }
                    }
                    .onDelete { covenantPrinciples.remove(atOffsets: $0) }

                    HStack {
                        TextField("Add a covenant principle", text: $newPrinciple)
                        Button("Add") {
                            let trimmed = newPrinciple.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            covenantPrinciples.append(trimmed)
                            newPrinciple = ""
                        }
                        .disabled(newPrinciple.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } header: {
                    Text("Covenant Principles")
                } footer: {
                    Text("These define how your community treats one another.")
                }
            }
            .navigationTitle("New Community")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await createCommunity() }
                    } label: {
                        if isCreating {
                            ProgressView()
                        } else {
                            Text("Create")
                                .font(AMENFont.semiBold(15))
                        }
                    }
                    .disabled(!canCreate || isCreating)
                }
            }
        }
    }

    private func createCommunity() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isCreating = true
        defer { isCreating = false }

        let community = ArkCommunity(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            leaderId: uid,
            covenantPrinciples: covenantPrinciples,
            memberCount: 1,
            isVerified: false,
            category: category
        )

        do {
            _ = try await ArkService.shared.createCommunity(community)
            dlog("✅ Created community: \(community.name)")
            dismiss()
        } catch {
            dlog("❌ Failed to create community: \(error)")
        }
    }
}

// MARK: - Convenience extension (reused from ArkCommunityDetailView)

private extension ArkCommunity {
    var categoryDisplayName: String {
        switch category {
        case "small_group": return "Small Group"
        case "ministry":    return "Ministry"
        case "recovery":    return "Recovery"
        case "study":       return "Study"
        case "prayer":      return "Prayer"
        default:            return category.capitalized
        }
    }
}
