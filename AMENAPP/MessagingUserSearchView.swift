//
//  MessagingUserSearchView.swift
//  AMENAPP
//
//  User search specifically for starting new message conversations
//

import SwiftUI
import FirebaseAuth

struct MessagingUserSearchView: View {
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var searchResults: [ContactUser] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    
    let onUserSelected: (ContactUser) -> Void
    
    private let messagingService = FirebaseMessagingService.shared
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar
                searchBar
                    .padding()
                    .background(Color(.systemGroupedBackground))
                
                // Results
                if isSearching {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    errorView(error)
                } else if searchText.isEmpty {
                    emptySearchView
                } else if searchResults.isEmpty {
                    noResultsView
                } else {
                    searchResultsList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("New Message")
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
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                
                TextField("Search by name or username", text: $searchText)
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
                            errorMessage = nil
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
        .onChange(of: searchText) { _, newValue in
            if !newValue.isEmpty {
                // Debounce search
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
                    if searchText == newValue {
                        performSearch()
                    }
                }
            } else {
                searchResults = []
                errorMessage = nil
            }
        }
    }
    
    // MARK: - Views
    
    private var emptySearchView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: 100, height: 100)
                    .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
                
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text("Search for people")
                    .font(.custom("OpenSans-Bold", size: 22))
                    .foregroundStyle(.primary)
                
                Text("Find someone to start a conversation with")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var noResultsView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: 100, height: 100)
                    .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
                
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.gray, .gray.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text("No users found")
                    .font(.custom("OpenSans-Bold", size: 22))
                    .foregroundStyle(.primary)
                
                Text("Try searching with a different name or username")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundStyle(.red)
            
            Text(message)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button {
                performSearch()
            } label: {
                Text("Try Again")
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.blue)
                    )
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchResults) { user in
                    Button {
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                        onUserSelected(user)
                        dismiss()
                    } label: {
                        MessagingUserRow(user: user)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    if user.id != searchResults.last?.id {
                        Divider()
                            .padding(.leading, 80)
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
    
    private func performSearch() {
        guard !searchText.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        errorMessage = nil
        
        Task {
            do {
                let users = try await messagingService.searchUsers(query: searchText)
                
                await MainActor.run {
                    searchResults = users
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    print("❌ Error searching users: \(error)")
                    errorMessage = "Unable to search users. Please check your connection and try again."
                    searchResults = []
                    isSearching = false
                }
            }
        }
    }
}

// MARK: - Messaging User Row

struct MessagingUserRow: View {
    let user: ContactUser
    
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
            // Avatar
            ZStack {
                Circle()
                    .fill(avatarColor.opacity(0.15))
                    .frame(width: 56, height: 56)
                
                if let avatarUrl = user.profileImageURL, let url = URL(string: avatarUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                    } placeholder: {
                        Text(initials)
                            .font(.custom("OpenSans-Bold", size: 18))
                            .foregroundStyle(avatarColor)
                    }
                } else {
                    Text(initials)
                        .font(.custom("OpenSans-Bold", size: 18))
                        .foregroundStyle(avatarColor)
                }
            }
            
            // User Info
            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName)
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.primary)
                
                Text("@\(user.username)")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                
                if user.showActivityStatus {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        
                        Text("Active")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.green)
                    }
                }
            }
            
            Spacer()
            
            // Message indicator
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

#Preview {
    MessagingUserSearchView { user in
        print("Selected user: \(user.displayName)")
    }
}
