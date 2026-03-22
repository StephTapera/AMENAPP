//
//  AMENInbox.swift
//  AMENAPP
//
//  Complete Messages Inbox redesign.
//  - White/black palette, premium minimal AMEN style
//  - Reference: "Let's Stay Connected" layout adapted to AMEN's language
//  - UnifiedChatView is NOT touched — only the inbox list is here
//
//  Components (all private or file-scoped):
//    AMENInboxTokens     — design constants
//    InboxAISummaryService — OpenAI per-conversation preview (cached)
//    QuickAccessRow      — horizontal recent-contacts strip
//    AMENThreadRow       — single conversation cell (Equatable, stable ID)
//    InboxEmptyState     — no messages / no results
//    InboxSearchBar      — debounced search field
//

import SwiftUI
import Combine
import FirebaseAuth

// MARK: - Design Tokens

enum AMENInboxTokens {
    // Colors — AMEN black/white system
    static let background    = Color(.systemBackground)
    static let surface       = Color(.secondarySystemBackground)
    static let separator     = Color(.separator).opacity(0.35)
    static let primaryText   = Color(.label)
    static let secondaryText = Color(.secondaryLabel)
    static let tertiaryText  = Color(.tertiaryLabel)
    static let unreadDot     = Color(uiColor: .label)  // adapts: black in light, white in dark
    static let accent        = Color(uiColor: .label)  // CTA, active state

    // Hero header
    // "01" editorial index marker beside the hero title
    static let editorialIndexColor = Color(.tertiaryLabel)
    // Warm amber accent used for the user's first name
    static let greetingAccent = Color(red: 0.85, green: 0.55, blue: 0.15)

    // Typography
    // Large lowercase editorial title ("messages")
    static let editorialHeroFont = Font.system(size: 48, weight: .light, design: .default)
    // Small index label ("01")
    static let editorialIndexFont = Font.system(size: 18, weight: .light, design: .default)
    // Greeting above hero
    static let greetingFont      = Font.system(size: 13, weight: .semibold)
    // Compact collapsed title
    static let heroFont          = Font.system(size: 28, weight: .bold, design: .default)
    static let nameFontRead      = Font.system(size: 15, weight: .regular)
    static let nameFontUnread    = Font.system(size: 15, weight: .semibold)
    static let previewFont       = Font.system(size: 13, weight: .regular)
    static let previewFontUnread = Font.system(size: 13, weight: .medium)
    static let timestampFont     = Font.system(size: 12, weight: .regular)
    static let labelFont         = Font.system(size: 11, weight: .semibold)
    static let aiLabelFont       = Font.system(size: 11, weight: .medium, design: .monospaced)
    // Filter pill
    static let pillFont          = Font.system(size: 13, weight: .medium)
    static let pillFontActive    = Font.system(size: 13, weight: .semibold)

    // Metrics
    static let avatarSize: CGFloat      = 50
    static let quickAvatarSize: CGFloat = 44
    static let headerAvatarSize: CGFloat = 30   // small avatar chip in header top-left
    static let hPad: CGFloat            = 20
    static let rowVPad: CGFloat         = 12
    static let separatorLeading: CGFloat = 90   // aligns under text, skips avatar
}

// MARK: - AI Summary Service

/// Generates one-line "smart preview" summaries for conversations using OpenAI.
/// Results are cached in memory (keyed by conversationId + lastMessage hash)
/// so we never call the API twice for the same content.
@MainActor
final class InboxAISummaryService: ObservableObject {
    static let shared = InboxAISummaryService()

    /// conversationId → summary string
    @Published private(set) var summaries: [String: String] = [:]
    /// conversationId → in-flight flag
    private var inFlight: Set<String> = []
    /// conversationId → hash of lastMessage at time of last fetch
    private var fetchedHashes: [String: Int] = [:]

    private init() {}

