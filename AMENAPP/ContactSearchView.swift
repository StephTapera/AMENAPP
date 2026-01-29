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
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                
                TextField("Search by name, username, or interests", text: $searchText)
                    .font(.custom("OpenSans-Regular", size: 16))
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
                            .font(.system(size: 16))
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
                .font(.custom("OpenSans-Bold", size: 18))
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
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("No users found")
                .font(.custom("OpenSans-Bold", size: 18))
                .foregroundStyle(.primary)
            
            Text("Try searching by name or username")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    // MARK: - Recent Contacts
    
    private var recentContactsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent")
                .font(.custom("OpenSans-Bold", size: 18))
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
                    .font(.custom("OpenSans-Bold", size: 18))
                
                Spacer()
                
                Button {
                    Task {
                        await loadSuggestedUsers()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
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
                .font(.custom("OpenSans-Bold", size: 18))
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
                print("Error searching users: \(error)")
                isSearching = false
            }
        }
    }
    
    private func loadSuggestedUsers() async {
        // In production, this would fetch users based on:
        // - Mutual connections
        // - Similar interests
        // - Same church/group
        // - Activity patterns
        
        suggestedUsers = SearchableUser.sampleUsers.shuffled().prefix(5).map { $0 }
    }
    
    private func loadRecentContacts() async {
        // Load users you've recently messaged
        recentContacts = SearchableUser.sampleUsers.shuffled().prefix(4).map { $0 }
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
                print("Error creating conversation: \(error)")
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
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())
                        } placeholder: {
                            Text(user.initials)
                                .font(.custom("OpenSans-Bold", size: 18))
                                .foregroundStyle(user.avatarColor)
                        }
                    } else {
                        Text(user.initials)
                            .font(.custom("OpenSans-Bold", size: 18))
                            .foregroundStyle(user.avatarColor)
                    }
                }
                
                // User Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.name)
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.primary)
                    
                    if let username = user.username {
                        Text("@\(username)")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                    
                    if !user.interests.isEmpty {
                        Text(user.interests.prefix(3).joined(separator: " • "))
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Message Button
                Button(action: onMessage) {
                    Image(systemName: "message.fill")
                        .font(.system(size: 18, weight: .semibold))
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
                        .font(.custom("OpenSans-Bold", size: 20))
                        .foregroundStyle(user.avatarColor)
                }
                
                // Name
                Text(user.name.split(separator: " ").first ?? "")
                    .font(.custom("OpenSans-SemiBold", size: 13))
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
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(color)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(.primary)
                    
                    Text(count + " members")
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
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
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
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
                                .font(.custom("OpenSans-Bold", size: 36))
                                .foregroundStyle(user.avatarColor)
                        }
                        
                        // Name and Username
                        VStack(spacing: 4) {
                            Text(user.name)
                                .font(.custom("OpenSans-Bold", size: 24))
                                .foregroundStyle(.primary)
                            
                            if let username = user.username {
                                Text("@\(username)")
                                    .font(.custom("OpenSans-Regular", size: 15))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        // Bio
                        if let bio = user.bio {
                            Text(bio)
                                .font(.custom("OpenSans-Regular", size: 15))
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
                                        .font(.custom("OpenSans-Bold", size: 16))
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
                                        .font(.custom("OpenSans-Bold", size: 16))
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
                                .font(.custom("OpenSans-Bold", size: 18))
                                .padding(.horizontal)
                            
                            FlowLayout(spacing: 8) {
                                ForEach(user.interests, id: \.self) { interest in
                                    Text(interest)
                                        .font(.custom("OpenSans-SemiBold", size: 13))
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
                            // Report user
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
                            .font(.system(size: 18, weight: .semibold))
                    }
                }
            }
        }
    }
}

// MARK: - Searchable User Model
// Note: SearchableUser is now defined in SearchableUser.swift

#Preview {
    ContactSearchView()
}
