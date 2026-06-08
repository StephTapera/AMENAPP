// BereanMentorPulseView.swift
// AMENAPP — Berean Mentorship OS — Mentor Pulse view
// Shown only when isMentor == true. No public metrics.
// Swift 6, iOS 18+, SwiftUI.

import SwiftUI
import FirebaseAuth

// MARK: - Root view

struct BereanMentorPulseView: View {
    @StateObject private var service = BereanMentorshipService.shared
    @AppStorage("bereanMentorshipOS_enabled") private var isEnabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedMentorship: BereanMentorship?
    @State private var actionPulseItem: BereanMentorPulseItem?

    var body: some View {
        Group {
            if !isEnabled {
                BereanMentorshipFeaturePlaceholder(
                    icon: "person.2.circle",
                    message: "Mentorship OS is not enabled.",
                    detail: "Turn on Berean Mentorship in Settings to get started."
                )
            } else if !service.isMentor {
                BereanMentorshipFeaturePlaceholder(
                    icon: "person.badge.shield.checkmark",
                    message: "Enable mentor mode in your profile",
                    detail: "Once approved, your mentee pulse will appear here."
                )
            } else {
                pulseContent
            }
        }
        .navigationTitle("Mentor Pulse")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedMentorship) { mentorship in
            LogSessionSheet(mentorship: mentorship)
        }
        .confirmationDialog(
            "Mentee Action",
            isPresented: Binding(
                get: { actionPulseItem != nil },
                set: { if !$0 { actionPulseItem = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let item = actionPulseItem {
                Button("Send Message") {
                    actionPulseItem = nil
                }
                Button("Schedule Session") {
                    if let match = service.myMentorships.first(where: { $0.menteeId == item.menteeId }) {
                        selectedMentorship = match
                    }
                    actionPulseItem = nil
                }
                Button("Log Prayer") {
                    Task { await service.dismissPulseItem(id: item.id) }
                    actionPulseItem = nil
                }
                Button("Dismiss", role: .destructive) {
                    Task { await service.dismissPulseItem(id: item.id) }
                    actionPulseItem = nil
                }
                Button("Cancel", role: .cancel) {
                    actionPulseItem = nil
                }
            }
        }
    }

    // MARK: - Pulse content

    private var pulseContent: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            if service.isLoading && service.myMentorships.isEmpty {
                ProgressView("Loading mentee pulse...")
                    .foregroundStyle(Color.secondary)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        pulseItemsSection
                        upcomingSessionsSection
                    }
                    .padding(.bottom, 40)
                }
                .refreshable {
                    await service.loadMentorships()
                    try? await service.fetchMentorPulse()
                }
            }
        }
        .onAppear {
            Task {
                await service.loadMentorships()
                try? await service.fetchMentorPulse()
            }
        }
    }

    // MARK: - Pulse items section

    @ViewBuilder
    private var pulseItemsSection: some View {
        let items = service.mentorPulse?.items ?? []
        let menteeCount = service.myMentorships.filter { $0.status == .active }.count

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(.systemScaled(11))
                    .foregroundStyle(Color.accentColor)
                Text("YOUR MENTEES")
                    .font(.systemScaled(10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .tracking(2)
                if menteeCount > 0 {
                    Text("\(menteeCount)")
                        .font(.systemScaled(10, weight: .bold))
                        .foregroundStyle(Color(.systemGroupedBackground))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                        .accessibilityLabel("\(menteeCount) active mentees")
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)

            if items.isEmpty {
                BereanMentorEmptyPulseView()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            } else {
                ForEach(items) { item in
                    MentorPulseItemRow(item: item)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .onTapGesture { actionPulseItem = item }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                Task { await service.dismissPulseItem(id: item.id) }
                            } label: {
                                Label("Dismiss", systemImage: "xmark.circle")
                            }
                            .tint(Color(hex: "#E05252"))
                        }
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: items.count)

                    Divider()
                        .background(Color(UIColor.separator))
                        .padding(.horizontal, 20)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
    }

    // MARK: - Upcoming sessions section

    @ViewBuilder
    private var upcomingSessionsSection: some View {
        let upcoming = service.myMentorships.filter { m in
            guard let next = m.nextSessionDate else { return false }
            return next > Date() && next <= Date().addingTimeInterval(7 * 24 * 3600)
        }.sorted { ($0.nextSessionDate ?? .distantFuture) < ($1.nextSessionDate ?? .distantFuture) }

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.systemScaled(11))
                    .foregroundStyle(Color.accentColor)
                Text("UPCOMING SESSIONS")
                    .font(.systemScaled(10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .tracking(2)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)

            if upcoming.isEmpty {
                Text("No sessions in the next 7 days.")
                    .font(.systemScaled(14))
                    .foregroundStyle(Color.secondary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            } else {
                ForEach(upcoming) { mentorship in
                    UpcomingSessionRow(mentorship: mentorship) {
                        selectedMentorship = mentorship
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)

                    Divider()
                        .background(Color(UIColor.separator))
                        .padding(.horizontal, 20)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }
}

// MARK: - Pulse item row

struct MentorPulseItemRow: View {
    let item: BereanMentorPulseItem

    private var initialsText: String {
        item.menteeName
            .split(separator: " ")
            .compactMap { $0.first.map { String($0) } }
            .prefix(2)
            .joined()
            .uppercased()
    }

    private var relativeDateText: String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: item.date, relativeTo: Date())
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Text(initialsText)
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.menteeName)
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(Color.primary)
                    Text("·")
                        .foregroundStyle(Color.secondary.opacity(0.5))
                    Text(item.signal.displayName)
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundStyle(item.signal.color)
                }
                Text(item.detail)
                    .font(.systemScaled(13))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(2)
                Text(relativeDateText)
                    .font(.systemScaled(11))
                    .foregroundStyle(Color.secondary)
            }

            Spacer()

            Image(systemName: item.signal.systemImage)
                .font(.systemScaled(20))
                .foregroundStyle(item.signal.color)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.menteeName), \(item.signal.displayName): \(item.detail)")
        .accessibilityHint("Tap for actions")
    }
}

