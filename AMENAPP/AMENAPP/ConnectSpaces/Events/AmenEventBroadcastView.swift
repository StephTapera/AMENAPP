import SwiftUI
import FirebaseFunctions
import FirebaseAnalytics

// MARK: - Supporting enums

private enum RecipientScope: String, CaseIterable, Identifiable {
    case allMembers     = "All Members"
    case paidOnly       = "Paid Members Only"
    case specificTier   = "Specific Tier"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .allMembers:   return "person.3.fill"
        case .paidOnly:     return "star.fill"
        case .specificTier: return "square.stack.fill"
        }
    }
}

private enum BroadcastPriority: String, CaseIterable, Identifiable {
    case normal        = "Normal"
    case urgent        = "Urgent"
    case prayerRequest = "Prayer Request"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .normal:        return "bell.fill"
        case .urgent:        return "exclamationmark.triangle.fill"
        case .prayerRequest: return "hands.sparkles.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .normal:        return Color(hex: "D9A441")
        case .urgent:        return Color(hex: "FF3B30")
        case .prayerRequest: return Color(hex: "6E4BB5")
        }
    }
}

private enum SendTiming {
    case now
    case scheduled(Date)

    var isScheduled: Bool {
        if case .scheduled = self { return true }
        return false
    }

    var scheduledDate: Date? {
        if case .scheduled(let d) = self { return d }
        return nil
    }
}

private enum BroadcastState: Equatable {
    case idle
    case sending
    case success(memberCount: Int)
    case failure(String)

    static func == (lhs: BroadcastState, rhs: BroadcastState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.sending, .sending): return true
        case (.success(let a), .success(let b)):   return a == b
        case (.failure(let a), .failure(let b)):   return a == b
        default: return false
        }
    }
}

// MARK: - View

struct AmenEventBroadcastView: View {

    // MARK: Inputs
    let spaceId: String
    let spaceName: String
    let event: AmenSpaceEvent?
    let onDismiss: () -> Void

    // MARK: State
    @State private var messageText: String = ""
    @State private var recipientScope: RecipientScope = .allMembers
    @State private var priority: BroadcastPriority = .normal
    @State private var scheduleEnabled: Bool = false
    @State private var scheduledDate: Date = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    @State private var broadcastState: BroadcastState = .idle
    @State private var showToast: Bool = false

    // MARK: Environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Constants
    private let charLimit = 500

    private var sendTiming: SendTiming {
        scheduleEnabled ? .scheduled(scheduledDate) : .now
    }

    private var isFormValid: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isSending: Bool {
        broadcastState == .sending
    }

    // MARK: Body

