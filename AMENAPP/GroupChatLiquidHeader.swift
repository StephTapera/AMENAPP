//
//  GroupChatLiquidHeader.swift
//  AMENAPP
//
//  Premium Liquid Glass member cluster for group chats only
//  Real-time profile photo updates with lightweight animation
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Group Chat Participant Model

struct GroupChatParticipant: Identifiable, Equatable {
    let id: String
    let displayName: String
    let profileImageURL: String?
    let initials: String
    
    static func == (lhs: GroupChatParticipant, rhs: GroupChatParticipant) -> Bool {
        lhs.id == rhs.id && lhs.profileImageURL == rhs.profileImageURL
    }
}

// MARK: - Main Header View

struct GroupChatLiquidHeader: View {
    let conversationId: String
    let groupName: String
    let onTapInfo: () -> Void
    
    @State private var participants: [GroupChatParticipant] = []
    @State private var profileListeners: [String: ListenerRegistration] = [:]
    
    private let maxVisibleAvatars = 6
    
    var body: some View {
        VStack(spacing: 12) {
            // Liquid Glass member cluster
            GroupChatMemberCluster(
                participants: Array(participants.prefix(maxVisibleAvatars)),
                totalCount: participants.count,
                onTap: onTapInfo
            )
            .padding(.top, 8)
            
            // Group name
            Text(groupName)
                .font(.systemScaled(16, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.85))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .onAppear {
            loadParticipants()
        }
        .onDisappear {
            cleanupListeners()
        }
    }
    
    // MARK: - Load Participants
    
    private func loadParticipants() {
        guard Auth.auth().currentUser?.uid != nil else { return }
        
        lazy var db = Firestore.firestore()
        db.collection("conversations")
            .document(conversationId)
            .getDocument { snapshot, error in
                guard let data = snapshot?.data(),
                      let participantIds = data["participants"] as? [String] else {
                    return
                }
                
                // Load participant data and set up real-time listeners
                for participantId in participantIds {
                    loadParticipantData(participantId: participantId)
                    startProfilePhotoListener(userId: participantId)
                }
            }
    }
    
    // MARK: - Load Single Participant
    
    private func loadParticipantData(participantId: String) {
        lazy var db = Firestore.firestore()
        db.collection("users")
            .document(participantId)
            .getDocument { snapshot, error in
                guard let data = snapshot?.data() else { return }
                
                let displayName = data["displayName"] as? String ?? "User"
                let profileImageURL = data["profileImageURL"] as? String
                let initials = Self.getInitials(from: displayName)
                
                let participant = GroupChatParticipant(
                    id: participantId,
                    displayName: displayName,
                    profileImageURL: profileImageURL,
                    initials: initials
                )
                
                DispatchQueue.main.async {
                    if let index = participants.firstIndex(where: { $0.id == participantId }) {
                        participants[index] = participant
                    } else {
                        participants.append(participant)
                    }
                }
            }
    }
    
    // MARK: - Real-time Profile Photo Listener
    
    private func startProfilePhotoListener(userId: String) {
        // Prevent duplicate listeners
        guard profileListeners[userId] == nil else { return }
        
        lazy var db = Firestore.firestore()
        let listener = db.collection("users")
            .document(userId)
            .addSnapshotListener { snapshot, error in
                guard let data = snapshot?.data(),
                      let profileImageURL = data["profileImageURL"] as? String else {
                    return
                }
                
                // Update only the profile photo if it changed
                DispatchQueue.main.async {
                    if let index = participants.firstIndex(where: { $0.id == userId }) {
                        if participants[index].profileImageURL != profileImageURL {
                            participants[index] = GroupChatParticipant(
                                id: participants[index].id,
                                displayName: participants[index].displayName,
                                profileImageURL: profileImageURL,
                                initials: participants[index].initials
                            )
                        }
                    }
                }
            }
        
        profileListeners[userId] = listener
    }
    
    // MARK: - Cleanup
    
    private func cleanupListeners() {
        for (_, listener) in profileListeners {
            listener.remove()
        }
        profileListeners.removeAll()
    }
    
    // MARK: - Helper
    
    private static func getInitials(from name: String) -> String {
        let words = name.split(separator: " ")
        if words.count > 1 {
            return String(words[0].prefix(1)) + String(words[1].prefix(1))
        } else if let first = words.first {
            return String(first.prefix(2))
        }
        return "?"
    }
}

// MARK: - Member Cluster View

struct GroupChatMemberCluster: View {
    let participants: [GroupChatParticipant]
    let totalCount: Int
    let onTap: () -> Void
    
    @State private var appeared = false
    
    private var overflowCount: Int {
        max(0, totalCount - participants.count)
    }
    
    var body: some View {
        Button(action: onTap) {
            // Liquid Glass organic blob container
            ZStack {
                // Glass material background
                glassBlobBackground
                
                // Avatar bubbles
                HStack(spacing: -8) {
                    ForEach(Array(participants.enumerated()), id: \.element.id) { index, participant in
                        GroupChatMemberBubble(participant: participant)
                            .transition(.scale.combined(with: .opacity))
                            .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(Double(index) * 0.05), value: appeared)
                    }
                    
                    // Overflow count bubble
                    if overflowCount > 0 {
                        overflowBubble
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .scaleEffect(appeared ? 1 : 0.9)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(Motion.adaptive(.spring(response: 0.5, dampingFraction: 0.75))) {
                    appeared = true
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Glass Blob Background
    
    private var glassBlobBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.95),
                        Color.white.opacity(0.85)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                // Top highlight
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.6),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            )
            .overlay(
                // Border
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
            .shadow(color: Color.black.opacity(0.02), radius: 16, x: 0, y: 4)
    }
    
    // MARK: - Overflow Bubble
    
    private var overflowBubble: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.08))
                .frame(width: 40, height: 40)
            
            Text("+\(overflowCount)")
                .font(.systemScaled(13, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.6))
        }
        .overlay(
            Circle()
                .stroke(Color.white, lineWidth: 2)
        )
    }
}

// MARK: - Individual Member Bubble

struct GroupChatMemberBubble: View {
    let participant: GroupChatParticipant
    
    @State private var driftOffset: CGSize = .zero
    
    var body: some View {
        ZStack {
            // Profile photo or initials fallback
            if let urlString = participant.profileImageURL,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        initialsView
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                            .transition(.opacity)
                    case .failure:
                        initialsView
                    @unknown default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: 40, height: 40)
        .overlay(
            Circle()
                .stroke(Color.white, lineWidth: 2)
        )
        .offset(driftOffset)
        .onAppear {
            startSubtleDrift()
        }
    }
    
    // MARK: - Initials Fallback
    
    private var initialsView: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.12),
                            Color.black.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text(participant.initials)
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.5))
        }
        .frame(width: 40, height: 40)
    }
    
    // MARK: - Subtle Drift Animation
    
    private func startSubtleDrift() {
        // Very subtle floating effect - minimal CPU impact
        withAnimation(
            .easeInOut(duration: 3.0)
            .repeatForever(autoreverses: true)
        ) {
            driftOffset = CGSize(
                width: Double.random(in: -1...1),
                height: Double.random(in: -2...2)
            )
        }
    }
}
