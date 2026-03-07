//
//  InAppNotificationBanner.swift
//  AMENAPP
//
//  Instagram-style in-app notification banner.
//  Appears at the top of the screen when a new notification arrives while
//  the app is in the foreground. Tapping navigates to the relevant content.
//  Swipe up or wait 4 seconds to dismiss.
//

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Manager

/// Drives the in-app banner. Observes NotificationService and surfaces new
/// notifications one at a time, queuing extras so nothing is lost.
@MainActor
final class InAppNotificationBanner: ObservableObject {

    static let shared = InAppNotificationBanner()

    @Published private(set) var current: AppNotification?
    @Published private(set) var isVisible = false

    // Navigation target posted as a notification so ContentView can act on it
    static let navigateNotificationName = Notification.Name("InAppBannerNavigate")

    private var queue: [AppNotification] = []
    private var dismissTask: Task<Void, Never>?

    // MARK: - Persisted shown IDs
    // Keyed by user UID so IDs don't leak between accounts.
    // Survives app restarts so already-dismissed banners never re-appear.
    // Capped at 500 entries to prevent unbounded growth.

    private var shownIdsKey: String {
        "banner_shown_ids_\(Auth.auth().currentUser?.uid ?? "anon")"
    }

    private var shownIds: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: shownIdsKey) ?? []) }
        set {
            // Trim to the most-recent 500 if overfilled (order doesn't matter, just cap size)
            let trimmed = newValue.count > 500 ? Set(newValue.prefix(500)) : newValue
            UserDefaults.standard.set(Array(trimmed), forKey: shownIdsKey)
        }
    }

    private init() {}

    // MARK: - Public API

    /// Called by the view modifier whenever `NotificationService.notifications` changes.
    func handleNewNotifications(_ notifications: [AppNotification]) {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }

        // Find the most recent unread notification that isn't from the current user
        // and hasn't been shown yet this session.
        let candidates = notifications
            .filter { !$0.read && $0.actorId != currentUserId }
            .sorted { ($0.createdAt.seconds) > ($1.createdAt.seconds) }

        for notification in candidates {
            guard let id = notification.id, !shownIds.contains(id) else { continue }
            // Don't show message-type notifications — those are handled by UnifiedChatView.
            if notification.type == .message || notification.type == .messageRequest { continue } // swiftlint:disable:this line_length
            enqueue(notification)
            break // one at a time; the rest will come on the next update cycle
        }
    }

    func dismiss() {
        // Mark the current notification as read in Firestore so the Firestore
        // listener won't re-deliver it after dismissal.
        if let notificationId = current?.id {
            Task {
                try? await NotificationService.shared.markAsRead(notificationId)
                await BadgeCountManager.shared.immediateUpdate()
            }
        }

        dismissTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isVisible = false
        }
        Task {
            try? await Task.sleep(nanoseconds: 350_000_000) // match animation
            await MainActor.run {
                current = nil
                showNextIfQueued()
            }
        }
    }

    func tapBanner() {
        guard let notification = current else { return }
        NotificationCenter.default.post(
            name: Self.navigateNotificationName,
            object: notification
        )
        dismiss()
    }

    // MARK: - Private

    private func enqueue(_ notification: AppNotification) {
        guard let id = notification.id else { return }
        // Don't re-queue something already visible or queued
        if current?.id == id { return }
        if queue.contains(where: { $0.id == id }) { return }

        if isVisible {
            queue.append(notification)
        } else {
            show(notification)
        }
    }

    private func show(_ notification: AppNotification) {
        if let id = notification.id {
            var updated = shownIds
            updated.insert(id)
            shownIds = updated
        }
        current = notification

        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            isVisible = true
        }

        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000) // 4 s
            guard !Task.isCancelled else { return }
            await MainActor.run { dismiss() }
        }

        // Reply Assist: trigger Dynamic Island live activity for actionable notification types
        triggerReplyAssistIfNeeded(notification)
    }

    private func triggerReplyAssistIfNeeded(_ notification: AppNotification) {
        // Only trigger for comment, mention, reply, dm types
        let actionableTypes: Set<AppNotification.NotificationType> = [.comment, .reply, .mention]
        guard actionableTypes.contains(notification.type) else { return }

        let typeString: String
        switch notification.type {
        case .comment:  typeString = "comment"
        case .reply:    typeString = "reply"
        case .mention:  typeString = "mention"
        default:        return
        }

        let info = NotificationTriggerInfo(
            type: typeString,
            entityId: notification.postId ?? "",
            subEntityId: notification.commentId,
            actorId: notification.actorId ?? "",
            actorDisplayName: notification.actorName ?? notification.actorUsername
        )

        ReplyActivityTriggers.shared.handle(notification: info)
    }

    private func showNextIfQueued() {
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000) // brief pause between banners
            await MainActor.run { show(next) }
        }
    }
}

