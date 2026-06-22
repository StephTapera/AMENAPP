import Foundation
import SwiftUI

@MainActor
final class FeedModeManager: ObservableObject {
    static let shared = FeedModeManager()
    @Published private(set) var activeModes: Set<FeedMode> = []
    private init() {}

    func activate(_ mode: FeedMode) {
        activeModes.insert(mode)
        FeedDirectionAnalytics.modeActivated(mode: mode.rawValue)
        NotificationCenter.default.post(name: .feedIntelligenceDidUpdate, object: nil)
    }

    func deactivate(_ mode: FeedMode) {
        activeModes.remove(mode)
        NotificationCenter.default.post(name: .feedIntelligenceDidUpdate, object: nil)
    }

    func toggle(_ mode: FeedMode) {
        if activeModes.contains(mode) { deactivate(mode) } else { activate(mode) }
    }

    var isActive: Bool { !activeModes.isEmpty }

    func rankingAdjustments() -> [String: Double] {
        var adjustments: [String: Double] = [:]
        for mode in activeModes {
            switch mode {
            case .berean:
                adjustments["biblicalTeachingScore"] = 2.0
                adjustments["scriptureReferences"] = 1.5
            case .worship:
                adjustments["worshipScore"] = 2.0
                adjustments["musicContent"] = 1.0
            case .calmFeed:
                adjustments["emotionalIntensity"] = -1.5
                adjustments["conflictScore"] = -2.0
                adjustments["outrageScore"] = -2.0
            case .focus:
                adjustments["educationalScore"] = 2.0
                adjustments["mediaPacingScore"] = -1.0
            case .community:
                adjustments["localChurchScore"] = 2.0
                adjustments["communityScore"] = 1.5
            case .sundayRest:
                adjustments["worshipScore"] = 1.5
                adjustments["outrageScore"] = -3.0
                adjustments["conflictScore"] = -3.0
            }
        }
        return adjustments
    }
}
