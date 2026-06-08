//
//  ContactSearchView.swift
//  AMENAPP
//
//  User Discovery and Contact Search
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Contact Search View

struct ContactSearchView: View {
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var searchResults: [SearchableUser] = []
    @State private var isSearching = false
    @State private var recentContacts: [SearchableUser] = []
    @State private var suggestedUsers: [SearchableUser] = []
    @State private var selectedUser: SearchableUser?
    @State private var showingConversation = false
    
    private let firebaseService = FirebaseMessagingService.shared
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Search Bar
                    searchBar
                    
                    // Search Results or Browse Options
                    if !searchText.isEmpty {
                        searchResultsSection
                    } else {
                        VStack(spacing: 24) {
                            // Recent Contacts
                            if !recentContacts.isEmpty {
                                recentContactsSection
                            }
                            
                            // Suggested Users (Based on mutual connections, similar interests)
                            suggestedUsersSection
                            
                            // Browse by Category
                            browseByCategorySection
                        }
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Find People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadSuggestedUsers()
                await loadRecentContacts()
            }
            .sheet(item: $selectedUser) { user in
                UserProfileSheet(user: user) {
                    startConversation(with: user)
                }
            }
        }
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.systemScaled(16))
                    .foregroundStyle(.secondary)
                
                TextField("Search by name, username, or interests", text: $searchText)
                    .font(AMENFont.regular(16))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit {
                        performSearch()
                    }
                
                if !searchText.isEmpty {
                    Button {
                        withAnimation {
                            searchText = ""
                            searchResults = []
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.systemScaled(16))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            )
            
            if isSearching {
                ProgressView()
                    .padding(.trailing, 8)
            }
        }
        .padding(.horizontal)
        .onChange(of: searchText) { _, newValue in
            if !newValue.isEmpty {
                performSearch()
            } else {
                searchResults = []
            }
        }
    }
    
    // MARK: - Search Results
    
    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Search Results")
                .font(AMENFont.bold(18))
                .padding(.horizontal)
            
            if isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if searchResults.isEmpty {
                emptySearchResults
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(searchResults) { user in
                        ContactUserSearchRow(user: user) {
                            selectedUser = user
                        } onMessage: {
                            startConversation(with: user)
                        }
                        
                        if user.id != searchResults.last?.id {
                            Divider()
                                .padding(.leading, 80)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                .padding(.horizontal)
            }
        }
    }
    
    private var emptySearchResults: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.systemScaled(48))
                .foregroundStyle(.secondary)
            
            Text("No users found")
                .font(AMENFont.bold(18))
                .foregroundStyle(.primary)
            
            Text("Try searching by name or username")
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    // MARK: - Recent Contacts
    
    private var recentContactsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent")
                .font(AMENFont.bold(18))
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(recentContacts) { user in
                        RecentContactCard(user: user) {
                            startConversation(with: user)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Suggested Users
    
    private var suggestedUsersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Suggested for You")
                    .font(AMENFont.bold(18))
                
                Spacer()
                
                Button {
                    Task {
                        await loadSuggestedUsers()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal)
            
            LazyVStack(spacing: 0) {
                ForEach(suggestedUsers) { user in
                    ContactUserSearchRow(user: user) {
                        selectedUser = user
                    } onMessage: {
                        startConversation(with: user)
                    }
                    
                    if user.id != suggestedUsers.last?.id {
                        Divider()
                            .padding(.leading, 80)
                    }
                }
            }
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            .padding(.horizontal)
        }
    }
    
    // MARK: - Browse by Category
    
    private var browseByCategorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Browse by Interest")
                .font(AMENFont.bold(18))
                .padding(.horizontal)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                CategoryBrowseCard(
                    icon: "cross.fill",
                    title: "Ministry",
                    color: .purple,
                    count: "234+"
                )
                
                CategoryBrowseCard(
                    icon: "brain.head.profile",
                    title: "Tech & AI",
                    color: .blue,
                    count: "567+"
                )
                
                CategoryBrowseCard(
                    icon: "briefcase.fill",
                    title: "Business",
                    color: .green,
                    count: "432+"
                )
                
                CategoryBrowseCard(
                    icon: "paintbrush.fill",
                    title: "Creative",
                    color: .orange,
                    count: "321+"
                )
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Actions
    
    private func performSearch() {
        guard !searchText.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        
        Task { @MainActor in
            do {
                let users = try await firebaseService.searchUsers(query: searchText)
                searchResults = users.map { SearchableUser(from: $0) }
                isSearching = false
            } catch {
                dlog("Error searching users: \(error)")
                isSearching = false
            }
        }
    }
    
    private func loadSuggestedUsers() async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        do {
            lazy var db = Firestore.firestore()
            // Fetch users the current user follows as suggestions
            let snapshot = try await db.collection("follows")
                .whereField("followerId", isEqualTo: currentUserId)
                .limit(to: 5)
                .getDocuments()
            let followingIds = snapshot.documents.compactMap { $0.data()["followingId"] as? String }
            guard !followingIds.isEmpty else { return }
            let userDocs = try await db.collection("users")
                .whereField(FieldPath.documentID(), in: followingIds)
                .getDocuments()
            await MainActor.run {
                suggestedUsers = userDocs.documents.compactMap { doc -> SearchableUser? in
                    let d = doc.data()
                    guard let name = d["displayName"] as? String else { return nil }
                    return SearchableUser(
                        id: doc.documentID,
                        name: name,
                        username: d["username"] as? String,
                        bio: d["bio"] as? String,
                        avatarUrl: d["profileImageURL"] as? String
                    )
                }
            }
        } catch {
            dlog("Error loading suggested users: \(error)")
        }
    }

    private func loadRecentContacts() async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        do {
            lazy var db = Firestore.firestore()
            // Fetch recent 1:1 conversation partners
            let snapshot = try await db.collection("conversations")
                .whereField("participantIds", arrayContains: currentUserId)
                .whereField("isGroup", isEqualTo: false)
                .order(by: "lastMessageTimestamp", descending: true)
                .limit(to: 4)
                .getDocuments()
            var partnerIds: [String] = []
            for doc in snapshot.documents {
                if let ids = doc.data()["participantIds"] as? [String] {
                    if let partnerId = ids.first(where: { $0 != currentUserId }) {
                        partnerIds.append(partnerId)
                    }
                }
            }
            guard !partnerIds.isEmpty else { return }
            let userDocs = try await db.collection("users")
                .whereField(FieldPath.documentID(), in: partnerIds)
                .getDocuments()
            await MainActor.run {
                recentContacts = userDocs.documents.compactMap { doc -> SearchableUser? in
                    let d = doc.data()
                    guard let name = d["displayName"] as? String else { return nil }
                    return SearchableUser(
                        id: doc.documentID,
                        name: name,
                        username: d["username"] as? String,
                        bio: d["bio"] as? String,
                        avatarUrl: d["profileImageURL"] as? String
                    )
                }
            }
        } catch {
            dlog("Error loading recent contacts: \(error)")
        }
    }
    
    private func startConversation(with user: SearchableUser) {
        dismiss()
        
        Task { @MainActor in
            do {
                let conversationId = try await firebaseService.getOrCreateDirectConversation(
                    withUserId: user.id,
                    userName: user.name
                )
                
                // Notify MessagesView to open this conversation
                NotificationCenter.default.post(
                    name: .openConversation,
                    object: nil,
                    userInfo: ["conversationId": conversationId]
                )
            } catch {
                dlog("Error creating conversation: \(error)")
            }
        }
    }
}

