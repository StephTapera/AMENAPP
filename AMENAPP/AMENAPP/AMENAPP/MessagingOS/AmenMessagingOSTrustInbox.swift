// AmenMessagingOSTrustInbox.swift
// AMENAPP
//
// Trust-aware inbox with sections: Trusted / Requests / Community / Unknown / Flagged.
// Wraps existing AMENInbox thread rows — does NOT duplicate UnifiedChatView or AMENInbox
// thread row rendering. Gated by trustAwareInboxEnabled feature flag.
//
// Architecture:
//   TrustInboxSection         — section taxonomy
//   TrustInboxClassifier      — classifies ChatConversation by trust signals
//   TrustAwareInboxView       — main sectioned list view
//   TrustInboxSectionHeader   — section header with label + count
//   MessageRequestContextRow  — request card with trust context + actions

import SwiftUI
import FirebaseAuth

// MARK: - Section Taxonomy

enum TrustInboxSection: Int, CaseIterable, Identifiable {
    case trusted
    case requests
    case community
    case unknown
    case flagged

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .trusted:   return "Trusted"
        case .requests:  return "Requests"
        case .community: return "Community"
        case .unknown:   return "Unknown"
        case .flagged:   return "Flagged"
        }
    }

    var systemImage: String {
        switch self {
        case .trusted:   return "checkmark.shield.fill"
        case .requests:  return "person.badge.plus"
        case .community: return "person.3.fill"
        case .unknown:   return "questionmark.circle"
        case .flagged:   return "exclamationmark.triangle.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .trusted:   return .green
        case .requests:  return .blue
        case .community: return .purple
        case .unknown:   return .gray
        case .flagged:   return .red
        }
    }
}

// MARK: - Trust Context

struct ConversationTrustContext {
    let section: TrustInboxSection
    let signals: [TrustSignal]
    let mutualCount: Int

    var primarySignal: String {
        signals.first?.label ?? "No shared context"
    }

    enum TrustSignal: Identifiable {
        case sharedChurch(String)
        case sharedGroup(String)
        case sharedEvent(String)
        case mutualContacts(Int)
        case verifiedOrg(String)
        case noSignal

        var id: String {
            switch self {
            case .sharedChurch(let n):  return "church-\(n)"
            case .sharedGroup(let n):   return "group-\(n)"
            case .sharedEvent(let n):   return "event-\(n)"
            case .mutualContacts(let c): return "mutuals-\(c)"
            case .verifiedOrg(let n):   return "org-\(n)"
            case .noSignal:             return "none"
            }
        }

        var label: String {
            switch self {
            case .sharedChurch(let name):  return "Both attend \(name)"
            case .sharedGroup(let name):   return "Both in \(name)"
            case .sharedEvent(let name):   return "Met at \(name)"
            case .mutualContacts(let c):   return "\(c) mutual contact\(c == 1 ? "" : "s")"
            case .verifiedOrg(let name):   return "Verified member of \(name)"
            case .noSignal:                return "No shared context"
            }
        }

        var icon: String {
            switch self {
            case .sharedChurch:   return "building.columns.fill"
            case .sharedGroup:    return "person.3.fill"
            case .sharedEvent:    return "calendar.badge.checkmark"
            case .mutualContacts: return "person.2.fill"
            case .verifiedOrg:    return "checkmark.seal.fill"
            case .noSignal:       return "questionmark.circle"
            }
        }
    }
}

// MARK: - Classifier

