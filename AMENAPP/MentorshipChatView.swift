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
    @State private var showBookingAlert = false

    /// Build a ChatConversation suitable for UnifiedChatView
    private var conversation: ChatConversation {
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
                        .font(.systemScaled(12))
                        .lineLimit(1)
                    Spacer()
                    Button("Respond") { showCheckIn = true }
                        .font(.systemScaled(12, weight: .semibold))
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
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showBookingAlert = true
                } label: {
                    Label("Book", systemImage: "calendar.badge.plus")
                        .font(.systemScaled(14))
                }
            }
        }
        .alert("Book a Session", isPresented: $showBookingAlert) {
            Button("Send Request in Chat") {
                // Insert a booking request message into the conversation
                NotificationCenter.default.post(
                    name: Notification.Name("MentorshipBookingRequest"),
                    object: nil,
                    userInfo: ["chatId": chatId, "mentorName": mentorName,
                               "message": "Hi \(mentorName), I'd like to book a mentorship session. When are you available?"]
                )
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Send a scheduling request to \(mentorName) through the chat.")
        }
    }
}
