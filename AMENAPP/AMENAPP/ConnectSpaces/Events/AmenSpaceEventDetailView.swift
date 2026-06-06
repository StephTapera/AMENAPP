import SwiftUI
import FirebaseAnalytics
import FirebaseFunctions
import FirebaseAuth

private enum CalendarAddState: Equatable {
    case idle
    case adding
    case added
    case error(String)
}

struct AmenSpaceEventDetailView: View {
    let event: AmenSpaceEvent
    let spaceName: String
    let isRSVPed: Bool
    let onRSVP: () -> Void
    let onAddToCalendar: () -> Void
    let onJoinLive: () -> Void

    @State private var calendarAddState: CalendarAddState = .idle
    @State private var localIsRSVPed: Bool
    @State private var showLiveRoomToast = false
    @Environment(\.dismiss) private var dismiss

    private let calendarService = AmenCalendarInviteService()

    init(
        event: AmenSpaceEvent,
        spaceName: String,
        isRSVPed: Bool,
        onRSVP: @escaping () -> Void,
        onAddToCalendar: @escaping () -> Void,
        onJoinLive: @escaping () -> Void
    ) {
        self.event = event
        self.spaceName = spaceName
        self.isRSVPed = isRSVPed
        self.onRSVP = onRSVP
        self.onAddToCalendar = onAddToCalendar
        self.onJoinLive = onJoinLive
        self._localIsRSVPed = State(initialValue: isRSVPed)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: "070607").ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    heroCard
                    VStack(spacing: 12) {
                        rsvpAndCalendarRow
                        rsvpCountRow
                        descriptionBlock
                        if event.isLive {
                            joinLiveCTA
                        }
                        if event.replayRef != nil && AMENFeatureFlags.shared.replayEnabled {
                            replayButton
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }

            glassNavBar
        }
        .overlay(calendarToast, alignment: .bottom)
        .onAppear {
            Analytics.logEvent("space_event_viewed", parameters: [
                "event_id": event.id,
                "event_type": event.type.displayName
            ])
        }
    }

    // MARK: - Sub-views

    private var glassNavBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Dismiss")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: event.type.systemImageName)
                    .font(.system(size: 22))
                    .foregroundStyle(Color(hex: "D9A441"))
                Text(event.type.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(hex: "D9A441"))
                if event.isLive {
                    liveBadge
                }
            }

            Text(event.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundStyle(Color(hex: "D9A441"))
                Text(event.scheduledAt.formatted(as: "EEEE, MMMM d 'at' h:mm a"))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(event.durationMinutes) minutes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if event.isRecurring {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Image(systemName: "repeat")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Recurring")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 64)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "0F0E10"))
    }

    private var liveBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hex: "FF3B30"))
                .frame(width: 6, height: 6)
            Text("LIVE")
                .font(.caption2.weight(.black))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color(hex: "FF3B30").opacity(0.85), in: Capsule())
    }

    private var rsvpAndCalendarRow: some View {
        HStack(spacing: 10) {
            Button {
                // Optimistic update
                localIsRSVPed.toggle()
                onRSVP()
                Task {
                    try? await Functions.functions(region: "us-central1")
                        .httpsCallable("rsvpToSpaceEvent")
                        .call([
                            "eventId": event.id,
                            "spaceId": event.spaceId,
                            "uid": Auth.auth().currentUser?.uid ?? ""
                        ])
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: localIsRSVPed ? "checkmark.circle.fill" : "person.badge.plus")
                    Text(localIsRSVPed ? "Going" : "RSVP")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(localIsRSVPed ? Color(hex: "070607") : Color(hex: "D9A441"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    localIsRSVPed
                        ? Color(hex: "D9A441")
                        : Color(hex: "D9A441").opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color(hex: "D9A441").opacity(localIsRSVPed ? 0 : 0.4), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localIsRSVPed ? "Cancel RSVP" : "RSVP to this event")

            Button(action: handleAddToCalendar) {
                HStack(spacing: 6) {
                    if calendarAddState == .adding {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.white)
                    } else {
                        Image(systemName: "calendar.badge.plus")
                    }
                    Text("Calendar")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(calendarAddState == .adding)
            .accessibilityLabel("Add to Calendar")
        }
    }

    private var rsvpCountRow: some View {
        HStack {
            Image(systemName: "person.2.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(event.rsvpUserIds.count) people are going")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var descriptionBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About this event")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 14)
            Text(event.eventDescription)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "1A1820"), in: RoundedRectangle(cornerRadius: 14))
    }

    private var joinLiveCTA: some View {
        Button {
            if let roomId = event.liveRoomId,
               let url = URL(string: "amenapp://liveroom/\(roomId)"),
               UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else {
                withAnimation { showLiveRoomToast = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation { showLiveRoomToast = false }
                }
            }
            onJoinLive()
        } label: {
            HStack {
                Image(systemName: "video.fill")
                Text("Join Live")
                    .font(.headline.weight(.bold))
            }
            .foregroundStyle(Color(hex: "070607"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(hex: "D9A441"), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Join live event")
        .overlay(alignment: .top) {
            if showLiveRoomToast {
                Text("Live room starting soon")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .offset(y: -40)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var replayButton: some View {
        Button(action: {}) {
            HStack {
                Image(systemName: "play.rectangle.fill")
                Text("Watch Replay")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Color(hex: "D9A441"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(hex: "D9A441").opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color(hex: "D9A441").opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Watch replay")
    }

    @ViewBuilder
    private var calendarToast: some View {
        switch calendarAddState {
        case .added:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(hex: "D9A441"))
                Text("Added to Calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 32)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        case .error(let msg):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(Color(hex: "FF3B30"))
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        default:
            EmptyView()
        }
    }

    // MARK: - Actions

    private func handleAddToCalendar() {
        Task {
            withAnimation { calendarAddState = .adding }
            do {
                try await calendarService.addToCalendar(event: event, spaceName: spaceName)
                withAnimation { calendarAddState = .added }
                onAddToCalendar()
                try await Task.sleep(nanoseconds: 2_500_000_000)
                withAnimation { calendarAddState = .idle }
            } catch {
                withAnimation { calendarAddState = .error(error.localizedDescription) }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                withAnimation { calendarAddState = .idle }
            }
        }
    }
}

private extension Date {
    func formatted(as format: String) -> String {
        let f = DateFormatter()
        f.dateFormat = format
        return f.string(from: self)
    }
}

private extension AmenSpaceEventType {
    var systemImageName: String {
        switch self {
        case .livestream:          return "video.fill"
        case .audioHuddle:         return "mic.fill"
        case .communityEvent:      return "person.3.fill"
        case .recurringGathering:  return "repeat"
        case .prayerMeeting:       return "hands.sparkles.fill"
        case .studySession:        return "book.fill"
        }
    }

    var displayName: String {
        switch self {
        case .livestream:          return "Livestream"
        case .audioHuddle:         return "Audio Huddle"
        case .communityEvent:      return "Community Event"
        case .recurringGathering:  return "Gathering"
        case .prayerMeeting:       return "Prayer Meeting"
        case .studySession:        return "Study Session"
        }
    }
}

#Preview {
    AmenSpaceEventDetailView(
        event: AmenSpaceEvent(
            id: "e1",
            spaceId: "s1",
            hostUserId: "u1",
            title: "Sunday Evening Worship",
            eventDescription: "A 90-minute live worship service streamed to all members of the Grace Church Space. Bring your Bible and come ready to encounter God.",
            type: .livestream,
            scheduledAt: Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date(),
            durationMinutes: 90,
            isRecurring: true,
            recurrenceRule: "FREQ=WEEKLY;BYDAY=SU",
            rsvpUserIds: ["u2", "u3", "u4"],
            maxAttendees: 500,
            requiredTierId: nil,
            isLive: false,
            liveRoomId: nil,
            replayRef: nil,
            calendarInviteSentAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        ),
        spaceName: "Grace Church",
        isRSVPed: false,
        onRSVP: {},
        onAddToCalendar: {},
        onJoinLive: {}
    )
}