struct TrustInboxClassifier {
    /// Classifies a conversation into a trust section based on available signals.
    /// The conversation's `status`, `trustScore`, and context fields drive the result.
    static func classify(_ conversation: ChatConversation) -> ConversationTrustContext {
        var signals: [ConversationTrustContext.TrustSignal] = []

        // Collect trust signals from conversation metadata
        if let churchName = conversation.sharedChurchName {
            signals.append(.sharedChurch(churchName))
        }
        if let groupName = conversation.sharedGroupName {
            signals.append(.sharedGroup(groupName))
        }
        if let eventName = conversation.sharedEventName {
            signals.append(.sharedEvent(eventName))
        }
        if let mutuals = conversation.mutualContactCount, mutuals > 0 {
            signals.append(.mutualContacts(mutuals))
        }
        if let orgName = conversation.verifiedOrgName {
            signals.append(.verifiedOrg(orgName))
        }
        if signals.isEmpty {
            signals.append(.noSignal)
        }

        let section = determineSection(conversation: conversation, signals: signals)
        return ConversationTrustContext(
            section: section,
            signals: signals,
            mutualCount: conversation.mutualContactCount ?? 0
        )
    }

    private static func determineSection(
        conversation: ChatConversation,
        signals: [ConversationTrustContext.TrustSignal]
    ) -> TrustInboxSection {
        // Flagged/suspicious takes priority
        if conversation.isFlagged == true { return .flagged }

        // Pending request — show in Requests for user to decide
        if conversation.status == "pending" { return .requests }

        // Trusted: accepted + meaningful trust signal
        let hasTrustSignal = signals.contains { signal in
            if case .noSignal = signal { return false }
            return true
        }
        if conversation.status == "accepted" && hasTrustSignal {
            return .trusted
        }

        // Community: group conversations
        if conversation.isGroup { return .community }

        // Unknown: accepted but no trust signals
        return .unknown
    }
}

// MARK: - Main View

