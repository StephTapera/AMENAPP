import Foundation
import UserNotifications
import CoreLocation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
class SmartPrayerReminderScheduler: NSObject, ObservableObject {
    static let shared = SmartPrayerReminderScheduler()
    
    // MARK: - Published Properties
    @Published var activeReminders: [PrayerReminder] = []
    @Published var locationPermissionGranted = false
    @Published var notificationPermissionGranted = false
    
    // MARK: - Services
    private let locationManager = CLLocationManager()
    private let notificationCenter = UNUserNotificationCenter.current()
    private let db = Firestore.firestore()
    
    // MARK: - User Defaults Keys
    private let remindersKey = "smartPrayerReminders"
    
    private override init() {
        super.init()
        locationManager.delegate = self
        loadReminders()
        checkPermissions()
    }
    
    // MARK: - Permission Management
    
    func requestPermissions() async {
        // Request notification permission
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            notificationPermissionGranted = granted
        } catch {
            print("❌ Notification permission error: \(error)")
        }
        
        // Request location permission
        locationManager.requestWhenInUseAuthorization()
    }
    
    private func checkPermissions() {
        // Check notification permission
        Task {
            let settings = await notificationCenter.notificationSettings()
            notificationPermissionGranted = settings.authorizationStatus == .authorized
        }
        
        // Check location permission
        let status = locationManager.authorizationStatus
        locationPermissionGranted = status == .authorizedWhenInUse || status == .authorizedAlways
    }
    
    // MARK: - Reminder Management
    
    func createReminder(
        title: String,
        type: PrayerReminderType,
        time: Date? = nil,
        location: PrayerLocation? = nil,
        recurrence: RecurrencePattern = .daily,
        isEnabled: Bool = true
    ) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw ReminderError.notAuthenticated
        }
        
        let reminderId = UUID().uuidString
        
        let reminder = PrayerReminder(
            id: reminderId,
            userId: userId,
            title: title,
            type: type,
            time: time,
            location: location,
            recurrence: recurrence,
            isEnabled: isEnabled,
            createdAt: Date()
        )
        
        // Save to Firestore
        try await db.collection("prayerReminders")
            .document(reminderId)
            .setData(reminder.toDictionary())
        
        // Add to local array
        activeReminders.append(reminder)
        saveReminders()
        
        // Schedule notification
        if isEnabled {
            try await scheduleReminder(reminder)
        }
        
        print("✅ Prayer reminder created: \(title)")
    }
    
    func updateReminder(_ reminder: PrayerReminder) async throws {
        guard let index = activeReminders.firstIndex(where: { $0.id == reminder.id }) else {
            throw ReminderError.reminderNotFound
        }
        
        // Update Firestore
        try await db.collection("prayerReminders")
            .document(reminder.id)
            .setData(reminder.toDictionary())
        
        // Update local array
        activeReminders[index] = reminder
        saveReminders()
        
        // Reschedule notification
        cancelReminder(reminder.id)
        if reminder.isEnabled {
            try await scheduleReminder(reminder)
        }
        
        print("✅ Prayer reminder updated: \(reminder.title)")
    }
    
    func deleteReminder(_ reminderId: String) async throws {
        // Delete from Firestore
        try await db.collection("prayerReminders")
            .document(reminderId)
            .delete()
        
        // Remove from local array
        activeReminders.removeAll { $0.id == reminderId }
        saveReminders()
        
        // Cancel notification
        cancelReminder(reminderId)
        
        print("✅ Prayer reminder deleted")
    }
    
    func toggleReminder(_ reminderId: String) async throws {
        guard let index = activeReminders.firstIndex(where: { $0.id == reminderId }) else {
            throw ReminderError.reminderNotFound
        }
        
        var reminder = activeReminders[index]
        reminder.isEnabled.toggle()
        
        try await updateReminder(reminder)
    }
    
    // MARK: - Notification Scheduling
    
    private func scheduleReminder(_ reminder: PrayerReminder) async throws {
        guard notificationPermissionGranted else {
            throw ReminderError.permissionDenied
        }
        
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = getReminderMessage(for: reminder.type)
        content.sound = .default
        content.categoryIdentifier = "PRAYER_REMINDER"
        content.userInfo = ["reminderId": reminder.id]
        
        // Create trigger based on reminder type
        var trigger: UNNotificationTrigger?
        
        switch reminder.type {
        case .timeBased:
            if let time = reminder.time {
                trigger = createTimeTrigger(for: time, recurrence: reminder.recurrence)
            }
            
        case .locationBased:
            if let location = reminder.location, locationPermissionGranted {
                trigger = createLocationTrigger(for: location)
            }
            
        case .hybrid:
            // For hybrid, prioritize time-based scheduling
            // Location will be monitored separately
            if let time = reminder.time {
                trigger = createTimeTrigger(for: time, recurrence: reminder.recurrence)
            }
            
            // Also start monitoring location
            if let location = reminder.location, locationPermissionGranted {
                startMonitoringLocation(location, for: reminder.id)
            }
        }
        
        guard let trigger = trigger else {
            throw ReminderError.invalidTrigger
        }
        
        // Schedule notification
        let request = UNNotificationRequest(
            identifier: reminder.id,
            content: content,
            trigger: trigger
        )
        
        try await notificationCenter.add(request)
        print("✅ Scheduled prayer reminder: \(reminder.title)")
    }
    
    private func createTimeTrigger(for time: Date, recurrence: RecurrencePattern) -> UNNotificationTrigger {
        let calendar = Calendar.current
        var dateComponents = calendar.dateComponents([.hour, .minute], from: time)
        
        switch recurrence {
        case .daily:
            // Repeats daily at the specified time
            return UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            
        case .weekly(let weekdays):
            // For weekly, we'll use the first weekday and let the notification repeat
            if let firstWeekday = weekdays.first {
                dateComponents.weekday = firstWeekday
            }
            return UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            
        case .custom(let interval):
            // Custom interval in seconds
            return UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: true)
            
        case .once:
            // One-time notification at the specified date/time
            let fullDateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: time)
            return UNCalendarNotificationTrigger(dateMatching: fullDateComponents, repeats: false)
        }
    }
    
    private func createLocationTrigger(for location: PrayerLocation) -> UNNotificationTrigger {
        let center = CLLocationCoordinate2D(
            latitude: location.latitude,
            longitude: location.longitude
        )
        
        let region = CLCircularRegion(
            center: center,
            radius: location.radius,
            identifier: location.id
        )
        
        region.notifyOnEntry = location.notifyOnEntry
        region.notifyOnExit = location.notifyOnExit
        
        return UNLocationNotificationTrigger(region: region, repeats: true)
    }
    
    private func cancelReminder(_ reminderId: String) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [reminderId])
        stopMonitoringLocation(reminderId)
        print("✅ Cancelled prayer reminder: \(reminderId)")
    }
    
    // MARK: - Location Monitoring
    
    private func startMonitoringLocation(_ location: PrayerLocation, for reminderId: String) {
        let center = CLLocationCoordinate2D(
            latitude: location.latitude,
            longitude: location.longitude
        )
        
        let region = CLCircularRegion(
            center: center,
            radius: location.radius,
            identifier: reminderId
        )
        
        region.notifyOnEntry = location.notifyOnEntry
        region.notifyOnExit = location.notifyOnExit
        
        locationManager.startMonitoring(for: region)
        print("✅ Started monitoring location: \(location.name)")
    }
    
    private func stopMonitoringLocation(_ reminderId: String) {
        for region in locationManager.monitoredRegions {
            if region.identifier == reminderId {
                locationManager.stopMonitoring(for: region)
                print("✅ Stopped monitoring location for reminder: \(reminderId)")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func getReminderMessage(for type: PrayerReminderType) -> String {
        switch type {
        case .timeBased:
            return "Take a moment to pray and connect with God 🙏"
        case .locationBased:
            return "You're at your prayer location. Time to connect with God 🙏"
        case .hybrid:
            return "Prayer reminder: Seek God in this moment 🙏"
        }
    }
    
    // MARK: - Preset Locations
    
    func addChurchLocation(
        name: String,
        latitude: Double,
        longitude: Double,
        radius: Double = 100.0
    ) async throws {
        let location = PrayerLocation(
            id: UUID().uuidString,
            name: name,
            type: .church,
            latitude: latitude,
            longitude: longitude,
            radius: radius,
            notifyOnEntry: true,
            notifyOnExit: false
        )
        
        try await createReminder(
            title: "Prayer Time at \(name)",
            type: .locationBased,
            location: location,
            recurrence: .daily
        )
    }
    
    func addHomeLocation(
        latitude: Double,
        longitude: Double,
        radius: Double = 50.0
    ) async throws {
        let location = PrayerLocation(
            id: UUID().uuidString,
            name: "Home",
            type: .home,
            latitude: latitude,
            longitude: longitude,
            radius: radius,
            notifyOnEntry: true,
            notifyOnExit: false
        )
        
        try await createReminder(
            title: "Home Prayer Time",
            type: .locationBased,
            location: location,
            recurrence: .daily
        )
    }
    
    // MARK: - Preset Time Schedules
    
    func addMorningPrayer(hour: Int = 7, minute: Int = 0) async throws {
        let calendar = Calendar.current
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        
        guard let time = calendar.date(from: components) else {
            throw ReminderError.invalidTime
        }
        
        try await createReminder(
            title: "Morning Prayer",
            type: .timeBased,
            time: time,
            recurrence: .daily
        )
    }
    
    func addEveningPrayer(hour: Int = 21, minute: Int = 0) async throws {
        let calendar = Calendar.current
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        
        guard let time = calendar.date(from: components) else {
            throw ReminderError.invalidTime
        }
        
        try await createReminder(
            title: "Evening Prayer",
            type: .timeBased,
            time: time,
            recurrence: .daily
        )
    }
    
    func addWeeklyChurchReminder(weekday: Int, hour: Int = 10, minute: Int = 0) async throws {
        let calendar = Calendar.current
        var components = DateComponents()
        components.weekday = weekday // 1 = Sunday, 7 = Saturday
        components.hour = hour
        components.minute = minute
        
        guard let time = calendar.date(from: components) else {
            throw ReminderError.invalidTime
        }
        
        try await createReminder(
            title: "Church Service Reminder",
            type: .timeBased,
            time: time,
            recurrence: .weekly([weekday])
        )
    }
    
    // MARK: - Persistence
    
    private func loadReminders() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        Task {
            do {
                let snapshot = try await db.collection("prayerReminders")
                    .whereField("userId", isEqualTo: userId)
                    .getDocuments()
                
                let reminders = snapshot.documents.compactMap { doc -> PrayerReminder? in
                    try? PrayerReminder.fromDictionary(doc.data())
                }
                
                await MainActor.run {
                    self.activeReminders = reminders
                }
                
                print("✅ Loaded \(reminders.count) prayer reminders")
            } catch {
                print("❌ Error loading reminders: \(error)")
            }
        }
    }
    
    private func saveReminders() {
        // Reminders are already saved to Firestore in create/update methods
        // This method is kept for compatibility
    }
    
    // MARK: - Analytics
    
    func getReminderStats() -> ReminderStats {
        let total = activeReminders.count
        let enabled = activeReminders.filter { $0.isEnabled }.count
        let timeBased = activeReminders.filter { $0.type == .timeBased }.count
        let locationBased = activeReminders.filter { $0.type == .locationBased }.count
        let hybrid = activeReminders.filter { $0.type == .hybrid }.count
        
        return ReminderStats(
            total: total,
            enabled: enabled,
            timeBased: timeBased,
            locationBased: locationBased,
            hybrid: hybrid
        )
    }
}

// MARK: - CLLocationManagerDelegate

extension SmartPrayerReminderScheduler: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            locationPermissionGranted = status == .authorizedWhenInUse || status == .authorizedAlways
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        print("✅ Entered prayer location: \(region.identifier)")
        // The notification will be triggered by UNLocationNotificationTrigger
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        print("✅ Exited prayer location: \(region.identifier)")
    }
}

