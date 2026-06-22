import SwiftUI
import FirebaseAuth
import FirebaseFunctions

// MARK: - Inline enums

enum VideoPlatform: String, CaseIterable, Identifiable {
    case zoom        = "Zoom"
    case teams       = "Microsoft Teams"
    case meet        = "Google Meet"
    case facetime    = "Apple FaceTime"
    case inApp       = "In-App Live Room"
    case phone       = "Phone"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .zoom:     return "video.fill"
        case .teams:    return "square.grid.2x2.fill"
        case .meet:     return "video.circle.fill"
        case .facetime: return "phone.fill"
        case .inApp:    return "dot.radiowaves.left.and.right"
        case .phone:    return "phone.circle.fill"
        }
    }

    /// Whether the host must paste a meeting link.
    var requiresURL: Bool {
        switch self {
        case .zoom, .teams, .meet: return true
        case .facetime, .inApp, .phone: return false
        }
    }
}

enum RecurrenceFrequency: String, CaseIterable, Identifiable {
    case weekly    = "Weekly"
    case biweekly  = "Bi-weekly"
    case monthly   = "Monthly"

    var id: String { rawValue }

    /// iCal RRULE string for AmenCalendarInviteService
    var rrule: String {
        switch self {
        case .weekly:   return "FREQ=WEEKLY"
        case .biweekly: return "FREQ=WEEKLY;INTERVAL=2"
        case .monthly:  return "FREQ=MONTHLY"
        }
    }
}

// MARK: - Composer view

struct AmenSmartEventComposerView: View {

    // MARK: Inputs
    let spaceId: String
    let spaceName: String
    let onDismiss: () -> Void
    let onEventCreated: (AmenSpaceEvent) -> Void

    // MARK: State
    @State private var title: String = ""
    @State private var selectedDate: Date = {
        // default to next even half-hour
        let now = Date()
        let comps = Calendar.current.dateComponents([.hour, .minute], from: now)
        let mins = (comps.minute ?? 0)
        let nextHalf = mins < 30 ? 30 : 60
        return Calendar.current.date(
            byAdding: .minute,
            value: nextHalf - mins,
            to: now
        ) ?? now
    }()
    @State private var durationMinutes: Int = 60
    @State private var platform: VideoPlatform = .zoom
    @State private var meetingURL: String = ""
    @State private var isRecurring: Bool = false
    @State private var recurrenceFrequency: RecurrenceFrequency = .weekly
    @State private var isBroadcasting: Bool = false
    @State private var broadcastError: String? = nil
    @State private var showShareSheet: Bool = false
    @State private var calendarAdded: Bool = false
    @State private var calendarError: String? = nil
    @State private var showCustomDuration: Bool = false
    @State private var customDurationText: String = ""

    // MARK: Environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Private
    private let calendarService = AmenCalendarInviteService()
    private let durations: [(label: String, minutes: Int)] = [
        ("30 min", 30),
        ("1 hr",   60),
        ("1.5 hr", 90),
        ("2 hr",  120),
        ("Custom", -1),
    ]

    // MARK: Derived

    private var isFormValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var resolvedRRULE: String? {
        guard isRecurring else { return nil }
        return recurrenceFrequency.rrule
    }

    private var durationLabel: String {
        if durationMinutes < 60 { return "\(durationMinutes) min" }
        let h = durationMinutes / 60
        let m = durationMinutes % 60
        return m == 0 ? "\(h) hour\(h > 1 ? "s" : "")" : "\(h)h \(m)m"
    }

    private var platformJoinText: String {
        switch platform {
        case .inApp:    return "In-App AMEN"
        case .phone:    return "Phone call"
        case .facetime: return "Apple FaceTime"
        default:
            let url = meetingURL.trimmingCharacters(in: .whitespacesAndNewlines)
            return url.isEmpty ? "[link pending]" : url
        }
    }