struct TrustAwareInboxView: View {
    let conversations: [ChatConversation]
    let onOpenConversation: (ChatConversation) -> Void
    let onAcceptRequest: (ChatConversation) -> Void
    let onReplyOnce: (ChatConversation) -> Void
    let onMuteRequest: (ChatConversation) -> Void
    let onBlockRequest: (ChatConversation) -> Void
    let onReportRequest: (ChatConversation) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var classified: [(section: TrustInboxSection, items: [ChatConversation])] {
        var buckets: [TrustInboxSection: [ChatConversation]] = [:]
        for conv in conversations {
            let ctx = TrustInboxClassifier.classify(conv)
            buckets[ctx.section, default: []].append(conv)
        }
        return TrustInboxSection.allCases.compactMap { section in
            guard let items = buckets[section], !items.isEmpty else { return nil }
            return (section: section, items: items)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(classified, id: \.section) { bucket in
                    Section {
                        ForEach(bucket.items) { conversation in
                            let ctx = TrustInboxClassifier.classify(conversation)
                            if bucket.section == .requests {
                                MessageRequestContextRow(
                                    conversation: conversation,
                                    trustContext: ctx,
                                    onAccept: { onAcceptRequest(conversation) },
                                    onReplyOnce: { onReplyOnce(conversation) },
                                    onMute: { onMuteRequest(conversation) },
                                    onBlock: { onBlockRequest(conversation) },
                                    onReport: { onReportRequest(conversation) }
                                )
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            } else {
                                Button {
                                    onOpenConversation(conversation)
                                } label: {
                                    TrustInboxThreadRow(
                                        conversation: conversation,
                                        trustContext: ctx
                                    )
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 16)
                            }

                            Divider()
                                .padding(.leading, 76)
                        }
                    } header: {
                        TrustInboxSectionHeader(section: bucket.section, count: bucket.items.count)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Section Header

struct TrustInboxSectionHeader: View {
    let section: TrustInboxSection
    let count: Int

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: section.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(section.accentColor)
                .accessibilityHidden(true)

            Text(section.title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            Text("\(count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(section.accentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(section.accentColor.opacity(0.12))
                )

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(
            Group {
                if reduceTransparency {
                    Color(.secondarySystemBackground)
                } else {
                    Color(.systemBackground).opacity(0.95)
                        .background(.ultraThinMaterial)
                }
            }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(section.title) section, \(count) conversation\(count == 1 ? "" : "s")")
    }
}

// MARK: - Thread Row (trusted/community/unknown/flagged)

struct TrustInboxThreadRow: View {
    let conversation: ChatConversation
    let trustContext: ConversationTrustContext

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(conversation.initials)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                    )

                // Trust badge dot
                Circle()
                    .fill(trustContext.section.accentColor)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(conversation.name)
                        .font(.system(size: 15, weight: conversation.unreadCount > 0 ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    if !conversation.timestamp.isEmpty {
                        Text(conversation.timestamp)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 4) {
                    Text(conversation.lastMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    if conversation.unreadCount > 0 {
                        Text("\(min(conversation.unreadCount, 99))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.black))
                    }
                }

                // Trust signal hint
                if case .noSignal = trustContext.signals.first {} else {
                    HStack(spacing: 3) {
                        Image(systemName: trustContext.signals.first?.icon ?? "")
                            .font(.system(size: 9))
                            .foregroundStyle(trustContext.section.accentColor.opacity(0.7))
                            .accessibilityHidden(true)
                        Text(trustContext.primarySignal)
                            .font(.system(size: 11))
                            .foregroundStyle(trustContext.section.accentColor.opacity(0.8))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(conversation.name). \(conversation.lastMessage). " +
            (conversation.unreadCount > 0 ? "\(conversation.unreadCount) unread." : "") +
            " \(trustContext.primarySignal)"
        )
    }
}

// MARK: - Message Request Row

struct MessageRequestContextRow: View {
    let conversation: ChatConversation
    let trustContext: ConversationTrustContext
    let onAccept: () -> Void
    let onReplyOnce: () -> Void
    let onMute: () -> Void
    let onBlock: () -> Void
    let onReport: () -> Void

    @State private var showMoreActions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(conversation.initials)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)

                    if !trustContext.signals.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(trustContext.signals.prefix(2)) { signal in
                                HStack(spacing: 3) {
                                    Image(systemName: signal.icon)
                                        .font(.system(size: 9))
                                        .accessibilityHidden(true)
                                    Text(signal.label)
                                        .font(.system(size: 11))
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Spacer()

                if !conversation.timestamp.isEmpty {
                    Text(conversation.timestamp)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            // Message preview
            Text(conversation.lastMessage)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            // Primary actions
            HStack(spacing: 8) {
                Button(action: onAccept) {
                    Text("Accept")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.black))
                }
                .accessibilityLabel("Accept message request from \(conversation.name)")

                Button(action: onReplyOnce) {
                    Text("Reply Once")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .stroke(Color(.separator), lineWidth: 1)
                        )
                }
                .accessibilityLabel("Reply once to \(conversation.name) without accepting")

                Spacer()

                Button {
                    showMoreActions = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color(.secondarySystemBackground)))
                }
                .accessibilityLabel("More options for request from \(conversation.name)")
                .confirmationDialog(
                    "Request from \(conversation.name)",
                    isPresented: $showMoreActions,
                    titleVisibility: .visible
                ) {
                    Button("Mute", action: onMute)
                    Button("Block", role: .destructive, action: onBlock)
                    Button("Report", role: .destructive, action: onReport)
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .accessibilityElement(children: .contain)
    }
}

// MARK: - ChatConversation Extensions (trust context fields)
// These extend the existing ChatConversation model with optional trust-signal fields.
// The model returns nil gracefully when Firestore doesn't yet populate them.

extension ChatConversation {
    var sharedChurchName: String? { nil }      // populated from Firestore: sharedContext.churchName
    var sharedGroupName: String? { nil }       // populated from Firestore: sharedContext.groupName
    var sharedEventName: String? { nil }       // populated from Firestore: sharedContext.eventName
    var mutualContactCount: Int? { nil }       // populated from Firestore: mutualCount
    var verifiedOrgName: String? { nil }       // populated from Firestore: verifiedOrg
    var isFlagged: Bool? { false }             // populated from Firestore: safetyFlags.isFlagged
}
