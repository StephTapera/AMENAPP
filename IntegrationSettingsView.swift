//
//  IntegrationSettingsView.swift
//  AMENAPP
//
//  Full user control over Widgets, Live Activities, and Siri & Shortcuts.
//  Also surfaces advanced notification preferences gated on AMENUserPreferences.
//
//  Design: dark glassmorphic, grouped sections, master-toggle collapse,
//  warm faith-forward copy, no nagging.
//

import SwiftUI
import UserNotifications

@MainActor
struct IntegrationSettingsView: View {

    @ObservedObject private var prefsService = AMENUserPreferencesService.shared
    @State private var systemNotifStatus: UNAuthorizationStatus = .notDetermined
    @State private var showResetConfirm = false

    private var prefs: AMENUserPreferences { prefsService.preferences }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // System permission banner (only if denied)
                    if systemNotifStatus == .denied {
                        systemPermissionBanner
                    }

                    notificationsSection
                    widgetsSection
                    liveActivitiesSection
                    siriSection
                    resetSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Integrations")
        .navigationBarTitleDisplayMode(.inline)
        .task { await checkSystemPermission() }
    }

    // MARK: - System Permission Banner

    private var systemPermissionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.slash.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 20))

            VStack(alignment: .leading, spacing: 3) {
                Text("Notifications are off")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Enable in iOS Settings to receive community updates.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.orange)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.3), lineWidth: 1))
        )
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        IntegrationSection(title: "Push Notifications", icon: "bell.badge.fill") {
            // Master toggle
            IntegrationToggle(
                label: "Enable Notifications",
                subtitle: "Stay connected to your community's prayers and moments",
                isOn: Binding(
                    get: { prefs.notificationsEnabled },
                    set: { v in prefsService.update { $0.notificationsEnabled = v } }
                )
            )

            if prefs.notificationsEnabled {
                Divider().background(Color.white.opacity(0.08))

                IntegrationToggle(
                    label: "Prayer Request Alerts",
                    subtitle: "Know when someone in your community needs prayer",
                    isOn: Binding(
                        get: { prefs.prayerRequestAlerts },
                        set: { v in prefsService.update { $0.prayerRequestAlerts = v } }
                    )
                )

                IntegrationToggle(
                    label: "Testimony Alerts",
                    subtitle: "Celebrate what God is doing in people's lives",
                    isOn: Binding(
                        get: { prefs.testimonyAlerts },
                        set: { v in prefsService.update { $0.testimonyAlerts = v } }
                    )
                )

                IntegrationToggle(
                    label: "Event Reminders",
                    subtitle: "Never miss a gathering or church event",
                    isOn: Binding(
                        get: { prefs.eventReminders },
                        set: { v in prefsService.update { $0.eventReminders = v } }
                    )
                )

                IntegrationToggle(
                    label: "Follow Activity",
                    subtitle: "Get a gentle nudge when people you follow share something new",
                    isOn: Binding(
                        get: { prefs.followActivityAlerts },
                        set: { v in prefsService.update { $0.followActivityAlerts = v } }
                    )
                )

                IntegrationToggle(
                    label: "First Amen Alert",
                    subtitle: "Be notified when your prayer request receives its first Amen",
                    isOn: Binding(
                        get: { prefs.firstAmenAlert },
                        set: { v in prefsService.update { $0.firstAmenAlert = v } }
                    )
                )

                IntegrationToggle(
                    label: "Morning Devotional",
                    subtitle: "A gentle daily reminder to start your day with scripture",
                    isOn: Binding(
                        get: { prefs.morningDevotionalEnabled },
                        set: { v in prefsService.update { $0.morningDevotionalEnabled = v } }
                    )
                )

                if prefs.morningDevotionalEnabled {
                    devotionalTimePicker
                }

                IntegrationToggle(
                    label: "Location-Based Church Reminders",
                    subtitle: "Receive reminders when you're near a church event (uses location)",
                    isOn: Binding(
                        get: { prefs.geofenceReminders },
                        set: { v in prefsService.update { $0.geofenceReminders = v } }
                    )
                )

                Divider().background(Color.white.opacity(0.08))
                maxNotificationsRow
            }
        }
    }

    private var devotionalTimePicker: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Devotional Time")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                Text("When would you like your daily reminder?")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            DatePicker(
                "",
                selection: Binding(
                    get: {
                        Calendar.current.date(
                            bySettingHour: prefs.morningDevotionalHour,
                            minute: prefs.morningDevotionalMinute,
                            second: 0,
                            of: Date()
                        ) ?? Date()
                    },
                    set: { date in
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                        prefsService.update {
                            $0.morningDevotionalHour = comps.hour ?? 8
                            $0.morningDevotionalMinute = comps.minute ?? 0
                        }
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .colorScheme(.dark)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var maxNotificationsRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Daily Reminder Limit")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                Text("\(prefs.maxDailyNotifications) per day (non-critical)")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Stepper(
                "",
                value: Binding(
                    get: { prefs.maxDailyNotifications },
                    set: { v in prefsService.update { $0.maxDailyNotifications = max(0, min(10, v)) } }
                ),
                in: 0...10
            )
            .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Widgets Section

    private var widgetsSection: some View {
        IntegrationSection(title: "Home Screen Widgets", icon: "square.grid.2x2.fill") {
            infoBanner(
                icon: "info.circle",
                text: "Widgets are managed from your iPhone's Home Screen. Long-press your wallpaper → tap + to add AMEN widgets."
            )

            IntegrationToggle(
                label: "Enable Widgets",
                subtitle: "Let AMEN widgets display live community data",
                isOn: Binding(
                    get: { prefs.widgetsEnabled },
                    set: { v in prefsService.update { $0.widgetsEnabled = v } }
                )
            )

            if prefs.widgetsEnabled {
                Divider().background(Color.white.opacity(0.08))

                IntegrationToggle(
                    label: "Daily Verse Widget",
                    subtitle: "Today's scripture at a glance",
                    isOn: Binding(
                        get: { prefs.dailyVerseWidgetEnabled },
                        set: { v in prefsService.update { $0.dailyVerseWidgetEnabled = v } }
                    )
                )

                IntegrationToggle(
                    label: "Community Pulse Widget",
                    subtitle: "Active prayer requests from your community",
                    isOn: Binding(
                        get: { prefs.communityPulseWidgetEnabled },
                        set: { v in prefsService.update { $0.communityPulseWidgetEnabled = v } }
                    )
                )

                IntegrationToggle(
                    label: "Upcoming Events Widget",
                    subtitle: "Next church event with a live countdown",
                    isOn: Binding(
                        get: { prefs.upcomingEventWidgetEnabled },
                        set: { v in prefsService.update { $0.upcomingEventWidgetEnabled = v } }
                    )
                )
            }
        }
    }

    // MARK: - Live Activities Section

    private var liveActivitiesSection: some View {
        IntegrationSection(title: "Dynamic Island & Live Activities", icon: "circle.dotted") {
            infoBanner(
                icon: "info.circle",
                text: "Live Activities appear in your Dynamic Island and Lock Screen during active events. Control access in iOS Settings → AMEN → Live Activities."
            )

            IntegrationToggle(
                label: "Enable Live Activities",
                subtitle: "See live prayer counts and church events on your Lock Screen",
                isOn: Binding(
                    get: { prefs.liveActivitiesEnabled },
                    set: { v in prefsService.update { $0.liveActivitiesEnabled = v } }
                )
            )

            if prefs.liveActivitiesEnabled {
                Divider().background(Color.white.opacity(0.08))

                IntegrationToggle(
                    label: "Prayer Chain Activity",
                    subtitle: "Live count of people praying together in a chain",
                    isOn: Binding(
                        get: { prefs.prayerChainLiveActivityEnabled },
                        set: { v in prefsService.update { $0.prayerChainLiveActivityEnabled = v } }
                    )
                )

                IntegrationToggle(
                    label: "Church Event Activity",
                    subtitle: "Live sermon and worship session updates on your Dynamic Island",
                    isOn: Binding(
                        get: { prefs.liveEventActivityEnabled },
                        set: { v in prefsService.update { $0.liveEventActivityEnabled = v } }
                    )
                )
            }
        }
    }

    // MARK: - Siri Section

    private var siriSection: some View {
        IntegrationSection(title: "Siri & Shortcuts", icon: "waveform") {
            IntegrationToggle(
                label: "Siri Integration",
                subtitle: "Use voice to post prayers, share testimonies, and check today's verse",
                isOn: Binding(
                    get: { prefs.siriIntegrationEnabled },
                    set: { v in prefsService.update { $0.siriIntegrationEnabled = v } }
                )
            )

            if prefs.siriIntegrationEnabled {
                Divider().background(Color.white.opacity(0.08))

                IntegrationToggle(
                    label: "Siri Suggestions",
                    subtitle: "Let Siri proactively suggest AMEN actions based on your patterns",
                    isOn: Binding(
                        get: { prefs.siriSuggestionsEnabled },
                        set: { v in prefsService.update { $0.siriSuggestionsEnabled = v } }
                    )
                )

                IntegrationToggle(
                    label: "In-App Siri Tips",
                    subtitle: "Show helpful Siri shortcut prompts at natural moments in the app",
                    isOn: Binding(
                        get: { prefs.siriTipsEnabled },
                        set: { v in prefsService.update { $0.siriTipsEnabled = v } }
                    )
                )

                siriShortcutsList
            }
        }
    }

    private var siriShortcutsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Available shortcuts")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 16)
                .padding(.top, 4)

            ForEach([
                ("hands.and.sparkles", "Post a Prayer Request", "\"Hey Siri, post a prayer request on AMEN\""),
                ("sparkles",           "Share a Testimony",      "\"Hey Siri, share a testimony on AMEN\""),
                ("book.closed",        "Get Today's Verse",      "\"Hey Siri, today's verse on AMEN\""),
                ("calendar.badge.plus","RSVP to an Event",       "\"Hey Siri, RSVP to an event on AMEN\""),
                ("person.2.wave.2",    "Discover Prayer Needs",  "\"Hey Siri, discover prayer needs on AMEN\"")
            ], id: \.0) { icon, title, phrase in
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.system(size: 14)).foregroundStyle(.white)
                        Text(phrase).font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Reset

    private var resetSection: some View {
        Button {
            showResetConfirm = true
        } label: {
            Text("Reset to Defaults")
                .font(.system(size: 15))
                .foregroundStyle(.red.opacity(0.8))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
                )
        }
        .confirmationDialog(
            "Reset all integration settings to their defaults?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset to Defaults", role: .destructive) { prefsService.resetToDefaults() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Helpers

    private func infoBanner(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.06))
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func checkSystemPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        systemNotifStatus = settings.authorizationStatus
    }
}

// MARK: - Reusable Components

private struct IntegrationSection<Content: View>: View {
    let title: String
    let icon: String
    let content: () -> Content

    init(title: String, icon: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 10)

            // Content card
            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
    }
}

private struct IntegrationToggle: View {
    let label: String
    let subtitle: String
    let isOn: Binding<Bool>

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color.white.opacity(0.9))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .animation(.easeInOut(duration: 0.2), value: isOn.wrappedValue)
    }
}
