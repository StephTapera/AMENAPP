// FindChurch2AvailabilityService.swift
// AMENAPP — Find Church 2.0, Wave 2
//
// Computes AvailabilityStatus for a ChurchObject, layering in
// studyTonight (from linked GatheringObjects) and livestreamActive
// (from MediaLinks heuristic). Results are cached per-church for 5 min.

import Foundation

// MARK: - FindChurch2AvailabilityService

@MainActor
final class FindChurch2AvailabilityService: ObservableObject {

    // MARK: - Cache

    private struct CacheEntry {
        let status: AvailabilityStatus
        let cachedAt: Date
    }

    private var cache: [String: CacheEntry] = [:]
    private let cacheTTL: TimeInterval = 5 * 60  // 5 minutes

    // MARK: - Gatherings store (injected or shared)

    /// Gatherings indexed by ID. Populated lazily when `availabilityStatus(for:)` is called.
    /// Wave 2 callers should pre-populate this via `registerGatherings(_:)` after a fetch.
    private var gatheringsById: [String: GatheringObject] = [:]

    // MARK: - Public API

    /// Register gatherings so the service can resolve `gatheringIds` on a church.
    func registerGatherings(_ gatherings: [GatheringObject]) {
        for g in gatherings {
            gatheringsById[g.id] = g
        }
    }

    /// Returns cached or freshly computed `AvailabilityStatus` for the given church.
    /// Returns `.unknown` when the feature flag is off.
    func availabilityStatus(for church: ChurchObject) -> AvailabilityStatus {
        guard AMENFeatureFlags.shared.findChurch2AvailabilityEnabled else {
            return .unknown
        }

        // Return cache hit if still fresh
        if let entry = cache[church.id], -entry.cachedAt.timeIntervalSinceNow < cacheTTL {
            return entry.status
        }

        let computed = computeStatus(for: church)
        cache[church.id] = CacheEntry(status: computed, cachedAt: Date())
        return computed
    }

    /// Evict the cached status for a church (call after a claim or profile update).
    func invalidateCache(for churchId: String) {
        cache.removeValue(forKey: churchId)
    }

    // MARK: - Private computation

    private func computeStatus(for church: ChurchObject) -> AvailabilityStatus {
        // Base computation from structured service times
        var status = AvailabilityStatus.compute(from: church.serviceTimes)

        // Layer 1: studyTonight — any linked gathering occurring today
        status.studyTonight = hasGatheringToday(for: church)

        // Layer 2: livestreamActive — heuristic based on MediaLinks + Sunday proximity
        status.livestreamActive = isLivestreamActive(mediaLinks: church.mediaLinks,
                                                      serviceTimes: church.serviceTimes)

        return status
    }

    // MARK: - studyTonight helper

    private func hasGatheringToday(for church: ChurchObject) -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        for gId in church.gatheringIds {
            guard let gathering = gatheringsById[gId],
                  !gathering.isDeleted,
                  gathering.isPublic else {
                continue
            }
            // One-time gathering: check if startsAt falls on today
            if let startsAt = gathering.startsAt,
               startsAt >= today && startsAt < tomorrow {
                return true
            }
            // Weekly/biweekly/ongoing gatherings: treat as "tonight" if cadence is weekly+
            if gathering.meetingCadence == .weekly || gathering.meetingCadence == .ongoing {
                return true
            }
        }
        return false
    }

    // MARK: - livestreamActive heuristic

    /// Returns true when:
    ///   1. The church has a detected livestream media type, AND
    ///   2. The current time is within 3 hours before or after any Sunday service start.
    ///
    /// This is a best-effort heuristic; authoritative state requires a CF.
    private func isLivestreamActive(mediaLinks: MediaLinks,
                                    serviceTimes: [StructuredServiceTime]) -> Bool {
        guard mediaLinks.detectedMediaType == .livestream
                || mediaLinks.detectedMediaType == .multiple else {
            return false
        }

        let now = Date()
        let calendar = Calendar.current
        let sundayWeekday = 1  // Calendar.weekday: 1 = Sunday

        let nowComponents = calendar.dateComponents(in: TimeZone.current, from: now)
        guard let todayWeekday = nowComponents.weekday else { return false }

        // Only consider Sunday services for the livestream heuristic
        let sundayServices = serviceTimes.filter { $0.dayOfWeek == sundayWeekday }
        guard !sundayServices.isEmpty else { return false }

        let windowSeconds: TimeInterval = 3 * 60 * 60  // ±3 hours

        for service in sundayServices {
            var serviceComponents = DateComponents()
            serviceComponents.year   = nowComponents.year
            serviceComponents.month  = nowComponents.month
            serviceComponents.day    = nowComponents.day
            serviceComponents.hour   = service.startHour
            serviceComponents.minute = service.startMinute
            serviceComponents.second = 0

            let tz = TimeZone(identifier: service.timezone) ?? TimeZone.current
            serviceComponents.timeZone = tz

            guard let serviceTime = calendar.date(from: serviceComponents) else { continue }

            let delta = now.timeIntervalSince(serviceTime)  // positive = after service start
            // Active window: up to 3 h before start through 3 h after start
            if delta >= -windowSeconds && delta <= windowSeconds {
                return true
            }
        }

        return false
    }
}