    var body: some View {
        ZStack {
            Color(hex: "070607").ignoresSafeArea()

            VStack(spacing: 0) {
                navBar
                ScrollView {
                    VStack(spacing: 16) {
                        if let event = event {
                            eventPreviewCard(event)
                        }
                        messageCard
                        recipientCard
                        priorityCard
                        scheduleCard
                        if case .failure(let msg) = broadcastState {
                            errorBanner(msg)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
                sendButton
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
        }
        .overlay(toastOverlay, alignment: .bottom)
        .onAppear {
            Analytics.logEvent("event_broadcast_composer_viewed", parameters: [
                "space_id": spaceId,
                "has_event": event != nil ? "true" : "false",
            ])
        }
    }

    // MARK: - Nav bar

    private var navBar: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Dismiss announcement composer")
            Spacer()
            VStack(spacing: 2) {
                Text("Announce")
                    .font(.systemScaled(17, weight: .semibold))
                    .foregroundStyle(.white)
                Text(spaceName)
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(Color(hex: "D9A441"))
            }
            Spacer()
            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.thinMaterial)
    }

    // MARK: - Event preview card (Liquid Glass)

    private func eventPreviewCard(_ event: AmenSpaceEvent) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(hex: "D9A441").opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: platformImageForEvent(event))
                    .font(.systemScaled(16))
                    .foregroundStyle(Color(hex: "D9A441"))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.systemScaled(10))
                        .foregroundStyle(.secondary)
                    Text(event.scheduledAt.broadcastShortLabel)
                        .font(.systemScaled(12))
                        .foregroundStyle(.secondary)
                    if event.durationMinutes > 0 {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text("\(event.durationMinutes) min")
                            .font(.systemScaled(12))
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 3) {
                    Image(systemName: "paperclip")
                        .font(.systemScaled(9))
                    Text(".ics will be auto-attached")
                        .font(.systemScaled(11))
                }
                .foregroundStyle(Color(hex: "D9A441").opacity(0.8))
            }

            Spacer()
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(hex: "D9A441").opacity(0.25), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Attached event: \(event.title), \(event.scheduledAt.broadcastShortLabel)")
    }

    // MARK: - Message card

    private var messageCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if messageText.isEmpty {
                    Text("Write your message to \(recipientScope.rawValue.lowercased())…")
                        .font(.body)
                        .foregroundStyle(Color.white.opacity(0.3))
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $messageText)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .foregroundStyle(.white)
                    .font(.body)
                    .frame(minHeight: 140)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .onChange(of: messageText) { _, new in
                        if new.count > charLimit {
                            messageText = String(new.prefix(charLimit))
                        }
                    }
            }

            Divider().background(Color.white.opacity(0.06))

            HStack {
                Spacer()
                Text("\(messageText.count)/\(charLimit)")
                    .font(.systemScaled(11).monospacedDigit())
                    .foregroundStyle(
                        messageText.count > Int(Double(charLimit) * 0.9)
                            ? Color(hex: "FF3B30")
                            : Color.secondary
                    )
                    .padding(10)
            }
        }
        .background(Color(hex: "1A1820"), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        )
        .accessibilityLabel("Broadcast message composer")
    }

    // MARK: - Recipient card

    private var recipientCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Send To")
            VStack(spacing: 8) {
                ForEach(RecipientScope.allCases) { scope in
                    let isSel = recipientScope == scope
                    Button(action: {
                        withAnimation(reduceMotion ? .easeOut(duration: 0.10) : .spring(response: 0.22, dampingFraction: 0.9)) {
                            recipientScope = scope
                        }
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: scope.systemImage)
                                .font(.systemScaled(14))
                                .foregroundStyle(isSel ? Color(hex: "070607") : Color(hex: "D9A441"))
                                .frame(width: 22)
                            Text(scope.rawValue)
                                .font(.systemScaled(14, weight: .semibold))
                                .foregroundStyle(isSel ? Color(hex: "070607") : Color.white.opacity(0.85))
                            Spacer()
                            if isSel {
                                Image(systemName: "checkmark")
                                    .font(.systemScaled(12, weight: .bold))
                                    .foregroundStyle(Color(hex: "070607"))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            isSel ? Color(hex: "D9A441") : Color(hex: "1A1820"),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(scope.rawValue)\(isSel ? ", selected" : "")")
                }
            }
        }
    }

    // MARK: - Priority card

    private var priorityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Priority")
            HStack(spacing: 8) {
                ForEach(BroadcastPriority.allCases) { p in
                    let isSel = priority == p
                    Button(action: {
                        withAnimation(reduceMotion ? .easeOut(duration: 0.10) : .spring(response: 0.22, dampingFraction: 0.9)) {
                            priority = p
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: p.systemImage)
                                .font(.systemScaled(11))
                            Text(p.rawValue)
                                .font(.systemScaled(12, weight: .semibold))
                        }
                        .foregroundStyle(isSel ? Color(hex: "070607") : Color.white.opacity(0.85))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            isSel ? p.accentColor : p.accentColor.opacity(0.10),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(p.accentColor.opacity(isSel ? 0 : 0.35), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(p.rawValue) priority\(isSel ? ", selected" : "")")
                }
                Spacer()
            }
        }
    }

    // MARK: - Schedule card

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Delivery")
            Toggle(isOn: $scheduleEnabled) {
                HStack(spacing: 6) {
                    Image(systemName: scheduleEnabled ? "clock.fill" : "bolt.fill")
                        .foregroundStyle(Color(hex: "D9A441"))
                    Text(scheduleEnabled ? "Schedule for later" : "Send now")
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .tint(Color(hex: "D9A441"))
            .padding(14)
            .background(Color(hex: "1A1820"), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
            )
            .accessibilityLabel("Schedule message toggle")

            if scheduleEnabled {
                DatePicker(
                    "",
                    selection: $scheduledDate,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                .labelsHidden()
                .colorScheme(.dark)
                .padding(14)
                .background(Color(hex: "1A1820"), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                )
                .transition(.opacity)
                .accessibilityLabel("Scheduled delivery date and time")
            }
        }
    }

    // MARK: - Send button

    private var sendButton: some View {
        Button(action: handleSend) {
            HStack(spacing: 8) {
                if isSending {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color(hex: "070607"))
                    Text("Sending…")
                        .font(.systemScaled(16, weight: .semibold))
                        .foregroundStyle(Color(hex: "070607"))
                } else {
                    Image(systemName: scheduleEnabled ? "clock.badge.checkmark" : "paperplane.fill")
                    Text(scheduleEnabled ? "Schedule Message" : "Send Now")
                        .font(.systemScaled(16, weight: .semibold))
                }
            }
            .foregroundStyle(Color(hex: "070607"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                isFormValid ? Color(hex: "D9A441") : Color(hex: "D9A441").opacity(0.35),
                in: RoundedRectangle(cornerRadius: 14)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isFormValid || isSending)
        .accessibilityLabel(scheduleEnabled ? "Schedule message" : "Send message now")
    }

    // MARK: - Toast

    @ViewBuilder
    private var toastOverlay: some View {
        if showToast, case .success(let count) = broadcastState {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(hex: "D9A441"))
                Text("Message sent to \(count) member\(count == 1 ? "" : "s")")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 100)
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.systemScaled(11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(Color(hex: "FF3B30"))
            Text(message)
                .font(.systemScaled(13))
                .foregroundStyle(.white)
                .lineLimit(3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "FF3B30").opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(hex: "FF3B30").opacity(0.3), lineWidth: 0.5)
        )
        .accessibilityLabel("Error: \(message)")
    }

    private func platformImageForEvent(_ event: AmenSpaceEvent) -> String {
        switch event.type {
        case .livestream:          return "video.fill"
        case .audioHuddle:         return "mic.fill"
        case .communityEvent:      return "person.3.fill"
        case .recurringGathering:  return "repeat"
        case .prayerMeeting:       return "hands.sparkles.fill"
        case .studySession:        return "book.fill"
        }
    }

    // MARK: - Actions

    private func handleSend() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        Task {
            await MainActor.run {
                withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.82)) {
                    broadcastState = .sending
                }
            }

            do {
                var payload: [String: Any] = [
                    "spaceId":   spaceId,
                    "message":   trimmed,
                    "scope":     recipientScope.rawValue,
                    "priority":  priority.rawValue,
                    "sendNow":   !scheduleEnabled,
                ]
                if let event = event {
                    payload["eventId"] = event.id
                }
                if scheduleEnabled {
                    payload["scheduledAt"] = scheduledDate.timeIntervalSince1970
                }

                let fn = Functions.functions(region: "us-east1").httpsCallable("broadcastSpaceAnnouncement")
                let result = try await fn.call(payload)

                let count: Int
                if let data = result.data as? [String: Any],
                   let n = data["memberCount"] as? Int {
                    count = n
                } else {
                    count = 0
                }

                await MainActor.run {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.82)) {
                        broadcastState = .success(memberCount: count)
                        showToast = true
                    }
                }

                // Auto-dismiss toast after 2.5s, then close sheet
                try await Task.sleep(nanoseconds: 2_500_000_000)
                await MainActor.run {
                    withAnimation { showToast = false }
                }
                try await Task.sleep(nanoseconds: 300_000_000)
                await MainActor.run { onDismiss() }

            } catch {
                await MainActor.run {
                    withAnimation {
                        broadcastState = .failure(error.localizedDescription)
                    }
                }
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                await MainActor.run {
                    withAnimation { broadcastState = .idle }
                }
            }
        }
    }
}

// MARK: - Date extension (file-private)

private extension Date {
    var broadcastShortLabel: String {
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(self) {
            f.dateFormat = "'Today at' h:mm a"
        } else if cal.isDateInTomorrow(self) {
            f.dateFormat = "'Tomorrow at' h:mm a"
        } else {
            f.dateFormat = "EEE, MMM d 'at' h:mm a"
        }
        return f.string(from: self)
    }
}

// MARK: - Preview

#Preview {
    AmenEventBroadcastView(
        spaceId: "space_preview",
        spaceName: "Grace Church",
        event: AmenSpaceEvent(
            id: "e1",
            spaceId: "space_preview",
            hostUserId: "u1",
            title: "Sunday Evening Worship",
            eventDescription: "Join us live.",
            type: .livestream,
            scheduledAt: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date(),
            durationMinutes: 90,
            isRecurring: true,
            recurrenceRule: "FREQ=WEEKLY;BYDAY=SU",
            rsvpUserIds: [],
            maxAttendees: 500,
            requiredTierId: nil,
            isLive: false,
            liveRoomId: nil,
            replayRef: nil,
            calendarInviteSentAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        ),
        onDismiss: {}
    )
    .preferredColorScheme(.dark)
}