// MARK: - Upcoming session row

private struct UpcomingSessionRow: View {
    let mentorship: BereanMentorship
    let onLogTap: () -> Void

    private var formattedDate: String {
        guard let date = mentorship.nextSessionDate else { return "" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, h:mm a"
        return fmt.string(from: date)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(mentorship.menteeDisplayName)
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Text(formattedDate)
                    .font(.systemScaled(12))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            Spacer()
            Button(action: onLogTap) {
                Text("Log Session")
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1))
            }
            .accessibilityLabel("Log session with \(mentorship.menteeDisplayName)")
        }
    }
}

// MARK: - Empty pulse state

private struct BereanMentorEmptyPulseView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.systemScaled(32, weight: .ultraLight))
                .foregroundStyle(Color.accentColor.opacity(0.6))
            Text("Your mentees are doing great!")
                .font(.title3).bold()
                .foregroundStyle(Color.primary)
                .multilineTextAlignment(.center)
            Text("No items need your attention right now.")
                .font(.systemScaled(13))
                .foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}

// MARK: - Feature disabled placeholder (shared across Mentorship OS)

struct BereanMentorshipFeaturePlaceholder: View {
    let icon: String
    let message: String
    let detail: String

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.systemScaled(40, weight: .ultraLight))
                    .foregroundStyle(Color.accentColor.opacity(0.6))
                    .accessibilityHidden(true)
                Text(message)
                    .font(.title2).bold()
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.center)
                Text(detail)
                    .font(.systemScaled(14))
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message). \(detail)")
    }
}

// MARK: - Log Session Sheet

struct LogSessionSheet: View {
    let mentorship: BereanMentorship
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = BereanMentorshipService.shared

    @State private var notes: String = ""
    @State private var durationMinutes: Int = 30
    @State private var isLogging: Bool = false
    @State private var didLog: Bool = false

