//
//  UserSearchService.swift
//  AMENAPP
//
//  Created by Steph on 1/24/26.
//
//  Production-ready case-insensitive user search service
//

import Foundation
import FirebaseFirestore
import SwiftUI
import Combine

/// Production-level service for searching users with case-insensitive queries
@MainActor
class UserSearchService: ObservableObject {
    static let shared = UserSearchService()
    
    private let db = Firestore.firestore()
    private let searchResultsLimit = 50
    
    @Published var searchResults: [FirebaseSearchUser] = []
    @Published var isSearching: Bool = false
    @Published var searchError: String?
    
    private var searchTask: Task<Void, Never>?
    
    private init() {}
    
    // MARK: - Search Functions
    
    /// Search users by username or display name (case-insensitive)
    /// - Parameters:
    ///   - query: The search term
    ///   - searchType: Whether to search by username, display name, or both
    func searchUsers(query: String, searchType: SearchType = .both) async throws -> [FirebaseSearchUser] {
        // Cancel any ongoing search
        searchTask?.cancel()
        
        guard !query.isEmpty else {
            searchResults = []
            return []
        }
        
        isSearching = true
        searchError = nil
        
        defer {
            isSearching = false
        }
        
        do {
            let results: [FirebaseSearchUser]
            
            switch searchType {
            case .username:
                results = try await searchByUsername(query)
            case .displayName:
                results = try await searchByDisplayName(query)
            case .both:
                // Search both and combine results
                async let usernameResults = searchByUsername(query)
                async let displayNameResults = searchByDisplayName(query)
                
                let combined = try await usernameResults + displayNameResults
                
                // Remove duplicates based on userId
                results = combined.uniqued(by: \.id)
            }
            
            searchResults = results
            return results
            
        } catch {
            searchError = error.localizedDescription
            searchResults = []
            throw error
        }
    }
    
    /// Search users by username prefix (case-insensitive)
    private func searchByUsername(_ query: String) async throws -> [FirebaseSearchUser] {
        let lowercaseQuery = query.lowercased().trimmingCharacters(in: .whitespaces)
        
        guard !lowercaseQuery.isEmpty else {
            return []
        }
        
        let snapshot = try await db.collection("users")
            .whereField("usernameLowercase", isGreaterThanOrEqualTo: lowercaseQuery)
            .whereField("usernameLowercase", isLessThan: lowercaseQuery + "\u{f8ff}")
            .order(by: "usernameLowercase")
            .limit(to: searchResultsLimit)
            .getDocuments()
        
        return parseSearchResults(snapshot)
    }
    
    /// Search users by display name prefix (case-insensitive)
    private func searchByDisplayName(_ query: String) async throws -> [FirebaseSearchUser] {
        let lowercaseQuery = query.lowercased().trimmingCharacters(in: .whitespaces)
        
        guard !lowercaseQuery.isEmpty else {
            return []
        }
        
        let snapshot = try await db.collection("users")
            .whereField("displayNameLowercase", isGreaterThanOrEqualTo: lowercaseQuery)
            .whereField("displayNameLowercase", isLessThan: lowercaseQuery + "\u{f8ff}")
            .order(by: "displayNameLowercase")
            .limit(to: searchResultsLimit)
            .getDocuments()
        
        return parseSearchResults(snapshot)
    }
    
    /// Search for exact username match (case-insensitive)
    func findUserByExactUsername(_ username: String) async throws -> FirebaseSearchUser? {
        let lowercaseUsername = username.lowercased().trimmingCharacters(in: .whitespaces)
        
        let snapshot = try await db.collection("users")
            .whereField("usernameLowercase", isEqualTo: lowercaseUsername)
            .limit(to: 1)
            .getDocuments()
        
        return parseSearchResults(snapshot).first
    }
    
    /// Debounced search for real-time search as user types
    func debouncedSearch(query: String, searchType: SearchType = .both, delay: Duration = .milliseconds(300)) {
        // Cancel previous search
        searchTask?.cancel()
        
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        // Create new search task with delay
        searchTask = Task {
            do {
                try await Task.sleep(for: delay)
                
                // Check if cancelled
                try Task.checkCancellation()
                
                // Perform search
                _ = try await searchUsers(query: query, searchType: searchType)
                
            } catch is CancellationError {
                // Search was cancelled, do nothing
            } catch {
                searchError = error.localizedDescription
            }
        }
    }
    
    /// Clear search results
    func clearSearch() {
        searchTask?.cancel()
        searchResults = []
        searchError = nil
        isSearching = false
    }
    
    /// Fetch suggested users for discovery (random or based on criteria)
    func fetchSuggestedUsers(limit: Int = 20) async throws -> [FirebaseSearchUser] {
        // Fetch random users from Firestore
        // Note: For better suggestions, you could implement:
        // - Users with similar interests
        // - Users nearby (location-based)
        // - Popular/verified users
        // - Users the current user's friends follow
        
        let snapshot = try await db.collection("users")
            .limit(to: limit)
            .getDocuments()
        
        return parseSearchResults(snapshot)
    }
    
    // MARK: - Helper Functions
    
    private func parseSearchResults(_ snapshot: QuerySnapshot) -> [FirebaseSearchUser] {
        var users: [FirebaseSearchUser] = []
        
        for document in snapshot.documents {
            let data = document.data()
            
            guard let username = data["username"] as? String,
                  let displayName = data["displayName"] as? String else {
                print("⚠️ User \(document.documentID) missing required fields")
                continue
            }
            
            let profileImageURL = data["profileImageURL"] as? String
            let bio = data["bio"] as? String
            let isVerified = data["isVerified"] as? Bool ?? false
            
            users.append(FirebaseSearchUser(
                id: document.documentID,
                username: username,
                displayName: displayName,
                profileImageURL: profileImageURL,
                bio: bio,
                isVerified: isVerified
            ))
        }
        
        return users
    }
}

