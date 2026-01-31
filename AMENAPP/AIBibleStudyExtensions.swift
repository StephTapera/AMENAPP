//
//  AIBibleStudyExtensions.swift
//  AMENAPP
//
//  Helper functions and additional views for AI Bible Study
//

import SwiftUI

// MARK: - Helper Functions Extension

extension AIBibleStudyView {
    
    func clearConversation() {
        // Save current conversation before clearing
        if !messages.isEmpty {
            conversationHistory.append(messages)
        }
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            messages = []
        }
        
        // Add welcome message back
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
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
            // In production, save to UserDefaults or database
            print("💾 Saved conversation with \(messages.count) messages")
        }
    }
    
    func loadConversation(_ conversation: [AIStudyMessage]) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            messages = conversation
            selectedTab = .chat
        }
        showHistory = false
    }
}

// MARK: - Conversation History View

struct AIBibleStudyConversationHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var history: [[AIStudyMessage]]
    let onLoad: ([AIStudyMessage]) -> Void
    
    var body: some View {
        NavigationStack {
            List {
                if history.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock")
                            .font(.system(size: 50))
                            .foregroundStyle(.secondary)
                        
                        Text("No conversation history yet")
                            .font(.custom("OpenSans-Bold", size: 18))
                        
                        Text("Your past conversations will appear here")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(Array(history.enumerated()), id: \.offset) { index, conversation in
                        Button {
                            onLoad(conversation)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Conversation \(history.count - index)")
                                    .font(.custom("OpenSans-Bold", size: 16))
                                
                                if let firstUserMessage = conversation.first(where: { $0.isUser }) {
                                    Text(firstUserMessage.text)
                                        .font(.custom("OpenSans-Regular", size: 14))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                
                                Text("\(conversation.count) messages")
                                    .font(.custom("OpenSans-Regular", size: 12))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete { indexSet in
                        history.remove(atOffsets: indexSet)
                    }
                }
            }
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
    @AppStorage("dailyReminderTime") private var dailyReminderTime = Date()
    
    let responseStyles = ["Concise", "Balanced", "Detailed", "Academic"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Response Style", selection: $responseStyle) {
                        ForEach(responseStyles, id: \.self) { style in
                            Text(style).tag(style)
                        }
                    }
                    
                    Toggle("Include Scripture References", isOn: $includeReferences)
                } header: {
                    Text("AI Responses")
                } footer: {
                    Text("Choose how detailed you want AI responses to be")
                }
                
                Section {
                    Toggle("Daily Study Reminders", isOn: $enableNotifications)
                    
                    if enableNotifications {
                        DatePicker("Reminder Time", selection: $dailyReminderTime, displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Notifications")
                }
                
                Section {
                    Button("Clear All Conversations") {
                        // Clear history
                    }
                    .foregroundStyle(.red)
                    
                    Button("Export Study Notes") {
                        // Export functionality
                    }
                } header: {
                    Text("Data")
                }
                
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    
                    Link("Privacy Policy", destination: URL(string: "https://example.com/privacy")!)
                    Link("Terms of Service", destination: URL(string: "https://example.com/terms")!)
                }
            }
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