// MARK: - Models

struct PrayerReminder: Identifiable, Codable {
    let id: String
    let userId: String
    let title: String
    let type: PrayerReminderType
    let time: Date?
    let location: PrayerLocation?
    let recurrence: RecurrencePattern
    var isEnabled: Bool
    let createdAt: Date
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "userId": userId,
            "title": title,
            "type": type.rawValue,
            "recurrence": recurrence.toDictionary(),
            "isEnabled": isEnabled,
            "createdAt": Timestamp(date: createdAt)
        ]
        
        if let time = time {
            dict["time"] = Timestamp(date: time)
        }
        
        if let location = location {
            dict["location"] = location.toDictionary()
        }
        
        return dict
    }
    
    static func fromDictionary(_ dict: [String: Any]) throws -> PrayerReminder {
        guard let id = dict["id"] as? String,
              let userId = dict["userId"] as? String,
              let title = dict["title"] as? String,
              let typeRaw = dict["type"] as? String,
              let type = PrayerReminderType(rawValue: typeRaw),
              let recurrenceDict = dict["recurrence"] as? [String: Any],
              let recurrence = RecurrencePattern.fromDictionary(recurrenceDict),
              let isEnabled = dict["isEnabled"] as? Bool,
              let createdAtTimestamp = dict["createdAt"] as? Timestamp else {
            throw ReminderError.invalidData
        }
        
        let time = (dict["time"] as? Timestamp)?.dateValue()
        let location = (dict["location"] as? [String: Any]).flatMap { try? PrayerLocation.fromDictionary($0) }
        
        return PrayerReminder(
            id: id,
            userId: userId,
            title: title,
            type: type,
            time: time,
            location: location,
            recurrence: recurrence,
            isEnabled: isEnabled,
            createdAt: createdAtTimestamp.dateValue()
        )
    }
}

