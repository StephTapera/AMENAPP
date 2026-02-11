//
//  MutualConnectionsFeature.swift
//  AMENAPP
//
//  Production-ready Mutual Connections Badge
//  Shows stacked avatars of mutual followers (LinkedIn-style)
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Mutual Connections Data Model

struct MutualConnection: Identifiable {
    let id: String
    let displayName: String
    let username: String
    let profileImageURL: String?
    let initials: String
}

// MARK: - Mutual Connections Service

@MainActor
class MutualConnectionsService: ObservableObject {
    static let shared = MutualConnectionsService()

    private let db = Firestore.firestore()
    private var cache: [String: [MutualConnection]] = [:]

    private init() {}

    /// Get mutual followers between current user and target user
    func getMutualConnections(userId: String) async throws -> [MutualConnection] {
        // Check cache first
        if let cached = cache[userId] {
            return cached
        }

        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return []
        }

        // Don't show mutuals for yourself
        guard userId != currentUserId else {
            return []
        }

        // Get current user's followers
        let myFollowersSnapshot = try await db.collection("follows")
            .whereField("followingId", isEqualTo: currentUserId)
            .getDocuments()

        let myFollowerIds = Set(myFollowersSnapshot.documents.compactMap { $0.data()["followerId"] as? String })

        // Get target user's followers
        let theirFollowersSnapshot = try await db.collection("follows")
            .whereField("followingId", isEqualTo: userId)
            .getDocuments()

        let theirFollowerIds = Set(theirFollowersSnapshot.documents.compactMap { $0.data()["followerId"] as? String })

        // Find intersection (mutual followers)
        let mutualIds = myFollowerIds.intersection(theirFollowerIds)

        guard !mutualIds.isEmpty else {
            cache[userId] = []
            return []
        }

        // Fetch user profiles for mutual followers (limit to first 10)
        var mutualConnections: [MutualConnection] = []

        for mutualId in mutualIds.prefix(10) {
            do {
                let userDoc = try await db.collection("users").document(mutualId).getDocument()

                if let data = userDoc.data() {
                    let connection = MutualConnection(
                        id: mutualId,
                        displayName: data["displayName"] as? String ?? "Unknown",
                        username: data["username"] as? String ?? "",
                        profileImageURL: data["profileImageURL"] as? String,
                        initials: data["initials"] as? String ?? "?"
                    )
                    mutualConnections.append(connection)
                }
            } catch {
                print("⚠️ Failed to fetch mutual connection \(mutualId): \(error)")
            }
        }

        // Cache results
        cache[userId] = mutualConnections

        return mutualConnections
    }

    /// Clear cache for specific user
    func clearCache(for userId: String) {
        cache.removeValue(forKey: userId)
    }

    /// Clear all cache
    func clearAllCache() {
        cache.removeAll()
    }
}

// MARK: - Mutual Connections Badge View

struct MutualConnectionsBadge: View {
    let userId: String
    @State private var mutualConnections: [MutualConnection] = []
    @State private var isLoading = true
    @State private var showFullList = false

    private let displayLimit = 3 // Show first 3 avatars

    var body: some View {
        Group {
            if isLoading {
                loadingView
            } else if !mutualConnections.isEmpty {
                contentView
            }
        }
        .task {
            await loadMutualConnections()
        }
    }

    // MARK: - Loading State

    private var loadingView: some View {
        HStack(spacing: -8) {
            ForEach(0..<2, id: \.self) { _ in
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
        }
        .redacted(reason: .placeholder)
        .shimmer()
    }

    // MARK: - Main Content

    private var contentView: some View {
        Button {
            showFullList = true
        } label: {
            HStack(spacing: 6) {
                // Stacked avatars
                HStack(spacing: -8) {
                    ForEach(Array(mutualConnections.prefix(displayLimit).enumerated()), id: \.element.id) { index, connection in
                        ZStack {
                            Circle()
                                .fill(.white)
                                .frame(width: 26, height: 26)

                            if let urlString = connection.profileImageURL,
                               let url = URL(string: urlString) {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 24, height: 24)
                                        .clipShape(Circle())
                                } placeholder: {
                                    initialsView(connection.initials)
                                }
                            } else {
                                initialsView(connection.initials)
                            }
                        }
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .zIndex(Double(displayLimit - index)) // Stack in order
                    }
                }

                // Count text
                Text(mutualText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.black.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.04))
                    .overlay(
                        Capsule()
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showFullList) {
            MutualConnectionsListView(connections: mutualConnections)
        }
    }

    // MARK: - Helpers

    private func initialsView(_ initials: String) -> some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color.blue.opacity(0.7), Color.purple.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 24, height: 24)
            .overlay(
                Text(initials)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            )
    }

    private var mutualText: String {
        let count = mutualConnections.count
        if count <= displayLimit {
            return "\(count) mutual"
        } else {
            return "\(displayLimit)+ mutual"
        }
    }

    private func loadMutualConnections() async {
        isLoading = true
        defer { isLoading = false }

        do {
            mutualConnections = try await MutualConnectionsService.shared.getMutualConnections(userId: userId)
        } catch {
            print("❌ Failed to load mutual connections: \(error)")
            mutualConnections = []
        }
    }
}

// MARK: - Full List View

struct MutualConnectionsListView: View {
    @Environment(\.dismiss) var dismiss
    let connections: [MutualConnection]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(connections) { connection in
                        NavigationLink {
                            UserProfileView(userId: connection.id)
                        } label: {
                            mutualConnectionRow(connection)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(16)
            }
            .background(Color(white: 0.98))
            .navigationTitle("Mutual Connections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func mutualConnectionRow(_ connection: MutualConnection) -> some View {
        HStack(spacing: 12) {
            // Avatar
            if let urlString = connection.profileImageURL,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 44, height: 44)
                }
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(connection.initials)
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundColor(.white)
                    )
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(connection.displayName)
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(.black)

                Text("@\(connection.username)")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.black.opacity(0.5))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundStyle(.black.opacity(0.3))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white)
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
    }
}

// MARK: - Shimmer Effect Extension

extension View {
    func shimmer() -> some View {
        self.modifier(ShimmerModifier())
    }
}

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        .clear,
                        .white.opacity(0.3),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 300
                }
            }
    }
}
