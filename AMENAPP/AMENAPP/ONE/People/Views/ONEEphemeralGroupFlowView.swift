// ONEEphemeralGroupFlowView.swift
// ONE — Sheet flow for creating an ephemeral group thread.
// Step 1 → pick duration  Step 2 → pick expiry action  Step 3 → confirm & create

import SwiftUI

struct ONEEphemeralGroupFlowView: View {
    let participantUIDs: [String]
    let onCreate: (ONEEphemeralGroupSettings) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedDuration: EphemeralDuration = .oneDay
    @State private var selectedAction: ONEGroupExpiryAction = .deleteAll
    @State private var step: Int = 0

    // MARK: - Duration enum

    enum EphemeralDuration: String, CaseIterable, Identifiable {
        case oneDay    = "24 Hours"
        case threeDays = "3 Days"
        case oneWeek   = "7 Days"
        case oneMonth  = "30 Days"

        var id: String { rawValue }

        var timeInterval: TimeInterval {
            switch self {
            case .oneDay:    return 24 * 3_600
            case .threeDays: return 3 * 24 * 3_600
            case .oneWeek:   return 7 * 24 * 3_600
            case .oneMonth:  return 30 * 24 * 3_600
            }
        }

        var icon: String {
            switch self {
            case .oneDay:    return "clock.fill"
            case .threeDays: return "flame.fill"
            case .oneWeek:   return "calendar"
            case .oneMonth:  return "calendar.badge.clock"
            }
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressBar
                    .padding(.horizontal, ONE.Spacing.lg)
                    .padding(.vertical, ONE.Spacing.md)

                TabView(selection: $step) {
                    durationStep.tag(0)
                    actionStep.tag(1)
                    confirmStep.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("Ephemeral Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        HStack(spacing: ONE.Spacing.sm) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(i <= step ? ONE.Colors.ephemeralRed : Color.primary.opacity(0.10))
                    .frame(height: 3)
                    .animation(ONE.Motion.adaptive(reduceMotion: reduceMotion), value: step)
            }
        }
        .accessibilityLabel("Step \(step + 1) of 3")
    }

    // MARK: - Step 1: Duration

