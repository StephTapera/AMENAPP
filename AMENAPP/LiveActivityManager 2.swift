
//
//  LiveActivityManager.swift
//  AMENAPP
//
//  Central coordinator for all Live Activities / Dynamic Island integration.
//
//  SETUP REQUIRED (one-time, in Xcode):
//  1. AMENAPP target → General → Frameworks, Libraries → + → ActivityKit.framework
//  2. Info.plist → Add key: NSSupportsLiveActivities = YES
//
//  Until ActivityKit is linked, all public methods are safe no-ops.
//  After linking, full Dynamic Island + Lock Screen Live Activity support activates.
//

import Foundation
import UserNotifications

// MARK: - Supporting types for Reply Assist

/// All data needed to start or update a reply activity.
struct ReplyActivityEvent {
    let replyType: ReplyActivityAttributes.ReplyType
    /// postId for .comment/.toneAssist; conversationId for .dm.
    let entityId: String
    /// commentId for .comment (optional).
    let subEntityId: String?
    /// Display name of the actor — omitted on lock screen unless previews enabled.
    let actorDisplayName: String?
    /// Short context snippet (post topic or first line) — privacy-gated.
    let contextSnippet: String?
}

/// Reason the reply activity was ended.
enum ReplyEndReason {
    case userDismissed
    case userOpened
    case expired
}

@MainActor
final class LiveActivityManager {

    static let shared = LiveActivityManager()
    private init() {}

    // Stored activity IDs
    private var churchServiceActivityId: String?
    private var prayerActivityId: String?
    private var musicActivityId: String?

    // Service countdown timer
    private var serviceUpdateTimer: Task<Void, Never>?

    // MARK: - Availability

    var isLiveActivitiesAvailable: Bool {
        // Returns true only when ActivityKit is linked AND iOS 16.1+ AND user enabled Live Activities
        return LiveActivityBridge.shared.areActivitiesEnabled
    }

    // ──────────────────────────────────────────────────────────
    // MARK: - 1. Church Service
    // ──────────────────────────────────────────────────────────

    func startChurchServiceActivity(
        churchId: String,
        churchName: String,
        serviceType: String,
        serviceDate: Date
    ) {
        guard isLiveActivitiesAvailable else { return }
        Task { [weak self] in
            await self?.endChurchServiceActivity(animated: false)
            let id = await LiveActivityBridge.shared.startChurchService(
                churchId: churchId,
                churchName: churchName,
                serviceType: serviceType,
                serviceDate: serviceDate
            )
            self?.churchServiceActivityId = id
            if id != nil { self?.scheduleServiceUpdates(serviceDate: serviceDate) }
        }
    }

    func updateChurchServiceActivity(serviceDate: Date) {
        guard let id = churchServiceActivityId else { return }
        let minutes = Self.minutesUntil(serviceDate)
        if minutes < -110 {
            Task { [weak self] in await self?.endChurchServiceActivity(animated: true) }
            return
        }
        Task {
            await LiveActivityBridge.shared.updateChurchService(id: id, serviceDate: serviceDate, minutes: minutes)
        }
    }

    func endChurchServiceActivity(animated: Bool = true) async {
        serviceUpdateTimer?.cancel()
        serviceUpdateTimer = nil
        if let id = churchServiceActivityId {
            churchServiceActivityId = nil
            await LiveActivityBridge.shared.endChurchService(id: id, animated: animated)
        }
    }

    private func scheduleServiceUpdates(serviceDate: Date) {
        serviceUpdateTimer?.cancel()
        serviceUpdateTimer = Task { [weak self] in
            let end = serviceDate.addingTimeInterval(7200)
            while !Task.isCancelled && Date() < end {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { break }
                self?.updateChurchServiceActivity(serviceDate: serviceDate)
            }
        }
    }

    // ──────────────────────────────────────────────────────────
    // MARK: - 2. Prayer Reminder
    // ──────────────────────────────────────────────────────────

    func startPrayerActivity(prayerId: String, authorName: String, prayerTitle: String, amenCount: Int = 0) {
        guard isLiveActivitiesAvailable else { return }
        Task { [weak self] in
            await self?.endPrayerActivity(animated: false)
            let id = await LiveActivityBridge.shared.startPrayer(
                prayerId: prayerId,
                authorName: authorName,
                prayerTitle: prayerTitle,
                amenCount: amenCount
            )
            self?.prayerActivityId = id
        }
    }

