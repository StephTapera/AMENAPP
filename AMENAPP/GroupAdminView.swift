//
//  GroupAdminView.swift
//  AMENAPP
//
//  Group admin controls and management
//

import SwiftUI
import FirebaseAuth

// MARK: - Group Info & Admin Controls View

struct GroupInfoView: View {
    @Environment(\.dismiss) var dismiss
    let conversation: ChatConversation
    @StateObject private var messagingService = FirebaseMessagingService.shared
    @State private var groupName: String = ""
    @State private var groupMembers: [GroupMember] = []
    @State private var isLoading = false
    @State private var showAddMembers = false
    @State private var showEditName = false
    @State private var showLeaveConfirmation = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var currentUserId: String {
        Auth.auth().currentUser?.uid ?? ""
    }
    
    var isAdmin: Bool {
        groupMembers.first(where: { $0.userId == currentUserId })?.isAdmin ?? false
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Group header
                    groupHeader
                    
                    // Members section
                    membersSection
                    
                    // Admin actions (only for admins)
                    if isAdmin {
                        adminActionsSection
                    }
                    
                    // General actions
                    generalActionsSection
                    
                    // Leave group
                    leaveGroupSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Group Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showAddMembers) {
                AddGroupMembersView(conversationId: conversation.id)
            }
            .sheet(isPresented: $showEditName) {
                EditGroupNameView(conversationId: conversation.id, currentName: groupName)
            }
            .alert("Leave Group", isPresented: $showLeaveConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Leave", role: .destructive) {
                    leaveGroup()
                }
            } message: {
                Text("Are you sure you want to leave this group? You won't be able to see new messages.")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .task {
                await loadGroupInfo()
            }
        }
    }
    
    // MARK: - Group Header
    
    private var groupHeader: some View {
        VStack(spacing: 16) {
            // Group avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                conversation.avatarColor.opacity(0.3),
                                conversation.avatarColor.opacity(0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: "person.3.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(conversation.avatarColor)
            }
            
            // Group name
            Text(groupName.isEmpty ? conversation.name : groupName)
                .font(.custom("OpenSans-Bold", size: 24))
                .foregroundStyle(.primary)
            
            // Member count
            Text("\(groupMembers.count) members")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
            
            // Edit name button (admin only)
            if isAdmin {
                Button {
                    showEditName = true
                } label: {
                    Label("Edit Group Name", systemImage: "pencil")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.blue)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    // MARK: - Members Section
    
    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Members")
                    .font(.custom("OpenSans-Bold", size: 18))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                if isAdmin {
                    Button {
                        showAddMembers = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.blue)
                    }
                }
            }
            
            VStack(spacing: 0) {
                ForEach(groupMembers) { member in
                    GroupMemberRow(
                        member: member,
                        isCurrentUser: member.userId == currentUserId,
                        isAdmin: isAdmin,
                        onMakeAdmin: {
                            makeAdmin(member)
                        },
                        onRemoveAdmin: {
                            removeAdmin(member)
                        },
                        onRemoveMember: {
                            removeMember(member)
                        }
                    )
                    
                    if member.id != groupMembers.last?.id {
                        Divider()
                            .padding(.leading, 60)
                    }
                }
            }
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Admin Actions Section
    
    private var adminActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Admin Settings")
                .font(.custom("OpenSans-Bold", size: 18))
                .foregroundStyle(.primary)
            
            VStack(spacing: 0) {
                AdminActionRow(
                    icon: "person.badge.plus",
                    title: "Add Members",
                    color: .blue
                ) {
                    showAddMembers = true
                }
                
                Divider()
                    .padding(.leading, 60)
                
                AdminActionRow(
                    icon: "pencil",
                    title: "Edit Group Name",
                    color: .blue
                ) {
                    showEditName = true
                }
                
                Divider()
                    .padding(.leading, 60)
                
                AdminActionRow(
                    icon: "photo",
                    title: "Change Group Photo",
                    color: .blue
                ) {
                    // TODO: Implement photo change
                }
            }
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
    }
    
    // MARK: - General Actions Section
    
    private var generalActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions")
                .font(.custom("OpenSans-Bold", size: 18))
                .foregroundStyle(.primary)
            
            VStack(spacing: 0) {
                AdminActionRow(
                    icon: "bell.slash",
                    title: "Mute Notifications",
                    color: .orange
                ) {
                    // TODO: Implement mute
                }
                
                Divider()
                    .padding(.leading, 60)
                
                AdminActionRow(
                    icon: "magnifyingglass",
                    title: "Search in Conversation",
                    color: .blue
                ) {
                    // TODO: Implement search
                }
            }
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Leave Group Section
    
    private var leaveGroupSection: some View {
        Button {
            showLeaveConfirmation = true
        } label: {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 20))
                    .foregroundStyle(.red)
                
                Text("Leave Group")
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.red)
                
                Spacer()
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Actions
    
    private func loadGroupInfo() async {
        isLoading = true
        
        // TODO: Load from Firebase
        // For now, using placeholder
        await MainActor.run {
            groupName = conversation.name
            groupMembers = [
                GroupMember(userId: currentUserId, name: "You", isAdmin: true),
                GroupMember(userId: "user2", name: "John Doe", isAdmin: false),
                GroupMember(userId: "user3", name: "Jane Smith", isAdmin: false)
            ]
            isLoading = false
        }
    }
    
    private func makeAdmin(_ member: GroupMember) {
        guard isAdmin else { return }
        
        Task {
            do {
                // TODO: Implement in FirebaseMessagingService
                print("Making \(member.name) an admin")
                
                await MainActor.run {
                    if let index = groupMembers.firstIndex(where: { $0.id == member.id }) {
                        groupMembers[index].isAdmin = true
                    }
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to make user admin"
                    showError = true
                }
            }
        }
    }
    
    private func removeAdmin(_ member: GroupMember) {
        guard isAdmin else { return }
        
        Task {
            do {
                // TODO: Implement in FirebaseMessagingService
                print("Removing admin from \(member.name)")
                
                await MainActor.run {
                    if let index = groupMembers.firstIndex(where: { $0.id == member.id }) {
                        groupMembers[index].isAdmin = false
                    }
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to remove admin"
                    showError = true
                }
            }
        }
    }
    
    private func removeMember(_ member: GroupMember) {
        guard isAdmin else { return }
        
        Task {
            do {
                // TODO: Implement in FirebaseMessagingService
                print("Removing \(member.name) from group")
                
                await MainActor.run {
                    groupMembers.removeAll { $0.id == member.id }
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to remove member"
                    showError = true
                }
            }
        }
    }
    
    private func leaveGroup() {
        Task {
            do {
                // TODO: Implement in FirebaseMessagingService
                print("Leaving group")
                
                await MainActor.run {
                    dismiss()
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to leave group"
                    showError = true
                }
            }
        }
    }
}