// MARK: - Supporting Types

public enum SearchType {
    case username
    case displayName
    case both
}

/// Canonical definition of FirebaseSearchUser for user search
/// This is the ONLY definition - if you see ambiguity errors, search for other definitions and remove them
public struct FirebaseSearchUser: Identifiable, Hashable {
    public let id: String
    public let username: String
    public let displayName: String
    public let profileImageURL: String?
    public let bio: String?
    public let isVerified: Bool
    
    public init(id: String, username: String, displayName: String, profileImageURL: String?, bio: String?, isVerified: Bool) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.profileImageURL = profileImageURL
        self.bio = bio
        self.isVerified = isVerified
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: FirebaseSearchUser, rhs: FirebaseSearchUser) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Array Extension for Removing Duplicates

extension Array {
    func uniqued<T: Hashable>(by keyPath: KeyPath<Element, T>) -> [Element] {
        var seen = Set<T>()
        return filter { element in
            let value = element[keyPath: keyPath]
            if seen.contains(value) {
                return false
            } else {
                seen.insert(value)
                return true
            }
        }
    }
}

// MARK: - SwiftUI Search View

/// Production-ready user search view with real-time search
struct UserSearchView: View {
    @StateObject private var searchService = UserSearchService.shared
    @State private var searchQuery: String = ""
    @State private var selectedSearchType: SearchType = .both
    @Environment(\.dismiss) private var dismiss
    
    var onUserSelected: ((FirebaseSearchUser) -> Void)?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Type Picker
                Picker("Search Type", selection: $selectedSearchType) {
                    Text("Both").tag(SearchType.both)
                    Text("Username").tag(SearchType.username)
                    Text("Display Name").tag(SearchType.displayName)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Search Results
                if searchQuery.isEmpty {
                    emptyStateView
                } else if searchService.isSearching {
                    loadingView
                } else if let error = searchService.searchError {
                    errorView(error)
                } else if searchService.searchResults.isEmpty {
                    noResultsView
                } else {
                    searchResultsList
                }
            }
            .navigationTitle("Search Users")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchQuery, prompt: "Search by username or name...")
            .onChange(of: searchQuery) { oldValue, newValue in
                searchService.debouncedSearch(query: newValue, searchType: selectedSearchType)
            }
            .onChange(of: selectedSearchType) { oldValue, newValue in
                if !searchQuery.isEmpty {
                    searchService.debouncedSearch(query: searchQuery, searchType: newValue)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var searchResultsList: some View {
        List {
            ForEach(searchService.searchResults) { user in
                UserSearchResultRow(user: user)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onUserSelected?(user)
                        dismiss()
                    }
            }
        }
        .listStyle(.plain)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("Search for Users")
                .font(.custom("OpenSans-SemiBold", size: 18))
            
            Text("Enter a username or display name to find users")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Searching...")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(.red)
            
            Text("Search Error")
                .font(.custom("OpenSans-SemiBold", size: 18))
            
            Text(error)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button("Try Again") {
                searchService.debouncedSearch(query: searchQuery, searchType: selectedSearchType)
            }
            .font(.custom("OpenSans-SemiBold", size: 15))
            .foregroundStyle(.blue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var noResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("No Users Found")
                .font(.custom("OpenSans-SemiBold", size: 18))
            
            Text("Try a different search term")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - User Search Result Row

struct UserSearchResultRow: View {
    let user: FirebaseSearchUser
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile Image
            if let profileImageURL = user.profileImageURL, let url = URL(string: profileImageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 50, height: 50)
                            .overlay {
                                ProgressView()
                            }
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 50, height: 50)
                            .clipShape(Circle())
                    case .failure:
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 50, height: 50)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(.gray)
                            }
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .overlay {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.gray)
                    }
            }
            
            // User Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(user.displayName)
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(.primary)
                    
                    if user.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.blue)
                    }
                }
                
                Text("@\(user.username)")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                
                if let bio = user.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Messaging Search View (Simplified for selecting users to message)
// NOTE: MessagingUserSearchView has been moved to its own file: MessagingUserSearchView.swift
// The implementation below is commented out to avoid redeclaration errors.

/*
struct MessagingUserSearchView: View {
    @StateObject private var searchService = UserSearchService.shared
    @State private var searchQuery: String = ""
    @Environment(\.dismiss) private var dismiss
    
    var onUserSelected: (FirebaseSearchUser) -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if searchQuery.isEmpty {
                    emptyStateView
                } else if searchService.isSearching {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchService.searchResults.isEmpty {
                    noResultsView
                } else {
                    List {
                        ForEach(searchService.searchResults) { user in
                            UserSearchResultRow(user: user)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onUserSelected(user)
                                    // Don't dismiss here - let parent handle dismissal after conversation is ready
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchQuery, prompt: "Search users...")
            .onChange(of: searchQuery) { oldValue, newValue in
                searchService.debouncedSearch(query: newValue)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-Regular", size: 16))
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("Start a Conversation")
                .font(.custom("OpenSans-SemiBold", size: 18))
            
            Text("Search for a user to send them a message")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var noResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("No Users Found")
                .font(.custom("OpenSans-SemiBold", size: 18))
            
            Text("Try a different search term")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
*/

#Preview("Search View") {
    UserSearchView()
}

#Preview("Messaging Search") {
    MessagingUserSearchView { user in
        print("Selected user: \(user.displayName)")
    }
}
