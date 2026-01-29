//
//  GroupChatCreationView.swift
//  AMENAPP
//
//  Group Chat Creation & Management
//

// TEMPORARILY DISABLED FOR COMPILATION

/*

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Create Group View

struct CreateGroupView: View {
    @Environment(\.dismiss) var dismiss
    @State private var groupName = ""
    @State private var groupDescription = ""
    @State private var selectedUsers: Set<String> = []
    @State private var searchText = ""
    @State private var searchResults: [SearchableUser] = []
    @State private var isSearching = false
    @State private var showingGroupCreated = false
    @State private var createdGroupId: String?
    @State private var selectedGroupIcon = "person.3.fill"
    @State private var showIconPicker = false
    @State private var groupCategory: GroupCategory = .general
    @State private var isPrivate = false
    
    private let firebaseService = FirebaseMessagingService.shared
    
    enum GroupCategory: String, CaseIterable {
        case general = "General"
        case prayer = "Prayer"
        case ministry = "Ministry"
        case bible = "Bible Study"
        case fellowship = "Fellowship"
        case outreach = "Outreach"
        case tech = "Tech & AI"
        case business = "Business"
        case creative = "Creative"
        case youth = "Youth"
        
        var icon: String {
            switch self {
            case .general: return "person.3.fill"
            case .prayer: return "hands.sparkles.fill"
            case .ministry: return "cross.fill"
            case .bible: return "book.fill"
            case .fellowship: return "heart.circle.fill"
            case .outreach: return "globe.americas.fill"
            case .tech: return "brain.head.profile"
            case .business: return "briefcase.fill"
            case .creative: return "paintbrush.fill"
            case .youth: return "figure.walk"
            }
        }
        
        var color: Color {
            switch self {
            case .general: return .gray
            case .prayer: return .purple
            case .ministry: return .blue
            case .bible: return .orange
            case .fellowship: return .pink
            case .outreach: return .green
            case .tech: return .cyan
            case .business: return .indigo
            case .creative: return .yellow
            case .youth: return .red
            }
        }
    }
    
    var canCreate: Bool {
        !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        selectedUsers.count >= 1
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Group Icon & Name
                    groupHeaderSection
                    
                    // Category Selection
                    categorySection
                    
                    // Privacy Toggle
                    privacySection
                    
                    // Description
                    descriptionSection
                    
                    // Add Members Section
                    addMembersSection
                    
                    // Selected Members
                    if !selectedUsers.isEmpty {
                        selectedMembersSection
                    }
                    
                    // Create Button
                    createButtonSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showIconPicker) {
                GroupIconPickerView(selectedIcon: $selectedGroupIcon, category: groupCategory)
            }
            .fullScreenCover(isPresented: $showingGroupCreated) {
                if let groupId = createdGroupId {
                    GroupCreatedSuccessView(groupId: groupId, groupName: groupName)
                }
            }
        }
    }
    
    // MARK: - Group Header Section
    
    private var groupHeaderSection: some View {
        VStack(spacing: 16) {
            // Group Icon
            Button {
                showIconPicker = true
            } label: {
                ZStack {
                    Circle()
                        .fill(groupCategory.color.opacity(0.15))
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: selectedGroupIcon)
                        .font(.system(size: 40))
                        .foregroundStyle(groupCategory.color)
                    
                    // Edit icon
                    Circle()
                        .fill(Color.black)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "camera.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                        )
                        .offset(x: 35, y: 35)
                }
            }
            
            // Group Name
            VStack(spacing: 8) {
                TextField("Group Name", text: $groupName)
                    .font(.custom("OpenSans-Bold", size: 20))
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                    )
                
                Text("\(groupName.count)/50")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Category Section
    
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Category")
                .font(.custom("OpenSans-Bold", size: 16))
                .foregroundStyle(.primary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(GroupCategory.allCases, id: \.self) { category in
                        CategoryChip(
                            category: category,
                            isSelected: groupCategory == category
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                groupCategory = category
                                selectedGroupIcon = category.icon
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Privacy Section
    
    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Private Group")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.primary)
                    
                    Text("Only members can see group messages")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: $isPrivate)
                    .labelsHidden()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            )
        }
    }
    
    // MARK: - Description Section
    
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Description (Optional)")
                .font(.custom("OpenSans-Bold", size: 16))
                .foregroundStyle(.primary)
            
            TextField("What's this group about?", text: $groupDescription, axis: .vertical)
                .font(.custom("OpenSans-Regular", size: 15))
                .lineLimit(3...6)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                )
        }
    }
    
    // MARK: - Add Members Section
    
    private var addMembersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Add Members")
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text("\(selectedUsers.count) selected")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
            }
            
            // Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                
                TextField("Search people", text: $searchText)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .textInputAutocapitalization(.never)
                    .onChange(of: searchText) {
                        if !searchText.isEmpty {
                            performSearch()
                        }
                    }
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
            )
            
            // Search Results
            if !searchText.isEmpty && !searchResults.isEmpty {
                VStack(spacing: 0) {
                    ForEach(searchResults) { user in
                        UserSelectionRow(
                            user: user,
                            isSelected: selectedUsers.contains(user.id)
                        ) {
                            toggleUserSelection(user.id)
                        }
                        
                        if user.id != searchResults.last?.id {
                            Divider()
                                .padding(.leading, 60)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                )
            }
        }
    }
    
    // MARK: - Selected Members Section
    
    private var selectedMembersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Selected Members")
                .font(.custom("OpenSans-Bold", size: 16))
                .foregroundStyle(.primary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(getSelectedUsers(), id: \.id) { user in
                        SelectedMemberChip(user: user) {
                            withAnimation {
                                selectedUsers.remove(user.id)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Create Button Section
    
    private var createButtonSection: some View {
        Button {
            createGroup()
        } label: {
            HStack {
                if isSearching {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                    
                    Text("Create Group")
                        .font(.custom("OpenSans-Bold", size: 17))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(canCreate ? groupCategory.color : Color.gray)
            )
            .shadow(color: canCreate ? groupCategory.color.opacity(0.3) : .clear, radius: 12, y: 4)
        }
        .disabled(!canCreate || isSearching)
        .padding(.top, 8)
    }
    
    // MARK: - Actions
    
    private func performSearch() {
        isSearching = true
        
        Task {
            do {
                let users = try await firebaseService.searchUsers(query: searchText)
                await MainActor.run {
                    searchResults = users.map { SearchableUser(from: $0) }
                    isSearching = false
                }
            } catch {
                print("Error searching users: \(error)")
                await MainActor.run {
                    isSearching = false
                }
            }
        }
    }
    
    private func toggleUserSelection(_ userId: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if selectedUsers.contains(userId) {
                selectedUsers.remove(userId)
            } else {
                selectedUsers.insert(userId)
            }
        }
        
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    private func getSelectedUsers() -> [SearchableUser] {
        // In production, fetch actual user data
        return SearchableUser.sampleUsers.filter { selectedUsers.contains($0.id) }
    }
    
    private func createGroup() {
        guard canCreate else { return }
        
        isSearching = true
        
        Task {
            do {
                var participantIds = Array(selectedUsers)
                participantIds.append(firebaseService.currentUserId)
                
                var participantNames: [String: String] = [:]
                participantNames[firebaseService.currentUserId] = firebaseService.currentUserName
                
                // Add other participants (in production, fetch their names)
                for userId in selectedUsers {
                    if let user = SearchableUser.sampleUsers.first(where: { $0.id == userId }) {
                        participantNames[userId] = user.name
                    }
                }
                
                let conversationId = try await firebaseService.createConversation(
                    participantIds: participantIds,
                    participantNames: participantNames,
                    isGroup: true,
                    groupName: groupName
                )
                
                await MainActor.run {
                    createdGroupId = conversationId
                    showingGroupCreated = true
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            } catch {
                print("Error creating group: \(error)")
                await MainActor.run {
                    isSearching = false
                    // TODO: Show error alert
                }
            }
        }
    }
}

// MARK: - Category Chip

struct CategoryChip: View {
    let category: CreateGroupView.GroupCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 14, weight: .semibold))
                
                Text(category.rawValue)
                    .font(.custom("OpenSans-SemiBold", size: 14))
            }
            .foregroundStyle(isSelected ? .white : category.color)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? category.color : category.color.opacity(0.12))
                    .shadow(color: isSelected ? category.color.opacity(0.3) : .clear, radius: 8, y: 2)
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : category.color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - User Selection Row

struct UserSelectionRow: View {
    let user: SearchableUser
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(user.avatarColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Text(user.initials)
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(user.avatarColor)
                }
                
                // User Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.name)
                        .font(.custom("OpenSans-Bold", size: 15))
                        .foregroundStyle(.primary)
                    
                    if let username = user.username {
                        Text("@\(username)")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                // Selection Indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.blue : Color(.systemGray4), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 24, height: 24)
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Selected Member Chip

struct SelectedMemberChip: View {
    let user: SearchableUser
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // Avatar
            ZStack {
                Circle()
                    .fill(user.avatarColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                
                Text(user.initials)
                    .font(.custom("OpenSans-Bold", size: 11))
                    .foregroundStyle(user.avatarColor)
            }
            
            Text(user.name.split(separator: " ").first ?? "")
                .font(.custom("OpenSans-SemiBold", size: 13))
                .foregroundStyle(.primary)
                .lineLimit(1)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
        )
    }
}

// MARK: - Group Icon Picker

struct GroupIconPickerView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedIcon: String
    let category: CreateGroupView.GroupCategory
    
    private let icons = [
        "person.3.fill", "hands.sparkles.fill", "cross.fill",
        "book.fill", "heart.circle.fill", "globe.americas.fill",
        "brain.head.profile", "briefcase.fill", "paintbrush.fill",
        "figure.walk", "music.note", "flame.fill",
        "star.fill", "leaf.fill", "sparkles", "bolt.fill"
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(icons, id: \.self) { icon in
                        Button {
                            selectedIcon = icon
                            dismiss()
                            
                            let haptic = UIImpactFeedbackGenerator(style: .light)
                            haptic.impactOccurred()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(selectedIcon == icon ? category.color : category.color.opacity(0.12))
                                    .frame(width: 70, height: 70)
                                
                                Image(systemName: icon)
                                    .font(.system(size: 30))
                                    .foregroundStyle(selectedIcon == icon ? .white : category.color)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Group Created Success View

struct GroupCreatedSuccessView: View {
    @Environment(\.dismiss) var dismiss
    let groupId: String
    let groupName: String
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Success Animation
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.green.opacity(0.2), Color.green.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green)
            }
            
            VStack(spacing: 12) {
                Text("Group Created!")
                    .font(.custom("OpenSans-Bold", size: 28))
                    .foregroundStyle(.primary)
                
                Text("'\(groupName)' is ready for conversation")
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
            
            // Actions
            VStack(spacing: 12) {
                Button {
                    // Open group conversation
                    NotificationCenter.default.post(
                        name: .openConversation,
                        object: nil,
                        userInfo: ["conversationId": groupId]
                    )
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "message.fill")
                        Text("Start Chatting")
                            .font(.custom("OpenSans-Bold", size: 17))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .cornerRadius(14)
                }
                
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(.systemGray6))
                        )
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
    }
}

#if DEBUG
struct GroupChatCreationView_Previews: PreviewProvider {
    static var previews: some View {
        CreateGroupView()
    }
}
#endif
*/

