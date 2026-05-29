//
//  AmenLiveActivityManager.swift
//  AMENAPP
//
//  Manages the full lifecycle (start / update / end) of all AMEN Live Activities.
//  Call sites import this file and use `AmenLiveActivityManager.shared`.
//
// ═══════════════════════════════════════════════════════════════════════════════
// SETUP REQUIRED:
// 1. Add NSSupportsLiveActivities = YES to Info.plist
// 2. Add ActivityKit framework to target
// 3. Live Activity widget views need a WidgetBundle in a Widget Extension target
// ═══════════════════════════════════════════════════════════════════════════════

import Foundation
import SwiftUI

#if canImport(ActivityKit)
import ActivityKit
// Disambiguates from the local `struct Activity` in ActivityFeedService.swift
@available(iOS 16.2, *)
private typealias LiveActivity<T: ActivityAttributes> = ActivityKit.Activity<T>
#endif

// MARK: - AmenLiveActivityManager

@MainActor
final class AmenLiveActivityManager {

    // MARK: Singleton

    static let shared = AmenLiveActivityManager()
    private init() {}

    // MARK: - Active Activity References

#if canImport(ActivityKit)
    @available(iOS 16.2, *)
    private var prayerActivity: LiveActivity<PrayerSessionAttributes>?

    @available(iOS 16.2, *)
    private var bereanActivity: LiveActivity<BereanStudyAttributes>?

    @available(iOS 16.2, *)
    private var churchActivity: LiveActivity<ChurchEventAttributes>?
#endif

    // MARK: - Availability Guard

    /// Returns true when the OS supports Live Activities and the user has them enabled.
    private var activitiesEnabled: Bool {
#if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled
        }
#endif
        return false
    }

    // MARK: ──────────────────────────────────────────────────────────────────
    // MARK: Prayer Session
    // ──────────────────────────────────────────────────────────────────────────

    /// Starts a new Prayer Session Live Activity.
    /// - Parameters:
    ///   - topic: The prayer topic or scripture reference.
    ///   - group: The name of the prayer group or Space.
    ///   - title: The initial short title shown on the lock screen.
    func startPrayerSession(topic: String, group: String, title: String) async {
#if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            guard activitiesEnabled else { return }
            let attributes = PrayerSessionAttributes(prayerTopic: topic, groupName: group)
            let initialState = PrayerSessionAttributes.ContentState(
                prayerTitle: title,
                elapsedMinutes: 0,
                participantCount: 1,
                isChurchMode: false
            )
            do {
                prayerActivity = try LiveActivity<PrayerSessionAttributes>.request(
                    attributes: attributes,
                    contentState: initialState,
                    pushType: nil
                )
                dlog("LiveActivity started: PrayerSession — \(topic)")
            } catch {
                dlog("LiveActivity error: \(error)")
            }
        }
#endif
    }

    /// Updates the running Prayer Session with a new elapsed time and participant count.
    func updatePrayerSession(elapsed: Int, participants: Int) async {
#if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            guard activitiesEnabled, let activity = prayerActivity else { return }
            let updated = PrayerSessionAttributes.ContentState(
                prayerTitle: activity.contentState.prayerTitle,
                elapsedMinutes: elapsed,
                participantCount: participants,
                isChurchMode: activity.contentState.isChurchMode
            )
            do {
                try await activity.update(using: updated)
            } catch {
                dlog("LiveActivity error: \(error)")
            }
        }
#endif
    }

    /// Ends and immediately dismisses the Prayer Session Live Activity.
    func endPrayerSession() async {
#if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            guard let activity = prayerActivity else { return }
            await activity.end(using: activity.contentState, dismissalPolicy: .immediate)
            prayerActivity = nil
            dlog("LiveActivity ended: PrayerSession")
        }