    func markPrayerAsAnswered() {
        guard let id = prayerActivityId else { return }
        prayerActivityId = nil
        Task { await LiveActivityBridge.shared.markPrayerAnswered(id: id) }
    }

    func snoozePrayerActivity() {
        guard let id = prayerActivityId else { return }
        Task {
            let prayerId = await LiveActivityBridge.shared.snoozePrayer(id: id)
            scheduleSnoozeNotification(minutes: 15, prayerId: prayerId)
        }
    }

    func updatePrayerAmenCount(_ count: Int) {
        guard let id = prayerActivityId else { return }
        Task { await LiveActivityBridge.shared.updateAmenCount(id: id, count: count) }
    }

    func endPrayerActivity(animated: Bool = true) async {
        if let id = prayerActivityId {
            prayerActivityId = nil
            await LiveActivityBridge.shared.endPrayer(id: id, animated: animated)
        }
    }

    // ──────────────────────────────────────────────────────────
    // MARK: - 3. Worship Music
    // ──────────────────────────────────────────────────────────

    func startMusicActivity(
        songTitle: String,
        artist: String,
        albumArtURL: String? = nil,
        appleMusicURL: URL? = nil,
        churchNoteId: String? = nil,
        totalSeconds: Int = 0
    ) {
        guard isLiveActivitiesAvailable else { return }
        Task { [weak self] in
            await self?.endMusicActivity(animated: false)
            let id = await LiveActivityBridge.shared.startMusic(
                songTitle: songTitle,
                artist: artist,
                albumArtURL: albumArtURL,
                appleMusicURL: appleMusicURL,
                churchNoteId: churchNoteId,
                totalSeconds: totalSeconds
            )
            self?.musicActivityId = id
        }
    }

    func pauseMusicActivity() {
        guard let id = musicActivityId else { return }
        Task { await LiveActivityBridge.shared.pauseMusic(id: id) }
    }

    func updateMusicElapsed(_ elapsed: Int) {
        guard let id = musicActivityId else { return }
        Task { await LiveActivityBridge.shared.updateMusicElapsed(id: id, elapsed: elapsed) }
    }

    func endMusicActivity(animated: Bool = true) async {
        if let id = musicActivityId {
            musicActivityId = nil
            await LiveActivityBridge.shared.endMusic(id: id, animated: animated)
        }
    }

    // ──────────────────────────────────────────────────────────
    // MARK: - 4. Reply Assist (Comment / DM / Tone Assist)
    // ──────────────────────────────────────────────────────────

    /// ID of the currently active reply activity (only one at a time).
    private var replyActivityId: String?

    /// Debounce task — cancels and re-creates if another event arrives within 2 s.
    private var replyDebounceTask: Task<Void, Never>?

    /// Timeout task — ends the activity after 15 minutes.
    private var replyTimeoutTask: Task<Void, Never>?

    // MARK: Public API

