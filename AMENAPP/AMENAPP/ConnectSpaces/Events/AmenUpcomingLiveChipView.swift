import SwiftUI

struct AmenUpcomingLiveChipView: View {
    let event: AmenSpaceEvent
    let isRSVPed: Bool
    let onRSVP: () -> Void
    let onJoinLive: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    private var countdownText: String {
        if event.isLive { return "LIVE NOW" }
        let diff = event.scheduledAt.timeIntervalSinceNow
        if diff <= 0 { return "Starting soon" }
        let mins = Int(diff / 60)
        if mins < 60 { return "Starting in \(mins)m" }
        let hours = mins / 60
        if hours < 24 { return "Starting in \(hours)h" }
        let formatter = DateFormatter()
        let cal = Calendar.current
        formatter.dateFormat = cal.isDateInTomorrow(event.scheduledAt) ? "'Tomorrow' h:mma" : "EEE h:mma"
        return formatter.string(from: event.scheduledAt)
    }

    var body: some View {
        HStack(spacing: 8) {
            leadingIcon
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(countdownText)
                    .font(.caption2)
                    .foregroundStyle(event.isLive ? Color(hex: "FF3B30") : Color(hex: "D9A441"))
            }
            Spacer(minLength: 0)
            actionButton
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color(hex: "D9A441").opacity(0.25), lineWidth: 1)
        )
        .onAppear {
            guard event.isLive, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if event.isLive {
            Circle()
                .fill(Color(hex: "FF3B30"))
                .frame(width: 8, height: 8)
                .scaleEffect(pulsing && !reduceMotion ? 1.4 : 1.0)
                .overlay(
                    Circle()
                        .stroke(Color(hex: "FF3B30").opacity(0.35), lineWidth: 4)
                        .scaleEffect(pulsing && !reduceMotion ? 1.8 : 1.0)
                        .opacity(pulsing && !reduceMotion ? 0.0 : 0.6)
                )
        } else {
            Image(systemName: "clock.fill")
                .foregroundStyle(Color(hex: "D9A441"))
                .font(.caption)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if event.isLive {
            Button(action: onJoinLive) {
                Text("Join Live")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(hex: "FF3B30").opacity(0.85), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Join live event: \(event.title)")
        } else if isRSVPed {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color(hex: "D9A441"))
                .font(.system(size: 18))
                .accessibilityLabel("RSVPed to \(event.title)")
        } else {
            Button(action: onRSVP) {
                Text("RSVP")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(hex: "070607"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(hex: "D9A441"), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("RSVP to \(event.title)")
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        AmenUpcomingLiveChipView(
            event: .preview(isLive: true),
            isRSVPed: false,
            onRSVP: {},
            onJoinLive: {}
        )
        AmenUpcomingLiveChipView(
            event: .preview(isLive: false),
            isRSVPed: false,
            onRSVP: {},
            onJoinLive: {}
        )
        AmenUpcomingLiveChipView(
            event: .preview(isLive: false),
            isRSVPed: true,
            onRSVP: {},
            onJoinLive: {}
        )
    }
    .padding()
    .background(Color(hex: "070607"))
}

private extension AmenSpaceEvent {
    static func preview(isLive: Bool) -> AmenSpaceEvent {
        AmenSpaceEvent(
            id: UUID().uuidString,
            spaceId: "s1",
            hostUserId: "u1",
            title: "Sunday Evening Worship",
            eventDescription: "Join us live.",
            type: .livestream,
            scheduledAt: Date().addingTimeInterval(isLive ? 0 : 1400),
            durationMinutes: 90,
            isRecurring: false,
            recurrenceRule: nil,
            rsvpUserIds: [],
            maxAttendees: nil,
            requiredTierId: nil,
            isLive: isLive,
            liveRoomId: isLive ? "room1" : nil,
            replayRef: nil,
            calendarInviteSentAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
