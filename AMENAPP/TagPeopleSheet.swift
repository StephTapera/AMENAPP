import SwiftUI
import FirebaseAuth

/// Sheet for explicitly tagging people in a post (distinct from @mentions in text).
/// Selected users show as removable chips and are written to `taggedUserIds` on publish.
struct TagPeopleSheet: View {
    @Binding var taggedUsers: [MentionedUser]
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var searchResults: [AlgoliaUser] = []
    @State private var isSearching = false
    @State private var searchDebounce: Task<Void, Never>?
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search field
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                
                // Selected chips
                if !taggedUsers.isEmpty {
                    selectedChips
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    Divider()
                }
                
                // Results / empty state
                if isSearching {
                    ProgressView()
                        .padding(.top, 40)
                    Spacer()
                } else if !searchText.isEmpty && searchResults.isEmpty {
                    emptyState
                } else if searchText.isEmpty && taggedUsers.isEmpty {
                    instructionState
                } else {
                    resultsList
                }
            }
            .navigationTitle("Tag People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.custom("OpenSans-Regular", size: 16))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(taggedUsers.isEmpty ? Color.secondary : Color.purple)
                        .disabled(taggedUsers.isEmpty)
                }
            }
        }
        .onAppear { isSearchFocused = true }
        .onDisappear { searchDebounce?.cancel() }
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 16, weight: .medium))
            
            TextField("Search people to tag...", text: $searchText)
                .font(.custom("OpenSans-Regular", size: 15))
                .focused($isSearchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: searchText) { _, newValue in
                    scheduleSearch(for: newValue)
                }
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
    
    // MARK: - Selected Chips
    
    private var selectedChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(taggedUsers, id: \.userId) { user in
                    tagChip(for: user)
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private func tagChip(for user: MentionedUser) -> some View {
        HStack(spacing: 6) {
            // Avatar initial
            Circle()
                .fill(Color.purple.opacity(0.15))
                .frame(width: 24, height: 24)
                .overlay(
                    Text(user.displayName.prefix(1).uppercased())
                        .font(.custom("OpenSans-Bold", size: 11))
                        .foregroundStyle(.purple)
                )
            
            Text("@\(user.username)")
                .font(.custom("OpenSans-SemiBold", size: 13))
                .foregroundStyle(.primary)
            
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    taggedUsers.removeAll { $0.userId == user.userId }
                }
                HapticManager.impact(style: .light)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.purple.opacity(0.08))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.purple.opacity(0.2), lineWidth: 1)
                )
        )
        .transition(.scale.combined(with: .opacity))
    }
    
    // MARK: - Results List
    
    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchResults, id: \.objectID) { user in
                    let isAlreadyTagged = taggedUsers.contains { $0.userId == user.objectID }
                    
                    Button {
                        toggleTag(user: user)
                    } label: {
                        userRow(user: user, isSelected: isAlreadyTagged)
                    }
                    .buttonStyle(.plain)
                    
                    if user.objectID != searchResults.last?.objectID {
                        Divider()
                            .padding(.leading, 64)
                    }
                }
            }
            .padding(.top, 4)
        }
    }
    
    private func userRow(user: AlgoliaUser, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(Color.purple.opacity(0.12))
                .frame(width: 44, height: 44)
                .overlay(
                    Text(user.displayName.prefix(1).uppercased())
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.purple)
                )
            
            // Name + username
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(user.displayName)
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundStyle(.primary)
                    if user.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.blue)
                    }
                }
                Text("@\(user.username)")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Checkmark
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundStyle(isSelected ? Color.purple : Color(.systemGray4))
                .symbolEffect(.bounce, value: isSelected)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(isSelected ? Color.purple.opacity(0.04) : Color.clear)
    }
    
    // MARK: - Empty / Instruction States
    
    private var emptyState: some View {
        VStack {
            VStack(spacing: 12) {
                Image(systemName: "person.slash")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("No people found")
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.primary)
                Text("Try a different name or username")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 60)
            Spacer()
        }
    }
    
    private var instructionState: some View {
        VStack {
            VStack(spacing: 12) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.purple.opacity(0.6))
                Text("Tag people in your post")
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.primary)
                Text("Search by name or username. Tagged people will be notified.")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 60)
            Spacer()
        }
    }
    
    // MARK: - Actions
    
    private func toggleTag(user: AlgoliaUser) {
        withAnimation(.easeOut(duration: 0.15)) {
            if let index = taggedUsers.firstIndex(where: { $0.userId == user.objectID }) {
                taggedUsers.remove(at: index)
            } else {
                taggedUsers.append(MentionedUser(
                    userId: user.objectID,
                    username: user.username,
                    displayName: user.displayName
                ))
            }
        }
        HapticManager.impact(style: .light)
    }
    
    private func scheduleSearch(for query: String) {
        searchDebounce?.cancel()
        guard query.count >= 2 else {
            withAnimation(.easeOut(duration: 0.15)) {
                searchResults = []
                isSearching = false
            }
            return
        }
        isSearching = true
        searchDebounce = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms debounce
            guard !Task.isCancelled else { return }
            do {
                let results = try await AlgoliaSearchService.shared.searchUsers(query: query)
                // Filter out current user
                let currentUid = Auth.auth().currentUser?.uid
                withAnimation(.easeOut(duration: 0.15)) {
                    searchResults = results.filter { $0.objectID != currentUid }
                    isSearching = false
                }
            } catch {
                withAnimation { isSearching = false }
            }
        }
    }
}
