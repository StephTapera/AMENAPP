//
//  RemoteKillSwitch.swift
//  AMENAPP
//
//  Feature 57: Remote Kill Switch via Firebase Remote Config.
//  Disable features remotely without an App Store update.
//
//  H-33 addition: Firestore listener on systemStatus/berean.
//  When the bereanSLOCheck Cloud Function detects an SLO breach it writes
//  { status: "degraded" } to that document. This listener reacts in
//  real-time and sets bereanEnabled = false without waiting for the next
//  Remote Config fetch cycle (which can take up to 12 hours in production).
//

import Foundation
import Combine
import FirebaseCore
import FirebaseRemoteConfig
import FirebaseFirestore
import FirebaseAuth

@MainActor
class RemoteKillSwitch: ObservableObject {
    static let shared = RemoteKillSwitch()

    @Published var feedEnabled = true
    @Published var bereanEnabled = true
    @Published var messagingEnabled = true
    @Published var createPostEnabled = true
    @Published var searchEnabled = true
    @Published var notificationsEnabled = true

    @Published var maintenanceMode = false
    @Published var maintenanceMessage = ""
    @Published var minimumAppVersion = "1.0"

    /// Human-readable reason string set when berean is auto-disabled by SLO breach.
    @Published var bereanDegradedReason: String?

    // H-33: Firestore listener for systemStatus/berean (SLO kill switch)
    private var bereanStatusListener: ListenerRegistration?
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    private init() {
        loadFlags()
    }

    deinit {
        if let authStateHandle {
            Auth.auth().removeStateDidChangeListener(authStateHandle)
        }
        bereanStatusListener?.remove()
    }

    func loadFlags() {
        // Guard: Firebase may not be configured yet (SwiftUI initializes @StateObject
        // before AppDelegate.application(_:didFinishLaunchingWithOptions:) runs).
        // Default values (all enabled) are already set via property initializers.
        guard FirebaseApp.app() != nil else { return }

        // 1. Remote Config fetch (scheduled cadence, existing behaviour)
        let config = RemoteConfig.remoteConfig()
        // GAP A5-P1 RC defaults
        config.setDefaults([
            "kill_feed_enabled": true as NSObject,
            "kill_berean_enabled": true as NSObject,
            "kill_messaging_enabled": true as NSObject,
            "kill_create_post_enabled": true as NSObject,
            "kill_search_enabled": true as NSObject,
            "kill_notifications_enabled": true as NSObject,
            "maintenance_mode": false as NSObject,
            "maintenance_message": "" as NSObject,
        ])
        config.fetchAndActivate { [weak self] _, error in
            if let error = error {
                print("[RemoteKillSwitch] fetch error: \(error.localizedDescription)")
            }
            Task { @MainActor [weak self] in
                self?.applyFlags(RemoteConfig.remoteConfig())
            }
        }

        // 2. H-33: Firestore real-time listener — reacts immediately to SLO breaches
        //    written by bereanSLOCheck Cloud Function. This runs independently of
        //    the Remote Config cycle and provides sub-second kill latency.
        startAuthWatcherIfNeeded()
    }

    // MARK: - H-33 Firestore SLO listener

    private func startAuthWatcherIfNeeded() {
        guard authStateHandle == nil else { return }
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if user == nil {
                    self.bereanStatusListener?.remove()
                    self.bereanStatusListener = nil
                    return
                }
                self.attachBereanStatusListener()
            }
        }
    }

    /// Attaches a snapshot listener to `systemStatus/berean`.
    /// When `status == "degraded"` the listener sets `bereanEnabled = false`.
    /// When `status == "healthy"` (auto-recovery) it re-enables Berean only if
    /// Remote Config also has it enabled, to prevent premature re-enablement.
    private func attachBereanStatusListener() {
        bereanStatusListener?.remove()
        bereanStatusListener = Firestore.firestore()
            .document("systemStatus/berean")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error {
                        let nsError = error as NSError
                        if nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
                            self.bereanStatusListener?.remove()
                            self.bereanStatusListener = nil
                            return
                        }
                        print("[RemoteKillSwitch] systemStatus/berean listener error: \(error.localizedDescription)")
                        return
                    }
                    guard let data = snapshot?.data() else { return }
                    let status = data["status"] as? String ?? "healthy"
                    let reason = data["reason"] as? String
                    let autoTriggered = data["autoTriggered"] as? Bool ?? false

                    if status == "degraded" {
                        // SLO breach — disable Berean immediately regardless of Remote Config
                        self.bereanEnabled = false
                        self.bereanDegradedReason = reason ?? "Service temporarily unavailable."
                        print("[RemoteKillSwitch][H-33] Berean disabled by SLO breach: \(reason ?? "unknown")")
                    } else if status == "healthy" && autoTriggered {
                        // Auto-recovery — re-enable only if Remote Config hasn't explicitly
                        // disabled Berean via kill_berean_enabled = false.
                        let rcEnabled = RemoteConfig.remoteConfig()
                            .configValue(forKey: "kill_berean_enabled").boolValue
                        // configValue returns false when the key is absent and no default is set,
                        // so treat the lastFetchStatus guard the same way applyFlags() does.
                        let remoteConfigSaysDegraded = RemoteConfig.remoteConfig().lastFetchStatus != .noFetchYet && !rcEnabled
                        if !remoteConfigSaysDegraded {
                            self.bereanEnabled = true
                            self.bereanDegradedReason = nil
                            print("[RemoteKillSwitch][H-33] Berean re-enabled after SLO recovery.")
                        }
                    }
                }
            }
    }

    // MARK: - Remote Config

    private func applyFlags(_ config: RemoteConfig) {
        feedEnabled = config.configValue(forKey: "kill_feed_enabled").boolValue
        // H-33: Only apply RC value for bereanEnabled if Firestore SLO hasn't already
        // disabled it. The Firestore listener takes precedence while degraded.
        let rcBereanEnabled = config.configValue(forKey: "kill_berean_enabled").boolValue
        if bereanDegradedReason == nil {
            bereanEnabled = rcBereanEnabled
        }
        messagingEnabled = config.configValue(forKey: "kill_messaging_enabled").boolValue
        createPostEnabled = config.configValue(forKey: "kill_create_post_enabled").boolValue
        searchEnabled = config.configValue(forKey: "kill_search_enabled").boolValue
        notificationsEnabled = config.configValue(forKey: "kill_notifications_enabled").boolValue

        maintenanceMode = config.configValue(forKey: "maintenance_mode").boolValue
        maintenanceMessage = config.configValue(forKey: "maintenance_message").stringValue
        minimumAppVersion = config.configValue(forKey: "minimum_app_version").stringValue

        // Default: all enabled if Remote Config hasn't been set
        if config.lastFetchStatus == .noFetchYet {
            feedEnabled = true
            if bereanDegradedReason == nil { bereanEnabled = true }
            messagingEnabled = true
            createPostEnabled = true
            searchEnabled = true
            notificationsEnabled = true
        }
    }

    /// Check if current app version meets minimum requirement.
    var isAppVersionValid: Bool {
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return current.compare(minimumAppVersion, options: .numeric) != .orderedAscending
    }
}
