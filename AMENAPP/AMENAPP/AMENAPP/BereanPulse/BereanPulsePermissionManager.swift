import Contacts
import CoreLocation
import EventKit
import Foundation
import FirebaseAuth
import FirebaseFirestore
import UserNotifications

@MainActor
final class BereanPulsePermissionManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var statuses: [BereanPulsePermissionSource: BereanPulsePermissionStatus] = [:]
    @Published var preferenceToggles: [BereanPulsePermissionSource: Bool] = [:]

    private let locationManager = CLLocationManager()
    private let eventStore = EKEventStore()
    private let contactsStore = CNContactStore()
    private let defaults = UserDefaults.standard
    private let db = Firestore.firestore()
    private var locationContinuation: CheckedContinuation<BereanPulsePermissionStatus, Never>?

    override init() {
        super.init()
        locationManager.delegate = self
        BereanPulsePermissionSource.allCases.forEach {
            preferenceToggles[$0] = defaults.object(forKey: toggleKey(for: $0)) as? Bool ?? defaultToggle(for: $0)
        }
        refreshStatuses()
        Task { await loadServerToggles() }
    }

    func refreshStatuses() {
        statuses[.location] = mapLocationStatus(locationManager.authorizationStatus)
        statuses[.calendar] = mapCalendarStatus(EKEventStore.authorizationStatus(for: .event))
        statuses[.contacts] = mapContactsStatus(CNContactStore.authorizationStatus(for: .contacts))
        statuses[.notifications] = .notRequested

        for source in BereanPulsePermissionSource.allCases where statuses[source] == nil {
            statuses[source] = preferenceToggles[source] == true ? .granted : .notRequested
        }

        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run {
                self.statuses[.notifications] = self.mapNotificationStatus(settings.authorizationStatus)
            }
        }
    }

    func status(for source: BereanPulsePermissionSource) -> BereanPulsePermissionStatus {
        statuses[source] ?? .notRequested
    }

    func isGranted(_ source: BereanPulsePermissionSource) -> Bool {
        status(for: source) == .granted
    }

    func setConsent(_ granted: Bool, for source: BereanPulsePermissionSource) {
        preferenceToggles[source] = granted
        defaults.set(granted, forKey: toggleKey(for: source))
        if !source.requiresSystemPrompt {
            statuses[source] = granted ? .granted : .denied
        }
        Task { await persistConsent(for: source, granted: granted) }
    }

    func requestPermission(for source: BereanPulsePermissionSource) async -> BereanPulsePermissionStatus {
        switch source {
        case .location:
            if status(for: .location) != .notRequested {
                return status(for: .location)
            }
            return await withCheckedContinuation { continuation in
                locationContinuation = continuation
                locationManager.requestWhenInUseAuthorization()
            }
        case .calendar:
            do {
                let granted = try await eventStore.requestFullAccessToEvents()
                let status: BereanPulsePermissionStatus = granted ? .granted : .denied
                statuses[.calendar] = status
                await persistConsent(for: .calendar, granted: granted)
                return status
            } catch {
                statuses[.calendar] = .denied
                await persistConsent(for: .calendar, granted: false)
                return .denied
            }
        case .contacts:
            do {
                let granted = try await contactsStore.requestAccess(for: .contacts)
                let status: BereanPulsePermissionStatus = granted ? .granted : .denied
                statuses[.contacts] = status
                await persistConsent(for: .contacts, granted: granted)
                return status
            } catch {
                statuses[.contacts] = .denied
                await persistConsent(for: .contacts, granted: false)
                return .denied
            }
        case .notifications:
            let granted = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            let status: BereanPulsePermissionStatus = granted == true ? .granted : .denied
            statuses[.notifications] = status
            await persistConsent(for: .notifications, granted: granted == true)
            return status
        case .amenActivity, .bereanChatHistory, .savedPosts, .prayerJournal, .churchActivity, .wellnessHealth, .workProjectContext, .appUsageBehavior:
            setConsent(true, for: source)
            return .granted
        }
    }

    func limitedExplanation(for source: BereanPulsePermissionSource) -> String {
        String(localized: source.explanationKey)
    }

    private func defaultToggle(for source: BereanPulsePermissionSource) -> Bool {
        switch source {
        case .amenActivity, .churchActivity, .savedPosts, .appUsageBehavior:
            return true
        case .bereanChatHistory, .prayerJournal, .location, .calendar, .contacts, .notifications, .wellnessHealth, .workProjectContext:
            return false
        }
    }

    private func toggleKey(for source: BereanPulsePermissionSource) -> String {
        "bereanPulse.toggle.\(source.rawValue)"
    }

    private func mapLocationStatus(_ status: CLAuthorizationStatus) -> BereanPulsePermissionStatus {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notRequested
        @unknown default:
            return .unavailable
        }
    }

    private func mapCalendarStatus(_ status: EKAuthorizationStatus) -> BereanPulsePermissionStatus {
        switch status {
        case .fullAccess, .writeOnly:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notRequested
        @unknown default:
            return .unavailable
        }
    }

    private func mapContactsStatus(_ status: CNAuthorizationStatus) -> BereanPulsePermissionStatus {
        switch status {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notRequested
        case .limited:
            return .limited
        @unknown default:
            return .unavailable
        }
    }

    private func mapNotificationStatus(_ status: UNAuthorizationStatus) -> BereanPulsePermissionStatus {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return .granted
        case .denied:
            return .denied
        case .notDetermined:
            return .notRequested
        @unknown default:
            return .unavailable
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = mapLocationStatus(manager.authorizationStatus)
        statuses[.location] = status
        if status != .notRequested {
            locationContinuation?.resume(returning: status)
            locationContinuation = nil
            Task { await persistConsent(for: .location, granted: status == .granted) }
        }
    }

    private func loadServerToggles() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let document = try await db.collection("users")
                .document(uid)
                .collection("bereanPulse")
                .document("main")
                .collection("permissions")
                .document("main")
                .getDocument()
            guard let data = document.data() else { return }
            for source in BereanPulsePermissionSource.allCases {
                if let granted = data[source.rawValue] as? Bool {
                    preferenceToggles[source] = granted
                    defaults.set(granted, forKey: toggleKey(for: source))
                    if !source.requiresSystemPrompt {
                        statuses[source] = granted ? .granted : .denied
                    }
                }
            }
        } catch {
            return
        }
    }

    private func persistConsent(for source: BereanPulsePermissionSource, granted: Bool) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try? await db.collection("users")
            .document(uid)
            .collection("bereanPulse")
            .document("main")
            .collection("permissions")
            .document("main")
            .setData([source.rawValue: granted, "updatedAt": Timestamp(date: Date())], merge: true)
    }
}
