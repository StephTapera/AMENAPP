import SwiftUI
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class NotificationPreferencesService: ObservableObject {
    @Published var preferences: NotificationPreferences = .defaults
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    var userId: String? { Auth.auth().currentUser?.uid }

    func startListening() {
        guard let uid = userId else { return }
        listener = db.collection("users").document(uid)
            .collection("notificationPreferences").document("current")
            .addSnapshotListener { [weak self] snapshot, _ in
                if let prefs = try? snapshot?.data(as: NotificationPreferences.self) {
                    self?.preferences = prefs
                }
            }
    }

    func save() async {
        guard let uid = userId else { return }
        try? await db.collection("users").document(uid)
            .collection("notificationPreferences").document("current")
            .setData(from: preferences)
    }

    func muteFor24Hours() async {
        preferences.mutedUntil = Timestamp(date: Date().addingTimeInterval(86400))
        await save()
    }

    func clearMute() async {
        preferences.mutedUntil = nil
        await save()
    }

    deinit { listener?.remove() }
}

struct NotificationPreferencesView: View {
    @StateObject private var service = NotificationPreferencesService()
    @State private var showQuietHoursDetail = false

    var isMuted: Bool {
        if let until = service.preferences.mutedUntil?.dateValue() { return until > Date() }
        return false
    }

    var body: some View {
        List {
            Section {
                Toggle(isOn: $service.preferences.enabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Notifications").font(.custom("OpenSans-Bold", size: 15)).foregroundStyle(AmenTheme.Colors.textPrimary)
                        Text("Master toggle for all AMEN notifications").font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(AmenTheme.Colors.textSecondary)
                    }
                }
                .tint(Color(red: 0.10, green: 0.60, blue: 0.56))
                .onChange(of: service.preferences.enabled) { _, _ in Task { await service.save() } }
                .accessibilityLabel("Enable notifications: \(service.preferences.enabled ? "on" : "off")")

                Picker("Frequency", selection: $service.preferences.frequency) {
                    ForEach(NotificationFrequency.allCases, id: \.self) { f in Text(f.displayName).tag(f) }
                }
                .font(.custom("OpenSans-Regular", size: 15))
                .onChange(of: service.preferences.frequency) { _, _ in Task { await service.save() } }
            } header: {
                Text("General").font(.custom("OpenSans-Bold", size: 13))
            }

            Section {
                quietHoursRow
            } header: {
                Text("Quiet Hours").font(.custom("OpenSans-Bold", size: 13))
            } footer: {
                Text("During quiet hours, notifications are held until morning.")
                    .font(.custom("OpenSans-Regular", size: 12))
            }

            Section {
                categoryRow(title: "Crisis Escalation", subtitle: "Proactive support offers", isOn: $service.preferences.crisisEscalation, icon: "heart.circle.fill", color: Color(red: 0.40, green: 0.70, blue: 0.95))
                categoryRow(title: "Giving Milestones", subtitle: "Goal completions and badges", isOn: $service.preferences.givingMilestone, icon: "dollarsign.circle.fill", color: Color(red: 0.83, green: 0.69, blue: 0.22))
                categoryRow(title: "Wellness Reminders", subtitle: "Streak reminders and badges", isOn: $service.preferences.wellnessReminder, icon: "leaf.circle.fill", color: Color(red: 0.10, green: 0.60, blue: 0.56))
                categoryRow(title: "Support Group Updates", subtitle: "New posts in your groups", isOn: $service.preferences.supportGroupUpdate, icon: "person.2.circle.fill", color: Color(red: 0.60, green: 0.50, blue: 0.90))
                categoryRow(title: "Friend Activity", subtitle: "Posts and milestones from friends", isOn: $service.preferences.friendActivity, icon: "person.crop.circle.fill", color: Color(red: 0.10, green: 0.60, blue: 0.56))
                categoryRow(title: "Church News", subtitle: "Updates from your church", isOn: $service.preferences.churchNews, icon: "building.columns.circle.fill", color: Color(red: 0.83, green: 0.69, blue: 0.22))
            } header: {
                Text("Categories").font(.custom("OpenSans-Bold", size: 13))
            }

            Section {
                if isMuted {
                    HStack {
                        Image(systemName: "moon.zzz.fill").foregroundStyle(AmenTheme.Colors.textTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Muted").font(.custom("OpenSans-Bold", size: 14)).foregroundStyle(AmenTheme.Colors.textPrimary)
                            if let until = service.preferences.mutedUntil?.dateValue() {
                                Text("Until \(until.formatted(.relative(presentation: .named)))")
                                    .font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(AmenTheme.Colors.textSecondary)
                            }
                        }
                        Spacer()
                        Button("Unmute") { Task { await service.clearMute() } }
                            .font(.custom("OpenSans-Regular", size: 14)).foregroundStyle(Color(red: 0.10, green: 0.60, blue: 0.56))
                    }
                    .accessibilityLabel("Notifications muted. Tap Unmute to enable")
                } else {
                    Button { Task { await service.muteFor24Hours() } } label: {
                        Label("Mute for 24 hours", systemImage: "moon.zzz.fill")
                            .font(.custom("OpenSans-Regular", size: 15)).foregroundStyle(AmenTheme.Colors.textPrimary)
                    }
                    .accessibilityLabel("Mute all notifications for 24 hours")
                }
            } header: {
                Text("Snooze").font(.custom("OpenSans-Bold", size: 13))
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { service.startListening() }
    }

    private var quietHoursRow: some View {
        VStack(spacing: 10) {
            Toggle(isOn: $service.preferences.quietHoursEnabled) {
                Text("Quiet Hours").font(.custom("OpenSans-Bold", size: 14)).foregroundStyle(AmenTheme.Colors.textPrimary)
            }
            .tint(Color(red: 0.10, green: 0.60, blue: 0.56))
            .onChange(of: service.preferences.quietHoursEnabled) { _, _ in Task { await service.save() } }
            .accessibilityLabel("Quiet hours: \(service.preferences.quietHoursEnabled ? "on" : "off")")

            if service.preferences.quietHoursEnabled {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start").font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(AmenTheme.Colors.textTertiary)
                        Text(service.preferences.quietHoursStart).font(.custom("OpenSans-Bold", size: 15)).foregroundStyle(AmenTheme.Colors.textPrimary)
                    }
                    Spacer()
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(AmenTheme.Colors.textTertiary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("End").font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(AmenTheme.Colors.textTertiary)
                        Text(service.preferences.quietHoursEnd).font(.custom("OpenSans-Bold", size: 15)).foregroundStyle(AmenTheme.Colors.textPrimary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Quiet hours from \(service.preferences.quietHoursStart) to \(service.preferences.quietHoursEnd)")
            }
        }
    }

    private func categoryRow(title: String, subtitle: String, isOn: Binding<Bool>, icon: String, color: Color) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(color).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.custom("OpenSans-Bold", size: 14)).foregroundStyle(AmenTheme.Colors.textPrimary)
                    Text(subtitle).font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(AmenTheme.Colors.textSecondary)
                }
            }
        }
        .tint(color)
        .onChange(of: isOn.wrappedValue) { _, _ in Task { await service.save() } }
        .accessibilityLabel("\(title): \(isOn.wrappedValue ? "on" : "off")")
    }
}
