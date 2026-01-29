//
//  PeopleDiscoveryView.swift
//  AMENAPP
//
//  Created by Steph on 1/28/26.
//
//  View for discovering and connecting with other users
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - People Discovery View

struct PeopleDiscoveryViewNew: View {
    @StateObject private var viewModel = PeopleDiscoveryViewModelNew()
    @State private var searchText = ""
    @State private var selectedFilter: DiscoveryFilter = .suggested
    
    enum DiscoveryFilter: String, CaseIterable {
        case suggested = "Suggested"
        case recent = "Recent"
        case popular = "Popular"
        case nearby = "Nearby"
        
        var icon: String {
            switch self {
            case .suggested: return "star.fill"
            case .recent: return "clock.fill"
            case .popular: return "flame.fill"
            case .nearby: return "location.fill"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Search Bar
                    searchBarView
                    
                    // Filter Chips
                    filterChipsView
                    
                    // Content
                    if viewModel.isLoading && viewModel.users.isEmpty {
                        loadingView
                    } else if viewModel.users.isEmpty {
                        emptyStateView
                    } else {
                        usersListView
                    }
                }
                .padding(.vertical)
            }
            .background(Color(white: 0.98))
            .navigationTitle("Discover People")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                await viewModel.loadUsers(filter: selectedFilter)
            }
        }
    }
    
    // MARK: - Search Bar
    
    private var searchBarView: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField("Search people...", text: $searchText)
                .font(.custom("OpenSans-Regular", size: 16))
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: searchText) { oldValue, newValue in
                    Task {
                        await viewModel.searchUsers(query: newValue)
                    }
                }
            
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal, 20)
    }
    
    // MARK: - Filter Chips
    
    private var filterChipsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(DiscoveryFilter.allCases, id: \.self) { filter in
                    FilterChipNew(
                        filter: filter,
                        isSelected: selectedFilter == filter
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedFilter = filter
                        }
                        Task {
                            await viewModel.loadUsers(filter: filter)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Users List
    
    private var usersListView: some View {
        LazyVStack(spacing: 16) {
            ForEach(viewModel.users) { user in
                NavigationLink {
                    UserProfileView(userId: user.id ?? "")
                } label: {
                    UserDiscoveryCard(user: user)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Load more trigger
            if viewModel.hasMore && !viewModel.isLoadingMore {
                Color.clear
                    .frame(height: 20)
                    .onAppear {
                        Task {
                            await viewModel.loadMore()
                        }
                    }
            }
            
            if viewModel.isLoadingMore {
                ProgressView()
                    .padding()
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Discovering people...")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color(white: 0.95))
                    .frame(width: 120, height: 120)
                    .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
                
                Image(systemName: "person.2.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.secondary)
            }
            
            Text("No users found")
                .font(.custom("OpenSans-Bold", size: 20))
            
            Text("Try adjusting your filters or search query")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Filter Chip

struct FilterChipNew: View {
    let filter: PeopleDiscoveryViewNew.DiscoveryFilter
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: filter.icon)
                    .font(.system(size: 13, weight: .semibold))
                
                Text(filter.rawValue)
                    .font(.custom("OpenSans-Bold", size: 14))
            }
            .foregroundStyle(isSelected ? .white : .black.opacity(0.7))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? Color.black : Color.white)
                    .shadow(color: .black.opacity(isSelected ? 0.15 : 0.08), radius: isSelected ? 12 : 8, x: 0, y: isSelected ? 6 : 4)
            )
            .scaleEffect(isSelected ? 1.05 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - User Discovery Card

struct UserDiscoveryCard: View {
    let user: UserModel
    @State private var isFollowing = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.black)
                    .frame(width: 60, height: 60)
                
                if let profileImageURL = user.profileImageURL, !profileImageURL.isEmpty {
                    AsyncImage(url: URL(string: profileImageURL)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                        default:
                            Text(user.initials)
                                .font(.custom("OpenSans-Bold", size: 22))
                                .foregroundStyle(.white)
                        }
                    }
                } else {
                    Text(user.initials)
                        .font(.custom("OpenSans-Bold", size: 22))
                        .foregroundStyle(.white)
                }
            }
            
            // User Info
            VStack(alignment: .leading, spacing: 6) {
                Text(user.displayName)
                    .font(.custom("OpenSans-Bold", size: 17))
                    .foregroundStyle(.black)
                
                Text("@\(user.username)")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                
                if let bio = user.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.black.opacity(0.7))
                        .lineLimit(2)
                        .padding(.top, 2)
                }
                
                // Stats
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Text("\(user.followersCount)")
                            .font(.custom("OpenSans-Bold", size: 13))
                        Text("followers")
                            .font(.custom("OpenSans-Regular", size: 13))
                    }
                    .foregroundStyle(.secondary)
                    
                    HStack(spacing: 4) {
                        Text("\(user.postsCount)")
                            .font(.custom("OpenSans-Bold", size: 13))
                        Text("posts")
                            .font(.custom("OpenSans-Regular", size: 13))
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            
            Spacer()
            
            // Follow Button
            CompactFollowButton(isFollowing: $isFollowing)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
        )
        .task {
            // Load follow status when card appears
            await loadFollowStatus()
        }
    }
    
    private func loadFollowStatus() async {
        guard let userId = user.id,
              let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let doc = try await Firestore.firestore()
                .collection("users")
                .document(currentUserId)
                .collection("following")
                .document(userId)
                .getDocument()
            
            isFollowing = doc.exists
        } catch {
            print("❌ Failed to load follow status: \(error)")
        }
    }
}

