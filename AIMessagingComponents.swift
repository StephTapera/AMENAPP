//
//  AIMessagingComponents.swift
//  AMENAPP
//
//  AI-powered messaging UI components
//  Ice breakers, smart replies, and conversation insights
//

import SwiftUI

// MARK: - Ice Breaker Card

struct IceBreakerCard: View {
    let iceBreaker: IceBreakerSuggestion
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            action()
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blue)

                    Text("AI Suggestion")
                        .font(.custom("OpenSans-SemiBold", size: 11))
                        .foregroundColor(.blue)

                    Spacer()

                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.blue)
                }

                Text(iceBreaker.message)
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let sharedInterest = iceBreaker.sharedInterest {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.red.opacity(0.7))

                        Text("Shared: \(sharedInterest)")
                            .font(.custom("OpenSans-Regular", size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(isPressed ? 0.15 : 0.08), radius: isPressed ? 4 : 8, y: isPressed ? 2 : 4)
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Smart Reply Chip

struct SmartReplyChip: View {
    let suggestion: MessageSuggestion
    let action: () -> Void

    private var chipColor: Color {
        switch suggestion.type {
        case .response:
            return .blue
        case .scriptural:
            return .purple
        case .question:
            return .green
        case .encouragement:
            return .orange
        case .iceBreaker:
            return .blue
        }
    }

    private var icon: String {
        switch suggestion.type {
        case .response:
            return "bubble.left.fill"
        case .scriptural:
            return "book.fill"
        case .question:
            return "questionmark.circle.fill"
        case .encouragement:
            return "heart.fill"
        case .iceBreaker:
            return "sparkles"
        }
    }

    var body: some View {
        Button(action: {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            action()
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))

                Text(suggestion.text)
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .lineLimit(2)
            }
            .foregroundColor(chipColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(chipColor.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Ice Breakers Section

struct IceBreakersSection: View {
    let iceBreakers: [IceBreakerSuggestion]
    let onSelect: (IceBreakerSuggestion) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.blue)

                        Text("Start the Conversation")
                            .font(.custom("OpenSans-Bold", size: 18))
                    }

                    Text("Try one of these AI-powered icebreakers")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.gray.opacity(0.5))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Ice breaker cards
            ForEach(iceBreakers) { iceBreaker in
                IceBreakerCard(iceBreaker: iceBreaker) {
                    onSelect(iceBreaker)
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 12)
        .background(
            Color(white: 0.97)
                .ignoresSafeArea()
        )
    }
}

// MARK: - Smart Replies Bar

struct SmartRepliesBar: View {
    let suggestions: [MessageSuggestion]
    let onSelect: (MessageSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.blue)

                Text("Smart Replies")
                    .font(.custom("OpenSans-SemiBold", size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions) { suggestion in
                        SmartReplyChip(suggestion: suggestion) {
                            onSelect(suggestion)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 8)
        .background(Color(white: 0.98))
    }
}

// MARK: - Conversation Insights Card

struct ConversationInsightsCard: View {
    let insight: ConversationInsight
    @State private var isExpanded = false

    private var toneColor: Color {
        switch insight.tone {
        case .encouraging:
            return .orange
        case .prayerful:
            return .purple
        case .friendly:
            return .blue
        case .supportive:
            return .green
        case .conversational:
            return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "brain")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(toneColor)

                    Text(insight.title)
                        .font(.custom("OpenSans-Bold", size: 15))
                }

                Spacer()

                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.gray)
                }
            }

            // Insight text
            Text(insight.insight)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundColor(.black.opacity(0.8))
                .lineLimit(isExpanded ? nil : 2)

            if isExpanded {
                // Scripture reference
                if let scripture = insight.scriptureReference {
                    HStack(spacing: 6) {
                        Image(systemName: "book.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.purple)

                        Text(scripture)
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundColor(.purple)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.purple.opacity(0.1))
                    )
                }

                // Action items
                if !insight.actionItems.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Suggested Actions:")
                            .font(.custom("OpenSans-SemiBold", size: 12))
                            .foregroundColor(.secondary)

                        ForEach(insight.actionItems, id: \.self) { action in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 12))
                                    .foregroundColor(toneColor)

                                Text(action)
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundColor(.black.opacity(0.7))
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(toneColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(toneColor.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Loading State

struct AILoadingIndicator: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.8)
                .tint(.blue)

            Text(text)
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color(white: 0.95))
        )
    }
}
