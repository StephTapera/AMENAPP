import SwiftUI

// MARK: - ExperienceNotificationSettingsView

/// User-level notification preferences for a specific experience.
/// Saves via ContextualExperienceService.updateNotificationSettings.
struct ExperienceNotificationSettingsView: View {

    let experienceId: String

    @State private var announcements = true
    @State private var prayers = true
    @State private var discussions = true
    @State private var events = true
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var savedSuccess = false

    @Environment(\.dismiss) private var dismiss

    private let service = ContextualExperienceService.shared

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                Section {
                    toggleRow(
                        label: "Announcements",
                        icon: "megaphone.fill",
                        description: "Important updates from organizers",
                        isOn: $announcements
                    )
                    toggleRow(
                        label: "Prayers",
                        icon: "hands.and.sparkles.fill",
                        description: "New prayer prompts and responses",
                        isOn: $prayers
                    )
                    toggleRow(
                        label: "Discussions",
                        icon: "bubble.left.and.bubble.right.fill",
                        description: "New discussion threads and replies",
                        isOn: $discussions
                    )
                    toggleRow(
                        label: "Events",
                        icon: "calendar.badge.plus",
                        description: "Upcoming event reminders",
                        isOn: $events
                    )
                } header: {
                    Text("Notify Me About")
                } footer: {
                    Text("You can update these preferences at any time.")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }

                if let error = saveError {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(AmenTheme.Colors.statusError)
                                .imageScale(.small)
                            Text(error)
                                .font(AMENFont.regular(13))
                                .foregroundStyle(AmenTheme.Colors.statusError)
                        }
                    }
                }

                if savedSuccess {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AmenTheme.Colors.statusSuccess)
                                .imageScale(.small)
                            Text("Preferences saved.")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(AmenTheme.Colors.statusSuccess)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .background(AmenTheme.Colors.backgroundPrimary)
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        HapticManager.impact(style: .light)
                        dismiss()
                    }
                    .accessibilityLabel("Cancel notification settings")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        HapticManager.impact(style: .light)
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Save")
                                .font(AMENFont.semiBold(15))
                        }
                    }
                    .disabled(isSaving)
                    .accessibilityLabel("Save notification preferences")
                }
            }
        }
    }

    // MARK: - Toggle row

    private func toggleRow(
        label: String,
        icon: String,
        description: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(AMENFont.regular(15))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Text(description)
                    .font(AMENFont.regular(12))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(isOn.wrappedValue ? "On" : "Off"). \(description)")
        .accessibilityHint("Double-tap to toggle")
    }

    // MARK: - Save

    private func save() async {
        isSaving = true
        saveError = nil
        savedSuccess = false
        do {
            try await service.updateNotificationSettings(
                experienceId: experienceId,
                settings: [
                    "announcements": announcements,
                    "prayers": prayers,
                    "discussions": discussions,
                    "events": events
                ]
            )
            savedSuccess = true
            try? await Task.sleep(nanoseconds: 800_000_000)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}