    /// Start or update the reply activity for an incoming comment, DM, or tone-assist event.
    ///
    /// - If a reply activity is already running, it is updated (not duplicated).
    /// - Multiple rapid events are debounced with a 2-second window.
    /// - User must have enabled "Show Reply Suggestions" in Settings; otherwise this is a no-op.
    func startReplyActivity(event: ReplyActivityEvent) {
        guard isLiveActivitiesAvailable else { return }
        guard UserDefaults.standard.bool(forKey: "replyAssist_suggestionsEnabled") else { return }

        // Debounce: cancel any pending start and wait 2 s for additional events
        replyDebounceTask?.cancel()
        replyDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.launchOrUpdateReplyActivity(event: event)
        }
    }

    /// Immediately end the reply activity (e.g., user opened the destination).
    func endReplyActivity(reason: ReplyEndReason = .userDismissed) {
        replyDebounceTask?.cancel()
        replyTimeoutTask?.cancel()
        guard let id = replyActivityId else { return }
        replyActivityId = nil
        Task { await LiveActivityBridge.shared.endReplyActivity(id: id, animated: reason != .expired) }
    }

    /// Update the reply activity with freshly generated suggestions.
    func updateReplySuggestions(suggestion1: String, suggestion2: String, suggestion3: String, snippet: String?) {
        guard let id = replyActivityId else { return }
        let showPreviews = UserDefaults.standard.bool(forKey: "replyAssist_showPreviews")
        let privacy: ReplyActivityAttributes.PrivacyLevel = showPreviews ? .previewAllowed : .noPreview
        let safeSnippet = showPreviews ? snippet : nil
        Task {
            await LiveActivityBridge.shared.updateReplyActivity(
                id: id,
                suggestion1: suggestion1,
                suggestion2: suggestion2,
                suggestion3: suggestion3,
                privacyLevel: privacy,
                contextSnippet: safeSnippet
            )
        }
    }

    // MARK: Private helpers

    private func launchOrUpdateReplyActivity(event: ReplyActivityEvent) async {
        let showPreviews = UserDefaults.standard.bool(forKey: "replyAssist_showPreviews")
        let privacy: ReplyActivityAttributes.PrivacyLevel = showPreviews ? .previewAllowed : .noPreview
        let now = Date()
        let formatter = ISO8601DateFormatter()
        let createdAtISO = formatter.string(from: now)
        let expiresAtISO = formatter.string(from: now.addingTimeInterval(15 * 60))

        // Privacy: only pass displayName if previews allowed
        let displayName = showPreviews ? event.actorDisplayName : nil
        let snippet = showPreviews ? event.contextSnippet : nil

        if let existingId = replyActivityId {
            // Update the existing activity with the new event details
            await LiveActivityBridge.shared.updateReplyActivity(
                id: existingId,
                suggestion1: "",
                suggestion2: "",
                suggestion3: "",
                privacyLevel: privacy,
                contextSnippet: snippet
            )
        } else {
            // Start a new activity in loading state; suggestions will follow via updateReplySuggestions()
            let id = await LiveActivityBridge.shared.startReplyActivity(
                replyType: event.replyType,
                entityId: event.entityId,
                subEntityId: event.subEntityId,
                displayName: displayName,
                createdAtISO: createdAtISO,
                expiresAtISO: expiresAtISO,
                privacyLevel: privacy,
                contextSnippet: snippet
            )
            replyActivityId = id
            if id != nil { scheduleReplyTimeout() }
        }
    }

    private func scheduleReplyTimeout() {
        replyTimeoutTask?.cancel()
        replyTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15 * 60 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.endReplyActivity(reason: .expired)
        }
    }

    // ──────────────────────────────────────────────────────────
    // MARK: - End All
    // ──────────────────────────────────────────────────────────

    func endAllActivities() {
        Task { [weak self] in
            await self?.endChurchServiceActivity(animated: false)
            await self?.endPrayerActivity(animated: false)
            await self?.endMusicActivity(animated: false)
            self?.endReplyActivity(reason: .userDismissed)
        }
    }

    // ──────────────────────────────────────────────────────────
    // MARK: - Restoration
    // ──────────────────────────────────────────────────────────

    func restoreActiveActivities() {
        Task { [weak self] in
            let ids = await LiveActivityBridge.shared.restoreActiveIds()
            self?.churchServiceActivityId = ids.church
            self?.prayerActivityId        = ids.prayer
            self?.musicActivityId         = ids.music
            self?.replyActivityId         = ids.reply
            if ids.reply != nil { self?.scheduleReplyTimeout() }
        }
    }

    // ──────────────────────────────────────────────────────────
    // MARK: - Helpers
    // ──────────────────────────────────────────────────────────

    static func minutesUntil(_ date: Date) -> Int {
        Int(date.timeIntervalSinceNow / 60)
    }

    static func serviceDisplayTime(phase: String, minutes: Int) -> String {
        switch phase {
        case "active":  return "\(abs(minutes)) min in"
        case "ending":  return "Wrapping up"
        default:        return minutes <= 0 ? "Starting now" : "Starts in \(minutes) min"
        }
    }

    private func scheduleSnoozeNotification(minutes: Int, prayerId: String) {
        let content = UNMutableNotificationContent()
        content.title = "Prayer Reminder"
        content.body = "Time to continue your prayer"
        content.sound = .default
        content.userInfo = ["prayerId": prayerId, "type": "prayer_snooze"]
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(minutes * 60),
            repeats: false
        )
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: "prayer_snooze_\(prayerId)_\(Int(Date().timeIntervalSince1970))",
                content: content,
                trigger: trigger
            )
        )
    }
}