enum PrayerReminderType: String, Codable {
    case timeBased
    case locationBased
    case hybrid
}

struct PrayerLocation: Codable {
    let id: String
    let name: String
    let type: LocationType
    let latitude: Double
    let longitude: Double
    let radius: Double
    let notifyOnEntry: Bool
    let notifyOnExit: Bool
    
    enum LocationType: String, Codable {
        case church
        case home
        case custom
    }
    
    func toDictionary() -> [String: Any] {
        return [
            "id": id,
            "name": name,
            "type": type.rawValue,
            "latitude": latitude,
            "longitude": longitude,
            "radius": radius,
            "notifyOnEntry": notifyOnEntry,
            "notifyOnExit": notifyOnExit
        ]
    }
    
    static func fromDictionary(_ dict: [String: Any]) throws -> PrayerLocation {
        guard let id = dict["id"] as? String,
              let name = dict["name"] as? String,
              let typeRaw = dict["type"] as? String,
              let type = LocationType(rawValue: typeRaw),
              let latitude = dict["latitude"] as? Double,
              let longitude = dict["longitude"] as? Double,
              let radius = dict["radius"] as? Double,
              let notifyOnEntry = dict["notifyOnEntry"] as? Bool,
              let notifyOnExit = dict["notifyOnExit"] as? Bool else {
            throw ReminderError.invalidData
        }
        
        return PrayerLocation(
            id: id,
            name: name,
            type: type,
            latitude: latitude,
            longitude: longitude,
            radius: radius,
            notifyOnEntry: notifyOnEntry,
            notifyOnExit: notifyOnExit
        )
    }
}

