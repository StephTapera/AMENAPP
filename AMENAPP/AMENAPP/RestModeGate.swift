import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseAnalytics

// MARK: - AmenRoute

enum AmenRoute: String, CaseIterable {
    case feed
    case createPost
    case comments
    case messages
    case notifications
    case findChurch
    case churchNotes
    case bible
    case dailyVerse
    case prayerRequest
    case savedNotes
    case emergencySupport
    case trending
    case likes
    case reposts
    case profile
    case trustedCircle = "trusted_circle"             // TrustedCircleView (emergency family contact)
    case childSafetyReport = "child_safety_report"    // ChildSafetyAgentStubView (stub, pending approval)

    var policyKey: String {
        switch self {
        case .feed:             return "main_feed"
        case .createPost:       return "create_post"
        case .comments:         return "comments"
        case .messages:         return "messages"
        case .notifications:    return "social_notifications"
        case .findChurch:       return "find_church"
        case .churchNotes:      return "church_notes"
        case .bible:            return "bible"
        case .dailyVerse:       return "daily_verse"
        case .prayerRequest:    return "prayer_request"
        case .savedNotes:       return "saved_notes"
        case .emergencySupport: return "emergency_support"
        case .trending:         return "trending"
        case .likes:            return "likes"
        case .reposts:          return "reposts"
        case .profile:          return "profile"
        case .trustedCircle:    return "trusted_circle"
        case .childSafetyReport: return "child_safety_report"
        }
    }
}

// MARK: - RestModeGate

@MainActor
final class RestModeGate: ObservableObject {

    static let shared = RestModeGate()

    @Published var isActive: Bool = false
    @Published var policy: RestModePolicy?
    @Published var overrideExpiresAt: Date?

    private let db = Firestore.firestore()
    private var overrideTimer: Timer?

    private init() {}

    // MARK: Public API

    func canOpen(_ route: AmenRoute) -> Bool {
        guard isActive else { return true }
        guard !isOverrideActive else { return true }
        guard let policy else { return true }
        return policy.allowedRoutes.contains(route.policyKey)
    }

    var isOverrideActive: Bool {
        guard let exp = overrideExpiresAt else { return false }
        return exp > Date()
    }

    var activeLevel: RestModeLevel {
        policy?.modeLevel ?? .worship
    }

    var activeName: String {
        policy?.modeName.displayName ?? "Lord's Day Mode"
    }

    // MARK: Load & evaluate

    func evaluateNow() {
        guard let uid = Auth.auth().currentUser?.uid else {
            isActive = false
            return
        }
        Task { await loadAndEvaluate(userId: uid) }
    }

    private func loadAndEvaluate(userId: String) async {
        do {
            let snap = try await db.collection("restModePolicies").document(userId).getDocument()
            guard snap.exists, let pol = try? snap.data(as: RestModePolicy.self) else {
                isActive = false
                return
            }
            let active = Self.isPolicyActive(pol)
            policy = pol
            isActive = active
            if active {
                Analytics.logEvent("rest_mode_active", parameters: [
                    "mode_level": pol.modeLevel.rawValue,
                    "mode_name": pol.modeName.rawValue
                ])
            }
        } catch {
            isActive = false
        }
    }

    // MARK: Activation logic (pure, testable)

    static func isPolicyActive(_ policy: RestModePolicy) -> Bool {
        guard policy.enabled else { return false }
        let tz = TimeZone(identifier: policy.timezone) ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let now = Date()
        let weekday = cal.component(.weekday, from: now)

        switch policy.activeDay {
        case .sunday:
            guard weekday == 1 else { return false }
        case .saturday:
            guard weekday == 7 else { return false }
        case .custom:
            guard let sched = policy.customSchedule,
                  sched.days.contains(weekday) else { return false }
            return isWithinWindow(now: now, cal: cal, start: sched.startTime, end: sched.endTime)
        }
        return isWithinWindow(now: now, cal: cal, start: policy.startTime, end: policy.endTime)
    }

    static func isWithinWindow(now: Date, cal: Calendar, start: String, end: String) -> Bool {
        let c = cal.dateComponents([.hour, .minute], from: now)
        guard let h = c.hour, let m = c.minute else { return false }
        let nowM  = h * 60 + m
        let startM = parseMins(start)
        let endM   = parseMins(end)
        return startM <= endM ? (nowM >= startM && nowM <= endM) : (nowM >= startM || nowM <= endM)
    }

    static func parseMins(_ hhmm: String) -> Int {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }

    // MARK: Override

    func activateOverride(reason: RestModeOverrideReason) {
        let minutes = policy?.overrideDurationMinutes ?? 15
        overrideExpiresAt = Date().addingTimeInterval(Double(minutes * 60))
        Analytics.logEvent("rest_mode_override_used", parameters: [
            "reason_code": reason.rawValue,
            "duration_minutes": minutes
        ])
        overrideTimer?.invalidate()
        overrideTimer = Timer.scheduledTimer(withTimeInterval: Double(minutes * 60), repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.overrideExpiresAt = nil
            }
        }
    }

    // MARK: Analytics

    func logRouteBlocked(_ route: AmenRoute) {
        Analytics.logEvent("rest_mode_route_blocked", parameters: ["route": route.rawValue])
    }

    func logRestModeHomeViewed() {
        Analytics.logEvent("rest_mode_home_viewed", parameters: [:])
    }

    func logOverrideRequested() {
        Analytics.logEvent("rest_mode_override_requested", parameters: [:])
    }
}

// MARK: - ShouldShowSundayHome convenience

extension RestModeGate {
    var shouldShowSundayHome: Bool {
        isActive && !isOverrideActive
    }
}

// MARK: - Notification filter helper

extension RestModeGate {
    func shouldMuteNotification(type: String) -> Bool {
        guard isActive, !isOverrideActive else { return false }
        return policy?.notificationPolicy.mutedTypes.contains(type) ?? false
    }
}
