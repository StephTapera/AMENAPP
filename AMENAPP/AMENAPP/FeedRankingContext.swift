import Foundation
import SwiftUI

@MainActor
final class FeedRankingContextManager: ObservableObject {
    static let shared = FeedRankingContextManager()
    @Published private(set) var context: FeedRankingContext = .default
    private init() {
        NotificationCenter.default.addObserver(
            forName: .feedIntelligenceDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        Task {
            if let summary = try? await AmenFeedDirectionService.shared.getFeedIntelligenceSummary() {
                context = FeedRankingContext(
                    activePreferenceSignalIds: summary.activeSignals.map(\.id),
                    activeModes: summary.activeModes,
                    suppressedTopics: Array(summary.suppressedTopics.keys),
                    boostedTopics: Array(summary.boostedTopics.keys),
                    localHour: Calendar.current.component(.hour, from: Date()),
                    isSunday: Calendar.current.component(.weekday, from: Date()) == 1,
                    feedHealthMode: summary.feedHealth.preferCalmContent ? "calm" : nil
                )
            }
        }
    }
}

extension FeedRankingContext {
    static let `default` = FeedRankingContext(
        activePreferenceSignalIds: [], activeModes: [],
        suppressedTopics: [], boostedTopics: [],
        localHour: Calendar.current.component(.hour, from: Date()),
        isSunday: Calendar.current.component(.weekday, from: Date()) == 1,
        feedHealthMode: nil
    )
}
