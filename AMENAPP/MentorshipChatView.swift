// MentorshipChatView.swift
// AMENAPP
// Reuses UnifiedChatView for 1:1 mentorship messaging.
// Collection path: mentorshipChats/{chatId}/messages

import SwiftUI
import FirebaseAuth

struct MentorshipChatView: View {
    let chatId: String
    let mentorName: String
    let mentorPhotoURL: String?
    let pendingCheckIn: MentorshipCheckIn?

    @Environment(\.dismiss) private var dismiss
    @State private var showCheckIn = false

    /// Build a ChatConversation suitable for UnifiedChatView
    private var conversation: ChatConversation {
        let uid = Auth.auth().currentUser?.uid ?? ""
        return ChatConversation(
            id: chatId,
            name: mentorName,
            lastMessage: "",
            timestamp: "",
            isGroup: false,
            unreadCount: 0,
            avatarColor: Color(red: 0.49, green: 0.23, blue: 0.93),
            status: "accepted",
            profilePhotoURL: mentorPhotoURL,
            isPinned: false,
            isMuted: false,
            requesterId: nil,
            otherParticipantId: nil,
            source: .direct,
            otherUserBio: nil,
            otherUserUsername: nil
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Pending check-in banner
            if let checkIn = pendingCheckIn {
                HStack(spacing: 10) {
                    Image(systemName: "checklist")
                        .foregroundStyle(Color(red: 0.49, green: 0.23, blue: 0.93))
                    Text("Check-in due: \"\(String(checkIn.prompt.prefix(40)))...\"")
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer()
                    Button("Respond") { showCheckIn = true }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(red: 0.49, green: 0.23, blue: 0.93))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(red: 0.49, green: 0.23, blue: 0.93).opacity(0.06))
            }

            // Reuse existing UnifiedChatView with the mentorship chat conversationId
            UnifiedChatView(conversation: conversation)
        }
        .navigationTitle(mentorName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCheckIn) {
            if let ci = pendingCheckIn {
                CheckInView(checkIn: ci, onComplete: { showCheckIn = false })
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // Book session — placeholder for calendly/in-app scheduler
                    dlog("📅 Book session tapped")
                } label: {
                    Label("Book", systemImage: "calendar.badge.plus")
                        .font(.system(size: 14))
                }
            }
        }
    }
}
