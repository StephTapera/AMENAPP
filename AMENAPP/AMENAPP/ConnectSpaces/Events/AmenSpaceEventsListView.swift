import SwiftUI

struct AmenSpaceEventsListView: View {
    let events: [AmenSpaceEvent]
    let rsvpedEventIds: Set<String>
    let onSelectEvent: (AmenSpaceEvent) -> Void
    let onRSVP: (AmenSpaceEvent) -> Void

    private var sorted: [AmenSpaceEvent] {
        Array(events.sorted { $0.scheduledAt < $1.scheduledAt }.prefix(10))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Coming Up")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            if sorted.isEmpty {
                Text("No upcoming events")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(sorted) { event in
                            SpaceEventCard(
                                event: event,
                                isRSVPed: rsvpedEventIds.contains(event.id),
                                onTap: { onSelectEvent(event) },
                                onRSVP: { onRSVP(event) }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

private struct SpaceEventCard: View {
    let event: AmenSpaceEvent
    let isRSVPed: Bool
    let onTap: () -> Void
    let onRSVP: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: event.type.systemImageName)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "D9A441"))
                    Spacer()
                    if event.isLive {
                        liveBadge
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)

                Text(event.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)

                Spacer(minLength: 4)

                dateChip
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }
            .frame(width: 160, height: 120)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        event.isLive
                            ? Color(hex: "FF3B30").opacity(0.5)
                            : Color(hex: "D9A441").opacity(0.2),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(event.title), \(event.scheduledAt.shortLabel)")
        .accessibilityHint("Tap to view event details")
    }

    private var liveBadge: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Color(hex: "FF3B30"))
                .frame(width: 5, height: 5)
            Text("LIVE")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color(hex: "FF3B30").opacity(0.85), in: Capsule())
    }

    private var dateChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "calendar")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(event.scheduledAt.shortLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
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
}

private extension Date {
    var shortLabel: String {
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(self) {
            f.dateFormat = "'Today' h:mma"
        } else if cal.isDateInTomorrow(self) {
            f.dateFormat = "'Tomorrow' h:mma"
        } else {
            f.dateFormat = "MMM d, h:mma"
        }
        return f.string(from: self)
    }
}

#Preview {
    ZStack {
        Color(hex: "070607").ignoresSafeArea()
        AmenSpaceEventsListView(
            events: [
                AmenSpaceEvent(
                    id: "e1", spaceId: "s1", hostUserId: "u1",
                    title: "Sunday Evening Worship",
                    eventDescription: "Live worship.",
                    type: .livestream,
                    scheduledAt: Date().addingTimeInterval(3600),
                    durationMinutes: 90,
                    isRecurring: true,
                    recurrenceRule: "FREQ=WEEKLY",
                    rsvpUserIds: ["u2"],
                    maxAttendees: nil,
                    requiredTierId: nil,
                    isLive: true,
                    liveRoomId: "room1",
                    replayRef: nil,
                    calendarInviteSentAt: nil,
                    createdAt: Date(),
                    updatedAt: Date()
                ),
                AmenSpaceEvent(
                    id: "e2", spaceId: "s1", hostUserId: "u1",
                    title: "Wednesday Bible Study: Romans 8",
                    eventDescription: "Deep dive.",
                    type: .studySession,
                    scheduledAt: Date().addingTimeInterval(86400 * 3),
                    durationMinutes: 60,
                    isRecurring: false,
                    recurrenceRule: nil,
                    rsvpUserIds: [],
                    maxAttendees: 50,
                    requiredTierId: nil,
                    isLive: false,
                    liveRoomId: nil,
                    replayRef: nil,
                    calendarInviteSentAt: nil,
                    createdAt: Date(),
                    updatedAt: Date()
                ),
                AmenSpaceEvent(
                    id: "e3", spaceId: "s1", hostUserId: "u1",
                    title: "Friday Prayer Circle",
                    eventDescription: "Intercession.",
                    type: .prayerMeeting,
                    scheduledAt: Date().addingTimeInterval(86400 * 5),
                    durationMinutes: 45,
                    isRecurring: false,
                    recurrenceRule: nil,
                    rsvpUserIds: [],
                    maxAttendees: nil,
                    requiredTierId: nil,
                    isLive: false,
                    liveRoomId: nil,
                    replayRef: nil,
                    calendarInviteSentAt: nil,
                    createdAt: Date(),
                    updatedAt: Date()
                ),
            ],
            rsvpedEventIds: ["e1"],
            onSelectEvent: { _ in },
            onRSVP: { _ in }
        )
    }
}
