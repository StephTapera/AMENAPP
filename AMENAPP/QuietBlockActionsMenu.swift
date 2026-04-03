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
            ScrollView {
                VStack(spacing: 0) {
                    // MARK: Safety Actions
                    Text("SAFETY ACTIONS")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
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
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.leading, 16)

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
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.leading, 16)

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
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    // MARK: Interaction Limits
                    Text("INTERACTION LIMITS")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
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
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.leading, 16)

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
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    Spacer(minLength: 32)
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Manage @\(targetUsername)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(AMENFont.semiBold(16))
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
                dlog("❌ Error performing quiet block: \(error)")
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
                    .font(.systemScaled(18))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AMENFont.semiBold(16))
                    .foregroundStyle(.primary)

                Text(description)
                    .font(AMENFont.regular(13))
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
