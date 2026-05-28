// FilterTabData.swift
// AMENAPP — Spaces v2 Chat Layer (Agent B)
//
// Data contract that Agent C consumes when rendering the
// All / VIP / Unreads / External filter tab row in the Space list header.
// Keep this file free of UI logic — data only.

import Foundation

/// Data that drives All / VIP / Unreads / External filter tabs.
/// Agent C imports this. Do not put UI logic here.
struct SpaceFilterTabData {
    /// Which filter this tab represents.
    let filter: ThreadFilter
    /// Badge count shown on the tab; 0 = no badge rendered.
    let count: Int
    /// Whether this tab is currently selected.
    let isSelected: Bool

    init(filter: ThreadFilter, count: Int, isSelected: Bool) {
        self.filter = filter
        self.count = count
        self.isSelected = isSelected
    }
}

extension SpaceFilterTabData {
    /// Convenience factory: build the full tab-data array from service state.
    /// Pass `vipCount` as the number of VIP threads currently held in
    /// `SpacesChatService.vipThreadIds`.
    static func makeAll(
        threads: [ThreadSummary],
        vipThreadIds: Set<String>,
        currentFilter: ThreadFilter
    ) -> [SpaceFilterTabData] {
        let unreadCount   = threads.filter { $0.unreadCount > 0 }.count
        let externalCount = threads.filter { $0.hasExternalMembers }.count
        let vipCount      = threads.filter { vipThreadIds.contains($0.id) }.count

        return ThreadFilter.allCases.map { filter in
            let count: Int
            switch filter {
            case .all:      count = threads.count
            case .vip:      count = vipCount
            case .unreads:  count = unreadCount
            case .external: count = externalCount
            }
            return SpaceFilterTabData(
                filter: filter,
                count: count,
                isSelected: filter == currentFilter
            )
        }
    }
}
