//
//  AIBibleStudyExtensions.swift
//  AMENAPP
//
//  Helper functions and additional views for AI Bible Study
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Helper Functions Extension

extension AIBibleStudyView {

    func clearConversation() {
        // Save current conversation before clearing
        if !messages.isEmpty {
            conversationHistory.append(messages)
        }

        withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.7))) {
            messages = []
        }

        // Add welcome message back
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(Motion.adaptive(.spring(response: 0.6, dampingFraction: 0.8))) {
                messages.append(AIStudyMessage(
                    text: "New conversation started! How can I help you study Scripture today?",
                    isUser: false
                ))
            }
        }

        // Haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }

    func saveCurrentConversation() {
        if messages.count > 1 { // More than just the welcome message
            conversationHistory.append(messages)

            // Save to Firestore
            Task {
                do {
                    try await saveConversationToFirestore(messages: messages)
                    dlog("💾 Saved conversation with \(messages.count) messages to Firestore")
                } catch {
                    dlog("❌ Failed to save conversation: \(error)")
                }
            }
        }
    }

    private func saveConversationToFirestore(messages: [AIStudyMessage]) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "AIBibleStudy", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }

        lazy var db = Firestore.firestore()

        // Create conversation document
        let conversationData: [String: Any] = [
            "userId": userId,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "messageCount": messages.count,
            "preview": messages.first(where: { $0.isUser })?.text.prefix(100) ?? "New conversation"
        ]

        let conversationRef = try await db.collection("aiBibleStudyConversations")
            .addDocument(data: conversationData)

        // Save messages as subcollection
        let batch = db.batch()
        for (index, message) in messages.enumerated() {
            let messageRef = conversationRef.collection("messages").document("\(index)")
            let messageData: [String: Any] = [
                "text": message.text,
                "isUser": message.isUser,
                "timestamp": FieldValue.serverTimestamp(),
                "index": index
            ]
            batch.setData(messageData, forDocument: messageRef)
        }

        try await batch.commit()
        dlog("✅ Saved conversation \(conversationRef.documentID) with \(messages.count) messages")
    }

    func loadConversation(_ conversation: [AIStudyMessage]) {
        withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.7))) {
            messages = conversation
            selectedTab = .chat
        }
        showHistory = false
    }

    func loadConversationsFromFirestore() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        do {
            lazy var db = Firestore.firestore()
            let snapshot = try await db.collection("aiBibleStudyConversations")
                .whereField("userId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
                .limit(to: 20)
                .getDocuments()

            var loadedConversations: [[AIStudyMessage]] = []

            for document in snapshot.documents {
                let conversationId = document.documentID

                // Load messages for this conversation
                let messagesSnapshot = try await db.collection("aiBibleStudyConversations")
                    .document(conversationId)
                    .collection("messages")
                    .order(by: "index")
                    .getDocuments()

                let messages: [AIStudyMessage] = messagesSnapshot.documents.compactMap { doc in
                    guard let text = doc.data()["text"] as? String,
                          let isUser = doc.data()["isUser"] as? Bool else {
                        return nil
                    }

                    return AIStudyMessage(
                        text: text,
                        isUser: isUser
                    )
                }

                if !messages.isEmpty {
                    loadedConversations.append(messages)
                }
            }

            await MainActor.run {
                conversationHistory = loadedConversations
                dlog("✅ Loaded \(loadedConversations.count) conversations from Firestore")
            }
        } catch {
            dlog("❌ Failed to load conversations: \(error)")
        }
    }
}

// MARK: - Conversation History View

struct AIBibleStudyConversationHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var history: [[AIStudyMessage]]
    let onLoad: ([AIStudyMessage]) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if history.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "clock")
                                .font(.systemScaled(50))
                                .foregroundStyle(.secondary)

                            Text("No conversation history yet")
                                .font(AMENFont.bold(18))

                            Text("Your past conversations will appear here")
                                .font(AMENFont.regular(14))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        Text("PAST CONVERSATIONS")
                            .font(AMENFont.bold(11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 8)

                        VStack(spacing: 0) {
                            ForEach(Array(history.enumerated()), id: \.offset) { index, conversation in
                                Button {
                                    onLoad(conversation)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Conversation \(history.count - index)")
                                                .font(AMENFont.bold(16))
                                                .foregroundStyle(.primary)

                                            if let firstUserMessage = conversation.first(where: { $0.isUser }) {
                                                Text(firstUserMessage.text)
                                                    .font(AMENFont.regular(14))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)
                                            }

                                            Text("\(conversation.count) messages")
                                                .font(AMENFont.regular(12))
                                                .foregroundStyle(.tertiary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.systemScaled(13, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                }
                                .buttonStyle(.plain)

                                if index < history.count - 1 {
                                    Divider().padding(.leading, 16)
                                }
                            }
                        }
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                        .padding(.horizontal, 16)
                        // Swipe-to-delete: handled via context menu on each row since we're not in a List
                        // Note: ForEach .onDelete requires List; kept as-is via direct deletion below.
                    }

                    Spacer(minLength: 32)
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Conversation History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - AI Settings View

struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("aiResponseStyle") private var responseStyle = "Balanced"
    @AppStorage("includeReferences") private var includeReferences = true
    @AppStorage("enableNotifications") private var enableNotifications = true
    @AppStorage("dailyReminderTime") private var dailyReminderTimeInterval: Double = Date().timeIntervalSinceReferenceDate
    private var dailyReminderTimeBinding: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSinceReferenceDate: dailyReminderTimeInterval) },
            set: { dailyReminderTimeInterval = $0.timeIntervalSinceReferenceDate }
        )
    }

    let responseStyles = ["Concise", "Balanced", "Detailed", "Academic"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {

                    // MARK: AI Responses
                    Text("AI RESPONSES")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        HStack {
                            Text("Response Style")
                                .font(AMENFont.regular(16))
                            Spacer()
                            Picker("Response Style", selection: $responseStyle) {
                                ForEach(responseStyles, id: \.self) { style in
                                    Text(style).tag(style)
                                }
                            }
                            .labelsHidden()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        Divider().padding(.leading, 16)

                        Toggle("Include Scripture References", isOn: $includeReferences)
                            .font(AMENFont.regular(16))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    Text("Choose how detailed you want AI responses to be")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    // MARK: Notifications
                    Text("NOTIFICATIONS")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        Toggle("Daily Study Reminders", isOn: $enableNotifications)
                            .font(AMENFont.regular(16))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                        if enableNotifications {
                            Divider().padding(.leading, 16)
                            DatePicker("Reminder Time", selection: dailyReminderTimeBinding, displayedComponents: .hourAndMinute)
                                .font(AMENFont.regular(16))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                        }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    // MARK: Data
                    Text("DATA")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        Button("Clear All Conversations") {
                            // Clear history
                        }
                        .font(AMENFont.regular(16))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        Divider().padding(.leading, 16)

                        Button("Export Study Notes") {
                            // Export functionality
                        }
                        .font(AMENFont.regular(16))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    // MARK: About
                    Text("ABOUT")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        HStack {
                            Text("Version")
                                .font(AMENFont.regular(16))
                            Spacer()
                            Text("1.0.0")
                                .font(AMENFont.regular(16))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        Divider().padding(.leading, 16)

                        Link("Privacy Policy", destination: URL(string: "https://amenapp.com/privacy")!)
                            .font(AMENFont.regular(16))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                        Divider().padding(.leading, 16)

                        Link("Terms of Service", destination: URL(string: "https://amenapp.com/terms")!)
                            .font(AMENFont.regular(16))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    Spacer(minLength: 32)
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
