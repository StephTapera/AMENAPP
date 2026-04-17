import Foundation
import FirebaseAuth

// MARK: - Chat Calendar Bridge
/// Bridges ChatMemoryItem date data to CalendarService for EventKit integration.
/// Handles permission flow, event construction, duplicate detection, and
/// confirmation tracking back to memory items.

@MainActor
final class ChatCalendarBridge: ObservableObject {
    static let shared = ChatCalendarBridge()

    @Published var showCalendarConfirmation = false
    @Published var pendingCalendarItem: ChatMemoryItem?
    @Published var lastAddedEventTitle: String?
    @Published private(set) var isAdding = false

    private let calendarService = CalendarService.shared
    private let memoryService = ChatMemoryService.shared

    private init() {}

    // MARK: - Public API

    /// Prompt the user to add a memory item's date to their calendar.
    /// Shows confirmation alert — never auto-commits.
    func promptCalendarAdd(for item: ChatMemoryItem) {
        guard item.calendarState == .pending || item.calendarState == .none else { return }
        guard item.dueDate != nil else { return }

        pendingCalendarItem = item
        showCalendarConfirmation = true

        // Mark as prompted
        Task {
            await memoryService.updateCalendarState(item, state: .prompted)
        }
    }

    /// After user confirms, actually create the calendar event.
    func confirmCalendarAdd() async {
        guard let item = pendingCalendarItem, let dueDate = item.dueDate else {
            pendingCalendarItem = nil
            showCalendarConfirmation = false
            return
        }

        isAdding = true

        // Request permission if needed
        let hasPermission = await calendarService.requestCalendarPermission()
        guard hasPermission else {
            await memoryService.updateCalendarState(item, state: .dismissed)
            isAdding = false
            pendingCalendarItem = nil
            showCalendarConfirmation = false
            return
        }

        // Construct AMENEvent from memory item
        let event = constructEvent(from: item, date: dueDate)

        // Add to calendar
        if let eventId = await calendarService.addEventToCalendar(event) {
            await memoryService.updateCalendarState(item, state: .added, eventId: eventId)
            lastAddedEventTitle = item.summary
            dlog("✅ [ChatCalendar] Added event: \(item.summary)")
        } else {
            await memoryService.updateCalendarState(item, state: .dismissed)
            dlog("⚠️ [ChatCalendar] Failed to add event")
        }

        isAdding = false
        pendingCalendarItem = nil
        showCalendarConfirmation = false
    }

    /// User declined the calendar add.
    func declineCalendarAdd() async {
        guard let item = pendingCalendarItem else {
            showCalendarConfirmation = false
            return
        }

        await memoryService.updateCalendarState(item, state: .dismissed)
        pendingCalendarItem = nil
        showCalendarConfirmation = false
    }

    // MARK: - Event Construction

    private func constructEvent(from item: ChatMemoryItem, date: Date) -> AMENEvent {
        let calendar = Calendar.current
        let endDate = calendar.date(byAdding: .hour, value: 1, to: date) ?? date

        let uid = Auth.auth().currentUser?.uid ?? ""
        let displayName = Auth.auth().currentUser?.displayName ?? "Me"

        return AMENEvent(
            title: item.title.isEmpty ? item.summary : item.title,
            eventType: .generalReminder,
            startDate: date,
            endDate: endDate,
            timeZoneIdentifier: TimeZone.current.identifier,
            location: nil,
            locationURL: nil,
            isOnline: false,
            onlineMeetingURL: nil,
            notes: "From AMEN chat: \(item.summary)",
            organizerName: displayName,
            organizerId: uid,
            organizerAvatarURL: nil,
            imageURL: nil,
            deepLinkURL: nil,
            capacity: 0,
            rsvpCount: 0,
            rsvpDeadline: nil,
            requiresApproval: false,
            isPublic: false,
            isFeatured: false,
            tags: ["chat-memory"],
            reminderOffsets: [.fifteenMinutesBefore],
            moderationState: "active",
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
