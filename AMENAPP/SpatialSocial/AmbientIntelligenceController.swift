import Foundation
import SwiftUI
import UserNotifications
import FirebaseAuth
import FirebaseFirestore

// Controls the ambient signal layer: subtle, non-intrusive awareness signals
// that surface only when relevant and confidence is high enough.
// This is the opposite of push-first notification design.
@MainActor
final class AmbientIntelligenceController: ObservableObject {
    static let shared = AmbientIntelligenceController()

    @Published private(set) var activeSignals: [AmbientSignal] = []
    @Published private(set) var topSignal: AmbientSignal?

    private lazy var db = Firestore.firestore()
    private var cleanupTask: Task<Void, Never>?

    private init() {}

    // Evaluate which signals to surface based on current context
    func evaluate(
        environment: SpatialEnvironment,
        nearbyGatherings: [NearbyGathering],
        locationContext: LocationContext
    ) {
        var signals: [AmbientSignal] = []

        // New environment shift
        if environment.isNew && environment.type != .unknown {
            signals.append(AmbientSignal(
                id: "env_\(environment.type.rawValue)",
                type: .environmentShift,
                message: "You're in \(environment.broadArea).",
                detail: environment.type.surfaceAdaptation.showChurchDiscovery ? "Tap to find a church nearby." : nil,
                confidence: environment.confidence,
                priority: .medium,
                action: environment.type.surfaceAdaptation.showChurchDiscovery
                    ? AmbientSignalAction(label: "Find Church", deepLinkPath: "amen://companion/discover")
                    : nil,
                expiresAt: Date().addingTimeInterval(3600)
            ))
        }

        // Nearby gatherings
        for gathering in nearbyGatherings.prefix(2) where gathering.participantCount > 0 {
            signals.append(AmbientSignal(
                id: "gathering_\(gathering.id)",
                type: .nearbyGathering,
                message: "\(gathering.title) is nearby.",
                detail: "\(gathering.countLabel) attending",
                confidence: 0.8,
                priority: .medium,
                action: AmbientSignalAction(label: "View", deepLinkPath: "amen://gathering/\(gathering.id)"),
                expiresAt: gathering.startsAt?.addingTimeInterval(3600) ?? Date().addingTimeInterval(7200)
            ))
        }

        // Service reminder (church saved + Sunday)
        let isSundaySoon = [6, 7, 1].contains(Calendar.current.component(.weekday, from: Date()))
        if isSundaySoon && !ChurchCompanionService.shared.savedChurches.isEmpty {
            signals.append(AmbientSignal(
                id: "service_reminder_sunday",
                type: .serviceReminder,
                message: "Sunday is coming up.",
                detail: "You have a saved church. Want to plan a visit?",
                confidence: 0.9,
                priority: .high,
                action: AmbientSignalAction(label: "Plan Visit", deepLinkPath: "amen://companion/visit"),
                expiresAt: Calendar.current.nextDate(after: Date(), matching: DateComponents(weekday: 1), matchingPolicy: .nextTime) ?? Date().addingTimeInterval(3 * 24 * 3600)
            ))
        }

        let eligible = signals
            .filter { !$0.isExpired && $0.confidence >= 0.7 }
            .sorted { $0.priority > $1.priority }

        activeSignals = eligible
        topSignal = eligible.first
    }

    func dismissSignal(id: String) {
        activeSignals.removeAll { $0.id == id }
        topSignal = activeSignals.first
    }

    // Deliver ambient signal as a silent local notification (no alert sound)
    func deliverAsAmbientNotification(_ signal: AmbientSignal) async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = signal.message
        if let detail = signal.detail { content.body = detail }
        content.sound = nil // ambient — no sound
        content.userInfo = ["signalId": signal.id, "signalType": signal.type.rawValue]
        if let action = signal.action { content.userInfo["deepLinkPath"] = action.deepLinkPath }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "ambient_\(signal.id)", content: content, trigger: trigger)
        try? await center.add(request)
    }

    func clearExpired() {
        activeSignals.removeAll { $0.isExpired }
        topSignal = activeSignals.first
    }
}
