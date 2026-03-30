// RSVPFlowView.swift
// AMEN Calendar — RSVP Flow + Add to Calendar Integration

import SwiftUI

struct RSVPFlowView: View {
    let event: AMENEvent
    var onRSVPComplete: ((RSVPStatus) -> Void)?

    @StateObject private var calendarService = CalendarService.shared
    @StateObject private var reminderService = ReminderSchedulerService.shared
    @State private var selectedStatus: RSVPStatus = .going
    @State private var addToCalendar = true
    @State private var enableReminder = true
    @State private var selectedReminders: Set<ReminderOffset> = []
    @State private var addFollowUp = false
    @State private var note = ""
    @State private var step: RSVPStep = .statusSelection
    @State private var isSubmitting = false
    @State private var submitted = false
    @Environment(\.dismiss) private var dismiss

    enum RSVPStep {
        case statusSelection, calendarOptions, confirmation
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .statusSelection:
                    statusSelectionStep
                case .calendarOptions:
                    calendarOptionsStep
                case .confirmation:
                    confirmationStep
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                let suggested = reminderService.suggestedReminders(for: event.eventType)
                selectedReminders = Set(suggested)
            }
        }
    }

    private var navigationTitle: String {
        switch step {
        case .statusSelection: return "RSVP"
        case .calendarOptions: return "Calendar"
        case .confirmation:    return "All Set"
        }
    }

    // MARK: - Step 1: Status Selection

    @ViewBuilder
    private var statusSelectionStep: some View {
        VStack(spacing: 24) {
            Spacer()

            // Event mini-card
            eventMiniCard

            VStack(spacing: 12) {
                Text("Are you going?")
                    .font(.custom("OpenSans-Bold", size: 22))
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    rsvpOption(.going)
                    rsvpOption(.maybe)
                    rsvpOption(.notGoing)
                }

                if event.requiresApproval {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill").font(.system(size: 12)).foregroundStyle(.secondary)
                        Text("This event requires organizer approval.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }

            // Optional note
            VStack(alignment: .leading, spacing: 6) {
                Text("Note to organizer (optional)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("e.g. \"Bringing a guest\"", text: $note)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 24)

            // Continue
            Button {
                if selectedStatus == .going || selectedStatus == .maybe {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { step = .calendarOptions }
                } else {
                    submitRSVP()
                }
            } label: {
                Text(selectedStatus == .notGoing ? "Submit" : "Continue")
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(selectedStatus.color, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.liquidGlass)
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Step 2: Calendar Options

    @ViewBuilder
    private var calendarOptionsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary
                eventDateSummary
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                // Add to calendar toggle
                VStack(alignment: .leading, spacing: 12) {
                    calendarToggle

                    if addToCalendar {
                        calendarPrivacyNote
                    }
                }
                .padding(.horizontal, 24)

                Divider().padding(.horizontal, 24)

                // Reminders
                if addToCalendar {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Reminders")
                                .font(.custom("OpenSans-Bold", size: 16))
                            Text("We suggest these based on the event type.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }

                        ForEach(suggestedReminderOffsets, id: \.self) { offset in
                            let fireDate = event.startDate.addingTimeInterval(-TimeInterval(offset.minutesBefore * 60))
                            if fireDate > Date() {
                                reminderRow(offset: offset)
                            }
                        }

                        if event.eventType == .jobInterview {
                            Toggle("Add follow-up reminder after event", isOn: $addFollowUp)
                                .font(.system(size: 14))
                                .tint(event.eventType.color)
                        }
                    }
                    .padding(.horizontal, 24)
                }

                // Save without calendar option
                Button {
                    addToCalendar = false
                    submitRSVP()
                } label: {
                    Text("Save RSVP without adding to calendar")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                // Confirm
                Button {
                    submitRSVP()
                } label: {
                    HStack {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text(addToCalendar ? "RSVP & Add to Calendar" : "Confirm RSVP")
                                .font(.custom("OpenSans-Bold", size: 16))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(event.eventType.color, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.liquidGlass)
                .disabled(isSubmitting)
                .padding(.horizontal, 24)

                Spacer(minLength: 40)
            }
        }
    }

    // MARK: - Step 3: Confirmation

    @ViewBuilder
    private var confirmationStep: some View {
        VStack(spacing: 24) {
            Spacer()

            // Success animation
            ZStack {
                Circle()
                    .fill(selectedStatus.color.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: selectedStatus.icon)
                    .font(.system(size: 44))
                    .foregroundStyle(selectedStatus.color)
            }

            VStack(spacing: 8) {
                Text("You're \(selectedStatus.label.lowercased())!")
                    .font(.custom("OpenSans-Bold", size: 26))

                Text(confirmationSubtitle)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            // Calendar confirmation
            if addToCalendar {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 18))
                        .foregroundStyle(Color(red: 0.18, green: 0.62, blue: 0.36))
                    Text("Added to your calendar")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(Color(red: 0.18, green: 0.62, blue: 0.36))
                }
                .padding(12)
                .background(Color(red: 0.18, green: 0.62, blue: 0.36).opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 40)
            }

            Button("Done") { dismiss() }
                .font(.custom("OpenSans-SemiBold", size: 16))
                .foregroundStyle(.white)
                .padding(.horizontal, 48)
                .padding(.vertical, 14)
                .background(event.eventType.color, in: RoundedRectangle(cornerRadius: 14))

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var eventMiniCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(event.eventType.color.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: event.eventType.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(event.eventType.color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.custom("OpenSans-Bold", size: 15))
                    .lineLimit(1)
                Text(shortDate)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func rsvpOption(_ status: RSVPStatus) -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                selectedStatus = status
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(selectedStatus == status ? status.color : Color(.systemGray5))
                        .frame(width: 52, height: 52)
                    Image(systemName: status.icon)
                        .font(.system(size: 22))
                        .foregroundStyle(selectedStatus == status ? .white : .secondary)
                }
                Text(status.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selectedStatus == status ? status.color : .secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var eventDateSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Event Details")
                .font(.custom("OpenSans-Bold", size: 16))
            Text(shortDate)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            if let location = event.location {
                Text(location)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var calendarToggle: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add to Calendar")
                    .font(.custom("OpenSans-SemiBold", size: 15))
                Text("Creates an event in your calendar app")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $addToCalendar)
                .labelsHidden()
                .tint(event.eventType.color)
        }
    }

    @ViewBuilder
    private var calendarPrivacyNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("AMEN only writes this event — it never reads your existing calendar data.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func reminderRow(offset: ReminderOffset) -> some View {
        HStack {
            Toggle(offset.label, isOn: Binding(
                get: { selectedReminders.contains(offset) },
                set: { isOn in
                    if isOn { selectedReminders.insert(offset) }
                    else { selectedReminders.remove(offset) }
                }
            ))
            .font(.custom("OpenSans-Regular", size: 14))
            .tint(event.eventType.color)
        }
    }

    // MARK: - Computed

    private var suggestedReminderOffsets: [ReminderOffset] {
        reminderService.suggestedReminders(for: event.eventType)
    }

    private var shortDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = event.timeZone
        return formatter.string(from: event.startDate)
    }

    private var confirmationSubtitle: String {
        switch selectedStatus {
        case .going:
            return addToCalendar
                ? "This event is on your calendar."
                : "Your RSVP has been recorded."
        case .maybe:
            return "You're tentatively attending. The organizer has been notified."
        case .notGoing:
            return "No worries — your response has been recorded."
        default:
            return "Your RSVP has been recorded."
        }
    }

    // MARK: - Submit

    private func submitRSVP() {
        isSubmitting = true
        Task {
            // RSVP to Firestore
            try? await calendarService.rsvp(eventId: event.id ?? "", status: selectedStatus, note: note)

            // Add to calendar if requested
            if addToCalendar && (selectedStatus == .going || selectedStatus == .maybe) {
                let granted = await calendarService.requestCalendarPermission()
                if granted {
                    let options = CalendarAddOptions(
                        addToCalendar: true,
                        enableReminder: !selectedReminders.isEmpty,
                        reminderOffsets: Array(selectedReminders),
                        addFollowUpReminder: addFollowUp
                    )
                    _ = await calendarService.addEventToCalendar(event, options: options)
                }

                // Schedule local notifications
                if reminderService.notificationPermissionGranted {
                    _ = await reminderService.scheduleReminders(
                        for: event,
                        offsets: Array(selectedReminders),
                        followUpAfterEvent: addFollowUp
                    )
                }
            }

            isSubmitting = false
            onRSVPComplete?(selectedStatus)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                step = .confirmation
            }
        }
    }
}

// MARK: - Smart Reminder Suggestion Banner

struct SmartReminderSuggestionBanner: View {
    let event: AMENEvent
    @StateObject private var reminderService = ReminderSchedulerService.shared
    @State private var dismissed = false
    @State private var isScheduling = false
    @State private var scheduled = false

    var body: some View {
        if !dismissed && !scheduled && event.isUpcoming && !reminderService.notificationPermissionGranted {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(event.eventType.color)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Set a reminder?")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                    Text(suggestedReminderText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        withAnimation { dismissed = true }
                    } label: {
                        Text("Not now")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        scheduleReminder()
                    } label: {
                        if isScheduling {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("Yes")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(event.eventType.color, in: Capsule())
                        }
                    }
                    .disabled(isScheduling)
                }
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(event.eventType.color.opacity(0.2), lineWidth: 1)
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var suggestedReminderText: String {
        let offsets = reminderService.suggestedReminders(for: event.eventType)
        let first = offsets.first?.label ?? "30 minutes before"
        return "Get reminded \(first.lowercased()) this event"
    }

    private func scheduleReminder() {
        isScheduling = true
        Task {
            let granted = await reminderService.requestNotificationPermission()
            if granted {
                let offsets = reminderService.suggestedReminders(for: event.eventType)
                _ = await reminderService.scheduleReminders(for: event, offsets: offsets)
                withAnimation { scheduled = true }
            }
            isScheduling = false
        }
    }
}

// MARK: - Add to Calendar Button (reusable component)

struct AddToCalendarButton: View {
    let event: AMENEvent
    var style: ButtonStyle_ = .primary

    @StateObject private var calendarService = CalendarService.shared
    @State private var addState: AddState = .idle

    enum AddState { case idle, loading, added, failed }
    enum ButtonStyle_: String { case primary, compact, icon }

    var body: some View {
        Button {
            addEvent()
        } label: {
            Group {
                switch style {
                case .primary:
                    primaryLabel
                case .compact:
                    compactLabel
                case .icon:
                    iconLabel
                }
            }
        }
        .buttonStyle(.liquidGlass)
        .disabled(addState == .loading || addState == .added)
    }

    @ViewBuilder
    private var primaryLabel: some View {
        HStack {
            if addState == .loading {
                ProgressView().tint(.white).scaleEffect(0.8)
            } else {
                Image(systemName: addState == .added ? "checkmark.circle.fill" : "calendar.badge.plus")
                Text(addState == .added ? "Added to Calendar" : "Add to Calendar")
                    .font(.custom("OpenSans-SemiBold", size: 14))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            addState == .added ? Color(red: 0.18, green: 0.62, blue: 0.36) : event.eventType.color,
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    @ViewBuilder
    private var compactLabel: some View {
        Image(systemName: addState == .added ? "checkmark.circle.fill" : "calendar.badge.plus")
            .font(.system(size: 16))
            .foregroundStyle(addState == .added ? Color(red: 0.18, green: 0.62, blue: 0.36) : event.eventType.color)
    }

    @ViewBuilder
    private var iconLabel: some View {
        Image(systemName: addState == .added ? "checkmark" : "calendar.badge.plus")
            .font(.system(size: 15))
            .foregroundStyle(addState == .added ? Color(red: 0.18, green: 0.62, blue: 0.36) : .primary)
    }

    private func addEvent() {
        addState = .loading
        Task {
            let granted = await calendarService.requestCalendarPermission()
            guard granted else { addState = .failed; return }
            let id = await calendarService.addEventToCalendar(event)
            withAnimation(.spring(response: 0.3)) {
                addState = id != nil ? .added : .failed
            }
        }
    }
}
