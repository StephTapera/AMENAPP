/*
import SwiftUI
import Foundation
import UIKit
import PhotosUI

struct MessageRequest: Identifiable, Hashable {
    let id: String
    let conversationId: String
    let fromUserId: String
    let fromUserName: String
    var isRead: Bool
    
    init(id: String, conversationId: String, fromUserId: String, fromUserName: String, isRead: Bool) {
        self.id = id
        self.conversationId = conversationId
        self.fromUserId = fromUserId
        self.fromUserName = fromUserName
        self.isRead = isRead
    }
}

enum RequestAction {
    case accept
    case decline
    case block
    case report
}

struct MessageRequestRow: View {
    let request: MessageRequest
    let onAction: (RequestAction) -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(request.fromUserName)
                    .font(.headline)
                Text("sent you a message request")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button(action: { onAction(.accept) }) {
                    Text("Accept")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
                .accessibilityLabel("Accept request from \(request.fromUserName)")
                Button(action: { onAction(.decline) }) {
                    Text("Decline")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.3))
                        .foregroundColor(.primary)
                        .cornerRadius(6)
                }
                .accessibilityLabel("Decline request from \(request.fromUserName)")
            }
            Menu {
                Button("Block", role: .destructive) {
                    onAction(.block)
                }
                Button("Report", role: .destructive) {
                    onAction(.report)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
                    .padding(.leading, 8)
                    .accessibilityLabel("More actions")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.secondarySystemBackground)))
    }
}

struct CreateGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var groupName = ""
    @State private var searchText = ""
    @State private var searchResults: [ContactUser] = []
    @State private var selectedUsers: Set<String> = []
    @State private var isSearching = false
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var searchTask: Task<Void, Never>?
    
    // Avatar State
    @State private var selectedItem: PhotosPickerItem?
    @State private var groupImage: UIImage?
    
    private let messagingService = FirebaseMessagingService.shared
    private let maxGroupMembers = 50
    private let maxGroupNameLength = 100
    
    private var canCreate: Bool {
        let trimmedName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty 
            && trimmedName.count <= maxGroupNameLength
            && selectedUsers.count >= 1 
            && selectedUsers.count <= maxGroupMembers
    }
    
    private var validationMessage: String? {
        let trimmedName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty && trimmedName.count > maxGroupNameLength {
            return "Group name must be \(maxGroupNameLength) characters or less"
        }
        if selectedUsers.count > maxGroupMembers {
            return "Maximum \(maxGroupMembers) members allowed"
        }
        return nil
    }
    
    var body: some View {
        NavigationStack {
            mainContent
                .background(Color(.systemGroupedBackground))
                .navigationTitle("New Group")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    toolbarContent
                }
                .alert("Error", isPresented: $showError) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(errorMessage ?? "An error occurred")
                }
                .onDisappear {
                    searchTask?.cancel()
                    searchTask = nil
                }
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                dismiss()
            }
        }
        
        ToolbarItem(placement: .confirmationAction) {
            if isCreating {
                ProgressView()
            } else {
                Button("Create") {
                    createGroup()
                }
                .font(.custom("OpenSans-Bold", size: 16))
                .disabled(!canCreate)
                .accessibilityIdentifier("CreateGroup_CreateButton")
            }
        }
    }
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            headerSection
            
            if !selectedUsers.isEmpty {
                selectedMembersSection
            }
            
            Divider()
            
            searchBarSection
            
            searchResultsContent
        }
    }
    
    @ViewBuilder
    private var searchResultsContent: some View {
        if isSearching {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if searchText.isEmpty {
            emptySearchView
        } else if searchResults.isEmpty {
            noResultsView
        } else {
            searchResultsList
        }
    }
    
    // MARK: - Views
    
    private var headerSection: some View {
        HStack(spacing: 16) {
            // Avatar Picker
            PhotosPicker(selection: $selectedItem, matching: .images) {
                if let groupImage = groupImage {
                    Image(uiImage: groupImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 70, height: 70)
                        .clipShape(Circle())
                } else {
                    ZStack {
                        Circle()
                            .fill(Color(.systemGray5))
                            .frame(width: 70, height: 70)
                        Image(systemName: "camera.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onChange(of: selectedItem, initial: false) { newValue,<#arg#>  in
                Task {
                    guard let item = newValue else { return }
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            self.groupImage = image
                        }
                    }
                }
            }
            .accessibilityLabel("Select group photo")

            // Name Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Group Name")
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(.secondary)
                
                TextField("Enter group name", text: $groupName)
                    .font(.custom("OpenSans-Regular", size: 16))
                
                Divider()
                
                if let message = validationMessage {
                    Text(message)
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.red)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    private var groupNameSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Group Name")
                .font(.custom("OpenSans-Bold", size: 14))
                .foregroundStyle(.secondary)
            
            TextField("Enter group name", text: $groupName)
                .font(.custom("OpenSans-Regular", size: 16))
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                )
            
            if let message = validationMessage {
                Text(message)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
    
    private var selectedMembersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Members (\(selectedUsers.count))")
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(.secondary)
                
                if selectedUsers.count >= maxGroupMembers {
                    Text("(Max reached)")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(selectedUsers), id: \.self) { userId in
                        if let user = searchResults.first(where: { $0.id == userId }) {
                            SelectedUserChip(user: user) {
                                withAnimation {
                                    selectedUsers.remove(userId)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 12)
        .background(Color(.systemGroupedBackground))
    }
    
    private var searchBarSection: some View {
        HStack(spacing: 12) {
            SearchTextField(
                text: $searchText,
                isSearching: isSearching,
                onTextChange: {
                    triggerSearch()
                },
                onClear: {
                    withAnimation {
                        searchText = ""
                        searchResults = []
                    }
                }
            )
            
            if isSearching {
                ProgressView()
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
    
    private var emptySearchView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "person.3.fill")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 8) {
                Text("Add members")
                    .font(.custom("OpenSans-Bold", size: 20))
                    .foregroundStyle(.primary)
                
                Text("Search for people to add to your group")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .padding()
    }
    
    private var noResultsView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            
            Text("No users found")
                .font(.custom("OpenSans-Bold", size: 18))
                .foregroundStyle(.primary)
            
            Spacer()
        }
    }
    
    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchResults) { user in
                    if let userId = user.id, !userId.isEmpty {
                        UserSelectionRow(
                            user: user,
                            isSelected: selectedUsers.contains(userId),
                            isDisabled: selectedUsers.count >= maxGroupMembers && !selectedUsers.contains(userId),
                            onTap: {
                                toggleUserSelection(userId: userId)
                            }
                        )
                        
                        if user.id != searchResults.last?.id {
                            Divider()
                                .padding(.leading, 80)
                        }
                    }
                }
            }
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            .padding()
        }
    }
    
    // MARK: - Actions
    
    private func triggerSearch() {
        searchTask?.cancel()
        
        let query = searchText
        
        guard !query.isEmpty else {
            isSearching = false
            searchResults = []
            return
        }
        
        isSearching = true
        
        searchTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                
                guard !Task.isCancelled else { return }
                
                await performSearch(query: query)
            } catch {
                // Ignore cancellation errors
            }
        }
    }
    
    @MainActor
    private func performSearch(query: String) async {
        guard !query.isEmpty else {
            isSearching = false
            searchResults = []
            return
        }
        
        isSearching = true
        
        do {
            let users = try await messagingService.searchUsers(query: query)
            searchResults = users
            isSearching = false
        } catch {
            print("❌ Error searching users: \(error)")
            errorMessage = "Failed to search users. Please try again."
            showError = true
            searchResults = []
            isSearching = false
        }
    }
    
    private func toggleUserSelection(userId: String) {
        guard !userId.isEmpty else {
            print("⚠️ Warning: Attempted to select user with empty ID")
            return
        }
        
        withAnimation {
            if selectedUsers.contains(userId) {
                selectedUsers.remove(userId)
            } else {
                guard selectedUsers.count < maxGroupMembers else {
                    errorMessage = "Maximum \(maxGroupMembers) members allowed"
                    showError = true
                    return
                }
                selectedUsers.insert(userId)
            }
        }
        
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    private func createGroup() {
        guard canCreate else { return }
        
        let trimmedGroupName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedGroupName.isEmpty,
              trimmedGroupName.count <= maxGroupNameLength,
              selectedUsers.count >= 1,
              selectedUsers.count <= maxGroupMembers else {
            errorMessage = "Please check your group name and member count"
            showError = true
            return
        }
        
        isCreating = true
        
        Task { @MainActor in
            do {
                var participantNames: [String: String] = [:]
                var validUserIds: [String] = []
                
                for userId in selectedUsers {
                    guard !userId.isEmpty else { continue }
                    
                    if let user = searchResults.first(where: { $0.id == userId }) {
                        participantNames[userId] = user.displayName
                        validUserIds.append(userId)
                    }
                }
                
                guard !validUserIds.isEmpty else {
                    throw NSError(
                        domain: "CreateGroupView",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "No valid users selected"]
                    )
                }
                
                let conversationId = try await messagingService.createGroupConversation(
                    participantIds: validUserIds,
                    participantNames: participantNames,
                    groupName: trimmedGroupName
                )
                
                print("✅ Created group conversation: \(conversationId)")
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                
                isCreating = false
                dismiss()
                
            } catch {
                print("❌ Error creating group: \(error)")
                errorMessage = error.localizedDescription
                showError = true
                isCreating = false
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
            }
        }
    }
}

// MARK: - Search TextField Component

private struct SearchTextField: View {
    @Binding var text: String
    let isSearching: Bool
    let onTextChange: () -> Void
    let onClear: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            
            TextField("Search people to add", text: createBinding())
                .font(.custom("OpenSans-Regular", size: 16))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit {
                    onTextChange()
                }
                .accessibilityIdentifier("CreateGroup_SearchTextField")
            
            if !text.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("CreateGroup_ClearSearchButton")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
    }
    
    private func createBinding() -> Binding<String> {
        Binding<String>(
            get: { text },
            set: { newValue in
                text = newValue
                onTextChange()
            }
        )
    }
}

// MARK: - User Selection Row Component

private struct UserSelectionRow: View {
    let user: ContactUser
    let isSelected: Bool
    let isDisabled: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            GroupMemberRow(user: user, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
    }
}

// MARK: - Selected User Chip

struct SelectedUserChip: View {
    let user: ContactUser
    let onRemove: () -> Void
    
    private var initials: String {
        let components = user.displayName.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        } else if let first = components.first {
            return String(first.prefix(2)).uppercased()
        }
        return "?"
    }
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Text(initials)
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.blue)
                    )
                    .accessibilityHidden(true)
                
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .background(
                            Circle()
                                .fill(Color.red)
                                .frame(width: 18, height: 18)
                        )
                }
                .offset(x: 4, y: -4)
                .accessibilityLabel("Remove \(user.displayName)")
                .accessibilityHint("Removes this member from the group")
            }
            
            Text(user.displayName.split(separator: " ").first.map(String.init) ?? "")
                .font(.custom("OpenSans-SemiBold", size: 12))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 60)
        }
    }
}

// MARK: - Group Member Row

struct GroupMemberRow: View {
    let user: ContactUser
    let isSelected: Bool
    
    private var initials: String {
        let components = user.displayName.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        } else if let first = components.first {
            return String(first.prefix(2)).uppercased()
        }
        return "?"
    }
    
    private var avatarColor: Color {
        let colors: [Color] = [.blue, .purple, .green, .orange, .pink, .cyan, .red, .indigo]
        let hash = abs(user.displayName.hashValue)
        return colors[hash % colors.count]
    }
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(avatarColor.opacity(0.15))
                    .frame(width: 56, height: 56)
                
                Text(initials)
                    .font(.custom("OpenSans-Bold", size: 18))
                    .foregroundStyle(avatarColor)
            }
            .accessibilityHidden(true)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName)
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.primary)
                
                Text("@\(user.username)")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            ZStack {
                Circle()
                    .strokeBorder(isSelected ? Color.blue : Color.secondary.opacity(0.3), lineWidth: 2)
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
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

struct MessageSettingsView: View {
    @AppStorage("muteUnknownSenders") private var muteUnknownSenders = false
    @AppStorage("allowReadReceipts") private var allowReadReceipts = true
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Mute Unknown Senders", isOn: $muteUnknownSenders)
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Automatically mute message requests from people you don't follow")
                }
                
                Section {
                    Toggle("Allow Read Receipts", isOn: $allowReadReceipts)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Let people see when you've read their messages")
                }
            }
            .navigationTitle("Message Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
*/

