// ShabbatModeService.swift
// AMENAPP
//
// Single source of truth for Shabbat Mode.
// - Active all day Sunday in user's LOCAL timezone (not server time)
// - Default ON for all users
// - User toggle persisted locally (UserDefaults) + remotely (Firestore users/{uid})
// - Cross-device sync: on app launch the remote value overwrites the local one
// - Stores IANA timezone string in device token doc so the server can validate
// - Logs analytics events for every blocked action

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Combine

// MARK: - AppFeature enum (single source of truth for all features)

/// Every navigable surface and action in the app.
/// Add new features here — the gate check in AppAccessController is the ONLY place that maps allowed/blocked.
enum AppFeature: String, CaseIterable {
    // Allowed on Shabbat
    case churchNotes      = "church_notes"
    case findChurch       = "find_church"
    case settings         = "settings"

    // Blocked on Shabbat
    case feed             = "feed"
    case postCreate       = "post_create"
    case commentCreate    = "comment_create"
    case reactions        = "reactions"
    case messages         = "messages"
    case notifications    = "notifications"
    case profileBrowse    = "profile_browse"
    case profileEdit      = "profile_edit"
    case peopleDiscovery  = "people_discovery"
    case search           = "search"
    case bereanAI         = "berean_ai"
    case prayer           = "prayer"
    case testimonies      = "testimonies"
    case repost           = "repost"
    case savePost         = "save_post"
    case createActivity   = "create_activity"

    /// Whether this feature is always allowed during Shabbat Mode.
    var isAllowedDuringShabbat: Bool {
        switch self {
        case .churchNotes, .findChurch, .settings:
            return true
        default:
            return false
        }
    }
}

// MARK: - AppAccessResult

enum AppAccessResult {
    case allowed
    case blocked(reason: ShabbatBlockReason)
}

struct ShabbatBlockReason {
    let feature: AppFeature
    let message: String = "AMEN is in Shabbat Mode. Church Notes and Find a Church are available today."
    let errorCode: String = "SHABBAT_MODE_BLOCKED"
}

// MARK: - ShabbatModeService

@MainActor
final class ShabbatModeService: ObservableObject {
    static let shared = ShabbatModeService()

    // MARK: - Published state

    /// True when it is Sunday in the user's local timezone.
    @Published private(set) var isSunday: Bool = false
    /// The user-controlled master toggle. Default = OFF (opt-in).
    @Published private(set) var isEnabled: Bool = false
    /// True when restrictions are actively applied (isSunday && isEnabled).
    @Published private(set) var isShabbatActive: Bool = false

    // MARK: - UserDefaults keys

    private let enabledKey   = "shabbatMode_enabled"
    private let timezoneKey  = "shabbatMode_userTimezone"

    // MARK: - Internal

    private var timer: AnyCancellable?
    private var firestoreListener: ListenerRegistration?

    // MARK: - Init

    private init() {
        loadLocalPreference()
        updateSundayState()
        startMinuteTicker()
        startFirestoreSync()
    }

    deinit {
        timer?.cancel()
        firestoreListener?.remove()
    }

    // MARK: - Public API

    /// Whether Shabbat is currently active.
    func isShabbatActiveNow() -> Bool { isShabbatActive }

    /// Whether a given feature may be accessed right now.
    func canAccess(_ feature: AppFeature) -> AppAccessResult {
        guard isShabbatActive else { return .allowed }
        guard !feature.isAllowedDuringShabbat else { return .allowed }
        return .blocked(reason: ShabbatBlockReason(feature: feature))
    }

