//
//  CommunityGroupsView.swift
//  AMENAPP
//
//  Browse and join community groups / circles beyond individual follows.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Models

struct CommunityGroup: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var description: String
    var category: GroupCategory
    var creatorId: String
    var memberCount: Int
    var coverImageURL: String?
    var isPrivate: Bool
    var createdAt: Date
    var rules: [String]

    enum GroupCategory: String, Codable, CaseIterable {
        case bible      = "Bible Study"
        case prayer     = "Prayer"
        case youth      = "Youth"
        case women      = "Women"
        case men        = "Men"
        case worship    = "Worship"
        case missions   = "Missions"
        case recovery   = "Recovery"
        case parenting  = "Parenting"
        case general    = "General"

        var icon: String {
            switch self {
            case .bible:     return "book.fill"
            case .prayer:    return "hands.sparkles.fill"
            case .youth:     return "figure.2.and.child.holdinghands"
            case .women:     return "person.fill"
            case .men:       return "person.fill"
            case .worship:   return "music.note"
            case .missions:  return "globe.americas.fill"
            case .recovery:  return "heart.circle.fill"
            case .parenting: return "figure.and.child.holdinghands"
            case .general:   return "person.3.fill"
            }
        }

        var color: Color {
            switch self {
            case .bible:     return .blue
            case .prayer:    return .purple
            case .youth:     return .orange
            case .women:     return .pink
            case .men:       return .indigo
            case .worship:   return .teal
            case .missions:  return .green
            case .recovery:  return .red
            case .parenting: return .mint
            case .general:   return .gray
            }
        }
    }
}

// MARK: - View

struct CommunityGroupsView: View {
    @State private var groups: [CommunityGroup] = []
    @State private var myGroups: [CommunityGroup] = []
    @State private var selectedCategory: CommunityGroup.GroupCategory?
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var showCreateSheet = false

    private let db = Firestore.firestore()

    var filteredGroups: [CommunityGroup] {
        var result = groups
        if let cat = selectedCategory {
            result = result.filter { $0.category == cat }
        }
        if !searchText.isEmpty {
            let lower = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(lower) ||
                $0.description.lowercased().contains(lower)
            }
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Search
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search groups...", text: $searchText)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.systemGray6)))
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Category filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        categoryPill(nil, label: "All")
                        ForEach(CommunityGroup.GroupCategory.allCases, id: \.self) { cat in
                            categoryPill(cat, label: cat.rawValue)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // My groups
                if !myGroups.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("My Groups")
                            .font(.system(size: 18, weight: .bold))
                            .padding(.horizontal, 16)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(myGroups) { group in
                                    myGroupCard(group)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }

                // Discover groups
                VStack(alignment: .leading, spacing: 12) {
                    Text("Discover Groups")
                        .font(.system(size: 18, weight: .bold))
                        .padding(.horizontal, 16)

                    if filteredGroups.isEmpty && !isLoading {
                        VStack(spacing: 12) {
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.secondary.opacity(0.5))
                            Text("No groups found")
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                    }

                    ForEach(filteredGroups) { group in
                        groupRow(group)
                            .padding(.horizontal, 16)
                    }
                }

                Spacer(minLength: 80)
            }
        }
        .overlay(alignment: .bottom) {
            Button {
                showCreateSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Create Group")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Capsule().fill(Color.blue))
                .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
            }
            .padding(.bottom, 20)
        }
        .onAppear { loadGroups() }
        .sheet(isPresented: $showCreateSheet) {
            CreateCommunityGroupSheet()
        }
        .navigationTitle("Community Groups")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func categoryPill(_ category: CommunityGroup.GroupCategory?, label: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.25)) {
                selectedCategory = category
            }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selectedCategory == category ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(selectedCategory == category ? Color.blue : Color(.systemGray5))
                )
        }
    }

    private func myGroupCard(_ group: CommunityGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Circle()
                .fill(group.category.color.opacity(0.2))
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: group.category.icon)
                        .foregroundStyle(group.category.color)
                )

            Text(group.name)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)

            Text("\(group.memberCount) members")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(width: 120)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.systemGray6)))
    }

    private func groupRow(_ group: CommunityGroup) -> some View {
        HStack(spacing: 14) {
            Circle()
                .fill(group.category.color.opacity(0.15))
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: group.category.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(group.category.color)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(group.name)
                        .font(.system(size: 16, weight: .semibold))
                    if group.isPrivate {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(group.description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(group.memberCount) members")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("Join") {}
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.blue)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().stroke(Color.blue, lineWidth: 1.5))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.systemGray6)))
    }

    private func loadGroups() {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        db.collection("communityGroups")
            .order(by: "memberCount", descending: true)
            .limit(to: 50)
            .getDocuments { snap, _ in
                let docs = snap?.documents ?? []
                let all = docs.compactMap { try? $0.data(as: CommunityGroup.self) }
                groups = all
                isLoading = false
            }

        db.collection("communityGroups")
            .whereField("memberIds", arrayContains: uid)
            .getDocuments { snap, _ in
                let docs = snap?.documents ?? []
                myGroups = docs.compactMap { try? $0.data(as: CommunityGroup.self) }
            }
    }
}

// MARK: - Create Group Sheet

struct CreateCommunityGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var category: CommunityGroup.GroupCategory = .general
    @State private var isPrivate = false
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Group Name", text: $name)
                    TextEditor(text: $description)
                        .frame(minHeight: 80)
                } header: {
                    Text("Details")
                }

                Section {
                    Picker("Category", selection: $category) {
                        ForEach(CommunityGroup.GroupCategory.allCases, id: \.self) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }
                }

                Section {
                    Toggle("Private Group", isOn: $isPrivate)
                } footer: {
                    Text("Private groups require approval to join.")
                }
            }
            .navigationTitle("Create Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        isCreating = true
                        guard let uid = FirebaseAuth.Auth.auth().currentUser?.uid else { return }

                        let group = CommunityGroup(
                            name: name,
                            description: description,
                            category: category,
                            creatorId: uid,
                            memberCount: 1,
                            isPrivate: isPrivate,
                            createdAt: Date(),
                            rules: []
                        )

                        let data = try? JSONEncoder().encode(group)
                        if let data, let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            var finalDict = dict
                            finalDict["memberIds"] = [uid]
                            Firestore.firestore().collection("communityGroups").document(group.id).setData(finalDict) { _ in
                                dismiss()
                            }
                        }
                    }
                    .disabled(name.isEmpty || isCreating)
                }
            }
        }
    }
}
