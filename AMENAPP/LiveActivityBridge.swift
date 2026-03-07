
//
//  LiveActivityBridge.swift
//  AMENAPP
//
//  Real ActivityKit implementation — compiles when ActivityKit.framework is linked.
//  Uses #if canImport(ActivityKit) so it degrades safely on macOS/simulator.
//

import Foundation

// MARK: - Shared value type

struct RestoredActivityIds {
    let church: String?
    let prayer: String?
    let music: String?
    let reply: String?

    init(church: String? = nil, prayer: String? = nil, music: String? = nil, reply: String? = nil) {
        self.church = church
        self.prayer = prayer
        self.music = music
        self.reply = reply
    }
}

// MARK: - Bridge

#if canImport(ActivityKit)
import ActivityKit

@MainActor
final class LiveActivityBridge {

    static let shared = LiveActivityBridge()
    private init() {}

    /// True when ActivityKit is available and the user hasn't disabled Live Activities.
    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // MARK: - Church Service

    func startChurchService(
        churchId: String,
        churchName: String,
        serviceType: String,
        serviceDate: Date
    ) async -> String? {
        guard areActivitiesEnabled else { return nil }
        guard let deepLink = URL(string: "amen://church?id=\(churchId)") else { return nil }

        let attrs = ChurchServiceActivityAttributes(
            churchId: churchId,
            churchName: churchName,
            serviceType: serviceType,
            deepLinkURL: deepLink
        )
        let mins = max(0, Int(serviceDate.timeIntervalSinceNow / 60))
        let state = ChurchServiceActivityAttributes.ContentState(
            phase: mins > 0 ? .upcoming : .active,
            minutesUntilStart: mins,
            displayTime: DateFormatter.localizedString(from: serviceDate, dateStyle: .none, timeStyle: .short)
        )
        let content = ActivityContent(state: state, staleDate: serviceDate.addingTimeInterval(7200))
        do {
            let activity = try Activity<ChurchServiceActivityAttributes>.request(
                attributes: attrs,
                content: content,
                pushType: nil
            )
            return activity.id
        } catch {
            return nil
        }
    }

