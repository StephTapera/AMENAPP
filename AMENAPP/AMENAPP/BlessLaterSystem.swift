import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseAnalytics
import UserNotifications

// MARK: - BlessLaterTiming
// When the deferred post should resurface. Users pick one at swipe time.

enum BlessLaterTiming: String, Codable, CaseIterable, Identifiable {
    case tonight            = "tonight"
    case tomorrowMorning    = "tomorrow_morning"
    case afterChurch        = "after_church"
    case nextWeek           = "next_week"
    case reflectLater       = "reflect_later"   // moved to Reflect Later lane, no reminder

    var id: String { rawValue }

    var displayText: String {
        switch self {
        case .tonight:          return "Tonight"
        case .tomorrowMorning:  return "Tomorrow morning"
        case .afterChurch:      return "After church"
        case .nextWeek:         return "Next week"
        case .reflectLater:     return "Reflect Later lane"
        }
    }

    var icon: String {
        switch self {
        case .tonight:          return "moon.stars"
        case .tomorrowMorning:  return "sunrise"
        case .afterChurch:      return "building.columns"
        case .nextWeek:         return "calendar"
        case .reflectLater:     return "bookmark.circle"
        }
    }

    var subtitle: String {
        switch self {
        case .tonight:          return "Around 8 PM"
        case .tomorrowMorning:  return "Around 8 AM"
        case .afterChurch:      return "Sunday afternoon"
        case .nextWeek:         return "Same time next week"
        case .reflectLater:     return "No reminder — goes to your Reflect Later lane"
        }
    }

    // Absolute date this timing resolves to
    func resolvedDate(from now: Date = Date()) -> Date? {
        var cal = Calendar.current
        cal.locale = Locale.current
        switch self {
        case .tonight:
            return cal.nextDate(after: now, matching: DateComponents(hour: 20, minute: 0), matchingPolicy: .nextTimePreservingSmallerComponents)
        case .tomorrowMorning:
            guard let tomorrow = cal.date(byAdding: .day, value: 1, to: now) else { return nil }
            return cal.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow)
        case .afterChurch:
            // Next Sunday at 1 PM
            let weekday = cal.component(.weekday, from: now)
            let daysUntilSunday = weekday == 1 ? 7 : (8 - weekday)
            guard let sunday = cal.date(byAdding: .day, value: daysUntilSunday, to: now) else { return nil }
            return cal.date(bySettingHour: 13, minute: 0, second: 0, of: sunday)
        case .nextWeek:
            return cal.date(byAdding: .weekOfYear, value: 1, to: now)
        case .reflectLater:
            return nil
        }
    }
}

// MARK: - BlessLaterItem
// Firestore model stored in users/{uid}/blessedLater/{postId}

struct BlessLaterItem: Codable, Identifiable {
    @DocumentID var id: String?
    let postId: String
    let postAuthorName: String
    let postContentPreview: String  // first 120 chars, for digest display
    let timing: BlessLaterTiming
    let resurfaceAt: Date?          // nil for reflectLater
    var isActive: Bool              // false once surfaced or dismissed
    var notificationId: String?     // local notification identifier
    @ServerTimestamp var createdAt: Date?
}

// MARK: - BlessLaterService

@MainActor
final class BlessLaterService: ObservableObject {
    static let shared = BlessLaterService()

    @Published var reflectLaterItems: [BlessLaterItem] = []
    @Published var upcomingItems: [BlessLaterItem] = []

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    private init() {}

    // MARK: Defer a post

    func blessLater(post: Post, timing: BlessLaterTiming) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let resurfaceAt = timing.resolvedDate()
        let item = BlessLaterItem(
            id: post.firestoreId,
            postId: post.firestoreId,
            postAuthorName: post.authorName,
            postContentPreview: String(post.content.prefix(120)),
            timing: timing,
            resurfaceAt: resurfaceAt,
            isActive: true
        )

        let ref = db.collection("users").document(uid).collection("blessedLater").document(post.firestoreId)
        try await ref.setData(try Firestore.Encoder().encode(item))

        if let fireAt = resurfaceAt {
            await scheduleLocalNotification(for: item, at: fireAt)
        }

