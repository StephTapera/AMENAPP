import SwiftUI

struct CommunityDiscernmentBanner: View {
    let signals: [CommunityDiscernmentSignal]
    let contentId: String
    let onRequestExplanation: () -> Void

    @State private var isExpanded = false

    var primarySignal: CommunityDiscernmentSignal? { signals.first }

    var body: some View {
        if let signal = primarySignal {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "person.2")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                    Text(signal.signalType.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                    Spacer()
                    Button(action: onRequestExplanation) {
                        Text("Explain this")
                            .font(.caption)
                            .foregroundStyle(Color.primary)
                    }
                    .accessibilityLabel("Request a Berean AI explanation of this teaching")
                }

                if let summary = signal.generatedSummary, isExpanded {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            .onTapGesture { withAnimation(.spring(response: 0.3)) { isExpanded.toggle() } }
            .accessibilityElement(children: .contain)
        }
    }
}

// MARK: - Clarity Signal Card

struct ClaritySignalCard: View {
    let signal: CommunityDiscernmentSignal

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconForSignal)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(signal.signalType.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.primary)
                if let summary = signal.generatedSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private var iconForSignal: String {
        switch signal.signalType {
        case .clarificationNeeded: return "questionmark.circle"
        case .concernRaised: return "exclamationmark.circle"
        case .communityEncouragement: return "heart.circle"
        case .confusionSignal: return "bubble.left.and.exclamationmark.bubble.right"
        case .bereanAnalysisRequested: return "brain.head.profile"
        case .scriptureShared: return "book.closed"
        }
    }
}
