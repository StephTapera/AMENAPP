//
//  QuietBlockActionsMenu.swift
//  AMENAPP
//
//  Quiet block tools: Block, Mute, Restrict, Hide Replies, Limit Mentions
//  Prevents harassment without forcing users to leave platform
//

import SwiftUI
import FirebaseAuth

struct QuietBlockActionsMenu: View {
    let targetUserId: String
    let targetUsername: String
    @ObservedObject private var trustService = TrustByDesignService.shared
    @State private var showConfirmation = false
    @State private var selectedAction: QuietBlockAction?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selectedAction = .block
                        showConfirmation = true
                    } label: {
                        ActionRow(
                            icon: "hand.raised.fill",
                            title: "Block",
                            description: "They can't see your content, DM you, or comment",
                            color: .red
                        )
                    }
                    
                    Button {
                        selectedAction = .mute
                        showConfirmation = true
                    } label: {
                        ActionRow(
                            icon: "speaker.slash.fill",
                            title: "Mute",
                            description: "Hide their posts and stories from your feed",
                            color: .orange
                        )
                    }
                    
                    Button {
                        selectedAction = .restrict
                        showConfirmation = true
                    } label: {
                        ActionRow(
                            icon: "eye.slash.fill",
                            title: "Restrict",
                            description: "They won't know. Their comments are hidden from others",
                            color: .purple
                        )
                    }
                } header: {
                    Text("SAFETY ACTIONS")
                        .font(.custom("OpenSans-Bold", size: 12))
                }
                
                Section {
                    Button {
                        selectedAction = .hideReplies
                        showConfirmation = true
                    } label: {
                        ActionRow(
                            icon: "text.bubble.fill",
                            title: "Hide Replies",
                            description: "Hide their comment replies on your posts",
                            color: .blue
                        )
                    }
                    
                    Button {
                        selectedAction = .limitMentions
                        showConfirmation = true
                    } label: {
                        ActionRow(
                            icon: "at.badge.minus",
                            title: "Limit Mentions",
                            description: "Prevent them from @mentioning you",
                            color: .blue
                        )
                    }
                } header: {
                    Text("INTERACTION LIMITS")
                        .font(.custom("OpenSans-Bold", size: 12))
                }
            }
            .navigationTitle("Manage @\(targetUsername)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
                }
            }
            .alert("Confirm Action", isPresented: $showConfirmation, presenting: selectedAction) { action in
                Button("Confirm", role: .destructive) {
                    performAction(action)
                }
                Button("Cancel", role: .cancel) {}
            } message: { action in
                Text(confirmationMessage(for: action))
            }
        }
    }
    
    private func performAction(_ action: QuietBlockAction) {
        Task {
            guard let userId = Auth.auth().currentUser?.uid else { return }
            
            do {
                try await trustService.performQuietBlock(
                    userId: userId,
                    targetUserId: targetUserId,
                    action: action
                )
                
                await MainActor.run {
                    dismiss()
                }
            } catch {
                print("❌ Error performing quiet block: \(error)")
            }
        }
    }
    
    private func confirmationMessage(for action: QuietBlockAction) -> String {
        switch action {
        case .block:
            return "Block @\(targetUsername)? They won't be able to see your content or contact you."
        case .mute:
            return "Mute @\(targetUsername)? You won't see their posts in your feed."
        case .restrict:
            return "Restrict @\(targetUsername)? Their comments will only be visible to them, and they won't know."
        case .hideReplies:
            return "Hide replies from @\(targetUsername) on your posts?"
        case .limitMentions:
            return "Prevent @\(targetUsername) from mentioning you in posts and comments?"
        }
    }
}

struct ActionRow: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.1))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.primary)
                
                Text(description)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    QuietBlockActionsMenu(targetUserId: "test123", targetUsername: "testuser")
}
