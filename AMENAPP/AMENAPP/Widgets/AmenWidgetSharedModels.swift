//
//  AmenWidgetSharedModels.swift
//  AMENAPP / AmenWidgetExtension
//
//  Shared data models and App Group persistence helpers used by BOTH
//  the main app target and the Widget Extension target.
//
//  IMPORTANT: Do NOT import UIKit here.
//  This file must compile cleanly in both the main app target and a
//  Widget Extension target. Only Foundation and WidgetKit are imported.
//

import Foundation
import WidgetKit

// Private dlog shim — file-scoped so it compiles in both the main app and the
// Widget Extension without conflicting with the global dlog in DebugLog.swift.
@inline(__always)
private func dlog(
    _ message: @autoclosure () -> String,
    file: StaticString = #file,
    line: UInt = #line
) {
    #if DEBUG
    print("[Widget]", message())
    #endif
}

// MARK: - Shared Data Models

/// Lightweight verse model persisted to the App Group UserDefaults
/// so the widget can display the current daily verse without a network call.
struct WidgetVerse: Codable, Hashable {
    /// Human-readable reference, e.g. "Romans 8:28"
    var reference: String
    /// Full verse body text
    var text: String
    /// Bible translation label, e.g. "NIV"
    var translation: String
    /// The calendar day this verse belongs to (used to detect staleness)
    var date: Date
}

/// Prayer statistics surfaced in the Prayer widget.
struct WidgetPrayerData: Codable {
    /// Total number of active prayer requests for the current user
    var prayerCount: Int
    /// Title of the most-recently added prayer request
    var latestPrayerTitle: String
    /// Timestamp of the last write — used to decide when to refresh
    var lastUpdated: Date
}

/// Next upcoming church event, if any, for the Church Event widget.
struct WidgetChurchEvent: Codable {
    var churchName: String
    var eventTitle: String
    var startTime: Date
    var address: String
}

// MARK: - AmenWidgetData namespace

/// Static helpers for reading and writing widget data through the shared App Group.
///
/// App Group ID: `group.com.amen.app`
/// Both the main app target and the Widget Extension target must have this
/// capability enabled in Xcode (Signing & Capabilities → App Groups).
enum AmenWidgetData {

    static let appGroupId = "group.com.amen.app"

    // MARK: UserDefaults keys

    private enum Key {
        static let verse        = "widget.verse"
        static let prayerData   = "widget.prayerData"
        static let churchEvent  = "widget.churchEvent"
    }

    // MARK: Shared defaults

    /// Returns the shared App Group UserDefaults, falling back to `.standard`
    /// if the App Group is not yet configured (e.g. simulator without entitlement).
    static func sharedDefaults() -> UserDefaults {
        UserDefaults(suiteName: appGroupId) ?? .standard
    }

    // MARK: - Verse

    static func saveVerse(_ verse: WidgetVerse) {
        do {
            let data = try JSONEncoder().encode(verse)
            sharedDefaults().set(data, forKey: Key.verse)
        } catch {
            dlog("⚠️ AmenWidgetData.saveVerse failed: \(error)")
        }
    }

    static func loadVerse() -> WidgetVerse? {
        guard let data = sharedDefaults().data(forKey: Key.verse) else { return nil }
        do {
            return try JSONDecoder().decode(WidgetVerse.self, from: data)
        } catch {
            dlog("⚠️ AmenWidgetData.loadVerse decode failed: \(error)")
            return nil
        }
    }

    // MARK: - Prayer Data

    static func savePrayerData(_ prayerData: WidgetPrayerData) {
        do {
            let encoded = try JSONEncoder().encode(prayerData)
            sharedDefaults().set(encoded, forKey: Key.prayerData)
        } catch {
            dlog("⚠️ AmenWidgetData.savePrayerData failed: \(error)")
        }
    }

    static func loadPrayerData() -> WidgetPrayerData? {
        guard let data = sharedDefaults().data(forKey: Key.prayerData) else { return nil }
        do {
            return try JSONDecoder().decode(WidgetPrayerData.self, from: data)
        } catch {
            dlog("⚠️ AmenWidgetData.loadPrayerData decode failed: \(error)")
            return nil
        }
    }

    // MARK: - Church Event

    /// Pass `nil` to clear a previously saved event.
    static func saveChurchEvent(_ event: WidgetChurchEvent?) {
        guard let event else {
            sharedDefaults().removeObject(forKey: Key.churchEvent)
            return
        }
        do {
            let data = try JSONEncoder().encode(event)
            sharedDefaults().set(data, forKey: Key.churchEvent)
        } catch {
            dlog("⚠️ AmenWidgetData.saveChurchEvent failed: \(error)")
        }
    }

    static func loadChurchEvent() -> WidgetChurchEvent? {
        guard let data = sharedDefaults().data(forKey: Key.churchEvent) else { return nil }
        do {
            return try JSONDecoder().decode(WidgetChurchEvent.self, from: data)
        } catch {
            dlog("⚠️ AmenWidgetData.loadChurchEvent decode failed: \(error)")
            return nil
        }
    }

    // MARK: - Timeline Reload

    /// Tells WidgetKit to invalidate all timelines and request fresh snapshots.
    /// Call this from the main app after writing new verse/prayer data.
    static func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
