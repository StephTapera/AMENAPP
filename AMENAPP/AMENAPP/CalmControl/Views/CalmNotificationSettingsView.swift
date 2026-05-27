import SwiftUI

struct CalmNotificationSettingsView: View {
    @StateObject private var service = CalmControlService.shared
    @StateObject private var rhythmService = AmenCalmRhythmService.shared

    var body: some View {
        List {
            Section {
                Picker("Notification Intensity", selection: $service.notificationSettings.intensity) {
                    ForEach(AmenNotificationIntensity.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.navigationLink)
            } header: {
                Text("Intensity")
            } footer: {
                Text("Choose how actively Amen reaches out. You can change this anytime.")
                    .font(.caption)
            }

            Section {
                ForEach(AmenRhythmNotificationCategory.allCases, id: \.self) { category in
                    Toggle(category.displayName, isOn: Binding(
                        get: { service.notificationSettings.isCategoryEnabled(category) },
                        set: { newVal in
                            service.notificationSettings.enabledCategories[category] = newVal
                        }
                    ))
                }
            } header: {
                Text("Notification Types")
            } footer: {
                Text("All notifications are optional. Turning them off won't affect your community participation.")
                    .font(.caption)
            }

            Section {
                Toggle("Quiet Hours (10 PM – 7 AM)", isOn: $service.notificationSettings.quietHoursEnabled)
            } header: {
                Text("Quiet Hours")
            } footer: {
                Text("No notifications during your rest window — including streak reminders.")
                    .font(.caption)
            }

            if rhythmService.rhythm.notificationsPausedDueToInactivity {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "moon.zzz.fill")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notifications paused")
                                .font(.subheadline.weight(.medium))
                            Text("We paused non-essential notifications while you were away. They'll resume when you return.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    Button("Resume Notifications") {
                        Task { await rhythmService.restoreAfterReturn() }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await service.saveNotificationSettings() }
                }
            }
        }
        .task {
            await service.loadAll()
            await rhythmService.loadAll()
        }
    }
}

#Preview {
    NavigationStack { CalmNotificationSettingsView() }
}