// MARK: - Contact User Search Row

struct ContactUserSearchRow: View {
    let user: SearchableUser
    let onTap: () -> Void
    let onMessage: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(user.avatarColor.opacity(0.15))
                        .frame(width: 56, height: 56)
                    
                    if let avatarUrl = user.avatarUrl, let url = URL(string: avatarUrl) {
                        CachedAsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())
                        } placeholder: {
                            Text(user.initials)
                                .font(AMENFont.bold(18))
                                .foregroundStyle(user.avatarColor)
                        }
                    } else {
                        Text(user.initials)
                            .font(AMENFont.bold(18))
                            .foregroundStyle(user.avatarColor)
                    }
                }
                
                // User Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.name)
                        .font(AMENFont.bold(16))
                        .foregroundStyle(.primary)
                    
                    if let username = user.username {
                        Text("@\(username)")
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.secondary)
                    }
                    
                    if !user.interests.isEmpty {
                        Text(user.interests.prefix(3).joined(separator: " • "))
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Message Button
                Button(action: onMessage) {
                    Image(systemName: "message.fill")
                        .font(.systemScaled(18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(Color.blue)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Recent Contact Card

struct RecentContactCard: View {
    let user: SearchableUser
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(user.avatarColor.opacity(0.15))
                        .frame(width: 64, height: 64)
                    
                    Text(user.initials)
                        .font(AMENFont.bold(20))
                        .foregroundStyle(user.avatarColor)
                }
                
                // Name
                Text(user.name.split(separator: " ").first ?? "")
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(width: 100)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Category Browse Card

struct CategoryBrowseCard: View {
    let icon: String
    let title: String
    let color: Color
    let count: String
    
    @State private var isPressed = false
    
    var body: some View {
        Button {
            // Navigate to category browse view
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.systemScaled(20, weight: .semibold))
                        .foregroundStyle(color)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AMENFont.bold(14))
                        .foregroundStyle(.primary)
                    
                    Text(count + " members")
                        .font(AMENFont.regular(11))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            )
            .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.7))) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - User Profile Sheet

struct UserProfileSheet: View {
    @Environment(\.dismiss) var dismiss
    let user: SearchableUser
    let onMessage: () -> Void
    
    @State private var isFollowing = false
    @State private var showReportConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Profile Header
                    VStack(spacing: 16) {
                        // Avatar
                        ZStack {
                            Circle()
                                .fill(user.avatarColor.opacity(0.15))
                                .frame(width: 100, height: 100)
                            
                            Text(user.initials)
                                .font(AMENFont.bold(36))
                                .foregroundStyle(user.avatarColor)
                        }
                        
                        // Name and Username
                        VStack(spacing: 4) {
                            Text(user.name)
                                .font(AMENFont.bold(24))
                                .foregroundStyle(.primary)
                            
                            if let username = user.username {
                                Text("@\(username)")
                                    .font(AMENFont.regular(15))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        // Bio
                        if let bio = user.bio {
                            Text(bio)
                                .font(AMENFont.regular(15))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        
                        // Action Buttons
                        HStack(spacing: 12) {
                            Button(action: onMessage) {
                                HStack(spacing: 8) {
                                    Image(systemName: "message.fill")
                                    Text("Message")
                                        .font(AMENFont.bold(16))
                                }
                                .foregroundStyle(Color.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.blue)
                                .cornerRadius(14)
                            }
                            
                            Button {
                                withAnimation {
                                    isFollowing.toggle()
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: isFollowing ? "checkmark" : "plus")
                                    Text(isFollowing ? "Following" : "Follow")
                                        .font(AMENFont.bold(16))
                                }
                                .foregroundStyle(isFollowing ? .primary : Color.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(isFollowing ? Color(.systemGray6) : Color.black)
                                .cornerRadius(14)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.top, 20)
                    
                    // Interests/Tags
                    if !user.interests.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Interests")
                                .font(AMENFont.bold(18))
                                .padding(.horizontal)
                            
                            AMENFlowLayout(spacing: 8) {
                                ForEach(user.interests, id: \.self) { interest in
                                    Text(interest)
                                        .font(AMENFont.semiBold(13))
                                        .foregroundStyle(.primary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule()
                                                .fill(Color(.systemGray6))
                                        )
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    // Stats
                    HStack(spacing: 32) {
                        StatView(count: "\(user.postCount)", label: "Posts")
                        StatView(count: "\(user.followerCount)", label: "Followers")
                        StatView(count: "\(user.followingCount)", label: "Following")
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemGray6))
                    )
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showReportConfirm = true
                        } label: {
                            Label("Report", systemImage: "exclamationmark.triangle")
                        }
                        
                        Button(role: .destructive) {
                            // Block user
                        } label: {
                            Label("Block", systemImage: "hand.raised")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.systemScaled(18, weight: .semibold))
                    }
                }
            }
        }
        .confirmationDialog("Report this user?", isPresented: $showReportConfirm, titleVisibility: .visible) {
            Button("Report", role: .destructive) {
                Task {
                    try? await ModerationService.shared.reportUser(
                        userId: user.id,
                        reason: .inappropriateContent,
                        additionalDetails: nil
                    )
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Searchable User Model
// Note: SearchableUser is now defined in SearchableUser.swift

#Preview {
    ContactSearchView()
}
