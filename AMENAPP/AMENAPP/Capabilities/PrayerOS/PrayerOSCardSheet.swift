// PrayerOSCardSheet.swift
// AMEN Capabilities v1 — Prayer card create/edit sheet (Wave 1: Lane D)
//
// Presents a Form-based sheet for creating or editing a PrayerCard.
// Create mode: calls PrayerOSService.createCard(...)
// Edit mode:   pre-fills fields from editingCard; calls PrayerOSService.updateCard(...)
// Dedupe:      shows an inline banner when the server returns a PrayerDedupeWarning.
//
// Contract: Docs/Capabilities/CONTRACTS.md §2.3, §3.3
// Models:   AMENAPP/AMENAPP/Capabilities/CapabilityModels.swift (FROZEN)

import SwiftUI

// MARK: - PrayerOSCardSheet

struct PrayerOSCardSheet: View {

    // MARK: Dependencies

    @StateObject private var service = PrayerOSService.shared
    @Environment(\.dismiss) private var dismiss

    // MARK: Input

    let editingCard: PrayerCard? // nil = create mode

    // MARK: Form state

    @State private var subjectName: String = ""
    @State private var subjectType: PrayerSubjectType = .person
    @State private var category: PrayerCategory = .other
    @State private var detail: String = ""
    @State private var weeklyReminder: Bool = false
    @State private var followUpDate: Date? = nil
    @State private var showFollowUpPicker: Bool = false

    // MARK: Save state

    @State private var dedupeWarning: PrayerDedupeWarning? = nil
    @State private var isSaving: Bool = false
    @State private var saveError: Error? = nil
    @State private var showErrorAlert: Bool = false

    // MARK: Constants

    private let maxDetailChars = 2000

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                subjectSection
                categorySection
                detailSection
                remindersSection
                followUpSection

