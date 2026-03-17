// EventDetailView.swift
// AMEN Calendar — Event Detail Page with Add to Calendar + RSVP
// Privacy-first, native iOS calendar UX

import SwiftUI
import EventKitUI
import EventKit

struct EventDetailView: View {
    let event: AMENEvent

    @StateObject private var calendarService = CalendarService.shared
    @StateObject private var reminderService = ReminderSchedulerService.shared
    @State private var myRSVP: AMENEventRSVP?
    @State private var calendarAddState: CalendarAddState = .none
    @State private var selectedReminderOffsets: Set<ReminderOffset> = []
    @State private var showCalendarPermissionExplanation = false
    @State private var showNativeEventEditor = false
    @State private var ekEventForEditing: EKEvent?
    @State private var showAddOptions = false
    @State private var isAddingToCalendar = false
    @State private var isLoadingRSVP = true
    @State private var showRSVPSheet = false
    @Environment(\.dismiss) private var dismiss

    enum CalendarAddState {
        case none, added, failed
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Event hero
                    eventHero

                    VStack(alignment: .leading, spacing: 20) {
                        // Title + organizer
                        eventHeader

                        // Date/time/location
                        eventDetailsGrid

                        Divider()

                        // Notes
                        if let notes = event.notes, !notes.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                sectionTitle("About This Event")
                                Text(notes)
                                    .font(.custom("OpenSans-Regular", size: 15))
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        // RSVP section
                        rsvpSection

                        // Calendar section
                        calendarSection

                        // Reminders section (shown after calendar added)
                        if calendarAddState == .added || myRSVP?.addedToCalendar == true {
                            remindersSection
                        }

                        // Safety / info note
                        safetyNote

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .font(.custom("OpenSans-Regular", size: 15))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    shareButton
                }
            }
            .task {
                myRSVP = await calendarService.fetchMyRSVP(for: event.id ?? "")
                if calendarService.isAlreadySaved(event) { calendarAddState = .added }

                // Pre-select suggested reminders
                let suggested = reminderService.suggestedReminders(for: event.eventType)
                selectedReminderOffsets = Set(suggested)
                isLoadingRSVP = false

                // Check notification permission
                reminderService.checkNotificationPermission()
            }
            .sheet(isPresented: $showNativeEventEditor) {
                if let ekEvent = ekEventForEditing {
                    EKEventEditViewWrapper(event: ekEvent, eventStore: CalendarService.shared)
                }
            }
            .sheet(isPresented: $showRSVPSheet) {
                RSVPFlowView(event: event) { status in
                    Task {
                        myRSVP = await calendarService.fetchMyRSVP(for: event.id ?? "")
                    }
                }
            }
        }
    }

    // MARK: - Event Hero

    @ViewBuilder
    private var eventHero: some View {
        ZStack(alignment: .bottomLeading) {
            if let imageURL = event.imageURL, let url = URL(string: imageURL) {
                CachedAsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    eventHeroPlaceholder
                }
                .frame(maxWidth: .infinity, maxHeight: 220)
                .clipped()
            } else {
                eventHeroPlaceholder
                    .frame(height: 200)
            }

            // Event type badge
            HStack(spacing: 6) {
                Image(systemName: event.eventType.icon)
                    .font(.system(size: 13))
                Text(event.eventType.label)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(16)
        }
    }

    @ViewBuilder
    private var eventHeroPlaceholder: some View {
        ZStack {
            event.eventType.color.opacity(0.25)
            Image(systemName: event.eventType.icon)
                .font(.system(size: 52))
                .foregroundStyle(event.eventType.color)
        }
    }

    // MARK: - Event Header

    @ViewBuilder
    private var eventHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            if event.isFeatured {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill").foregroundStyle(.yellow).font(.system(size: 11))
                    Text("Featured Event").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                }
            }

            Text(event.title)
                .font(.custom("OpenSans-Bold", size: 26))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Image(systemName: "person.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("By \(event.organizerName)")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Event Details Grid

    @ViewBuilder
    private var eventDetailsGrid: some View {
        VStack(spacing: 10) {
            // Date / Time
            detailRow(
                icon: "calendar",
                color: event.eventType.color,
                title: formattedDateRange,
                subtitle: formattedTimeRange
            )

            // Time Zone (if not local)
            if event.timeZone.identifier != TimeZone.current.identifier {
                detailRow(
                    icon: "globe",
                    color: .secondary,
                    title: "Time Zone: \(event.timeZone.identifier)",
                    subtitle: localTimeConversion
                )
            }

            // Location
            if event.isOnline {
                detailRow(
                    icon: "video.fill",
                    color: Color(red: 0.15, green: 0.45, blue: 0.90),
                    title: "Online Event",
                    subtitle: event.onlineMeetingURL != nil ? "Link shared after RSVP" : nil
                )
            } else if let location = event.location {
                detailRow(
                    icon: "mappin.circle.fill",
                    color: .red,
                    title: location,
                    subtitle: nil
                )
            }

            // Capacity
            if event.capacity > 0 {
                let spotsLeft = max(0, event.capacity - event.rsvpCount)
                detailRow(
                    icon: "person.2.fill",
                    color: spotsLeft < 10 ? .orange : .secondary,
                    title: "\(event.rsvpCount) attending",
                    subtitle: spotsLeft > 0 ? "\(spotsLeft) spots remaining" : "Event is full"
                )
            }
        }
    }

    // MARK: - RSVP Section

    @ViewBuilder
    private var rsvpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Your RSVP")

            if isLoadingRSVP {
                ProgressView()
            } else if let rsvp = myRSVP {
                currentRSVPView(rsvp)
            } else {
                rsvpCTA
            }
        }
        .padding(16)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func currentRSVPView(_ rsvp: AMENEventRSVP) -> some View {
        HStack(spacing: 12) {
            Image(systemName: rsvp.status.icon)
                .font(.system(size: 22))
                .foregroundStyle(rsvp.status.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(rsvp.status.label)
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(rsvp.status.color)
                Text("Tap to change your response")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showRSVPSheet = true
            } label: {
                Text("Change")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.15, green: 0.45, blue: 0.90))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.15, green: 0.45, blue: 0.90).opacity(0.10), in: Capsule())
            }
        }
    }

    @ViewBuilder
    private var rsvpCTA: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                rsvpButton(status: .going)
                rsvpButton(status: .maybe)
                rsvpButton(status: .notGoing)
            }
        }
    }

    @ViewBuilder
    private func rsvpButton(status: RSVPStatus) -> some View {
        Button {
            Task {
                try? await calendarService.rsvp(eventId: event.id ?? "", status: status)
                myRSVP = await calendarService.fetchMyRSVP(for: event.id ?? "")
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: status.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(status.color)
                Text(status.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(status.color)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(status.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Calendar Section

    @ViewBuilder
    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Add to Calendar")

            switch calendarAddState {
            case .none:
                calendarAddOptions

            case .added:
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color(red: 0.18, green: 0.62, blue: 0.36))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Added to Calendar")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                            .foregroundStyle(Color(red: 0.18, green: 0.62, blue: 0.36))
                        Text("You'll find it in your calendar app")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            calendarAddState = .none
                        }
                    } label: {
                        Text("Undo")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

            case .failed:
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Couldn't add to calendar")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Check calendar permissions in Settings.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var calendarAddOptions: some View {
        VStack(spacing: 10) {
            // Quick add
            Button {
                addToCalendarWithPermission(useNativeEditor: false)
            } label: {
                HStack {
                    if isAddingToCalendar {
                        ProgressView().tint(.white)
                    } else {
                        Label("Add to Calendar", systemImage: "calendar.badge.plus")
                    }
                }
                .font(.custom("OpenSans-SemiBold", size: 15))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(event.eventType.color, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(isAddingToCalendar)

            // Open native editor (user controls all fields)
            Button {
                addToCalendarWithPermission(useNativeEditor: true)
            } label: {
                Label("Add with Calendar App", systemImage: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(event.eventType.color)
            }
            .buttonStyle(.plain)

            // Privacy note
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                Text("AMEN only adds this event — it never reads your other calendar events.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Reminders Section

    @ViewBuilder
    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("Reminders")
                Spacer()
                if !reminderService.notificationPermissionGranted {
                    Text("Enable in Settings")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            if reminderService.notificationPermissionGranted {
                VStack(spacing: 6) {
                    ForEach(ReminderOffset.allCases.prefix(6)) { offset in
                        // Only show future-dated reminders
                        let fireDate = event.startDate.addingTimeInterval(-TimeInterval(offset.minutesBefore * 60))
                        if fireDate > Date() {
                            reminderToggleRow(offset: offset)
                        }
                    }
                }

                Button {
                    scheduleSelectedReminders()
                } label: {
                    Text("Save Reminders")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(red: 0.15, green: 0.45, blue: 0.90), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "bell.slash.fill")
                        .foregroundStyle(.secondary)
                    Text("Turn on notifications in Settings to receive event reminders.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(16)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func reminderToggleRow(offset: ReminderOffset) -> some View {
        HStack {
            Image(systemName: selectedReminderOffsets.contains(offset) ? "bell.fill" : "bell")
                .font(.system(size: 14))
                .foregroundStyle(selectedReminderOffsets.contains(offset) ? event.eventType.color : .secondary)
                .frame(width: 24)
            Text(offset.label)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.primary)
            Spacer()
            Toggle("", isOn: Binding(
                get: { selectedReminderOffsets.contains(offset) },
                set: { isOn in
                    if isOn {
                        selectedReminderOffsets.insert(offset)
                    } else {
                        selectedReminderOffsets.remove(offset)
                    }
                }
            ))
            .labelsHidden()
            .tint(event.eventType.color)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Safety Note

    @ViewBuilder
    private var safetyNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text("This event is hosted by \(event.organizerName). AMEN doesn't verify every event detail. Use your judgment.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Share Button

    @ViewBuilder
    private var shareButton: some View {
        ShareLink(
            item: event.deepLinkURL.flatMap { URL(string: $0) } ?? URL(string: "https://amenapp.com")!,
            subject: Text(event.title),
            message: Text("\(event.title) — \(formattedDateRange) on AMEN")
        ) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15))
        }
    }

    // MARK: - Formatting Helpers

    private var formattedDateRange: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeZone = event.timeZone
        return formatter.string(from: event.startDate)
    }

    private var formattedTimeRange: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.timeZone = event.timeZone
        return "\(formatter.string(from: event.startDate)) – \(formatter.string(from: event.endDate))"
    }

    private var localTimeConversion: String? {
        guard event.timeZone.identifier != TimeZone.current.identifier else { return nil }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.timeZone = .current
        return "Your local time: \(formatter.string(from: event.startDate))"
    }

    // MARK: - Actions

    private func addToCalendarWithPermission(useNativeEditor: Bool) {
        Task {
            // Check if permission is needed
            if calendarService.permissionState == .notDetermined {
                showCalendarPermissionExplanation = true
                return
            }

            if calendarService.permissionState == .denied {
                // Guide to settings
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    await UIApplication.shared.open(url)
                }
                return
            }

            let granted = await calendarService.requestCalendarPermission()
            guard granted else {
                withAnimation { calendarAddState = .failed }
                return
            }

            if useNativeEditor {
                // Open native EKEventEditViewController — user controls all fields
                let ekEvent = calendarService.makeEKEvent(
                    for: event,
                    options: CalendarAddOptions(
                        enableReminder: !selectedReminderOffsets.isEmpty,
                        reminderOffsets: Array(selectedReminderOffsets)
                    )
                )
                ekEventForEditing = ekEvent
                showNativeEventEditor = true
            } else {
                isAddingToCalendar = true
                let options = CalendarAddOptions(
                    addToCalendar: true,
                    enableReminder: !selectedReminderOffsets.isEmpty,
                    reminderOffsets: Array(selectedReminderOffsets)
                )
                let id = await calendarService.addEventToCalendar(event, options: options)
                isAddingToCalendar = false
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    calendarAddState = id != nil ? .added : .failed
                }
            }
        }
    }

    private func scheduleSelectedReminders() {
        Task {
            let granted = await reminderService.requestNotificationPermission()
            guard granted else { return }
            _ = await reminderService.scheduleReminders(
                for: event,
                offsets: Array(selectedReminderOffsets),
                followUpAfterEvent: event.eventType == .jobInterview
            )
        }
    }

    // MARK: - Sub-view helpers

    @ViewBuilder
    private func detailRow(icon: String, color: Color, title: String, subtitle: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(color)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundStyle(.primary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.custom("OpenSans-Bold", size: 16))
    }
}

// MARK: - EKEventEditView Wrapper (UIViewControllerRepresentable)

struct EKEventEditViewWrapper: UIViewControllerRepresentable {
    let event: EKEvent
    let eventStore: CalendarService

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.event = event
        controller.eventStore = EKEventStore()
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, EKEventEditViewDelegate {
        func eventEditViewController(
            _ controller: EKEventEditViewController,
            didCompleteWith action: EKEventEditViewAction
        ) {
            controller.dismiss(animated: true)
        }
    }
}