        Analytics.logEvent("bless_later_deferred", parameters: [
            "timing": timing.rawValue,
            "post_id": post.firestoreId
        ])
    }

    // MARK: Load active items

    func startListening() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        listener?.remove()
        listener = db.collection("users").document(uid).collection("blessedLater")
            .whereField("isActive", isEqualTo: true)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let docs = snap?.documents else { return }
                let items = docs.compactMap { try? $0.data(as: BlessLaterItem.self) }
                self.reflectLaterItems = items.filter { $0.timing == .reflectLater }
                self.upcomingItems = items.filter { $0.timing != .reflectLater }
                    .sorted { ($0.resurfaceAt ?? .distantFuture) < ($1.resurfaceAt ?? .distantFuture) }
            }
    }

    func stopListening() { listener?.remove() }

    // MARK: Dismiss (mark surfaced)

    func dismiss(itemId: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid).collection("blessedLater").document(itemId)
            .updateData(["isActive": false])
        Analytics.logEvent("bless_later_dismissed", parameters: ["item_id": itemId])
    }

    // MARK: Count for digest badge

    var reflectLaterCount: Int { reflectLaterItems.count }
    var dueCount: Int { upcomingItems.filter { ($0.resurfaceAt ?? .distantFuture) <= Date() }.count }

    // MARK: Local notification

    private func scheduleLocalNotification(for item: BlessLaterItem, at fireAt: Date) async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "A blessing you saved"
        content.body = item.postContentPreview.isEmpty ? "You deferred a post for later." : "\"\(item.postContentPreview.prefix(80))…\""
        content.sound = .default
        content.userInfo = ["postId": item.postId, "source": "bless_later"]

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireAt),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: "bless_later_\(item.postId)",
            content: content,
            trigger: trigger
        )

        try? await center.add(request)
    }
}

// MARK: - BlessLaterSheet
// Shown when user taps "Bless Later" in the PostCard action menu.
// Liquid Glass bottom sheet: calm, no shame, intentional framing.

struct BlessLaterSheet: View {

    let post: Post
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTiming: BlessLaterTiming? = nil
    @State private var isSubmitting = false
    @State private var didDefer = false

    var body: some View {
        VStack(spacing: 0) {
            dragHandle

            if didDefer {
                deferredConfirmation
            } else {
                timingPicker
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Subviews

    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(.systemGray4))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 20)
    }

    private var timingPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Bless Later")
                    .font(AMENFont.semiBold(20))
                    .padding(.horizontal, 24)

                Text("Come back to this when the moment is right.")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
            }
            .padding(.bottom, 24)

            VStack(spacing: 10) {
                ForEach(BlessLaterTiming.allCases) { timing in
                    BlessLaterTimingRow(
                        timing: timing,
                        isSelected: selectedTiming == timing
                    ) {
                        withAnimation(Motion.adaptive(.spring(response: 0.22, dampingFraction: 0.82))) {
                            selectedTiming = timing
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)

            confirmButton
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
        }
    }

    private var confirmButton: some View {
        Button {
            guard let timing = selectedTiming, !isSubmitting else { return }
            isSubmitting = true
            Task {
                try? await BlessLaterService.shared.blessLater(post: post, timing: timing)
                withAnimation { didDefer = true }
                isSubmitting = false
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                dismiss()
            }
        } label: {
            HStack {
                if isSubmitting {
                    ProgressView().tint(.white)
                } else {
                    Text(selectedTiming == nil ? "Choose a time" : "Bless Later")
                        .font(AMENFont.semiBold(16))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selectedTiming == nil ? Color(.systemGray4) : Color.primary)
            )
        }
        .buttonStyle(.plain)
        .disabled(selectedTiming == nil || isSubmitting)
        .animation(Motion.adaptive(.spring(response: 0.22, dampingFraction: 0.82)), value: selectedTiming)
    }

    private var deferredConfirmation: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.systemScaled(40, weight: .light))
                .foregroundStyle(.primary)

            Text("Blessed for later")
                .font(AMENFont.semiBold(18))

            if let timing = selectedTiming {
                Text(timing.subtitle)
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }
}

// MARK: - Timing Row

private struct BlessLaterTimingRow: View {
    let timing: BlessLaterTiming
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: timing.icon)
                    .font(.systemScaled(18, weight: .regular))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(timing.displayText)
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(isSelected ? .white : .primary)
                    Text(timing.subtitle)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(isSelected ? .white.opacity(0.75) : .secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.primary : Color(.systemGray6))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reflect Later Lane digest card (used in ChapelInbox)

struct ReflectLaterDigestCard: View {
    @ObservedObject private var service = BlessLaterService.shared
    var onOpen: () -> Void

    var body: some View {
        if service.reflectLaterCount > 0 || service.dueCount > 0 {
            Button(action: onOpen) {
                HStack(spacing: 14) {
                    Image(systemName: "tray.2")
                        .font(.systemScaled(22, weight: .light))
                        .foregroundStyle(.primary)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Saved for reflection")
                            .font(AMENFont.semiBold(15))
                        Text(digestSubtitle)
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(service.reflectLaterCount + service.dueCount)")
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.primary))
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var digestSubtitle: String {
        var parts: [String] = []
        if service.dueCount > 0 {
            parts.append("\(service.dueCount) ready now")
        }
        if service.reflectLaterCount > 0 {
            parts.append("\(service.reflectLaterCount) in Reflect Later")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Preview

#Preview {
    BlessLaterSheet(post: Post(
        authorName: "Grace Church",
        authorInitials: "GC",
        timeAgo: "2h",
        content: "God is still in the business of turning mourning into dancing. Your testimony is coming.",
        category: .testimonies,
        topicTag: nil,
        lightbulbCount: 0,
        commentCount: 0,
        repostCount: 0
    ))
    .presentationDetents([.medium])
}
