// AmenYouMenuSheet.swift
// AMEN Connect — "You" slide-up sheet (Amen-first inversion of Slack's account menu)
//
// Inverts Slack's "You" sheet:
//   • Presence is covenant, not surveillance — opt-in, expressive, consent-gated
//   • "VIP" → Covenant Circle (care + accountability fabric, not just notification bypass)
//   • Sabbath Mode is the anti-engagement crown jewel
//   • No status-broadcast pressure; the easy path is the small, intimate one

import SwiftUI
import FirebaseAuth

// MARK: - Menu item model

private struct AmenYouMenuItem: Identifiable {
    let id: String
    let icon: String
    let label: String
    let sublabel: String?
    let accent: Color
    let action: () -> Void
}

// MARK: - View

struct AmenYouMenuSheet: View {
    @Binding var showPresencePicker: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showProfile: Bool = false
    @State private var showPreferences: Bool = false
    @State private var showCovenantCircle: Bool = false
    @State private var showNotifications: Bool = false
    @State private var showSabbathScheduler: Bool = false

    @State private var sabbathModeEnabled: Bool = false

    private var displayName: String {
        Auth.auth().currentUser?.displayName ?? "You"
    }
    private var initials: String {
        let name = displayName
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    identityHeader
                    presenceStatusRow
                    Divider().padding(.horizontal, 20).padding(.vertical, 4)
                    sabbathModeRow
                    Divider().padding(.horizontal, 20).padding(.vertical, 4)
                    menuRows
                }
                .padding(.bottom, 32)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
            .navigationDestination(isPresented: $showProfile) {
                AmenConnectProfileView()
            }
            .navigationDestination(isPresented: $showPreferences) {
                AmenConnectPreferencesView()
            }
            .sheet(isPresented: $showCovenantCircle) {
                AmenCovenantCircleSheet()
            }
            .sheet(isPresented: $showSabbathScheduler) {
                AmenSabbathSchedulerSheet(isEnabled: $sabbathModeEnabled)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Identity header

    private var identityHeader: some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.amenPurple.opacity(0.15))
                    .frame(width: 56, height: 56)
                Text(initials)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.amenPurple)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(Auth.auth().currentUser?.email ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Signed in as \(displayName)")
    }

    // MARK: - Presence status row

    private var presenceStatusRow: some View {
        Button {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showPresencePicker = true
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Set Spiritual Presence")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("In the Word · visible to your Spaces")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set spiritual presence. Currently: In the Word. Tap to change.")
    }

    // MARK: - Sabbath mode row (anti-engagement crown jewel)

    private var sabbathModeRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(sabbathModeEnabled ? Color.amenBlue : Color(uiColor: .secondarySystemBackground))
                    .frame(width: 32, height: 32)
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(sabbathModeEnabled ? .white : .secondary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Sabbath Mode")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(sabbathModeEnabled
                     ? "Active · only emergency contacts can reach you"
                     : "Silence everything except true emergencies")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            HStack(spacing: 8) {
                Toggle("", isOn: $sabbathModeEnabled)
                    .labelsHidden()
                    .tint(Color.amenBlue)
                if sabbathModeEnabled {
                    Button {
                        showSabbathScheduler = true
                    } label: {
                        Image(systemName: "calendar")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.amenBlue)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Schedule Sabbath")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sabbath Mode \(sabbathModeEnabled ? "on" : "off"). \(sabbathModeEnabled ? "Only emergency contacts can reach you." : "Tap to silence everything except true emergencies.")")
    }

    // MARK: - Menu rows

    private var menuRows: some View {
        VStack(spacing: 2) {
            ForEach(menuItems) { item in
                menuRow(item)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func menuRow(_ item: AmenYouMenuItem) -> some View {
        Button(action: item.action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(item.accent.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: item.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(item.accent)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.label)
                        .font(.body)
                        .foregroundStyle(.primary)
                    if let sub = item.sublabel {
                        Text(sub)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.label + (item.sublabel.map { ". \($0)" } ?? ""))
    }

    private var menuItems: [AmenYouMenuItem] {
        [
            AmenYouMenuItem(
                id: "profile",
                icon: "person.circle",
                label: "View Profile",
                sublabel: "See how others see you in Amen",
                accent: Color.accentColor
            ) { showProfile = true },

            AmenYouMenuItem(
                id: "covenant",
                icon: "heart.circle.fill",
                label: "Covenant Circle",
                sublabel: "Spouse, family, mentor, pastor, inner circle",
                accent: Color.amenPurple
            ) { showCovenantCircle = true },

            AmenYouMenuItem(
                id: "invitations",
                icon: "envelope.open",
                label: "Invitations",
                sublabel: "Spaces and connections awaiting your response",
                accent: .orange
            ) { /* navigate to invitations */ },

            AmenYouMenuItem(
                id: "notifications",
                icon: "bell",
                label: "Notifications",
                sublabel: nil,
                accent: Color(uiColor: .systemYellow)
            ) { showNotifications = true },

            AmenYouMenuItem(
                id: "preferences",
                icon: "gearshape",
                label: "Preferences",
                sublabel: "Sabbath, rhythms, safety, appearance",
                accent: Color(uiColor: .systemGray)
            ) { showPreferences = true },
        ]
    }
}

// MARK: - Covenant Circle sheet (stub — wires to existing AmenCovenantManageView if present)

private struct AmenCovenantCircleSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let tiers = [
        ("Spouse", "heart.fill", Color.pink),
        ("Family", "house.fill", Color.orange),
        ("Pastor", "building.columns.fill", Color.amenPurple),
        ("Mentor", "person.crop.circle.badge.checkmark", Color.amenBlue),
        ("Inner Circle", "star.fill", Color(uiColor: .systemYellow)),
        ("Emergency Contacts", "exclamationmark.triangle.fill", Color.red),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Your Covenant Circle determines who can break Sabbath/DND for true emergencies, who sees your pastoral presence, and whose messages bypass the digest batch.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                Section("Relationship Tiers") {
                    ForEach(tiers, id: \.0) { tier in
                        Label(tier.0, systemImage: tier.1)
                            .foregroundStyle(tier.2)
                            .accessibilityLabel(tier.0)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Covenant Circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Sabbath scheduler sheet

private struct AmenSabbathSchedulerSheet: View {
    @Binding var isEnabled: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var startDay: Int = 6       // Friday (1=Sun…7=Sat)
    @State private var startHour: Int = 18     // 6 PM
    @State private var endDay: Int = 7         // Saturday
    @State private var endHour: Int = 21       // 9 PM
    @State private var liturgicalAware: Bool = true

    private let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Sabbath Mode Enabled", isOn: $isEnabled)
                        .tint(Color.amenBlue)
                } footer: {
                    Text("When on, all notifications are silenced except emergency contacts from your Covenant Circle.")
                }

                Section("Weekly Schedule") {
                    Picker("Start Day", selection: $startDay) {
                        ForEach(0..<7, id: \.self) { i in Text(weekdays[i]).tag(i) }
                    }
                    Stepper("Start Time: \(startHour):00", value: $startHour, in: 0...23)
                    Picker("End Day", selection: $endDay) {
                        ForEach(0..<7, id: \.self) { i in Text(weekdays[i]).tag(i) }
                    }
                    Stepper("End Time: \(endHour):00", value: $endHour, in: 0...23)
                }

                Section {
                    Toggle("Liturgical Awareness", isOn: $liturgicalAware)
                        .tint(Color.amenBlue)
                } footer: {
                    Text("Amen will automatically extend Sabbath mode during Advent, Lent, and other holy seasons if you choose.")
                }
            }
            .navigationTitle("Sabbath Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Preview

#Preview {
    AmenYouMenuSheet(showPresencePicker: .constant(false))
}