    func generateInviteText() -> String {
        let df = DateFormatter()
        df.dateFormat = "EEEE, MMMM d 'at' h:mm a"
        return """
        You're invited to \(title.trimmingCharacters(in: .whitespacesAndNewlines))
        Date: \(df.string(from: selectedDate))
        Duration: \(durationLabel)
        Join: \(platformJoinText)

        Add to calendar: [ICS file will be attached]
        """
    }

    // MARK: Body

    var body: some View {
        ZStack {
            Color(hex: "070607").ignoresSafeArea()

            VStack(spacing: 0) {
                navBar
                ScrollView {
                    VStack(spacing: 16) {
                        titleCard
                        dateTimeCard
                        durationCard
                        platformCard
                        if platform.requiresURL {
                            meetingURLCard
                        }
                        recurrenceCard
                        invitePreviewCard
                        if let err = broadcastError {
                            errorBanner(err)
                        }
                        if let err = calendarError {
                            errorBanner(err)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
                ctaRow
            }
        }
        .sheet(isPresented: $showShareSheet) {
            EventShareSheet(activityItems: shareItems())
        }
        .overlay(calendarToast, alignment: .bottom)
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
            .accessibilityLabel("Dismiss event composer")
            Spacer()
            Text("New Event")
                .font(.systemScaled(17, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            Color.clear.frame(width: 32, height: 32)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.thinMaterial)
    }

    // MARK: - Cards

    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Event Title")
            TextField("", text: $title, prompt: Text("Thursday 8pm Discipleship Call")
                .foregroundStyle(Color.white.opacity(0.3)))
                .foregroundStyle(.white)
                .font(.systemScaled(16, weight: .semibold))
                .padding(14)
                .background(Color(hex: "1A1820"), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                )
                .accessibilityLabel("Event title")
        }
    }

    private var dateTimeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Date & Time")
            DatePicker(
                "",
                selection: $selectedDate,
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
            .accessibilityLabel("Event date and time picker")
        }
    }

    private var durationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Duration")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(durations, id: \.minutes) { option in
                        let isCustom = option.minutes == -1
                        let isSelected = isCustom
                            ? showCustomDuration
                            : (durationMinutes == option.minutes && !showCustomDuration)
                        Button(action: {
                            if isCustom {
                                withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.82)) {
                                    showCustomDuration = true
                                }
                            } else {
                                withAnimation(reduceMotion ? .easeOut(duration: 0.10) : .spring(response: 0.22, dampingFraction: 0.9)) {
                                    durationMinutes = option.minutes
                                    showCustomDuration = false
                                }
                            }
                        }) {
                            Text(option.label)
                                .font(.systemScaled(13, weight: .semibold))
                                .foregroundStyle(isSelected ? Color(hex: "070607") : Color.white.opacity(0.85))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    isSelected ? Color(hex: "D9A441") : Color(hex: "D9A441").opacity(0.10),
                                    in: Capsule()
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color(hex: "D9A441").opacity(isSelected ? 0 : 0.3), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(option.label) duration\(isSelected ? ", selected" : "")")
                    }
                }
                .padding(.horizontal, 2)
            }
            if showCustomDuration {
                HStack(spacing: 8) {
                    TextField("", text: $customDurationText, prompt: Text("e.g. 75").foregroundStyle(.white.opacity(0.3)))
                        .keyboardType(.numberPad)
                        .foregroundStyle(.white)
                        .font(.systemScaled(15, weight: .semibold))
                        .onChange(of: customDurationText) { _, new in
                            if let mins = Int(new.filter(\.isNumber)), mins > 0 {
                                durationMinutes = min(mins, 480)
                            }
                        }
                        .padding(12)
                        .background(Color(hex: "1A1820"), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                        .accessibilityLabel("Custom duration in minutes")
                    Text("min")
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }
        }
    }

    private var platformCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Video Platform")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(VideoPlatform.allCases) { p in
                    let isSelected = platform == p
                    Button(action: {
                        withAnimation(reduceMotion ? .easeOut(duration: 0.10) : .spring(response: 0.22, dampingFraction: 0.9)) {
                            platform = p
                        }
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: p.systemImage)
                                .font(.systemScaled(18))
                                .foregroundStyle(isSelected ? Color(hex: "070607") : Color(hex: "D9A441"))
                            Text(p.rawValue)
                                .font(.systemScaled(10, weight: .semibold))
                                .foregroundStyle(isSelected ? Color(hex: "070607") : Color.white.opacity(0.75))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(
                            isSelected ? Color(hex: "D9A441") : Color(hex: "1A1820"),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(p.rawValue)\(isSelected ? ", selected" : "")")
                }
            }
        }
    }

    private var meetingURLCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Meeting Link")
            TextField("", text: $meetingURL, prompt: Text("Paste your \(platform.rawValue) link here")
                .foregroundStyle(Color.white.opacity(0.3)))
                .foregroundStyle(.white)
                .font(.systemScaled(14, weight: .semibold))
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(14)
                .background(Color(hex: "1A1820"), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                )
                .accessibilityLabel("Meeting link for \(platform.rawValue)")
        }
    }

    private var recurrenceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Recurring")
            Toggle(isOn: $isRecurring) {
                HStack(spacing: 6) {
                    Image(systemName: "repeat")
                        .foregroundStyle(Color(hex: "D9A441"))
                    Text("Repeat this event")
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
            .accessibilityLabel("Recurring event toggle")

            if isRecurring {
                HStack(spacing: 8) {
                    ForEach(RecurrenceFrequency.allCases) { freq in
                        let isSel = recurrenceFrequency == freq
                        Button(action: {
                            withAnimation(reduceMotion ? .easeOut(duration: 0.10) : .spring(response: 0.22, dampingFraction: 0.9)) {
                                recurrenceFrequency = freq
                            }
                        }) {
                            Text(freq.rawValue)
                                .font(.systemScaled(13, weight: .semibold))
                                .foregroundStyle(isSel ? Color(hex: "070607") : Color.white.opacity(0.85))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    isSel ? Color(hex: "6E4BB5") : Color(hex: "6E4BB5").opacity(0.12),
                                    in: Capsule()
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color(hex: "6E4BB5").opacity(isSel ? 0 : 0.4), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(freq.rawValue)\(isSel ? ", selected" : "")")
                    }
                    Spacer()
                }
                .transition(.opacity)
            }
        }
    }

    private var invitePreviewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Invite Preview")
            Text(generateInviteText())
                .font(.systemScaled(13))
                .foregroundStyle(Color.white.opacity(0.75))
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "1A1820"), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color(hex: "D9A441").opacity(0.2), lineWidth: 0.5)
                )
                .accessibilityLabel("Invite preview: \(generateInviteText())")
        }
    }

    // MARK: - CTA row

    private var ctaRow: some View {
        VStack(spacing: 10) {
            Divider().background(Color.white.opacity(0.06))
            HStack(spacing: 10) {
                // Add to My Calendar
                Button(action: handleAddToCalendar) {
                    Label(calendarAdded ? "Added" : "My Calendar", systemImage: calendarAdded ? "checkmark.circle.fill" : "calendar.badge.plus")
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(calendarAdded ? Color(hex: "D9A441") : Color.white.opacity(0.85))
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(calendarAdded ? "Event added to calendar" : "Add event to my calendar")
                .disabled(!isFormValid)

                // Share Invite
                Button(action: { showShareSheet = true }) {
                    Label("Share Invite", systemImage: "square.and.arrow.up")
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share event invite")
                .disabled(!isFormValid)
            }

            // Send to Space
            Button(action: handleBroadcast) {
                HStack(spacing: 8) {
                    if isBroadcasting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color(hex: "070607"))
                    } else {
                        Image(systemName: "megaphone.fill")
                    }
                    Text(isBroadcasting ? "Sending to Space…" : "Send to Space")
                        .font(.systemScaled(16, weight: .semibold))
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
            .disabled(!isFormValid || isBroadcasting)
            .accessibilityLabel("Send event to space")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    // MARK: - Toast overlays

    @ViewBuilder
    private var calendarToast: some View {
        if calendarAdded {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(hex: "D9A441"))
                Text("Added to Calendar")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 120)
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

    private func shareItems() -> [Any] {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let inviteText = generateInviteText()
        let event = buildSpaceEvent(title: trimmedTitle)
        let icsData = calendarService.icsData(for: event, spaceName: spaceName)
        // Wrap ics as a temporary file URL so the share sheet can attach it
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(trimmedTitle.replacingOccurrences(of: " ", with: "_")).ics")
        try? icsData.write(to: tmpURL)
        return [inviteText, tmpURL]
    }

    private func buildSpaceEvent(title: String) -> AmenSpaceEvent {
        AmenSpaceEvent(
            id: UUID().uuidString,
            spaceId: spaceId,
            hostUserId: "",           // filled server-side
            title: title,
            eventDescription: generateInviteText(),
            type: platform == .inApp ? .livestream : .communityEvent,
            scheduledAt: selectedDate,
            durationMinutes: durationMinutes,
            isRecurring: isRecurring,
            recurrenceRule: resolvedRRULE,
            rsvpUserIds: [],
            maxAttendees: nil,
            requiredTierId: nil,
            isLive: false,
            liveRoomId: nil,
            replayRef: nil,
            calendarInviteSentAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    // MARK: - Handlers

    private func handleAddToCalendar() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        let event = buildSpaceEvent(title: trimmedTitle)
        Task {
            do {
                try await calendarService.addToCalendar(event: event, spaceName: spaceName)
                await MainActor.run {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.82)) {
                        calendarAdded = true
                        calendarError = nil
                    }
                }
                try await Task.sleep(nanoseconds: 2_500_000_000)
                await MainActor.run {
                    withAnimation { calendarAdded = false }
                }
            } catch {
                await MainActor.run {
                    calendarError = error.localizedDescription
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run { calendarError = nil }
            }
        }
    }

    private func handleBroadcast() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        Task {
            await MainActor.run {
                withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.82)) {
                    isBroadcasting = true
                    broadcastError = nil
                }
            }

            do {
                let urlValue = platform.requiresURL
                    ? meetingURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    : nil

                let resolvedSpaceId = spaceId.isEmpty ? "" : spaceId
                let hostUserId = Auth.auth().currentUser?.uid ?? ""

                let payload: [String: Any] = [
                    "spaceId":            resolvedSpaceId,
                    "hostUserId":         hostUserId,
                    "title":              trimmedTitle,
                    "scheduledAt":        selectedDate.timeIntervalSince1970,
                    "durationMinutes":    durationMinutes,
                    "platform":           platform.rawValue,
                    "meetingURL":         urlValue as Any,
                    "isRecurring":        isRecurring,
                    "recurrenceRule":     resolvedRRULE as Any,
                    "inviteText":         generateInviteText(),
                ]

                let fn = Functions.functions(region: "us-east1").httpsCallable("broadcastSpaceEvent")
                _ = try await fn.call(payload)

                let newEvent = buildSpaceEvent(title: trimmedTitle)
                await MainActor.run {
                    withAnimation { isBroadcasting = false }
                    onEventCreated(newEvent)
                    onDismiss()
                }
            } catch {
                await MainActor.run {
                    withAnimation {
                        isBroadcasting = false
                        broadcastError = error.localizedDescription
                    }
                }
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                await MainActor.run {
                    withAnimation { broadcastError = nil }
                }
            }
        }
    }
}

// MARK: - UIActivityViewController wrapper

private struct EventShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    AmenSmartEventComposerView(
        spaceId: "space_preview",
        spaceName: "Grace Church",
        onDismiss: {},
        onEventCreated: { _ in }
    )
    .preferredColorScheme(.dark)
}