    /// Request a summary for a conversation. No-ops if:
    ///   - already have a fresh summary (same lastMessage)
    ///   - request is already in-flight
    ///   - lastMessage is too short to be worth summarising
    func requestSummary(for conversation: ChatConversation) {
        let id = conversation.id
        let msgHash = conversation.lastMessage.hashValue

        // Already have fresh result?
        if fetchedHashes[id] == msgHash, summaries[id] != nil { return }
        // In-flight?
        if inFlight.contains(id) { return }
        // Too short to be interesting
        guard conversation.lastMessage.count > 30 else { return }

        inFlight.insert(id)
        Task {
            defer { inFlight.remove(id) }
            let prompt = """
            Summarise this message preview in ONE short sentence (max 12 words). Plain text only, no punctuation at end.
            Message: \(conversation.lastMessage.prefix(300))
            """
            if let result = try? await OpenAIService.shared.sendMessageSync(prompt),
               !result.isEmpty {
                summaries[id] = result
                fetchedHashes[id] = msgHash
            }
        }
    }

    func summary(for conversation: ChatConversation) -> String? {
        summaries[conversation.id]
    }
}

// MARK: - Inbox Search Bar (debounced)

struct InboxSearchBar: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AMENInboxTokens.tertiaryText)

            TextField("Search conversations…", text: $text)
                .font(AMENInboxTokens.previewFont)
                .foregroundStyle(AMENInboxTokens.primaryText)
                .focused($focused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AMENInboxTokens.tertiaryText)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AMENInboxTokens.surface)
        )
    }
}

// MARK: - Quick Access Row

/// Horizontal strip of recent/pinned contacts.
/// Shows up to 6; each circle taps to open that conversation.
struct QuickAccessRow: View {
    let conversations: [ChatConversation]
    let onTap: (ChatConversation) -> Void

    // Show the 6 most recent accepted conversations, deduplicated by participant
    private var contacts: [ChatConversation] {
        var seen = Set<String>()
        var result: [ChatConversation] = []
        for conv in conversations where conv.status == "accepted" {
            // Use otherParticipantId for 1:1 chats; fall back to conv.id for groups
            let key = conv.otherParticipantId ?? conv.id
            if seen.insert(key).inserted {
                result.append(conv)
                if result.count == 6 { break }
            }
        }
        return result
    }

    var body: some View {
        if contacts.isEmpty { EmptyView() } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(contacts) { conv in
                        Button { onTap(conv) } label: {
                            VStack(spacing: 6) {
                                BreathingAvatarWrapper(conversation: conv)

                                Text(conv.name.components(separatedBy: " ").first ?? conv.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(AMENInboxTokens.secondaryText)
                                    .lineLimit(1)
                                    .frame(width: AMENInboxTokens.quickAvatarSize + 4)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, AMENInboxTokens.hPad)
                .padding(.vertical, 4)
            }
        }
    }
}

private struct QuickAvatarView: View {
    let conversation: ChatConversation
    var body: some View {
        Group {
            if let url = conversation.profilePhotoURL.flatMap(URL.init) {
                CachedAsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                        .frame(width: AMENInboxTokens.quickAvatarSize, height: AMENInboxTokens.quickAvatarSize)
                        .clipShape(Circle())
                } placeholder: {
                    initialsCircle(size: AMENInboxTokens.quickAvatarSize)
                }
            } else {
                initialsCircle(size: AMENInboxTokens.quickAvatarSize)
            }
        }
    }

    private func initialsCircle(size: CGFloat) -> some View {
        Circle()
            .fill(Color(.systemGray5))
            .frame(width: size, height: size)
            .overlay(
                Text(conversation.initials)
                    .font(.system(size: size * 0.32, weight: .semibold))
                    .foregroundStyle(AMENInboxTokens.secondaryText)
            )
    }
}

// MARK: - Breathing Avatar Wrapper

/// Wraps QuickAvatarView with breathing ring animation for unread conversations.
private struct BreathingAvatarWrapper: View {
    let conversation: ChatConversation
    @State private var animating = false

    private var isUnread: Bool { conversation.unreadCount > 0 }