    /// Enable or disable Shabbat Mode. Persists locally and to Firestore.
    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        updateShabbatActiveState()
        persistToFirestore(enabled: enabled)
        // Note: logStateTransition is called inside updateShabbatActiveState() on active→inactive
        // or inactive→active transitions; no separate call needed here.
        print("🕊️ ShabbatModeService: isEnabled = \(enabled)")
    }

    /// Returns true if today is Sunday in the given timezone (defaults to device timezone).
    func isSundayNow(in timeZone: TimeZone = .current) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.component(.weekday, from: Date()) == 1  // 1 == Sunday
    }

    /// The user's IANA timezone identifier (stored in device token for backend use).
    var userTimezoneIdentifier: String {
        TimeZone.current.identifier
    }

    // MARK: - Analytics hook

    /// Call this when a blocked action is attempted.
    func logBlocked(feature: AppFeature, route: String? = nil) {
        ShabbatAnalytics.logBlocked(feature: feature, route: route)
    }

    // MARK: - Private helpers

    private func loadLocalPreference() {
        // Default OFF: user must opt in via Settings → Sunday Church Focus
        if UserDefaults.standard.object(forKey: enabledKey) == nil {
            isEnabled = false
        } else {
            isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        }
    }

    private func updateSundayState() {
        let newIsSunday = isSundayNow()
        if isSunday != newIsSunday {
            isSunday = newIsSunday
        }
        updateShabbatActiveState()
    }

    private func updateShabbatActiveState() {
        let newActive = isEnabled && isSunday
        if isShabbatActive != newActive {
            isShabbatActive = newActive
            if newActive {
                ShabbatAnalytics.logStateTransition(enabled: true, isSunday: true)
            }
        }
    }

    private func startMinuteTicker() {
        // Re-evaluate every 60 s; catches midnight transitions
        timer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateSundayState()
            }
    }

    // MARK: - Firestore sync

    /// On init, read remote value and start listening for cross-device changes.
    private func startFirestoreSync() {
        guard let uid = Auth.auth().currentUser?.uid else {
            // Not signed in yet — listen for auth state change
            NotificationCenter.default.addObserver(
                forName: .init("AuthStateDidChange"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.startFirestoreSync() }
            }
            return
        }
        attachFirestoreListener(uid: uid)
    }

    private func attachFirestoreListener(uid: String) {
        let ref = Firestore.firestore().collection("users").document(uid)
        firestoreListener = ref.addSnapshotListener { [weak self] snapshot, _ in
            guard let self, let data = snapshot?.data() else { return }
            if let remoteEnabled = data["shabbatModeEnabled"] as? Bool {
                if remoteEnabled != self.isEnabled {
                    self.isEnabled = remoteEnabled
                    UserDefaults.standard.set(remoteEnabled, forKey: self.enabledKey)
                    self.updateShabbatActiveState()
                }
            }
        }
    }

    private func persistToFirestore(enabled: Bool) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let ref = Firestore.firestore().collection("users").document(uid)
        ref.setData(["shabbatModeEnabled": enabled], merge: true) { error in
            if let error {
                print("⚠️ ShabbatModeService: Firestore write failed: \(error)")
            }
        }
    }
}

// MARK: - AppAccessController (centralized gate)

/// Thin façade over ShabbatModeService — use this at every call site.
@MainActor
final class AppAccessController {
    static let shared = AppAccessController()
    private init() {}

    func canAccess(_ feature: AppFeature) -> AppAccessResult {
        ShabbatModeService.shared.canAccess(feature)
    }

    /// Convenience: returns true if allowed, logs + returns false if blocked.
    @discardableResult
    func checkAndLog(_ feature: AppFeature, route: String? = nil) -> Bool {
        let result = canAccess(feature)
        switch result {
        case .allowed:
            return true
        case .blocked(let reason):
            ShabbatModeService.shared.logBlocked(feature: feature, route: route)
            print("🚫 AppAccessController: blocked \(feature.rawValue) — \(reason.errorCode)")
            return false
        }
    }
}

// MARK: - ShabbatAnalytics

enum ShabbatAnalytics {
    /// Log when Shabbat restrictions block a user action.
    static func logBlocked(feature: AppFeature, route: String?) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        // Hash the uid so analytics is privacy-safe
        let hashedUid = String(uid.hashValue)
        let entry: [String: Any] = [
            "event": "shabbat_blocked",
            "feature": feature.rawValue,
            "route": route ?? "unknown",
            "timezone": TimeZone.current.identifier,
            "timestamp": FieldValue.serverTimestamp(),
            "userId_hashed": hashedUid
        ]
        // Write to a lightweight analytics collection (best-effort, not awaited)
        Firestore.firestore()
            .collection("analytics_shabbat_blocks")
            .addDocument(data: entry)
        print("📊 shabbat_blocked: feature=\(feature.rawValue) route=\(route ?? "-")")
    }

    /// Log when Shabbat active state transitions (foreground re-entry or toggle).
    static func logStateTransition(enabled: Bool, isSunday: Bool) {
        print("📊 shabbat_state_transition: enabled=\(enabled) isSunday=\(isSunday) tz=\(TimeZone.current.identifier)")
    }
}
