// AmenConnectPreferencesView.swift
// AMEN Connect — Preferences (Amen-first inversion of Slack's Preferences screen)
//
// Reorganized around formation values, not engagement mechanics:
//   1. Sabbath & Rhythms  — the most countercultural section, put first
//   2. Covenant Circle & Care
//   3. Safety Center      — visible and trust-building, not buried plumbing
//   4. Notifications
//   5. Appearance
//   6. Accessibility
//
// Liquid Glass: white/light, neutral gray backgrounds, SF type, monochrome line icons.
// No cosmic-dark, no gold, no purple accent surfaces — chrome only.

import SwiftUI

// MARK: - Preferences state

@MainActor
final class AmenConnectPreferencesViewModel: ObservableObject {

    // Sabbath & Rhythms
    @Published var sabbathEnabled: Bool = false
    @Published var sabbathStartDay: Int = 5         // Friday (0-indexed: 0=Sun)
    @Published var sabbathStartHour: Int = 18
    @Published var sabbathEndDay: Int = 6           // Saturday
    @Published var sabbathEndHour: Int = 21
    @Published var liturgicalAwareness: Bool = true
    @Published var notificationDelivery: NotificationDelivery = .digest
    @Published var quietHoursEnabled: Bool = true
    @Published var quietStart: Date = Calendar.current.date(from: DateComponents(hour: 22)) ?? Date()
    @Published var quietEnd: Date   = Calendar.current.date(from: DateComponents(hour: 7))  ?? Date()

    // Covenant Circle & Care
    @Published var pastoralPresenceOptIn: Bool = false
    @Published var presenceVisibility: PresenceVisibility = .covenantCircle
    @Published var careEscalationEnabled: Bool = true

    // Notifications
    @Published var directMessageAlerts: Bool = true
    @Published var covenantCircleBypassDND: Bool = true
    @Published var prayerRequestAlerts: Bool = true
    @Published var careAlerts: Bool = true
    @Published var eventReminders: Bool = true
    @Published var spaceDigestEnabled: Bool = true
    @Published var digestTime: Date = Calendar.current.date(from: DateComponents(hour: 8)) ?? Date()

    // Appearance
    @Published var colorScheme: AppColorScheme = .system
    @Published var messageDisplay: MessageDisplay = .comfortable

    // Accessibility
    @Published var reduceMotionOverride: Bool = false
    @Published var increasedContrast: Bool = false
    @Published var largerText: Bool = false
    @Published var screenReaderOptimized: Bool = false

    enum NotificationDelivery: String, CaseIterable {
        case digest   = "Daily Digest"
        case batched  = "Batched (every 2h)"
        case realTime = "Real-time (Covenant Circle only)"

        var description: String {
            switch self {
            case .digest:   return "One morning summary — recommended"
            case .batched:  return "Grouped every two hours"
            case .realTime: return "Immediate only for Covenant Circle and care alerts"
            }
        }
    }

    enum PresenceVisibility: String, CaseIterable {
        case covenantCircle = "Covenant Circle"
        case spaceAdmins    = "Space Admins"
        case allMembers     = "All Members"
        case nobody         = "Nobody"
    }

    enum AppColorScheme: String, CaseIterable {
        case system = "System"
        case light  = "Light"
        case dark   = "Dark"
    }

    enum MessageDisplay: String, CaseIterable {
        case compact     = "Compact"
        case comfortable = "Comfortable"
    }
}

// MARK: - Main View