#endif
    }

    // MARK: ──────────────────────────────────────────────────────────────────
    // MARK: Berean Study
    // ──────────────────────────────────────────────────────────────────────────

    /// Starts a Berean Study Live Activity for the given study plan.
    /// - Parameters:
    ///   - planName: Display name of the study plan.
    ///   - book: The opening book the user is studying.
    func startBereanStudy(planName: String, book: String) async {
#if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            guard activitiesEnabled else { return }
            let attributes = BereanStudyAttributes(studyPlanName: planName)
            let initialState = BereanStudyAttributes.ContentState(
                currentBook: book,
                currentVerse: "1:1",
                progressPercent: 0.0,
                streakDays: 0
            )
            do {
                bereanActivity = try LiveActivity<BereanStudyAttributes>.request(
                    attributes: attributes,
                    contentState: initialState,
                    pushType: nil
                )
                dlog("LiveActivity started: BereanStudy — \(planName)")
            } catch {
                dlog("LiveActivity error: \(error)")
            }
        }
#endif
    }

    /// Updates the Berean Study Live Activity with the user's current reading position.
    func updateBereanProgress(book: String, verse: String, progress: Double, streak: Int) async {
#if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            guard activitiesEnabled, let activity = bereanActivity else { return }
            let updated = BereanStudyAttributes.ContentState(
                currentBook: book,
                currentVerse: verse,
                progressPercent: max(0.0, min(1.0, progress)),
                streakDays: streak
            )
            do {
                try await activity.update(using: updated)
            } catch {
                dlog("LiveActivity error: \(error)")
            }
        }
#endif
    }

    /// Ends and immediately dismisses the Berean Study Live Activity.
    func endBereanStudy() async {
#if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            guard let activity = bereanActivity else { return }
            await activity.end(using: activity.contentState, dismissalPolicy: .immediate)
            bereanActivity = nil
            dlog("LiveActivity ended: BereanStudy")
        }
#endif
    }

    // MARK: ──────────────────────────────────────────────────────────────────
    // MARK: Church Event
    // ──────────────────────────────────────────────────────────────────────────

    /// Schedules a Church Event Live Activity.
    /// - Parameters:
    ///   - churchName: The church's display name.
    ///   - serviceName: Name of the specific service.
    ///   - address: Street address of the venue.
    ///   - startsAt: The absolute start `Date` of the service.
    func scheduleChurchEvent(
        churchName: String,
        serviceName: String,
        address: String,
        startsAt: Date
    ) async {
#if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            guard activitiesEnabled else { return }
            let minutesUntil = max(0, Int(startsAt.timeIntervalSinceNow / 60))
            let attributes = ChurchEventAttributes(churchName: churchName, address: address)
            let initialState = ChurchEventAttributes.ContentState(
                minutesUntilStart: minutesUntil,
                serviceName: serviceName,
                isLive: false
            )
            do {
                churchActivity = try LiveActivity<ChurchEventAttributes>.request(
                    attributes: attributes,
                    contentState: initialState,
                    pushType: nil
                )
                dlog("LiveActivity started: ChurchEvent — \(churchName) / \(serviceName)")
            } catch {
                dlog("LiveActivity error: \(error)")
            }
        }
#endif
    }

    /// Updates the Church Event countdown or transitions it to "Live" state.
    func updateChurchEvent(minutesUntil: Int, isLive: Bool) async {
#if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            guard activitiesEnabled, let activity = churchActivity else { return }
            let updated = ChurchEventAttributes.ContentState(
                minutesUntilStart: max(0, minutesUntil),
                serviceName: activity.contentState.serviceName,
                isLive: isLive
            )
            do {
                try await activity.update(using: updated)
            } catch {
                dlog("LiveActivity error: \(error)")
            }
        }
#endif
    }

    /// Ends and immediately dismisses the Church Event Live Activity.
    func endChurchEvent() async {
#if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            guard let activity = churchActivity else { return }
            await activity.end(using: activity.contentState, dismissalPolicy: .immediate)
            churchActivity = nil
            dlog("LiveActivity ended: ChurchEvent")
        }
#endif
    }
}
