//
//  VergeMessageBubbleView.swift
//  AMENAPP
//
//  Individual chat bubble for Verge live rooms.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct VergeMessageBubbleView: View {

    let message: VergeMessage
    let isOwnMessage: Bool

    @State private var showReactionPicker = false

    private let cyanAccent = Color(hex: "06B6D4")

    // MARK: - Body

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isOwnMessage {
                Spacer(minLength: 48)
                bubbleContent
            } else {
                avatarView
                bubbleContent
                Spacer(minLength: 48)
            }
        }
        .padding(.vertical, 3)
        .sheet(isPresented: $showReactionPicker) {
            reactionPickerSheet
                .presentationDetents([.height(140)])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Avatar

    private var avatarView: some View {
        VStack(alignment: .center, spacing: 2) {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 28, height: 28)
                .overlay(
                    Text(initials)
                        .font(AMENFont.bold(10))
                        .foregroundStyle(.white.opacity(0.7))
                )
                .overlay(
                    Circle().stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        }
        .padding(.top, 2)
    }

    // MARK: - Bubble Content

    private var bubbleContent: some View {
        VStack(alignment: isOwnMessage ? .trailing : .leading, spacing: 4) {

            // Author name (not shown for own messages)
            if !isOwnMessage {
                Text(message.authorName)
                    .font(AMENFont.semiBold(11))
                    .foregroundStyle(.white.opacity(0.5))
            }

            // Pinned indicator
            if message.isPinned {
                HStack(spacing: 4) {
                    Image(systemName: "pin.fill")
                        .font(.systemScaled(9, weight: .medium))
                        .foregroundStyle(Color.accentColor.opacity(0.7))
                    Text("Pinned")
                        .font(AMENFont.regular(10))
                        .foregroundStyle(Color.accentColor.opacity(0.7))
                }
            }

            // Message bubble
            HStack(spacing: 0) {
                // Left border accent
                if message.type == .question {
                    Rectangle()
                        .fill(cyanAccent)
                        .frame(width: 3)
                        .cornerRadius(1.5)
                } else if message.aiFlag == "insightful" {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 3)
                        .cornerRadius(1.5)
                }

                VStack(alignment: .leading, spacing: 4) {
                    // Type icon for special types
                    if message.type == .question || message.type == .aiInsight {
                        HStack(spacing: 4) {
                            Image(systemName: message.type == .question ? "questionmark.circle.fill" : "sparkles")
                                .font(.systemScaled(10, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(message.type.accentColor)
                            Text(message.type == .question ? "Question" : "AI Insight")
                                .font(AMENFont.semiBold(10))
                                .foregroundStyle(message.type.accentColor)
                        }
                    }

                    Text(message.content)
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)

                    if !isOwnMessage, AMENFeatureFlags.shared.accessibilityIntelligenceEnabled {
                        AILTranslatePill(
                            originalText: message.content,
                            originalRef: message.id ?? ""
                        )
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isOwnMessage
                          ? Color(hex: "6B48FF").opacity(0.25)
                          : Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                isOwnMessage
                                ? Color(hex: "6B48FF").opacity(0.3)
                                : Color.white.opacity(0.07),
                                lineWidth: 0.5
                            )
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onTapGesture(count: 2) {
                showReactionPicker = true
            }

            // Reactions row
            if !message.reactions.isEmpty {
                reactionsRow
            }
        }
    }

    // MARK: - Reactions Row

    private var reactionsRow: some View {
        HStack(spacing: 6) {
            ForEach(message.reactions.sorted(by: { $0.key < $1.key }), id: \.key) { emoji, count in
                HStack(spacing: 3) {
                    Text(emoji)
                        .font(.systemScaled(12))
                    Text("\(count)")
                        .font(AMENFont.regular(11))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.07)))
            }
        }
    }

    // MARK: - Reaction Picker Sheet

    private var reactionPickerSheet: some View {
        VStack(spacing: 14) {
            Text("React")
                .font(AMENFont.semiBold(15))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, 8)

            HStack(spacing: 20) {
                ForEach(["🙌", "🔥", "❤️", "🙏", "✨"], id: \.self) { emoji in
                    Button {
                        addReaction(emoji)
                        showReactionPicker = false
                    } label: {
                        Text(emoji).font(.systemScaled(32))
                    }
                    .buttonStyle(CoCreationPressStyle())
                }
            }
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Helpers

    private var initials: String {
        let name = message.authorName
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private func addReaction(_ emoji: String) {
        guard let msgId = message.id else { return }
        lazy var db = Firestore.firestore()
        let ref = db.collection("vergeMessages").document(msgId)
        let key = "reactions.\(emoji)"
        ref.updateData([key: FieldValue.increment(Int64(1))])
    }
}
