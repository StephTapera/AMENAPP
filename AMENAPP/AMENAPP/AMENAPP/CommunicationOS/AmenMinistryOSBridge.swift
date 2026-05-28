import SwiftUI

// MARK: - Ministry OS Intent Models

/// A lightweight bridge model that lets Messages, Spaces, and future ActionThreads
/// speak the same product language without forcing a backend migration first.
struct AmenMinistryIntentThread: Identifiable, Equatable {
    enum Kind: String {
        case space
        case groupConversation
        case action
        case decision
        case prayer

        var icon: String {
            switch self {
            case .space: return "person.3.sequence.fill"
            case .groupConversation: return "bubble.left.and.bubble.right.fill"
            case .action: return "checkmark.seal.fill"
            case .decision: return "arrow.triangle.branch"
            case .prayer: return "hands.sparkles.fill"
            }
        }
    }

    let id: String
    let title: String
    let subtitle: String
    let kind: Kind
    let urgencyScore: Int
    let unreadCount: Int

    var needsAttention: Bool { urgencyScore > 0 || unreadCount > 0 }
}

struct AmenMinistryReceipt: Equatable {
    let title: String
    let summary: String
    let timeDividendMinutes: Int
    let urgentCount: Int

    static func make(spaces: [AMENSpace], groupConversations: [ChatConversation]) -> AmenMinistryReceipt {
        let unreadGroups = groupConversations.reduce(0) { $0 + max(0, $1.unreadCount) }
        let activeSpaces = spaces.filter { $0.weeklyActiveUsers > 0 }.count
        let urgentCount = groupConversations.filter { $0.unreadCount > 0 }.count
        let minutes = min(18, max(3, (unreadGroups * 2) + activeSpaces))
        let summary: String

        if spaces.isEmpty && groupConversations.isEmpty {
            summary = "No connected ministry spaces yet. Start by joining a Space or creating a group conversation."
        } else if urgentCount > 0 {
            summary = "\(urgentCount) ministry thread\(urgentCount == 1 ? "" : "s") need attention. Spaces and group chats are gathered here so you can distill the noise before opening a feed."
        } else {
            summary = "Your ministry spaces are quiet. Review the active spaces when you want context, not because the inbox demands it."
        }

        return AmenMinistryReceipt(
            title: "Ministry OS",
            summary: summary,
            timeDividendMinutes: minutes,
            urgentCount: urgentCount
        )
    }
}

// MARK: - Messages Capsule Strip

struct AmenMinistryOSCapsuleStrip: View {
    let spaces: [AMENSpace]
    let groupConversations: [ChatConversation]
    let onOpenSpace: (AMENSpace) -> Void
    let onOpenConversation: (ChatConversation) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var receipt: AmenMinistryReceipt {
        AmenMinistryReceipt.make(spaces: spaces, groupConversations: groupConversations)
    }

    private var intentThreads: [AmenMinistryIntentThread] {
        let spaceThreads = spaces.prefix(4).map { space in
            AmenMinistryIntentThread(
                id: "space_\(space.id ?? space.name)",
                title: space.name,
                subtitle: "\(space.weeklyActiveUsers) active this week",
                kind: .space,
                urgencyScore: space.weeklyActiveUsers > 0 ? 1 : 0,
                unreadCount: 0
            )
        }

        let groupThreads = groupConversations.prefix(4).map { conversation in
            AmenMinistryIntentThread(
                id: "group_\(conversation.id)",
                title: conversation.name,
                subtitle: conversation.lastMessage.isEmpty ? "Group conversation" : conversation.lastMessage,
                kind: .groupConversation,
                urgencyScore: conversation.unreadCount > 0 ? 2 : 0,
                unreadCount: conversation.unreadCount
            )
        }

        return (Array(groupThreads) + Array(spaceThreads))
            .sorted { lhs, rhs in
                if lhs.needsAttention != rhs.needsAttention { return lhs.needsAttention && !rhs.needsAttention }
                return lhs.urgencyScore > rhs.urgencyScore
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            receiptCard
            if !intentThreads.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(intentThreads) { thread in
                            capsule(for: thread)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.bottom, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ministry operating system bridge")
    }

    private var receiptCard: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 36, height: 36)
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.72))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(receipt.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("\(receipt.timeDividendMinutes)m saved")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                }
                Text(receipt.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7)
        )
        .padding(.horizontal, 16)
    }

    private func capsule(for thread: AmenMinistryIntentThread) -> some View {
        Button {
            if thread.kind == .space,
               let space = spaces.first(where: { "space_\($0.id ?? $0.name)" == thread.id }) {
                onOpenSpace(space)
            } else if thread.kind == .groupConversation,
                      let conversation = groupConversations.first(where: { "group_\($0.id)" == thread.id }) {
                onOpenConversation(conversation)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: thread.kind.icon)
                    .font(.system(size: 12, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(thread.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(thread.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if thread.unreadCount > 0 {
                    Text("\(thread.unreadCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Circle().fill(Color.red))
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(minHeight: 44)
            .background(cardBackground, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(thread.needsAttention ? 0.18 : 0.08), lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(thread.title)")
        .accessibilityHint(thread.kind == .space ? "Opens this Amen Space" : "Opens this group conversation")
    }

    private var cardBackground: some ShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color(.secondarySystemBackground))
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }
}

// MARK: - Space Bridge Sheet

struct AmenMinistrySpaceBridgeSheet: View {
    let space: AMENSpace
    @ObservedObject var spacesViewModel: SpacesViewModel
    let onOpenMessages: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero
                    section(
                        title: "What this space is for",
                        body: space.description.isEmpty ? "A shared ministry space for conversation, care, planning, and formation." : space.description,
                        icon: "person.3.sequence.fill"
                    )
                    section(
                        title: "Message connection",
                        body: "When this Space has an active group conversation, it belongs in Messages as an operational thread. The Space remains the shared context; Messages becomes the place to act quickly.",
                        icon: "bubble.left.and.bubble.right.fill"
                    )
                    section(
                        title: "Best next action",
                        body: "Open the Space when you need context. Use Messages when someone needs a reply, decision, reminder, or follow-up.",
                        icon: "checkmark.seal.fill"
                    )
                }
                .padding(20)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Ministry OS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                actionBar
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text(space.name)
                    .font(.system(size: 22, weight: .bold))
                    .lineLimit(2)
            }
            Text("\(space.memberCount) members · \(space.weeklyActiveUsers) active this week")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            if !space.aiDetectedTopics.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(space.aiDetectedTopics.prefix(5), id: \.self) { topic in
                            Text(topic.capitalized)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.primary.opacity(0.06)))
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(sheetCardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7)
        )
    }

    private func section(title: String, body: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(0.05)))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(body)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(sheetCardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                onOpenMessages()
                dismiss()
            } label: {
                Label("Messages", systemImage: "bubble.left.and.bubble.right")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 46)
            }
            .buttonStyle(.bordered)

            NavigationLink {
                SpaceFeedView(space: space, vm: spacesViewModel)
            } label: {
                Label("Open Space", systemImage: "person.3.sequence")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 46)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(.regularMaterial)
    }

    private var sheetCardBackground: some ShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color(.secondarySystemBackground))
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }
}
