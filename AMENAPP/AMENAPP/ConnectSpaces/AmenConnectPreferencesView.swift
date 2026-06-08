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
                ConnectPreferencesSafetyCenterView()
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
                HapticsSettingsView()
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
                NetworkSettingsView()
            } label: {
                Label("Network Settings", systemImage: "network")
            }

            NavigationLink {
                CacheManagementView()
            } label: {
                Label("Debug & Reset Cache", systemImage: "arrow.clockwise.icloud")
            }

            NavigationLink {
                ConnectPrivacyPolicyView()
            } label: {
                Label("Privacy Policy", systemImage: "lock.doc")
            }

            NavigationLink {
                SendFeedbackView()
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
                NavigationLink("Manage Emergency Contacts") { EmergencyContactsView() }
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

private struct ConnectPreferencesSafetyCenterView: View {
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
                NavigationLink("Report a Problem") { ConnectReportProblemView() }
                NavigationLink("Block & Mute") { BlockMuteView() }
            }
        }
        .navigationTitle("Safety Center")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
    }
}

// MARK: - Destination views for preferences navigation

private struct HapticsSettingsView: View {
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("animationsReduced") private var animationsReduced = false

    var body: some View {
        Form {
            Section("Haptics") {
                Toggle("Enable Haptic Feedback", isOn: $hapticsEnabled)
                    .tint(Color.accentColor)
            }
            Section("Animations") {
                Toggle("Reduce Motion", isOn: $animationsReduced)
                    .tint(Color.accentColor)
                Text("When enabled, animations are simplified for comfort and battery efficiency.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Animation & Haptics")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NetworkSettingsView: View {
    var body: some View {
        Form {
            Section("System Settings") {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Open iOS Settings", systemImage: "gear")
                }
            }
            Section("Data Usage") {
                Label("Stream on Wi-Fi Only", systemImage: "wifi")
                    .foregroundStyle(.secondary)
                Text("To adjust data usage, open iOS Settings > AMEN.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Network Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CacheManagementView: View {
    @State private var cleared = false

    var body: some View {
        Form {
            Section("Cache") {
                Button(role: cleared ? .none : .destructive) {
                    URLCache.shared.removeAllCachedResponses()
                    cleared = true
                } label: {
                    Label(cleared ? "Cache Cleared" : "Clear Image Cache",
                          systemImage: cleared ? "checkmark.circle.fill" : "arrow.clockwise.icloud")
                        .foregroundStyle(cleared ? .green : .red)
                }
            }
            Section("App Data") {
                Text("Clearing the cache removes temporarily stored images and data. Your posts, messages, and settings are not affected.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Debug & Reset Cache")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ConnectPrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Privacy Policy")
                    .font(.title2.bold())
                Text("AMEN is built on a privacy-first foundation. We collect only what is necessary to deliver the service, never sell your data, and give you full control over your information.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text("Data We Collect")
                    .font(.headline)
                Text("• Account information (name, email, phone)\n• Content you post\n• Interaction data (likes, comments) to power your feed\n• Device information for security")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text("Your Rights")
                    .font(.headline)
                Text("You can export, delete, or restrict your data at any time from Settings > Account > Privacy Controls.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Button("View Full Policy Online") {
                    if let url = URL(string: "https://amenapp.com/privacy") {
                        UIApplication.shared.open(url)
                    }
                }
                .padding(.top)
            }
            .padding()
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SendFeedbackView: View {
    @State private var feedbackText = ""
    @State private var submitted = false

    var body: some View {
        Form {
            Section("Your Feedback") {
                TextEditor(text: $feedbackText)
                    .frame(minHeight: 120)
            }
            Section {
                Button(submitted ? "Submitted!" : "Send Feedback") {
                    guard !feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    submitted = true
                }
                .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || submitted)
            }
            Section {
                Text("Feedback is reviewed by our team. For urgent safety concerns, use the Report feature.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Send Feedback")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct EmergencyContactsView: View {
    var body: some View {
        Form {
            Section("Emergency Contacts") {
                Text("Emergency contacts can reach you even when Sabbath Mode or Do Not Disturb is active.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                NavigationLink("Add Emergency Contact") {
                    ContactPickerPromptView()
                }
            }
            Section("How It Works") {
                Label("Bypasses Sabbath Mode", systemImage: "moon.fill")
                Label("Bypasses DND Settings", systemImage: "bell.slash.fill")
                Label("Always notified immediately", systemImage: "bell.fill")
            }
        }
        .navigationTitle("Emergency Contacts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ConnectReportProblemView: View {
    @State private var description = ""
    @State private var submitted = false

    var body: some View {
        Form {
            Section("Describe the Problem") {
                TextEditor(text: $description)
                    .frame(minHeight: 120)
            }
            Section {
                Button(submitted ? "Report Sent" : "Submit Report") {
                    guard !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    submitted = true
                }
                .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || submitted)
            }
        }
        .navigationTitle("Report a Problem")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BlockMuteView: View {
    @ObservedObject private var blockService = BlockService.shared
    @State private var showUnblockConfirm = false
    @State private var userToUnblock: BlockedUserProfile?

    var body: some View {
        List {
            Section("Blocked Accounts") {
                if blockService.isLoading {
                    ProgressView().frame(maxWidth: .infinity, alignment: .center)
                } else if blockService.blockedUsersList.isEmpty {
                    Text("No blocked accounts")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(blockService.blockedUsersList) { user in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.displayName).font(.body)
                                Text("@\(user.username)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Unblock") {
                                userToUnblock = user
                                showUnblockConfirm = true
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.blue)
                        }
                    }
                }
            }
            Section("Muted Accounts") {
                Text("Muted accounts can still reach you but their messages arrive quietly. Manage mutes from any conversation by long-pressing a thread.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Text("To block or mute someone, visit their profile and tap the ··· menu.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Block & Mute")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Task { await blockService.loadBlockedUsers() } }
        .confirmationDialog(
            "Unblock @\(userToUnblock?.username ?? "")?",
            isPresented: $showUnblockConfirm,
            titleVisibility: .visible
        ) {
            Button("Unblock", role: .destructive) {
                if let user = userToUnblock {
                    Task { try? await blockService.unblockUser(userId: user.id) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They will be able to follow you and view your posts again.")
        }
    }
}

private struct ContactPickerPromptView: View {
    @State private var name = ""
    @State private var phone = ""
    @State private var saved = false

    var body: some View {
        Form {
            Section("Contact Info") {
                TextField("Name", text: $name)
                TextField("Phone Number", text: $phone)
                    .keyboardType(.phonePad)
            }
            Section {
                Button(saved ? "Saved" : "Save Emergency Contact") {
                    guard !name.isEmpty, !phone.isEmpty else { return }
                    saved = true
                }
                .disabled(name.isEmpty || phone.isEmpty || saved)
            }
            Section {
                Text("This contact will be able to reach you even when Sabbath Mode or DND is enabled.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Add Emergency Contact")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AmenConnectPreferencesView()
    }
}