// MARK: - Banner View

struct InAppNotificationBannerView: View {

    let notification: AppNotification
    let onTap: () -> Void
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var profileImage: Image? = nil

    // Notification type display helpers
    private var icon: String {
        switch notification.type {
        case .amen:                  return "hands.sparkles.fill"
        case .comment, .reply:       return "bubble.left.fill"
        case .mention:               return "at"
        case .follow,
             .followRequestAccepted: return "person.fill.checkmark"
        case .repost:                return "arrow.2.squarepath"
        case .prayerReminder,
             .prayerAnswered:        return "hands.sparkles.fill"
        case .churchNoteShared:      return "note.text"
        default:                     return "bell.fill"
        }
    }

    private var iconColor: Color {
        switch notification.type {
        case .amen:                  return Color(red: 0.98, green: 0.72, blue: 0.18) // warm gold
        case .comment, .reply:       return Color(red: 0.35, green: 0.65, blue: 1.0)
        case .mention:               return Color(red: 0.55, green: 0.45, blue: 1.0)
        case .follow,
             .followRequestAccepted: return Color(red: 0.3, green: 0.85, blue: 0.65)
        case .repost:                return Color(red: 0.4, green: 0.78, blue: 0.4)
        case .prayerReminder,
             .prayerAnswered:        return Color(red: 0.7, green: 0.55, blue: 1.0)
        default:                     return Color.secondary
        }
    }

