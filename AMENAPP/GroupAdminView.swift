//
//  GroupAdminView.swift
//  AMENAPP
//
//  Group admin controls and management
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import PhotosUI
import FirebaseStorage

// MARK: - Group Info & Admin Controls View

struct GroupInfoView: View {
    @Environment(\.dismiss) var dismiss
    let conversation: ChatConversation
    @ObservedObject private var messagingService = FirebaseMessagingService.shared
    @State private var groupName: String = ""
    @State private var groupMembers: [GroupMember] = []
    @State private var isLoading = false
    @State private var showAddMembers = false
    @State private var showEditName = false
    @State private var showLeaveConfirmation = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showPhotosPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isUploadingPhoto = false
    @State private var isMuted = false
    @State private var isTogglingMute = false
    /// Cancels the real-time conversation listener when the view disappears.
    @State private var conversationListener: ListenerRegistration?
    
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
            .photosPicker(isPresented: $showPhotosPicker, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task { await uploadGroupPhoto(item: newItem) }
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
            .onAppear {
                startListeningToGroupInfo()
            }
            .onDisappear {
                conversationListener?.remove()
                conversationListener = nil
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
                    icon: isUploadingPhoto ? "arrow.triangle.2.circlepath" : "photo",
                    title: isUploadingPhoto ? "Uploading..." : "Change Group Photo",
                    color: .blue
                ) {
                    showPhotosPicker = true
                }
                .disabled(isUploadingPhoto)
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
                    icon: isMuted ? "bell" : "bell.slash",
                    title: isMuted ? "Unmute Notifications" : "Mute Notifications",
                    color: .orange
                ) {
                    Task { await toggleMute() }
                }
                .disabled(isTogglingMute)
                
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
    
    /// Starts a real-time Firestore listener for the group conversation document.
    /// Updates are applied immediately so admin/member changes propagate without
    /// the user needing to dismiss and reopen the sheet.
    private func startListeningToGroupInfo() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        isLoading = true

        conversationListener = db.collection("conversations")
            .document(conversation.id)
            .addSnapshotListener { [self] snapshot, error in
                if error != nil {
                    DispatchQueue.main.async {
                        isLoading = false
                        errorMessage = "Could not load group info"
                        showError = true
                    }
                    return
                }

                guard let data = snapshot?.data() else { return }

                let participantIds = data["participantIds"] as? [String] ?? []
                let participantNames = data["participantNames"] as? [String: String] ?? [:]
                let participantPhotos = data["participantPhotoURLs"] as? [String: String] ?? [:]
                let adminIdSet = Set(data["adminIds"] as? [String] ?? [])

                let members: [GroupMember] = participantIds.map { pid in
                    GroupMember(
                        userId: pid,
                        name: participantNames[pid] ?? "Member",
                        isAdmin: adminIdSet.contains(pid),
                        profileImageUrl: participantPhotos[pid]
                    )
                }

                // If the current user was removed from the group, dismiss this sheet.
                let stillInGroup = participantIds.contains(userId)

                DispatchQueue.main.async {
                    isLoading = false
                    groupName = (data["groupName"] as? String) ?? conversation.name
                    groupMembers = members
                    if !stillInGroup {
                        dismiss()
                    }
                }
            }

        // Load mute status separately (not real-time — mute changes are local)
        Task {
            let muteDoc = try? await db.collection("mutedConversations")
                .document("\(userId)_\(conversation.id)")
                .getDocument()
            await MainActor.run {
                isMuted = muteDoc?.exists ?? false
            }
        }
    }
    
    private func makeAdmin(_ member: GroupMember) {
        guard isAdmin else { return }

        Task {
            do {
                let db = Firestore.firestore()
                try await db.collection("conversations").document(conversation.id)
                    .updateData(["adminIds": FieldValue.arrayUnion([member.userId])])

                await MainActor.run {
                    if let index = groupMembers.firstIndex(where: { $0.id == member.id }) {
                        groupMembers[index].isAdmin = true
                    }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
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
                let db = Firestore.firestore()
                try await db.collection("conversations").document(conversation.id)
                    .updateData(["adminIds": FieldValue.arrayRemove([member.userId])])

                await MainActor.run {
                    if let index = groupMembers.firstIndex(where: { $0.id == member.id }) {
                        groupMembers[index].isAdmin = false
                    }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
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
                try await FirebaseMessagingService.shared.removeParticipantFromGroup(
                    conversationId: conversation.id,
                    participantId: member.userId
                )

                await MainActor.run {
                    groupMembers.removeAll { $0.id == member.id }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to remove member"
                    showError = true
                }
            }
        }
    }
    
    private func uploadGroupPhoto(item: PhotosPickerItem) async {
        isUploadingPhoto = true
        defer { isUploadingPhoto = false }
        
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            
            let storage = Storage.storage()
            let ref = storage.reference().child("group_photos/\(conversation.id).jpg")
            
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            
            _ = try await ref.putDataAsync(data, metadata: metadata)
            let downloadURL = try await ref.downloadURL()
            
            // Update conversation document with new group photo URL
            let db = Firestore.firestore()
            try await db.collection("conversations").document(conversation.id)
                .updateData(["groupImageURL": downloadURL.absoluteString])
            
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
        } catch {
            await MainActor.run {
                errorMessage = "Failed to upload photo: \(error.localizedDescription)"
                showError = true
            }
        }
    }
    
    private func toggleMute() async {
        isTogglingMute = true
        defer { isTogglingMute = false }
        
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let db = Firestore.firestore()
        let muteRef = db.collection("mutedConversations").document("\(userId)_\(conversation.id)")
        
        do {
            if isMuted {
                try await muteRef.delete()
            } else {
                try await muteRef.setData([
                    "userId": userId,
                    "conversationId": conversation.id,
                    "mutedAt": FieldValue.serverTimestamp()
                ])
            }
            await MainActor.run { isMuted.toggle() }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to \(isMuted ? "unmute" : "mute") conversation"
                showError = true
            }
        }
    }
    
    private func leaveGroup() {
        Task {
            do {
                try await FirebaseMessagingService.shared.leaveGroup(conversationId: conversation.id)

                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
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
        guard !selectedUsers.isEmpty else { return }
        isAdding = true

        Task {
            do {
                let ids = selectedUsers.compactMap { $0.id }
                let names = Dictionary(uniqueKeysWithValues: selectedUsers.compactMap { user -> (String, String)? in
                    guard let id = user.id else { return nil }
                    return (id, user.displayName)
                })

                try await FirebaseMessagingService.shared.addParticipantsToGroup(
                    conversationId: conversationId,
                    participantIds: ids,
                    participantNames: names
                )

                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isAdding = false
                    // Dismiss anyway — error is non-critical
                    dismiss()
                }
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
            do {
                try await FirebaseMessagingService.shared.updateGroupName(
                    conversationId: conversationId,
                    newName: newName.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                }
            }
        }
    }
}
