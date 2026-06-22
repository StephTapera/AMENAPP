//
//  FollowRequestsView.swift
//  AMENAPP
//
//  Created by Steph on 1/28/26.
//
//  Manage follow requests for private accounts
//

import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

// MARK: - Follow Request Model

struct FollowRequest: Identifiable, Codable {
    @DocumentID var id: String?
    let fromUserId: String
    let toUserId: String
    let createdAt: Date
    var status: RequestStatus
    
    enum RequestStatus: String, Codable {
        case pending
        case accepted
        case rejected
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case fromUserId
        case toUserId
        case createdAt
        case status
    }
}

// MARK: - Follow Requests View

struct FollowRequestsView: View {
    @ObservedObject private var viewModel = FollowRequestsViewModel.shared  // P0 FIX: Use singleton
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.isLoading {
                    loadingView
                } else if viewModel.requests.isEmpty {
                    emptyStateView
                } else {
                    requestsListView
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Follow Requests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(AMENFont.semiBold(16))
                }
            }
            .task {
                await viewModel.loadRequests()
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Loading requests...")
                .font(AMENFont.regular(15))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color(white: 0.95))
                    .frame(width: 120, height: 120)
                    .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
                
                Image(systemName: "person.badge.clock")
                    .font(.systemScaled(50))
                    .foregroundStyle(.secondary)
            }
            
            Text("No Follow Requests")
                .font(AMENFont.bold(22))
            
            Text("When someone wants to follow you, their request will appear here")
                .font(AMENFont.regular(15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }
    
    // MARK: - Requests List
    
    private var requestsListView: some View {
        LazyVStack(spacing: 16) {
            ForEach(viewModel.requests) { request in
                FollowRequestCard(
                    request: request,
                    user: viewModel.requestUsers[request.fromUserId],
                    onAccept: {
                        Task {
                            await viewModel.acceptRequest(request)
                        }
                    },
                    onReject: {
                        Task {
                            await viewModel.rejectRequest(request)
                        }
                    }
                )
            }
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Follow Request Card

struct FollowRequestCard: View {
    let request: FollowRequest
    let user: UserModel?
    let onAccept: () -> Void
    let onReject: () -> Void
    
    @State private var isProcessing = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Avatar
            if let user = user {
                NavigationLink(destination: UserProfileView(userId: request.fromUserId)) {
                    ZStack {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 60, height: 60)
                        
                        if let profileImageURL = user.profileImageURL, !profileImageURL.isEmpty {
                            CachedAsyncImage(url: URL(string: profileImageURL)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .clipShape(Circle())
                            } placeholder: {
                                Text(user.initials)
                                    .font(AMENFont.bold(22))
                                    .foregroundStyle(.white)
                            }
                        } else {
                            Text(user.initials)
                                .font(AMENFont.bold(22))
                                .foregroundStyle(.white)
                        }
                    }
                }
                
                // User Info
                VStack(alignment: .leading, spacing: 6) {
                    Text(user.displayName)
                        .font(AMENFont.bold(16))
                        .foregroundStyle(.primary)
                    
                    Text("@\(user.username)")
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.secondary)
                    
                    Text(timeAgo(from: request.createdAt))
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                }
            } else {
                // Loading placeholder
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 60, height: 60)
                
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 120, height: 16)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 80, height: 14)
                }
            }
            
            Spacer()
            
            // Action Buttons
            if !isProcessing {
                VStack(spacing: 8) {
                    Button {
                        isProcessing = true
                        onAccept()
                    } label: {
                        Text("Accept")
                            .font(AMENFont.bold(14))
                            .foregroundStyle(.white)
                            .frame(width: 80)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.blue)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button {
                        isProcessing = true
                        onReject()
                    } label: {
                        Text("Decline")
                            .font(AMENFont.bold(14))
                            .foregroundStyle(.black.opacity(0.6))
                            .frame(width: 80)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(white: 0.93))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            } else {
                ProgressView()
                    .frame(width: 80)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
        .padding(.horizontal, 16)
    }
    
    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private func timeAgo(from date: Date) -> String {
        Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - View Model

@MainActor
class FollowRequestsViewModel: ObservableObject {
    // P0 FIX: Make singleton to prevent duplicate initialization
    static let shared = FollowRequestsViewModel()
    
    @Published var requests: [FollowRequest] = []
    @Published var requestUsers: [String: UserModel] = [:]
    @Published var isLoading = false
    @Published var error: String?
    
    // Track in-flight requests to prevent duplicates and drive spinner UI
    private var processingRequestIds: Set<String> = [] {
        willSet { objectWillChange.send() }
    }
    
    private lazy var db = Firestore.firestore()
    
    // P0 FIX: Private initializer for singleton pattern
    private init() {}
    
    func loadRequests() async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        isLoading = true
        
        do {
            // Fetch pending follow requests from server-authoritative subcollection path.
            // createFollow callable writes requests to users/{uid}/followRequests/{requesterId}.
            let snapshot = try await db.collection("users").document(currentUserId)
                .collection("followRequests")
                .whereField("status", isEqualTo: FollowRequest.RequestStatus.pending.rawValue)
                .order(by: "createdAt", descending: true)
                .getDocuments()
            
            requests = snapshot.documents.compactMap { doc in
                do {
                    return try doc.data(as: FollowRequest.self)
                } catch {
                    dlog("⚠️ Failed to parse follow request \(doc.documentID): \(error)")
                    return nil
                }
            }
            
            dlog("✅ Loaded \(requests.count) follow requests")
            
            // Fetch user data for each request with concurrency limiting
            await withTaskGroup(of: Void.self) { group in
                for request in requests {
                    if requestUsers[request.fromUserId] == nil {
                        group.addTask {
                            await self.fetchUserData(userId: request.fromUserId)
                        }
                    }
                }
            }
            
        } catch {
            self.error = error.localizedDescription
            dlog("❌ Failed to load follow requests: \(error)")
        }
        
        isLoading = false
    }
    
    func refresh() async {
        await loadRequests()
    }
    
    func acceptRequest(_ request: FollowRequest) async {
        // Guard against duplicate taps
        guard let requestId = request.id else {
            dlog("⚠️ Cannot process request without ID")
            return
        }
        
        guard !processingRequestIds.contains(requestId) else {
            dlog("⚠️ Request already processing: \(requestId)")
            return
        }
        
        processingRequestIds.insert(requestId)
        defer { processingRequestIds.remove(requestId) }
        
        do {
            // acceptFollowRequest callable: atomically deletes request, creates follow+index, updates counters.
            let callable = Functions.functions(region: "us-central1").httpsCallable("acceptFollowRequest")
            _ = try await callable.call(["requesterId": request.fromUserId])

            requests.removeAll { $0.id == request.id }
            dlog("✅ Accepted follow request via CF: \(request.fromUserId)")

            PrivacyAccessControl.shared.invalidate(userId: request.fromUserId)
            NotificationCenter.default.post(
                name: .followRelationshipChanged,
                object: nil,
                userInfo: ["userId": request.fromUserId]
            )
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
        } catch {
            self.error = error.localizedDescription
            dlog("❌ Failed to accept request: \(error)")
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
        }
    }
    
    func rejectRequest(_ request: FollowRequest) async {
        // ✅ P0-3: Guard against duplicate taps
        guard let requestId = request.id else {
            dlog("⚠️ Cannot process request without ID")
            return
        }
        
        guard !processingRequestIds.contains(requestId) else {
            dlog("⚠️ Request already processing: \(requestId)")
            return
        }
        
        processingRequestIds.insert(requestId)
        defer { processingRequestIds.remove(requestId) }
        
        do {
            // rejectFollowRequest callable: deletes from users/{uid}/followRequests/{requesterId}
            let callable = Functions.functions(region: "us-central1").httpsCallable("rejectFollowRequest")
            _ = try await callable.call(["requesterId": request.fromUserId])

            requests.removeAll { $0.id == request.id }
            dlog("✅ Rejected follow request via CF: \(request.fromUserId)")
            PrivacyAccessControl.shared.invalidate(userId: request.fromUserId)
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
        } catch {
            self.error = error.localizedDescription
            dlog("❌ Failed to reject request: \(error)")
        }
    }
    
    private func fetchUserData(userId: String) async {
        do {
            let userDoc = try await db.collection("users").document(userId).getDocument()
            if let user = try? userDoc.data(as: UserModel.self) {
                requestUsers[userId] = user
            }
        } catch {
            dlog("❌ Failed to fetch user data for \(userId): \(error)")
        }
    }
}

// MARK: - Follow Request Service

@MainActor
class FollowRequestService {
    static let shared = FollowRequestService()
    private lazy var db = Firestore.firestore()
    
    private init() {}
    
    /// Send a follow request to a user with a private account
    func sendFollowRequest(toUserId: String) async throws {
        guard Auth.auth().currentUser?.uid != nil else {
            throw NSError(domain: "FollowRequestService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Route through createFollow callable — handles private/public routing, idempotency,
        // subcollection write (users/{uid}/followRequests/{requesterId}), and server notification.
        let callable = Functions.functions(region: "us-central1").httpsCallable("createFollow")
        _ = try await callable.call(["followingId": toUserId])
        dlog("✅ Follow request sent via CF: \(toUserId)")
    }
    
    /// Check if a follow request is pending
    func hasPendingRequest(toUserId: String) async -> Bool {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return false
        }
        
        do {
            // Check subcollection path used by createFollow callable
            let doc = try await db.collection("users").document(toUserId)
                .collection("followRequests").document(currentUserId).getDocument()
            return doc.exists && (doc.data()?["status"] as? String) == "pending"
        } catch {
            dlog("❌ Error checking pending request: \(error)")
            return false
        }
    }
    
    /// Cancel a pending follow request
    func cancelFollowRequest(toUserId: String) async throws {
        // cancelFollowRequest callable deletes from users/{targetId}/followRequests/{requesterId}
        let callable = Functions.functions(region: "us-central1").httpsCallable("cancelFollowRequest")
        _ = try await callable.call(["targetId": toUserId])
        dlog("✅ Cancelled follow request via CF: \(toUserId)")
    }
}

// MARK: - Preview

#Preview {
    FollowRequestsView()
}
