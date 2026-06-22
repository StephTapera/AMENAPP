import SwiftUI

struct MessagingHomeView: View {
    private let threads = MessagingSampleData.threads
    private let actions = MessagingSampleData.smartActions
    private let selectedThreadID = MessagingSampleData.threads[0].id

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                header
                summaryCard
                threadList
                smartActions
            }
            .padding(20)
        }
        .background(Color.white)
        .navigationTitle("Messages")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Smart Messages")
                .font(.title2.weight(.semibold))
            Text("Context actions appear only after message safety scanning completes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var summaryCard: some View {
        SocialV2GlassCard(tintContext: .state, isActive: true) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 4) {
                    Text("45 messages while away")
                        .font(.headline)
                    Text("Summaries stay private to the thread and never bypass held messages.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var threadList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Threads")
                .font(.headline)

            ForEach(threads) { thread in
                Button {} label: {
                    MessagingThreadRow(thread: thread, isSelected: selectedThreadID == thread.id)
                }
                .buttonStyle(.plain)
                .disabled(!thread.canDeliverLatestMessage)
            }
        }
    }

    private var smartActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Context Actions")
                .font(.headline)

            SocialV2MessagingActionRow(spacing: 8) {
                ForEach(actions) { action in
                    SocialV2GlassPill(tintContext: action.tintContext, isSelected: action.isAvailable) {
                        Label(action.title, systemImage: action.systemImage)
                    }
                    .opacity(action.isAvailable ? 1 : 0.48)
                }
            }
        }
    }
}

private struct MessagingThreadRow: View {
    let thread: SocialV2MessageThread
    let isSelected: Bool

    var body: some View {
        SocialV2GlassCard(tintContext: thread.canDeliverLatestMessage ? .interactive : .alert, isActive: isSelected) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: thread.canDeliverLatestMessage ? "bubble.left.and.bubble.right.fill" : "lock.shield.fill")
                    .foregroundStyle(thread.canDeliverLatestMessage ? .blue : .secondary)

                VStack(alignment: .leading, spacing: 5) {
                    Text(thread.title)
                        .font(.headline)
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(thread.participantIDs.count) participants")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
    }

    private var statusText: String {
        guard let decision = thread.lastModerationDecision else {
            return "Delivery held until safety scan completes"
        }

        switch decision.status {
        case .approved:
            return "Scanned before delivery"
        case .pending:
            return "Scan pending, delivery held"
        case .held:
            return "Held for review: \(decision.policyReference)"
        case .removed:
            return "Removed: \(decision.policyReference)"
        }
    }
}

private struct MessagingSmartAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tintContext: SocialV2GlassTintContext
    let isAvailable: Bool
}

private enum MessagingSampleData {
    static let threads: [SocialV2MessageThread] = [
        SocialV2MessageThread(
            id: "thread-prayer-team",
            title: "Prayer Team",
            participantIDs: ["user-a", "user-b", "user-c", "user-d"],
            lastModerationDecision: SocialV2ModerationDecision(
                id: "mod-thread-prayer-team",
                status: .approved,
                policyReference: "message-safety",
                explanation: "No scam, grooming, harassment, spam, or fraud signals detected.",
                decidedAt: Date()
            ),
            updatedAt: Date()
        ),
        SocialV2MessageThread(
            id: "thread-volunteer-night",
            title: "Volunteer Night",
            participantIDs: ["user-a", "user-e", "user-f"],
            lastModerationDecision: SocialV2ModerationDecision(
                id: "mod-thread-volunteer-night",
                status: .held,
                policyReference: "fraud-review",
                explanation: "Delivery is held while a suspicious payment link is reviewed.",
                decidedAt: Date()
            ),
            updatedAt: Date()
        )
    ]

    static let smartActions: [MessagingSmartAction] = [
        MessagingSmartAction(id: "pray", title: "Pray Now", systemImage: "hands.sparkles", tintContext: .state, isAvailable: true),
        MessagingSmartAction(id: "encourage", title: "Send Encouragement", systemImage: "heart", tintContext: .interactive, isAvailable: true),
        MessagingSmartAction(id: "verse", title: "Share Verse", systemImage: "book", tintContext: .interactive, isAvailable: true),
        MessagingSmartAction(id: "blocked", title: "Hold Unsafe Link", systemImage: "lock.shield", tintContext: .alert, isAvailable: false)
    ]
}

private struct SocialV2MessagingActionRow<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: spacing) {
            content
        }
    }
}