    private let durationStep = 15
    private let durationMin  = 15
    private let durationMax  = 120

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Session with")
                                .font(.systemScaled(12))
                                .foregroundStyle(Color.secondary)
                            Text(mentorship.menteeDisplayName)
                                .font(.title2).bold()
                                .foregroundStyle(Color.primary)
                            Text(mentorship.focus)
                                .font(.systemScaled(13))
                                .foregroundStyle(Color.accentColor)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)

                        Divider()
                            .background(Color(UIColor.separator))
                            .padding(.horizontal, 24)

                        // Notes field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Session Notes")
                                .font(.systemScaled(13, weight: .semibold))
                                .foregroundStyle(Color.secondary)
                                .accessibilityAddTraits(.isHeader)

                            ZStack(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemGroupedBackground))
                                    .frame(minHeight: 120)

                                TextEditor(text: $notes)
                                    .scrollContentBackground(.hidden)
                                    .background(Color.clear)
                                    .foregroundStyle(Color.primary)
                                    .font(.systemScaled(14))
                                    .padding(12)
                                    .frame(minHeight: 120)

                                if notes.isEmpty {
                                    Text("What did you discuss? Key scripture, takeaways, follow-ups...")
                                        .font(.systemScaled(14))
                                        .foregroundStyle(Color.secondary.opacity(0.5))
                                        .padding(16)
                                        .allowsHitTesting(false)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Session notes")

                        // Duration stepper
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Duration")
                                .font(.systemScaled(13, weight: .semibold))
                                .foregroundStyle(Color.secondary)
                                .accessibilityAddTraits(.isHeader)

                            HStack {
                                Text("\(durationMinutes) minutes")
                                    .font(.systemScaled(16, weight: .medium))
                                    .foregroundStyle(Color.primary)
                                Spacer()
                                Stepper(value: $durationMinutes, in: durationMin...durationMax, step: durationStep) {
                                    EmptyView()
                                }
                                .labelsHidden()
                                .tint(Color.accentColor)
                                .accessibilityLabel("Session duration, \(durationMinutes) minutes")
                                .accessibilityAdjustableAction { direction in
                                    switch direction {
                                    case .increment: durationMinutes = min(durationMax, durationMinutes + durationStep)
                                    case .decrement: durationMinutes = max(durationMin, durationMinutes - durationStep)
                                    @unknown default: break
                                    }
                                }
                            }
                            .padding(16)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal, 24)

                        // Log button
                        Button {
                            Task { await logSession() }
                        } label: {
                            ZStack {
                                if isLogging {
                                    ProgressView().tint(Color(.systemGroupedBackground))
                                } else {
                                    Text(didLog ? "Logged!" : "Log Session")
                                        .font(.systemScaled(16, weight: .semibold))
                                        .foregroundStyle(Color(.systemGroupedBackground))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(isLogging || notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .padding(.horizontal, 24)
                        .accessibilityLabel("Log this session")
                        .accessibilityHint("Saves notes and duration for your mentee")

                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("Log Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.secondary)
                        .accessibilityLabel("Cancel logging session")
                }
            }
        }
    }

    private func logSession() async {
        guard !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isLogging = true
        defer { isLogging = false }
        do {
            try await service.logSession(
                mentorshipId: mentorship.id,
                notes: notes,
                durationMinutes: durationMinutes
            )
            didLog = true
            if let uid = Auth.auth().currentUser?.uid {
                await MentorshipIntelligenceService.shared.sessionCompleted(
                    mentorshipId: mentorship.id,
                    uid: uid
                )
            }
            try? await Task.sleep(for: .milliseconds(800))
            dismiss()
        } catch {
            // Error surfaced via service.lastError — no crash
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Mentor Pulse") {
    NavigationStack {
        BereanMentorPulseView()
    }
    .preferredColorScheme(.dark)
}

#Preview("Log Session Sheet") {
    LogSessionSheet(mentorship: BereanMentorshipMockData.mentorships[0])
}
#endif