    func updateChurchService(id: String, serviceDate: Date, minutes: Int) async {
        guard let activity = Activity<ChurchServiceActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        let state = ChurchServiceActivityAttributes.ContentState(
            phase: minutes > 0 ? .upcoming : .active,
            minutesUntilStart: minutes,
            displayTime: DateFormatter.localizedString(from: serviceDate, dateStyle: .none, timeStyle: .short)
        )
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    func endChurchService(id: String, animated: Bool) async {
        guard let activity = Activity<ChurchServiceActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        let policy: ActivityUIDismissalPolicy = animated ? .default : .immediate
        await activity.end(nil, dismissalPolicy: policy)
    }

    // MARK: - Prayer

    func startPrayer(prayerId: String, authorName: String, prayerTitle: String, amenCount: Int) async -> String? {
        guard areActivitiesEnabled else { return nil }
        guard let deepLink = URL(string: "amen://prayer?id=\(prayerId)") else { return nil }

        let attrs = PrayerReminderActivityAttributes(
            prayerId: prayerId,
            authorName: authorName,
            prayerTitle: prayerTitle,
            deepLinkURL: deepLink
        )
        let state = PrayerReminderActivityAttributes.ContentState(
            status: .active,
            minutesRemaining: 15,
            amenCount: amenCount
        )
        let expiry = Date().addingTimeInterval(15 * 60)
        let content = ActivityContent(state: state, staleDate: expiry)
        do {
            let activity = try Activity<PrayerReminderActivityAttributes>.request(
                attributes: attrs,
                content: content,
                pushType: nil
            )
            return activity.id
        } catch {
            return nil
        }
    }

    func markPrayerAnswered(id: String) async {
        guard let activity = Activity<PrayerReminderActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        var state = activity.content.state
        state.status = .prayed
        await activity.update(ActivityContent(state: state, staleDate: nil))
        try? await Task.sleep(for: .seconds(2))
        await activity.end(nil, dismissalPolicy: .default)
    }

    func snoozePrayer(id: String) async -> String {
        guard let activity = Activity<PrayerReminderActivityAttributes>.activities.first(where: { $0.id == id }) else { return id }
        var state = activity.content.state
        state.status = .snoozed
        state.minutesRemaining = 15
        await activity.update(ActivityContent(state: state, staleDate: nil))
        await activity.end(nil, dismissalPolicy: .default)
        return id
    }

    func updateAmenCount(id: String, count: Int) async {
        guard let activity = Activity<PrayerReminderActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        var state = activity.content.state
        state.amenCount = count
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    func endPrayer(id: String, animated: Bool) async {
        guard let activity = Activity<PrayerReminderActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        let policy: ActivityUIDismissalPolicy = animated ? .default : .immediate
        await activity.end(nil, dismissalPolicy: policy)
    }

    // MARK: - Music

    func startMusic(
        songTitle: String,
        artist: String,
        albumArtURL: String?,
        appleMusicURL: URL?,
        churchNoteId: String?,
        totalSeconds: Int
    ) async -> String? {
        guard areActivitiesEnabled else { return nil }
        guard let deepLink = URL(string: "amen://worship") else { return nil }

        let attrs = WorshipMusicActivityAttributes(
            songTitle: songTitle,
            artist: artist,
            albumArtURL: albumArtURL,
            appleMusicURL: appleMusicURL,
            churchNoteId: churchNoteId,
            deepLinkURL: deepLink
        )
        let state = WorshipMusicActivityAttributes.ContentState(
            isPlaying: true,
            elapsedSeconds: 0,
            totalSeconds: totalSeconds
        )
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(Double(totalSeconds) + 60))
        do {
            let activity = try Activity<WorshipMusicActivityAttributes>.request(
                attributes: attrs,
                content: content,
                pushType: nil
            )
            return activity.id
        } catch {
            return nil
        }
    }

    func pauseMusic(id: String) async {
        guard let activity = Activity<WorshipMusicActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        var state = activity.content.state
        state.isPlaying = false
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    func updateMusicElapsed(id: String, elapsed: Int) async {
        guard let activity = Activity<WorshipMusicActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        var state = activity.content.state
        state.elapsedSeconds = elapsed
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    func endMusic(id: String, animated: Bool) async {
        guard let activity = Activity<WorshipMusicActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        let policy: ActivityUIDismissalPolicy = animated ? .default : .immediate
        await activity.end(nil, dismissalPolicy: policy)
    }

    // MARK: - Reply Assist

    func startReplyActivity(
        replyType: ReplyActivityAttributes.ReplyType,
        entityId: String,
        subEntityId: String?,
        displayName: String?,
        createdAtISO: String,
        expiresAtISO: String,
        privacyLevel: ReplyActivityAttributes.PrivacyLevel,
        contextSnippet: String?
    ) async -> String? {
        guard areActivitiesEnabled else { return nil }

        let attrs = ReplyActivityAttributes(
            replyType: replyType,
            entityId: entityId,
            subEntityId: subEntityId,
            displayName: displayName,
            createdAtISO: createdAtISO,
            expiresAtISO: expiresAtISO
        )
        let state = ReplyActivityAttributes.ContentState.loading
        let expiresAt = ISO8601DateFormatter().date(from: expiresAtISO) ?? Date().addingTimeInterval(900)
        let content = ActivityContent(state: state, staleDate: expiresAt)
        do {
            let activity = try Activity<ReplyActivityAttributes>.request(
                attributes: attrs,
                content: content,
                pushType: nil
            )
            return activity.id
        } catch {
            return nil
        }
    }

    func updateReplyActivity(
        id: String,
        suggestion1: String,
        suggestion2: String,
        suggestion3: String,
        privacyLevel: ReplyActivityAttributes.PrivacyLevel,
        contextSnippet: String?
    ) async {
        guard let activity = Activity<ReplyActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        let state = ReplyActivityAttributes.ContentState(
            suggestion1: suggestion1,
            suggestion2: suggestion2,
            suggestion3: suggestion3,
            suggestionsReady: true,
            privacyLevel: privacyLevel,
            contextSnippet: contextSnippet
        )
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    func endReplyActivity(id: String, animated: Bool) async {
        guard let activity = Activity<ReplyActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        let policy: ActivityUIDismissalPolicy = animated ? .default : .immediate
        await activity.end(nil, dismissalPolicy: policy)
    }

    // MARK: - Restoration

    func restoreActiveIds() async -> RestoredActivityIds {
        let church = Activity<ChurchServiceActivityAttributes>.activities.first?.id
        let prayer = Activity<PrayerReminderActivityAttributes>.activities.first?.id
        let music  = Activity<WorshipMusicActivityAttributes>.activities.first?.id
        let reply  = Activity<ReplyActivityAttributes>.activities.first?.id
        return RestoredActivityIds(church: church, prayer: prayer, music: music, reply: reply)
    }
}

#else

// MARK: - Fallback stub (non-ActivityKit targets, macOS, etc.)

@MainActor
final class LiveActivityBridge {
    static let shared = LiveActivityBridge()
    private init() {}
    var areActivitiesEnabled: Bool { false }
    func startChurchService(churchId: String, churchName: String, serviceType: String, serviceDate: Date) async -> String? { nil }
    func updateChurchService(id: String, serviceDate: Date, minutes: Int) async {}
    func endChurchService(id: String, animated: Bool) async {}
    func startPrayer(prayerId: String, authorName: String, prayerTitle: String, amenCount: Int) async -> String? { nil }
    func markPrayerAnswered(id: String) async {}
    func snoozePrayer(id: String) async -> String { "" }
    func updateAmenCount(id: String, count: Int) async {}
    func endPrayer(id: String, animated: Bool) async {}
    func startMusic(songTitle: String, artist: String, albumArtURL: String?, appleMusicURL: URL?, churchNoteId: String?, totalSeconds: Int) async -> String? { nil }
    func pauseMusic(id: String) async {}
    func updateMusicElapsed(id: String, elapsed: Int) async {}
    func endMusic(id: String, animated: Bool) async {}
    func startReplyActivity(replyType: ReplyActivityAttributes.ReplyType, entityId: String, subEntityId: String?, displayName: String?, createdAtISO: String, expiresAtISO: String, privacyLevel: ReplyActivityAttributes.PrivacyLevel, contextSnippet: String?) async -> String? { nil }
    func updateReplyActivity(id: String, suggestion1: String, suggestion2: String, suggestion3: String, privacyLevel: ReplyActivityAttributes.PrivacyLevel, contextSnippet: String?) async {}
    func endReplyActivity(id: String, animated: Bool) async {}
    func restoreActiveIds() async -> RestoredActivityIds { RestoredActivityIds() }
}

#endif