    var body: some View {
        QuickAvatarView(conversation: conversation)
            .overlay(alignment: .bottomTrailing) {
                if isUnread {
                    Circle()
                        .fill(AMENInboxTokens.unreadDot)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(AMENInboxTokens.background, lineWidth: 1.5))
                        .offset(x: 2, y: 2)
                }
            }
            // Inner breathing ring
            .overlay {
                if isUnread {
                    Circle()
                        .stroke(Color.black.opacity(animating ? 0.55 : 0.18), lineWidth: 1.5)
                        .padding(-4)
                        .scaleEffect(animating ? 1.06 : 1.0)
                }
            }
            // Outer breathing ring
            .overlay {
                if isUnread {
                    Circle()
                        .stroke(Color.black.opacity(animating ? 0.15 : 0), lineWidth: 1)
                        .padding(-9)
                        .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true).delay(0.4), value: animating)
                }
            }
            .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true), value: animating)
            .onAppear {
                guard isUnread else { return }
                animating = true
            }
    }
}

// MARK: - Thread Row

/// Single conversation cell. Equatable on all visible fields → SwiftUI skips
/// re-renders when data hasn't changed, keeping scrolling at 60fps.
struct AMENThreadRow: View, Equatable {
    let conversation: ChatConversation
    let aiSummary: String?
    let onTap: () -> Void

    static func == (lhs: AMENThreadRow, rhs: AMENThreadRow) -> Bool {
        lhs.conversation == rhs.conversation && lhs.aiSummary == rhs.aiSummary
    }

    private var isUnread: Bool { conversation.unreadCount > 0 }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                // Avatar
                ThreadAvatarView(conversation: conversation)

                // Content column
                VStack(alignment: .leading, spacing: 3) {
                    // Name + timestamp row
                    HStack(alignment: .firstTextBaseline) {
                        Text(conversation.name)
                            .font(isUnread ? AMENInboxTokens.nameFontUnread : AMENInboxTokens.nameFontRead)
                            .foregroundStyle(AMENInboxTokens.primaryText)
                            .lineLimit(1)

                        if conversation.isGroup {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(AMENInboxTokens.tertiaryText)
                        }
                        if conversation.isMuted {
                            Image(systemName: "bell.slash.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(AMENInboxTokens.tertiaryText)
                        }

                        Spacer(minLength: 8)

                        Text(conversation.timestamp)
                            .font(AMENInboxTokens.timestampFont)
                            .foregroundStyle(isUnread ? AMENInboxTokens.primaryText : AMENInboxTokens.tertiaryText)
                    }

                    // AI summary OR last message preview
                    if let summary = aiSummary {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(AMENInboxTokens.tertiaryText)
                            Text(summary)
                                .font(AMENInboxTokens.aiLabelFont)
                                .foregroundStyle(AMENInboxTokens.tertiaryText)
                                .lineLimit(1)
                        }
                        // Raw preview below summary, lighter
                        Text(conversation.lastMessage)
                            .font(AMENInboxTokens.previewFont)
                            .foregroundStyle(isUnread ? AMENInboxTokens.secondaryText : AMENInboxTokens.tertiaryText)
                            .lineLimit(1)
                    } else {
                        Text(conversation.lastMessage.isEmpty ? "No messages yet" : conversation.lastMessage)
                            .font(isUnread ? AMENInboxTokens.previewFontUnread : AMENInboxTokens.previewFont)
                            .foregroundStyle(isUnread ? AMENInboxTokens.primaryText.opacity(0.75) : AMENInboxTokens.tertiaryText)
                            .lineLimit(2)
                    }
                }

                // Unread badge (right edge) — odometer roll on increment
                OdometerBadgeView(count: conversation.unreadCount)
            }
            .padding(.horizontal, AMENInboxTokens.hPad)
            .padding(.vertical, AMENInboxTokens.rowVPad)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(AMENInboxTokens.background)
    }
}

// Avatar that uses CachedAsyncImage with a stable initials fallback.
// Defined separately so SwiftUI's diffing sees a stable type.
private struct ThreadAvatarView: View {
    let conversation: ChatConversation