// MARK: - Group Member Model

struct GroupMember: Identifiable {
    let id = UUID()
    let userId: String
    let name: String
    var isAdmin: Bool
    var profileImageUrl: String?
}

// MARK: - Group Member Row

struct GroupMemberRow: View {
    let member: GroupMember
    let isCurrentUser: Bool
    let isAdmin: Bool
    let onMakeAdmin: () -> Void
    let onRemoveAdmin: () -> Void
    let onRemoveMember: () -> Void
    
    var body: some View {
        HStack(spacing: 14) {
            // Avatar
            Circle()
                .fill(Color.blue.opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay(
                    Text(member.name.prefix(2).uppercased())
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(.blue)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.name)
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundStyle(.primary)
                    
                    if member.isAdmin {
                        Text("Admin")
                            .font(.custom("OpenSans-SemiBold", size: 11))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.blue))
                    }
                }
                
                if isCurrentUser {
                    Text("You")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Admin controls menu
            if isAdmin && !isCurrentUser {
                Menu {
                    if !member.isAdmin {
                        Button {
                            onMakeAdmin()
                        } label: {
                            Label("Make Admin", systemImage: "star.fill")
                        }
                    } else {
                        Button {
                            onRemoveAdmin()
                        } label: {
                            Label("Remove Admin", systemImage: "star.slash")
                        }
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        onRemoveMember()
                    } label: {
                        Label("Remove from Group", systemImage: "person.badge.minus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .contentShape(Rectangle())
    }
}

// MARK: - Admin Action Row

struct AdminActionRow: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(color)
                    .frame(width: 30)
                
                Text(title)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .padding()
            .contentShape(Rectangle())
        }
    }
}

// MARK: - Add Group Members View

struct AddGroupMembersView: View {
    @Environment(\.dismiss) var dismiss
    let conversationId: String
    
    @State private var searchText = ""
    @State private var searchResults: [ContactUser] = []
    @State private var selectedUsers: [ContactUser] = []
    @State private var isSearching = false
    @State private var isAdding = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                searchBar
                
                // Selected users
                if !selectedUsers.isEmpty {
                    selectedUsersSection
                }
                
                // Search results
                searchResultsList
            }
            .navigationTitle("Add Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        addMembers()
                    } label: {
                        if isAdding {
                            ProgressView()
                        } else {
                            Text("Add")
                                .font(.custom("OpenSans-Bold", size: 16))
                        }
                    }
                    .disabled(selectedUsers.isEmpty || isAdding)
                }
            }
        }
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField("Search people", text: $searchText)
                .font(.custom("OpenSans-Regular", size: 15))
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding()
    }
    
    private var selectedUsersSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(selectedUsers, id: \.id) { user in
                    SelectedUserChip(user: user) {
                        selectedUsers.removeAll { $0.id == user.id }
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 12)
    }
    
    private var searchResultsList: some View {
        List {
            ForEach(searchResults, id: \.id) { user in
                Button {
                    toggleUserSelection(user)
                } label: {
                    HStack {
                        // Avatar
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Text(user.displayName.prefix(2).uppercased())
                                    .font(.custom("OpenSans-Bold", size: 14))
                                    .foregroundStyle(.blue)
                            )
                        
                        Text(user.displayName)
                            .font(.custom("OpenSans-Regular", size: 15))
                        
                        Spacer()
                        
                        if selectedUsers.contains(where: { $0.id == user.id }) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }
    
    private func toggleUserSelection(_ user: ContactUser) {
        if selectedUsers.contains(where: { $0.id == user.id }) {
            selectedUsers.removeAll { $0.id == user.id }
        } else {
            selectedUsers.append(user)
        }
    }
    
    private func addMembers() {
        isAdding = true
        
        Task {
            // TODO: Implement in FirebaseMessagingService
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            await MainActor.run {
                dismiss()
            }
        }
    }
}

// MARK: - Edit Group Name View

struct EditGroupNameView: View {
    @Environment(\.dismiss) var dismiss
    let conversationId: String
    let currentName: String
    
    @State private var newName: String = ""
    @State private var isSaving = false
    
    var canSave: Bool {
        !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        newName != currentName
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TextField("Group name", text: $newName)
                    .font(.custom("OpenSans-Regular", size: 17))
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding()
                
                Spacer()
            }
            .navigationTitle("Edit Group Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveName()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                                .font(.custom("OpenSans-Bold", size: 16))
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .onAppear {
                newName = currentName
            }
        }
    }
    
    private func saveName() {
        isSaving = true
        
        Task {
            // TODO: Implement in FirebaseMessagingService
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            await MainActor.run {
                dismiss()
            }
        }
    }
}