struct AmenConnectPreferencesView: View {
    @StateObject private var vm = AmenConnectPreferencesViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            sabbathRhythmsSection
            covenantCareSection
            safetyCenterSection
            notificationsSection
            appearanceSection
            accessibilitySection
            deviceSection
        }
        .navigationTitle("Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
    }

    // MARK: 1. Sabbath & Rhythms

    private var sabbathRhythmsSection: some View {
        Section {
            // Sabbath Mode toggle
            Toggle(isOn: $vm.sabbathEnabled) {
                Label("Sabbath Mode", systemImage: "moon.stars")
            }
            .tint(Color.amenBlue)
            .accessibilityLabel("Sabbath Mode \(vm.sabbathEnabled ? "on" : "off")")

            if vm.sabbathEnabled {
                sabbathScheduleRows
            }

            Toggle(isOn: $vm.liturgicalAwareness) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Liturgical Awareness", systemImage: "calendar.badge.clock")
                    Text("Extends quiet during Advent, Lent, and holy seasons")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(Color.amenBlue)

            // Quiet hours
            Toggle(isOn: $vm.quietHoursEnabled) {
                Label("Quiet Hours", systemImage: "bed.double")
            }
            .tint(Color.amenBlue)

            if vm.quietHoursEnabled {
                DatePicker("Starts", selection: $vm.quietStart, displayedComponents: .hourAndMinute)
                DatePicker("Ends",   selection: $vm.quietEnd,   displayedComponents: .hourAndMinute)
            }

            // Notification delivery model
            Picker(selection: $vm.notificationDelivery) {
                ForEach(AmenConnectPreferencesViewModel.NotificationDelivery.allCases, id: \.self) { d in
                    Text(d.rawValue).tag(d)
                }
            } label: {
                Label("Notification Delivery", systemImage: "tray")
            }
            .accessibilityLabel("Notification delivery mode: \(vm.notificationDelivery.rawValue)")

            if vm.notificationDelivery == .digest {
                DatePicker("Digest Time", selection: $vm.digestTime, displayedComponents: .hourAndMinute)
            }

        } header: {
            Label("Sabbath & Rhythms", systemImage: "moon.stars")
        } footer: {
            Text("When Sabbath Mode is on, all notifications pause except emergency contacts from your Covenant Circle. Nothing in faith tech does this — because it's commercially irrational for attention businesses.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var sabbathScheduleRows: some View {
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        Group {
            Picker("Starts", selection: $vm.sabbathStartDay) {
                ForEach(0..<7, id: \.self) { Text(days[$0]).tag($0) }
            }
            Stepper("At \(vm.sabbathStartHour):00", value: $vm.sabbathStartHour, in: 0...23)
            Picker("Ends", selection: $vm.sabbathEndDay) {
                ForEach(0..<7, id: \.self) { Text(days[$0]).tag($0) }
            }
            Stepper("At \(vm.sabbathEndHour):00", value: $vm.sabbathEndHour, in: 0...23)
        }
    }

    // MARK: 2. Covenant Circle & Care

    private var covenantCareSection: some View {
        Section {
            Picker(selection: $vm.presenceVisibility) {
                ForEach(AmenConnectPreferencesViewModel.PresenceVisibility.allCases, id: \.self) { v in
                    Text(v.rawValue).tag(v)
                }
            } label: {
                Label("Who sees my presence", systemImage: "eye")
            }

            // Pastoral presence — opt-in, always revocable, always visible to user
            Toggle(isOn: $vm.pastoralPresenceOptIn) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Pastoral Presence", systemImage: "person.badge.shield.checkmark")
                    Text("Allow your pastor/mentor to see when you've gone quiet. Opt-in. Always revocable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(Color.amenPurple)
            .accessibilityLabel("Pastoral Presence \(vm.pastoralPresenceOptIn ? "on" : "off"). Allows pastor or mentor to see your spiritual activity pattern. Opt-in and revocable.")

            Toggle(isOn: $vm.careEscalationEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Care Escalation", systemImage: "heart.text.square")
                    Text("Crisis signals route to a human — pastoral team, not AI alone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(Color.amenPurple)

            NavigationLink {
                AmenCovenantCirclePreferencesView()
            } label: {
                Label("Manage Covenant Circle", systemImage: "heart.circle")
            }

        } header: {
            Label("Covenant Circle & Care", systemImage: "heart.circle")
        } footer: {
            Text("Presence data that Slack uses for engagement tracking is used here as an invitation to be cared for. Default blast radius is always small.")
        }
    }

    // MARK: 3. Safety Center

    private var safetyCenterSection: some View {
        Section {
            NavigationLink {
                AmenConnectSafetyCenterView()
            } label: {
                Label("Safety Center", systemImage: "shield.lefthalf.filled")
                    .foregroundStyle(.primary)
            }
            Label("Moderation: On", systemImage: "checkmark.shield")
                .foregroundStyle(.green)
            Label("Link Scanning: On", systemImage: "link.badge.plus")
                .foregroundStyle(.green)
            Label("Image Safety: On", systemImage: "photo.badge.shield")
                .foregroundStyle(.green)

        } header: {
            Label("Safety Center", systemImage: "shield.lefthalf.filled")
        } footer: {
            Text("Safety is legible, not buried. Moderation, impersonation detection, link scanning, and image review are always on for spaces that include minors.")
        }
    }

    // MARK: 4. Notifications

    private var notificationsSection: some View {
        Section {
            Toggle(isOn: $vm.covenantCircleBypassDND) {
                Label("Covenant Circle bypasses DND", systemImage: "heart.fill")
            }
            .tint(Color.amenPurple)

            Toggle(isOn: $vm.directMessageAlerts) {
                Label("Direct Messages", systemImage: "bubble.left.and.bubble.right")
            }
            .tint(Color.accentColor)

            Toggle(isOn: $vm.prayerRequestAlerts) {
                Label("Prayer Requests", systemImage: "hands.sparkles")
            }
            .tint(Color.accentColor)

            Toggle(isOn: $vm.careAlerts) {
                Label("Care Alerts", systemImage: "heart.text.square")
            }
            .tint(Color.accentColor)

            Toggle(isOn: $vm.eventReminders) {
                Label("Event Reminders", systemImage: "calendar")
            }
            .tint(Color.accentColor)

            Toggle(isOn: $vm.spaceDigestEnabled) {
                Label("Space Digest", systemImage: "tray.2")
            }
            .tint(Color.accentColor)

        } header: {
            Label("Notifications", systemImage: "bell")
        } footer: {
            Text("Real-time alerts are reserved for Covenant Circle and true care escalation. Everything else arrives in your daily digest by default — no red-dot anxiety.")
        }
    }

    // MARK: 5. Appearance

    private var appearanceSection: some View {
        Section {
            Picker(selection: $vm.colorScheme) {
                ForEach(AmenConnectPreferencesViewModel.AppColorScheme.allCases, id: \.self) { s in
                    Text(s.rawValue).tag(s)
                }
            } label: {
                Label("Color Mode", systemImage: "circle.lefthalf.filled")
            }

            Picker(selection: $vm.messageDisplay) {
                ForEach(AmenConnectPreferencesViewModel.MessageDisplay.allCases, id: \.self) { d in
                    Text(d.rawValue).tag(d)
                }
            } label: {
                Label("Message Display", systemImage: "text.alignleft")
            }

        } header: {
            Label("Appearance", systemImage: "paintbrush")
        }
    }

    // MARK: 6. Accessibility

    private var accessibilitySection: some View {
        Section {
            Toggle(isOn: $vm.reduceMotionOverride) {
                Label("Reduce Motion", systemImage: "figure.walk")
            }
            .tint(Color.accentColor)

            Toggle(isOn: $vm.increasedContrast) {
                Label("Increase Contrast", systemImage: "circle.righthalf.filled")
            }
            .tint(Color.accentColor)

            Toggle(isOn: $vm.largerText) {
                Label("Larger Text", systemImage: "textformat.size")
            }
            .tint(Color.accentColor)

            Toggle(isOn: $vm.screenReaderOptimized) {
                Label("Screen Reader Optimized", systemImage: "waveform.path.ecg")
            }
            .tint(Color.accentColor)

            NavigationLink {
                EmptyView()
            } label: {
                Label("Animation & Haptics", systemImage: "hand.tap")
            }

        } header: {
            Label("Accessibility", systemImage: "figure.arms.open")
        }
    }

    // MARK: Device & App

    private var deviceSection: some View {
        Section {
            NavigationLink {
                EmptyView()
            } label: {
                Label("Network Settings", systemImage: "network")
            }

            NavigationLink {
                EmptyView()
            } label: {
                Label("Debug & Reset Cache", systemImage: "arrow.clockwise.icloud")
            }

            NavigationLink {
                EmptyView()
            } label: {
                Label("Privacy Policy", systemImage: "lock.doc")
            }

            NavigationLink {
                EmptyView()
            } label: {
                Label("Send Feedback", systemImage: "envelope")
            }

        } header: {
            Label("Device & App", systemImage: "iphone")
        }
    }
}

// MARK: - Covenant Circle sub-preferences (stub)

private struct AmenCovenantCirclePreferencesView: View {
    var body: some View {
        Form {
            Section("Emergency Escalation") {
                Label("Emergency contacts can break Sabbath/DND", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                NavigationLink("Manage Emergency Contacts") { EmptyView() }
            }
            Section("Pastoral Visibility") {
                Text("Choose which people in your Covenant Circle can see your spiritual rhythm data. Changes take effect immediately.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Covenant Circle")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
    }
}

// MARK: - Safety Center view (stub)

private struct AmenConnectSafetyCenterView: View {
    var body: some View {
        Form {
            Section("Active Protections") {
                Label("Content Moderation: On",       systemImage: "checkmark.shield.fill").foregroundStyle(.green)
                Label("Image Safety Review: On",      systemImage: "checkmark.shield.fill").foregroundStyle(.green)
                Label("Link Scanning: On",            systemImage: "checkmark.shield.fill").foregroundStyle(.green)
                Label("Impersonation Detection: On",  systemImage: "checkmark.shield.fill").foregroundStyle(.green)
                Label("CSAM Detection: On",           systemImage: "checkmark.shield.fill").foregroundStyle(.green)
            }
            Section("Minor Protection") {
                Text("Spaces with minors are always subject to stricter moderation, mandatory parental/guardian rings, and automatic NCMEC escalation for CSAM — never silent auto-action.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            Section {
                NavigationLink("Report a Problem") { EmptyView() }
                NavigationLink("Block & Mute") { EmptyView() }
            }
        }
        .navigationTitle("Safety Center")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AmenConnectPreferencesView()
    }
}