    var body: some View {
        Group {
            if let url = conversation.profilePhotoURL.flatMap(URL.init) {
                CachedAsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                        .frame(width: AMENInboxTokens.avatarSize, height: AMENInboxTokens.avatarSize)
                        .clipShape(Circle())
                } placeholder: {
                    skeletonCircle
                }
            } else {
                initialsCircle
            }
        }
    }

    private var skeletonCircle: some View {
        Circle()
            .fill(Color(.systemGray5))
            .frame(width: AMENInboxTokens.avatarSize, height: AMENInboxTokens.avatarSize)
            .overlay(
                Text(conversation.initials)
                    .font(.system(size: AMENInboxTokens.avatarSize * 0.32, weight: .semibold))
                    .foregroundStyle(Color(.secondaryLabel))
            )
            .shimmering()
    }

    private var initialsCircle: some View {
        Circle()
            .fill(Color(.systemGray5))
            .frame(width: AMENInboxTokens.avatarSize, height: AMENInboxTokens.avatarSize)
            .overlay(
                Text(conversation.initials)
                    .font(.system(size: AMENInboxTokens.avatarSize * 0.32, weight: .semibold))
                    .foregroundStyle(Color(.secondaryLabel))
            )
    }
}

// Subtle shimmer for skeleton state
private struct ShimmerView: View {
    @State private var phase: CGFloat = -1.0

    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [.clear, .white.opacity(0.3), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geo.size.width * 2)
            .offset(x: geo.size.width * phase)
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.0
                }
            }
        }
        .clipShape(Circle())
    }
}

private extension View {
    @ViewBuilder
    func shimmering() -> some View {
        self.overlay(ShimmerView())
    }
}

// MARK: - Separator

struct InboxSeparator: View {
    var body: some View {
        Divider()
            .padding(.leading, AMENInboxTokens.separatorLeading)
            .padding(.trailing, 0)
            .opacity(0.5)
    }
}

// MARK: - Empty States

struct InboxEmptyState: View {
    enum Mode { case noMessages, noResults(String) }
    let mode: Mode

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(AMENInboxTokens.tertiaryText)
            Text(headline)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AMENInboxTokens.primaryText)
            Text(subhead)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(AMENInboxTokens.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var icon: String {
        switch mode {
        case .noMessages: return "bubble.left.and.bubble.right"
        case .noResults: return "magnifyingglass"
        }
    }
    private var headline: String {
        switch mode {
        case .noMessages: return "No messages yet"
        case .noResults: return "No results"
        }
    }
    private var subhead: String {
        switch mode {
        case .noMessages: return "Start a conversation to connect with others in faith."
        case .noResults(let q): return "Nothing matched \"\(q)\". Try a different name or phrase."
        }
    }
}

// MARK: - Inbox Hero Header

/// Premium editorial header for the AMEN Messages inbox.
///
/// Layout (top → bottom):
///   Row 1: small avatar chip (left)  •  compose button (right)
///   Row 2: "01  messages" large lowercase editorial title with overflow menu
///   Row 3: debounced search bar
///
/// Inspired by the reference "01 inbox" editorial treatment — adapted to
/// AMEN's spiritual, minimal, liquid-glass design language.
struct InboxHeroHeader: View {
    let greetingName: String
    let onCompose: () -> Void
    let onBack: () -> Void
    @Binding var searchText: String

    // Tracks how far the content has scrolled — fed from parent — so the
    // header can compress when the user scrolls away.
    var scrollOffset: CGFloat = 0

    // Overflow menu
    @State private var showOverflow = false

    // Avatar image for the current user (optional — falls back to initials)
    @ObservedObject private var userService = UserService.shared

    private var userInitial: String {
        greetingName.prefix(1).uppercased()
    }