enum RecurrencePattern: Codable, Equatable {
    case daily
    case weekly([Int]) // Array of weekdays (1 = Sunday, 7 = Saturday)
    case custom(TimeInterval) // Custom interval in seconds
    case once
    
    func toDictionary() -> [String: Any] {
        switch self {
        case .daily:
            return ["type": "daily"]
        case .weekly(let weekdays):
            return ["type": "weekly", "weekdays": weekdays]
        case .custom(let interval):
            return ["type": "custom", "interval": interval]
        case .once:
            return ["type": "once"]
        }
    }
    
    static func fromDictionary(_ dict: [String: Any]) -> RecurrencePattern? {
        guard let type = dict["type"] as? String else { return nil }
        
        switch type {
        case "daily":
            return .daily
        case "weekly":
            if let weekdays = dict["weekdays"] as? [Int] {
                return .weekly(weekdays)
            }
            return nil
        case "custom":
            if let interval = dict["interval"] as? TimeInterval {
                return .custom(interval)
            }
            return nil
        case "once":
            return .once
        default:
            return nil
        }
    }
}

struct ReminderStats {
    let total: Int
    let enabled: Int
    let timeBased: Int
    let locationBased: Int
    let hybrid: Int
}

enum ReminderError: Error, LocalizedError {
    case notAuthenticated
    case reminderNotFound
    case permissionDenied
    case invalidTrigger
    case invalidTime
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User not authenticated"
        case .reminderNotFound:
            return "Reminder not found"
        case .permissionDenied:
            return "Permission denied. Please enable notifications and location access."
        case .invalidTrigger:
            return "Invalid reminder trigger"
        case .invalidTime:
            return "Invalid time specified"
        case .invalidData:
            return "Invalid reminder data"
        }
    }
}