                if let warning = dedupeWarning {
                    dedupeWarningSection(warning: warning)
                }
            }
            .background(.regularMaterial)
            .navigationTitle(editingCard == nil ? "New Prayer" : "Edit Prayer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onAppear { populateFields() }
            .alert("Unable to Save", isPresented: $showErrorAlert, presenting: saveError) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error.localizedDescription)
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var subjectSection: some View {
        Section {
            TextField("Name or topic", text: $subjectName)
                .textContentType(.name)
                .accessibilityLabel("Subject name")
                .accessibilityHint("Enter a person's name or a topic you are praying about")

            Picker("Type", selection: $subjectType) {
                Text("Person").tag(PrayerSubjectType.person)
                Text("Topic").tag(PrayerSubjectType.topic)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Subject type")
            .accessibilityHint("Choose whether you are praying for a person or a topic")
        } header: {
            Text("Subject")
                .font(.footnote)
        }
    }

    @ViewBuilder
    private var categorySection: some View {
        Section {
            Picker("Category", selection: $category) {
                ForEach(PrayerCategory.allCases, id: \.self) { cat in
                    Text(cat.displayName).tag(cat)
                }
            }
            .accessibilityLabel("Prayer category")
            .accessibilityHint("Select the category that best describes this prayer")
        } header: {
            Text("Category")
                .font(.footnote)
        }
    }

    @ViewBuilder
    private var detailSection: some View {
        Section {
            ZStack(alignment: .bottomTrailing) {
                TextEditor(text: $detail)
                    .frame(minHeight: 100)
                    .onChange(of: detail) { _, newValue in
                        if newValue.count > maxDetailChars {
                            detail = String(newValue.prefix(maxDetailChars))
                        }
                    }
                    .accessibilityLabel("Prayer detail")
                    .accessibilityHint("Describe what you are praying for, up to 2000 characters")

                Text("\(detail.count)/\(maxDetailChars)")
                    .font(.caption2)
                    .foregroundStyle(detail.count >= maxDetailChars ? .red : .secondary)
                    .padding([.bottom, .trailing], 4)
                    .accessibilityHidden(true)
            }
        } header: {
            Text("Detail")
                .font(.footnote)
        }
    }

    @ViewBuilder
    private var remindersSection: some View {
        Section {
            Toggle(isOn: $weeklyReminder) {
                Label("Weekly reminder", systemImage: "bell")
                    .font(.body)
            }
            .accessibilityLabel("Weekly reminder")
            .accessibilityHint("When on, you will be reminded to pray for this each week")
        } header: {
            Text("Reminders")
                .font(.footnote)
        }
    }

    @ViewBuilder
    private var followUpSection: some View {
        Section {
            Toggle("Set a check-in date", isOn: $showFollowUpPicker)
                .accessibilityLabel("Set a check-in date")
                .accessibilityHint("Toggle to add a date when you want to follow up on this prayer")

            if showFollowUpPicker {
                DatePicker(
                    "Check in on:",
                    selection: Binding(
                        get: { followUpDate ?? Date().addingTimeInterval(7 * 24 * 3600) },
                        set: { followUpDate = $0 }
                    ),
                    in: Date()...,
                    displayedComponents: .date
                )
                .accessibilityLabel("Follow-up date")
                .accessibilityHint("Select the date you want to be reminded to check in on this prayer")
            }
        } header: {
            Text("Follow-up")
                .font(.footnote)
        }
    }

    @ViewBuilder
    private func dedupeWarningSection(warning: PrayerDedupeWarning) -> some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("You're already praying for \(warning.displayName).")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Button("View existing prayer") {
                        // Dismiss this sheet; the caller navigates to the existing card.
                        // Navigation is handled by the parent via the returned cardId.
                        dismiss()
                    }
                    .font(.subheadline)
                    .accessibilityLabel("View existing prayer for \(warning.displayName)")
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Duplicate prayer warning: you are already praying for \(warning.displayName)")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                dismiss()
            }
            .accessibilityLabel("Cancel")
        }

        ToolbarItem(placement: .confirmationAction) {
            if isSaving {
                ProgressView()
                    .accessibilityLabel("Saving")
            } else {
                Button("Save") {
                    Task { await save() }
                }
                .fontWeight(.semibold)
                .disabled(subjectName.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel(editingCard == nil ? "Save new prayer" : "Save changes")
                .accessibilityHint("Double-tap to save this prayer card")
            }
        }
    }

    // MARK: - Actions

    /// Pre-fills form fields when editing an existing card.
    private func populateFields() {
        guard let card = editingCard else { return }
        subjectName = card.subject.displayName
        subjectType = card.subject.type
        category = card.category
        detail = card.detail

        weeklyReminder = card.reminders.contains { $0.rrule.contains("FREQ=WEEKLY") }

        if let firstPending = card.followUps.first(where: { $0.status == .pending }) {
            followUpDate = firstPending.dueAt
            showFollowUpPicker = true
        }
    }

    /// Saves the card — creates in create mode, updates in edit mode.
    private func save() async {
        let name = subjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }

        let subject = PrayerSubject(
            type: subjectType,
            displayName: name,
            linkedContactRef: editingCard?.subject.linkedContactRef
        )

        let reminders = buildReminders()
        let followUps = buildFollowUps()

        do {
            if let card = editingCard {
                // Edit mode
                let patch = PrayerUpdatePatch(
                    detail: detail,
                    category: category,
                    status: nil,
                    reminders: reminders.isEmpty ? nil : reminders,
                    followUps: followUps.isEmpty ? nil : followUps
                )
                try await service.updateCard(cardId: card.id, patch: patch)
                dismiss()
            } else {
                // Create mode
                let response = try await service.createCard(
                    subject: subject,
                    category: category,
                    detail: detail,
                    reminders: reminders,
                    followUps: followUps
                )
                if let warning = response.dedupeWarning {
                    // Surface the dedupe warning inline; do NOT dismiss.
                    dedupeWarning = warning
                } else {
                    // Reload the list and close.
                    try await service.loadCards(status: .active)
                    dismiss()
                }
            }
        } catch {
            saveError = error
            showErrorAlert = true
        }
    }

    // MARK: - Builder helpers

    private func buildReminders() -> [PrayerReminder] {
        guard weeklyReminder else { return [] }
        // Next Monday at 9 AM local time
        let nextFireAt = nextWeekday(from: Date(), hour: 9)
        return [PrayerReminder(rrule: "FREQ=WEEKLY;BYDAY=MO", nextFireAt: nextFireAt)]
    }

    private func buildFollowUps() -> [PrayerFollowUp] {
        guard showFollowUpPicker, let dueAt = followUpDate else { return [] }
        return [PrayerFollowUp(dueAt: dueAt, status: .pending, note: nil)]
    }

    /// Returns the next occurrence of `weekday` (1=Sunday … 7=Saturday) at `hour` local time.
    private func nextWeekday(from date: Date, hour: Int) -> Date {
        var components = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        components.weekday = 2 // Monday
        components.hour = hour
        components.minute = 0
        components.second = 0
        let candidate = Calendar.current.date(from: components) ?? date
        if candidate <= date {
            return Calendar.current.date(byAdding: .weekOfYear, value: 1, to: candidate) ?? candidate
        }
        return candidate
    }
}

// MARK: - Preview

#Preview("Create") {
    PrayerOSCardSheet(editingCard: nil)
}