    private var durationStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ONE.Spacing.lg) {
                stepHeader(
                    icon: "flame.fill",
                    title: "How long should this group exist?",
                    subtitle: "After this time, the group follows the action you choose next."
                )

                VStack(spacing: ONE.Spacing.sm) {
                    ForEach(EphemeralDuration.allCases) { dur in
                        durationOption(dur)
                    }
                }

                primaryButton("Choose What Happens After") {
                    withAnimation(ONE.Motion.adaptive(reduceMotion: reduceMotion)) { step = 1 }
                }
            }
            .padding(ONE.Spacing.lg)
        }
    }

    private func durationOption(_ dur: EphemeralDuration) -> some View {
        let selected = selectedDuration == dur
        return Button { selectedDuration = dur } label: {
            HStack(spacing: ONE.Spacing.md) {
                Image(systemName: dur.icon)
                    .font(.systemScaled(18))
                    .foregroundStyle(selected ? ONE.Colors.ephemeralRed : .secondary)
                    .frame(width: 28)
                Text(dur.rawValue)
                    .font(.systemScaled(15, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.systemScaled(18))
                        .foregroundStyle(ONE.Colors.ephemeralRed)
                }
            }
            .padding(ONE.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: ONE.Radius.card, style: .continuous)
                    .fill(selected ? ONE.Colors.ephemeralRed.opacity(0.08) : Color.primary.opacity(0.04))
                    .stroke(selected ? ONE.Colors.ephemeralRed.opacity(0.30) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(dur.rawValue)\(selected ? ", selected" : "")")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - Step 2: Expiry Action

    private var actionStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ONE.Spacing.lg) {
                stepHeader(
                    icon: "questionmark.circle.fill",
                    title: "What happens when it expires?",
                    subtitle: "Everyone in the group will see this choice before joining."
                )

                VStack(spacing: ONE.Spacing.sm) {
                    ForEach(ONEGroupExpiryAction.flowCases, id: \.self) { action in
                        expiryActionOption(action)
                    }
                }

                HStack(spacing: ONE.Spacing.sm) {
                    backButton { step = 0 }
                    primaryButton("Review & Create") {
                        withAnimation(ONE.Motion.adaptive(reduceMotion: reduceMotion)) { step = 2 }
                    }
                }
            }
            .padding(ONE.Spacing.lg)
        }
    }

    private func expiryActionOption(_ action: ONEGroupExpiryAction) -> some View {
        let selected = selectedAction == action
        return Button { selectedAction = action } label: {
            HStack(alignment: .top, spacing: ONE.Spacing.md) {
                Image(systemName: action.flowIcon)
                    .font(.systemScaled(18))
                    .foregroundStyle(selected ? action.flowTint : .secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(action.flowLabel)
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(action.flowSubtitle)
                        .font(.systemScaled(12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.systemScaled(18))
                        .foregroundStyle(action.flowTint)
                }
            }
            .padding(ONE.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: ONE.Radius.card, style: .continuous)
                    .fill(selected ? action.flowTint.opacity(0.06) : Color.primary.opacity(0.04))
                    .stroke(selected ? action.flowTint.opacity(0.25) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(action.flowLabel): \(action.flowSubtitle)\(selected ? ", selected" : "")")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - Step 3: Confirm

    private var confirmStep: some View {
        ScrollView {
            VStack(spacing: ONE.Spacing.lg) {
                stepHeader(
                    icon: "checkmark.shield.fill",
                    title: "Review your ephemeral group",
                    subtitle: "Invited members will see these settings before joining."
                )

                VStack(spacing: ONE.Spacing.sm) {
                    summaryRow("person.3.fill",   "Members",       "\(participantUIDs.count) people")
                    summaryRow("clock.fill",        "Expires after", selectedDuration.rawValue)
                    summaryRow(selectedAction.flowIcon, "On expiry", selectedAction.flowLabel)
                    summaryRow("lock.fill",          "Encryption",   "End-to-end (cr_1.0)")
                }

                HStack(spacing: ONE.Spacing.sm) {
                    backButton { step = 1 }
                    Button("Create Group") { createGroup() }
                        .buttonStyle(.borderedProminent)
                        .tint(ONE.Colors.ephemeralRed)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Create ephemeral group, expires in \(selectedDuration.rawValue)")
                }
            }
            .padding(ONE.Spacing.lg)
        }
    }

    // MARK: - Helpers

    private func stepHeader(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: ONE.Spacing.sm) {
            Image(systemName: icon)
                .font(.systemScaled(32))
                .foregroundStyle(ONE.Colors.ephemeralRed)
            Text(title).font(.systemScaled(20, weight: .bold))
            Text(subtitle)
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func summaryRow(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.systemScaled(14))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(label).font(.systemScaled(14)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.systemScaled(14, weight: .medium)).foregroundStyle(.primary)
        }
        .padding(.vertical, ONE.Spacing.sm)
        .padding(.horizontal, ONE.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: ONE.Radius.card, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func primaryButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.systemScaled(15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, ONE.Spacing.sm)
        }
        .buttonStyle(.borderedProminent)
        .tint(ONE.Colors.ephemeralRed)
    }

    private func backButton(action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(ONE.Motion.adaptive(reduceMotion: reduceMotion)) { action() } }) {
            Text("Back")
                .font(.systemScaled(15, weight: .medium))
                .padding(.vertical, ONE.Spacing.sm)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.secondary)
    }

    private func createGroup() {
        let settings = ONEEphemeralGroupSettings(
            groupID: UUID().uuidString,
            expiresAt: Date().addingTimeInterval(selectedDuration.timeInterval),
            onExpiry: selectedAction
        )
        onCreate(settings)
        dismiss()
    }
}

// MARK: - ONEGroupExpiryAction UI metadata

extension ONEGroupExpiryAction {
    var flowLabel: String {
        switch self {
        case .archive:        return "Archive"
        case .album:          return "Collaborative Album"
        case .deleteAll:      return "Delete Everything"
        case .highlightsOnly: return "Highlights Only"
        }
    }

    var flowSubtitle: String {
        switch self {
        case .archive:        return "Save as a read-only archive visible only to members."
        case .album:          return "Convert to a shared photo album that persists."
        case .deleteAll:      return "All messages and media are permanently deleted. No recovery."
        case .highlightsOnly: return "Keep only moments someone marked as 'Remember'."
        }
    }

    var flowIcon: String {
        switch self {
        case .archive:        return "archivebox.fill"
        case .album:          return "photo.stack.fill"
        case .deleteAll:      return "trash.fill"
        case .highlightsOnly: return "star.fill"
        }
    }

    var flowTint: Color {
        switch self {
        case .archive:        return ONE.Colors.witnessGold
        case .album:          return ONE.Colors.privateIndigo
        case .deleteAll:      return ONE.Colors.ephemeralRed
        case .highlightsOnly: return ONE.Colors.repairGreen
        }
    }

    static var flowCases: [ONEGroupExpiryAction] {
        [.deleteAll, .highlightsOnly, .album, .archive]
    }
}