// MARK: - Compact Follow Button

struct CompactFollowButton: View {
    @Binding var isFollowing: Bool
    @State private var isPressed = false
    
    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isFollowing.toggle()
                
                let haptic = UIImpactFeedbackGenerator(style: isFollowing ? .medium : .light)
                haptic.impactOccurred()
            }
        } label: {
            HStack(spacing: 4) {
                if !isFollowing {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                }
                Text(isFollowing ? "Following" : "Follow")
                    .font(.custom("OpenSans-Bold", size: 12))
            }
            .foregroundStyle(isFollowing ? Color.secondary : Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isFollowing ? Color.clear : Color.black)
                    .overlay(
                        Capsule()
                            .stroke(isFollowing ? Color.secondary.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - View Model

@MainActor
class PeopleDiscoveryViewModelNew: ObservableObject {
    @Published var users: [UserModel] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var hasMore = true
    @Published var error: String?
    
    private let db = Firestore.firestore()
    private var lastDocument: DocumentSnapshot?
    private let pageSize = 20
    
    func loadUsers(filter: PeopleDiscoveryViewNew.DiscoveryFilter) async {
        isLoading = true
        lastDocument = nil
        
        do {
            users = try await fetchUsers(filter: filter, limit: pageSize)
            hasMore = users.count >= pageSize
        } catch {
            self.error = error.localizedDescription
            print("❌ Failed to load users: \(error)")
        }
        
        isLoading = false
    }
    
    func loadMore() async {
        guard !isLoadingMore && hasMore else { return }
        
        isLoadingMore = true
        
        do {
            let newUsers = try await fetchUsers(filter: PeopleDiscoveryViewNew.DiscoveryFilter.suggested, limit: pageSize, afterDocument: lastDocument)
            users.append(contentsOf: newUsers)
            hasMore = newUsers.count >= pageSize
        } catch {
            print("❌ Failed to load more users: \(error)")
        }
        
        isLoadingMore = false
    }
    
    func refresh() async {
        await loadUsers(filter: PeopleDiscoveryViewNew.DiscoveryFilter.suggested)
    }
    
    func searchUsers(query: String) async {
        guard !query.isEmpty else {
            await loadUsers(filter: PeopleDiscoveryViewNew.DiscoveryFilter.suggested)
            return
        }
        
        isLoading = true
        
        do {
            // Search by display name or username
            let lowercaseQuery = query.lowercased()
            
            let snapshot = try await db.collection("users")
                .whereField("username", isGreaterThanOrEqualTo: lowercaseQuery)
                .whereField("username", isLessThanOrEqualTo: lowercaseQuery + "\u{f8ff}")
                .limit(to: pageSize)
                .getDocuments()
            
            users = snapshot.documents.compactMap { try? $0.data(as: UserModel.self) }
            
            // Also search by display name if username search didn't yield many results
            if users.count < 5 {
                let nameSnapshot = try await db.collection("users")
                    .whereField("displayName", isGreaterThanOrEqualTo: query)
                    .whereField("displayName", isLessThanOrEqualTo: query + "\u{f8ff}")
                    .limit(to: pageSize)
                    .getDocuments()
                
                let nameResults = nameSnapshot.documents.compactMap { try? $0.data(as: UserModel.self) }
                
                // Merge results, avoiding duplicates
                for user in nameResults {
                    if !users.contains(where: { $0.id == user.id }) {
                        users.append(user)
                    }
                }
            }
            
            print("✅ Search found \(users.count) users for query: \(query)")
            
        } catch {
            print("❌ Search failed: \(error)")
        }
        
        isLoading = false
    }
    
    private func fetchUsers(filter: PeopleDiscoveryViewNew.DiscoveryFilter, limit: Int, afterDocument: DocumentSnapshot? = nil) async throws -> [UserModel] {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "PeopleDiscovery", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        var query = db.collection("users")
            .limit(to: limit)
        
        // Apply filter
        switch filter {
        case .suggested:
            // For now, just return recent users (you can add ML-based suggestions later)
            query = query.order(by: "createdAt", descending: true)
        case .recent:
            query = query.order(by: "createdAt", descending: true)
        case .popular:
            query = query.order(by: "followersCount", descending: true)
        case .nearby:
            // TODO: Implement location-based filtering
            query = query.order(by: "createdAt", descending: true)
        }
        
        // Pagination
        if let afterDocument = afterDocument {
            query = query.start(afterDocument: afterDocument)
        }
        
        let snapshot = try await query.getDocuments()
        lastDocument = snapshot.documents.last
        
        // Filter out current user
        let fetchedUsers = snapshot.documents.compactMap { try? $0.data(as: UserModel.self) }
        return fetchedUsers.filter { $0.id != currentUserId }
    }
}

// MARK: - Preview

#Preview {
    let view = PeopleDiscoveryViewNew()
    return view
}