    // Hero opacity/scale on scroll — subtle parallax feel
    private var heroOpacity: Double {
        let progress = min(max(scrollOffset / 80, 0), 1)
        return Double(1.0 - progress * 0.4)
    }
    private var heroOffset: CGFloat {
        min(scrollOffset * 0.25, 20)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Row 1: Avatar chip + compose button ──────────────────────────
            HStack(alignment: .center) {
                // Small user avatar — doubles as navigation hint back to profile
                Button(action: onBack) {
                    Group {
                        if let urlStr = userService.currentUser?.profileImageURL,
                           let url = URL(string: urlStr) {
                            CachedAsyncImage(url: url) { img in
                                img.resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: AMENInboxTokens.headerAvatarSize,
                                           height: AMENInboxTokens.headerAvatarSize)
                                    .clipShape(Circle())
                            } placeholder: {
                                initialsChip
                            }
                        } else {
                            initialsChip
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Spacer()

                // Notification Bell Button
                NotificationBellButton()
                
                // Compose new message
                Button(action: onCompose) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(AMENInboxTokens.primaryText)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New message")
            }
            .padding(.horizontal, AMENInboxTokens.hPad)
            .padding(.top, 10)

            // ── Row 2: Editorial hero title ──────────────────────────────────
            HStack(alignment: .lastTextBaseline, spacing: 0) {

                // "01" index marker — left-anchored, small, light weight
                Text("01")
                    .font(AMENInboxTokens.editorialIndexFont)
                    .foregroundStyle(AMENInboxTokens.editorialIndexColor)
                    .kerning(1)
                    .padding(.trailing, 10)
                    .accessibilityHidden(true)

                // "messages" — large lowercase hero word
                Text("messages")
                    .font(AMENInboxTokens.editorialHeroFont)
                    .foregroundStyle(AMENInboxTokens.primaryText)
                    .kerning(-1.5)  // tight tracking for editorial feel
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Spacer(minLength: 10)

                // ⋯ overflow menu
                Menu {
                    Button {
                        onCompose()
                    } label: {
                        Label("New Message", systemImage: "square.and.pencil")
                    }
                    Button {
                        showOverflow = false
                    } label: {
                        Label("Mark All Read", systemImage: "envelope.open")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AMENInboxTokens.secondaryText)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More options")
            }
            .padding(.horizontal, AMENInboxTokens.hPad)
            .padding(.top, 6)
            .padding(.bottom, 14)
            .offset(y: heroOffset)
            .opacity(heroOpacity)

            // ── Row 3: Search bar ─────────────────────────────────────────────
            InboxSearchBar(text: $searchText)
                .padding(.horizontal, AMENInboxTokens.hPad)
                .padding(.bottom, 12)
        }
        .background(AMENInboxTokens.background)
    }

    // Small initials circle — fallback when no profile photo
    private var initialsChip: some View {
        ZStack {
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: AMENInboxTokens.headerAvatarSize,
                       height: AMENInboxTokens.headerAvatarSize)
            Text(userInitial)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AMENInboxTokens.secondaryText)
        }
    }
}

// MARK: - Section Label

struct InboxSectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(AMENInboxTokens.labelFont)
            .foregroundStyle(AMENInboxTokens.tertiaryText)
            .kerning(0.8)
            .padding(.horizontal, AMENInboxTokens.hPad)
            .padding(.top, 16)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Odometer Badge View

/// Unread count badge with odometer-style digit roll animation on increment.
struct OdometerBadgeView: View {
    let count: Int
    @State private var appeared = false
    @State private var digitKey = UUID()

    var body: some View {
        Group {
            if count > 0 {
                VStack {
                    Spacer().frame(height: 4)
                    HStack(spacing: 0) {
                        let digits = digitsFor(count)
                        ForEach(Array(digits.enumerated()), id: \.offset) { idx, digit in
                            Text(digit)
                                .font(.system(size: count > 9 ? 10 : 11, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 8, height: 14)
                                .clipped()
                                .offset(y: appeared ? 0 : 14)
                                .opacity(appeared ? 1 : 0)
                                .animation(
                                    .spring(response: 0.3, dampingFraction: 0.72)
                                    .delay(Double(idx) * 0.04),
                                    value: digitKey
                                )
                        }
                    }
                    .padding(.horizontal, count > 9 ? 5 : 3)
                    .padding(.vertical, 2)
                    .background(
                        Group {
                            if count > 9 {
                                Capsule().fill(AMENInboxTokens.unreadDot)
                            } else {
                                Circle().fill(AMENInboxTokens.unreadDot)
                                    .frame(width: 19, height: 19)
                            }
                        }
                    )
                }
            }
        }
        .scaleEffect(count > 0 ? 1 : 0)
        .opacity(count > 0 ? 1 : 0)
        .animation(.spring(response: 0.4, dampingFraction: 0.55), value: count)
        .onAppear { appeared = true }
        .onChange(of: count) { _, _ in
            // Re-trigger digit roll on count change
            appeared = false
            digitKey = UUID()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                appeared = true
            }
        }
    }

    private func digitsFor(_ n: Int) -> [String] {
        if n > 99 { return ["9", "+"] }
        if n > 9 { return Array(String(n)).map(String.init) }
        return [String(n)]
    }
}