    private var bodyText: String {
        let name = notification.actorName ?? notification.actorUsername ?? "Someone"
        switch notification.type {
        case .amen:                  return "\(name) amen'd your post"
        case .comment:
            if let text = notification.commentText, !text.isEmpty {
                let trimmed = text.count > 60 ? String(text.prefix(60)) + "…" : text
                return "\(name) commented: \(trimmed)"
            }
            return "\(name) commented on your post"
        case .reply:
            if let text = notification.commentText, !text.isEmpty {
                let trimmed = text.count > 60 ? String(text.prefix(60)) + "…" : text
                return "\(name) replied: \(trimmed)"
            }
            return "\(name) replied to your comment"
        case .mention:               return "\(name) mentioned you"
        case .follow:                return "\(name) followed you"
        case .followRequestAccepted: return "\(name) accepted your follow request"
        case .repost:                return "\(name) reposted your post"
        case .prayerAnswered:        return "\(name) marked your prayer as answered"
        case .prayerReminder:        return "Time to pray"
        case .churchNoteShared:      return "\(name) shared church notes with you"
        default:                     return "\(name) sent you a notification"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 42, height: 42)

                if let image = profileImage {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 42, height: 42)
                        .clipShape(Circle())
                } else {
                    // Fallback initials
                    Text(initials)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                // Notification type icon badge
                Circle()
                    .fill(iconColor)
                    .frame(width: 18, height: 18)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .overlay {
                        Circle().stroke(Color(.systemBackground), lineWidth: 1.5)
                    }
                    .offset(x: 14, y: 14)
            }

            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(bodyText)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(timeAgo)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Dismiss chevron
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(Circle().fill(Color(.tertiarySystemBackground)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
                }
        }
        .padding(.horizontal, 12)
        .offset(y: dragOffset)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    // Allow upward drag only
                    let dy = value.translation.height
                    if dy < 0 {
                        dragOffset = dy * 0.4 // rubber band
                    }
                }
                .onEnded { value in
                    if value.translation.height < -40 {
                        onDismiss()
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .onTapGesture {
            onTap()
        }
        .task {
            await loadProfileImage()
        }
    }

    // MARK: - Helpers

    private var initials: String {
        let name = notification.actorName ?? notification.actorUsername ?? "?"
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    private var timeAgo: String {
        let seconds = Date().timeIntervalSince(notification.createdAt.dateValue())
        switch seconds {
        case ..<60:         return "just now"
        case ..<3600:       return "\(Int(seconds / 60))m ago"
        case ..<86400:      return "\(Int(seconds / 3600))h ago"
        default:            return "\(Int(seconds / 86400))d ago"
        }
    }

    private func loadProfileImage() async {
        guard let urlString = notification.actorProfileImageURL,
              !urlString.isEmpty,
              let url = URL(string: urlString) else { return }
        var profileRequest = URLRequest(url: url)
        profileRequest.timeoutInterval = 3
        guard let (data, _) = try? await URLSession.shared.data(for: profileRequest),
              let uiImage = UIImage(data: data) else { return }
        await MainActor.run {
            profileImage = Image(uiImage: uiImage)
        }
    }
}

// MARK: - View Modifier

private struct InAppNotificationBannerModifier: ViewModifier {

    @StateObject private var banner = InAppNotificationBanner.shared
    @ObservedObject private var notificationService = NotificationService.shared
    @State private var navigationObserver: NSObjectProtocol?

    func body(content: Content) -> some View {
        content
            .onChange(of: notificationService.notifications) { _, newNotifications in
                banner.handleNewNotifications(newNotifications)
            }
            .overlay(alignment: .top) {
                if banner.isVisible, let notification = banner.current {
                    InAppNotificationBannerView(
                        notification: notification,
                        onTap: { banner.tapBanner() },
                        onDismiss: { banner.dismiss() }
                    )
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal:   .move(edge: .top).combined(with: .opacity)
                        )
                    )
                    .animation(.spring(response: 0.45, dampingFraction: 0.82), value: banner.isVisible)
                    .padding(.top, safeAreaTop + 8)
                    .zIndex(1000)
                }
            }
            .onAppear {
                // P0 FIX: Remove any existing observer before registering a new one.
                // Without this, rapid view reattach (e.g. tab switches) stacks up
                // multiple observers that fire on every navigation notification.
                if let existing = navigationObserver {
                    NotificationCenter.default.removeObserver(existing)
                    navigationObserver = nil
                }
                navigationObserver = NotificationCenter.default.addObserver(
                    forName: InAppNotificationBanner.navigateNotificationName,
                    object: nil,
                    queue: .main
                ) { note in
                    guard let notification = note.object as? AppNotification else { return }
                    handleNavigation(for: notification)
                }
            }
            .onDisappear {
                if let obs = navigationObserver {
                    NotificationCenter.default.removeObserver(obs)
                    navigationObserver = nil
                }
            }
    }

    private var safeAreaTop: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .windows
            .first?
            .safeAreaInsets.top) ?? 44
    }

    private func handleNavigation(for notification: AppNotification) {
        // Post a deep-link navigation event using the existing
        // PushNotificationHandler infrastructure.
        var userInfo: [String: Any] = [:]
        if let type = notificationTypeString(for: notification.type) {
            userInfo["type"] = type
        }
        if let postId = notification.postId { userInfo["postId"] = postId }
        if let actorId = notification.actorId { userInfo["actorId"] = actorId }
        if let conversationId = notification.conversationId { userInfo["conversationId"] = conversationId }
        if let prayerId = notification.prayerId { userInfo["prayerId"] = prayerId }
        if let noteId = notification.noteId { userInfo["noteId"] = noteId }
        if let commentId = notification.commentId { userInfo["commentId"] = commentId }

        NotificationCenter.default.post(
            name: Notification.Name("handleNotificationNavigation"),
            object: nil,
            userInfo: userInfo
        )
    }

    private func notificationTypeString(for type: AppNotification.NotificationType) -> String? {
        switch type {
        case .amen:                  return "amen"
        case .comment:               return "comment"
        case .reply:                 return "reply"
        case .mention:               return "mention"
        case .follow:                return "follow"
        case .followRequestAccepted: return "follow_request_accepted"
        case .repost:                return "repost"
        case .prayerReminder:        return "prayer_reminder"
        case .prayerAnswered:        return "prayer_answered"
        case .churchNoteShared:      return "church_note_shared"
        default:                     return nil
        }
    }
}

extension View {
    /// Adds the Instagram-style in-app notification banner overlay.
    func inAppNotificationBanner() -> some View {
        modifier(InAppNotificationBannerModifier())
    }
}
