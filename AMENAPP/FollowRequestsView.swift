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
    @StateObject private var viewModel = FollowRequestsViewModel()
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
            .background(Color(white: 0.98))
            .navigationTitle("Follow Requests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
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
                .font(.custom("OpenSans-Regular", size: 15))
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
                    .font(.system(size: 50))
                    .foregroundStyle(.secondary)
            }
            
            Text("No Follow Requests")
                .font(.custom("OpenSans-Bold", size: 22))
            
            Text("When someone wants to follow you, their request will appear here")
                .font(.custom("OpenSans-Regular", size: 15))
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
        .padding(20)
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
                }
                
                // User Info
                VStack(alignment: .leading, spacing: 6) {
                    Text(user.displayName)
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.black)
                    
                    Text("@\(user.username)")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                    
                    Text(timeAgo(from: request.createdAt))
                        .font(.custom("OpenSans-Regular", size: 12))
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
                            .font(.custom("OpenSans-Bold", size: 14))
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
                            .font(.custom("OpenSans-Bold", size: 14))
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
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
        )
    }
    
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - View Model

@MainActor
class FollowRequestsViewModel: ObservableObject {
    @Published var requests: [FollowRequest] = []
    @Published var requestUsers: [String: UserModel] = [:]
    @Published var isLoading = false
    @Published var error: String?
    
    private let db = Firestore.firestore()
    
    func loadRequests() async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        isLoading = true
        
        do {
            // Fetch pending follow requests
            let snapshot = try await db.collection("followRequests")
                .whereField("toUserId", isEqualTo: currentUserId)
                .whereField("status", isEqualTo: FollowRequest.RequestStatus.pending.rawValue)
                .order(by: "createdAt", descending: true)
                .getDocuments()
            
            requests = snapshot.documents.compactMap { try? $0.data(as: FollowRequest.self) }
            
            print("✅ Loaded \(requests.count) follow requests")
            
            // Fetch user data for each request
            for request in requests {
                if requestUsers[request.fromUserId] == nil {
                    await fetchUserData(userId: request.fromUserId)
                }
            }
            
        } catch {
            self.error = error.localizedDescription
            print("❌ Failed to load follow requests: \(error)")
        }
        
        isLoading = false
    }
    
    func refresh() async {
        await loadRequests()
    }
    
    func acceptRequest(_ request: FollowRequest) async {
        do {
            // Create follow relationship
            let followService = FollowService.shared
            try await followService.followUser(userId: request.fromUserId)
            
            // Update request status
            if let requestId = request.id {
                try await db.collection("followRequests").document(requestId).updateData([
                    "status": FollowRequest.RequestStatus.accepted.rawValue
                ])
            }
            
            // Remove from local array
            requests.removeAll { $0.id == request.id }
            
            print("✅ Accepted follow request from: \(request.fromUserId)")
            
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
        } catch {
            self.error = error.localizedDescription
            print("❌ Failed to accept request: \(error)")
            
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
        }
    }
    
    func rejectRequest(_ request: FollowRequest) async {
        do {
            // Update request status
            if let requestId = request.id {
                try await db.collection("followRequests").document(requestId).updateData([
                    "status": FollowRequest.RequestStatus.rejected.rawValue
                ])
            }
            
            // Remove from local array
            requests.removeAll { $0.id == request.id }
            
            print("✅ Rejected follow request from: \(request.fromUserId)")
            
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            
        } catch {
            self.error = error.localizedDescription
            print("❌ Failed to reject request: \(error)")
        }
    }
    
    private func fetchUserData(userId: String) async {
        do {
            let userDoc = try await db.collection("users").document(userId).getDocument()
            if let user = try? userDoc.data(as: UserModel.self) {
                requestUsers[userId] = user
            }
        } catch {
            print("❌ Failed to fetch user data for \(userId): \(error)")
        }
    }
}

// MARK: - Follow Request Service

@MainActor
class FollowRequestService {
    static let shared = FollowRequestService()
    private let db = Firestore.firestore()
    
    private init() {}
    
    /// Send a follow request to a user with a private account
    func sendFollowRequest(toUserId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "FollowRequestService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Check if request already exists
        let existingSnapshot = try await db.collection("followRequests")
            .whereField("fromUserId", isEqualTo: currentUserId)
            .whereField("toUserId", isEqualTo: toUserId)
            .whereField("status", isEqualTo: FollowRequest.RequestStatus.pending.rawValue)
            .limit(to: 1)
            .getDocuments()
        
        guard existingSnapshot.documents.isEmpty else {
            print("⚠️ Follow request already sent")
            return
        }
        
        // Create new request
        let request = FollowRequest(
            fromUserId: currentUserId,
            toUserId: toUserId,
            createdAt: Date(),
            status: .pending
        )
        
        try db.collection("followRequests").document().setData(from: request)
        
        print("✅ Follow request sent to: \(toUserId)")
        
        // Send notification
        try await createFollowRequestNotification(toUserId: toUserId)
    }
    
    /// Check if a follow request is pending
    func hasPendingRequest(toUserId: String) async -> Bool {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return false
        }
        
        do {
            let snapshot = try await db.collection("followRequests")
                .whereField("fromUserId", isEqualTo: currentUserId)
                .whereField("toUserId", isEqualTo: toUserId)
                .whereField("status", isEqualTo: FollowRequest.RequestStatus.pending.rawValue)
                .limit(to: 1)
                .getDocuments()
            
            return !snapshot.documents.isEmpty
        } catch {
            print("❌ Error checking pending request: \(error)")
            return false
        }
    }
    
    /// Cancel a pending follow request
    func cancelFollowRequest(toUserId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "FollowRequestService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let snapshot = try await db.collection("followRequests")
            .whereField("fromUserId", isEqualTo: currentUserId)
            .whereField("toUserId", isEqualTo: toUserId)
            .whereField("status", isEqualTo: FollowRequest.RequestStatus.pending.rawValue)
            .limit(to: 1)
            .getDocuments()
        
        for document in snapshot.documents {
            try await document.reference.delete()
        }
        
        print("✅ Cancelled follow request to: \(toUserId)")
    }
    
    private func createFollowRequestNotification(toUserId: String) async throws {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        // Fetch current user's name
        let userDoc = try await db.collection("users").document(currentUserId).getDocument()
        let displayName = userDoc.data()?["displayName"] as? String ?? "Someone"
        
        let notification: [String: Any] = [
            "userId": toUserId,
            "type": "followRequest",
            "fromUserId": currentUserId,
            "fromUserName": displayName,
            "message": "\(displayName) wants to follow you",
            "createdAt": Date(),
            "isRead": false
        ]
        
        try await db.collection("notifications").addDocument(data: notification)
        
        print("✅ Follow request notification created for user: \(toUserId)")
    }
}

// MARK: - Preview

#Preview {
    FollowRequestsView()
}
