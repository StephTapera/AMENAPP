// EventCard.swift
// AMEN — Creator Profiles (ministry hubs) — Wave 3
//
// One CreatorHubEvent rendered as a translucent glass card: date/time formatted in
// the event's own time zone, a type label, location (geo.locationName), and a status
// pill. The actions row supports RSVP (server-driven via CreatorHubService.rsvp), a
// smart "Leave by HH:mm" reminder when one is returned, Add-to-Calendar (emits a
// CreatorHubCalendarPayload to the parent), Register/Ticket (opens the URL), Map (opens
// the geo coordinate), and Share.
//
// Conventions: black primary text; ONE glass card (flat children — no glass-on-glass);
// AmenTheme.Colors.* + Color(hex:) tokens; Dynamic Type; VoiceOver labels on every
// control + .accessibilityElement(children: .combine) on the metadata block.

import SwiftUI

struct EventCard: View {
    let creatorId: String
    let event: CreatorHubEvent

    /// Add-to-Calendar — emits the server-built calendar payload up to the host
    /// (which performs the EventKit-style intent).
    var onAddToCalendar: (CreatorHubCalendarPayload) -> Void = { _ in }
    /// Share this event.
    var onShare: (CreatorHubEvent) -> Void = { _ in }

    @Environment(\.openURL) private var openURL

    @State private var isGoing = false
    @State private var rsvpInFlight = false
    @State private var rsvpResult: CreatorHubRsvpResult?
    @State private var rsvpError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            metadata
            if let leaveBy = leaveByLabel {
                leaveByPill(leaveBy)
            }
            if let rsvpError {
                Text(rsvpError)
                    .font(.caption)
                    .foregroundStyle(AmenTheme.Colors.statusError)
            }
            actionsRow
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .amenGlassCard(cornerRadius: 18)
    }

    // MARK: - Header (title + status pill)

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(event.title)
                .font(.headline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            statusPill
        }
    }

    private var statusPill: some View {
        let (label, tint) = statusStyle
        return Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint))
            .accessibilityLabel("Status: \(label)")
    }

    private var statusStyle: (String, Color) {
        switch event.status {
        case .draft:     return ("Draft", AmenTheme.Colors.textTertiary)
        case .scheduled: return ("Upcoming", AmenTheme.Colors.amenGoldText)
        case .live:      return ("Live", Color(hex: "E0394B"))
        case .ended:     return ("Ended", AmenTheme.Colors.textTertiary)
        case .canceled:  return ("Canceled", AmenTheme.Colors.statusError)
        }
    }

    // MARK: - Metadata (type / date-time / location)

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(event.type.displayLabel, systemImage: "tag")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AmenTheme.Colors.textSecondary)

            Label(formattedDateTime, systemImage: "calendar")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)

            if let name = event.geo?.locationName, !name.isEmpty {
                Label(name, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
        }
        .labelStyle(.titleAndIcon)
        .accessibilityElement(children: .combine)
    }

    private var formattedDateTime: String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: event.timeZone) ?? .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let start = formatter.string(from: event.startsAt)
        if let endsAt = event.endsAt {
            let timeOnly = DateFormatter()
            timeOnly.timeZone = TimeZone(identifier: event.timeZone) ?? .current
            timeOnly.dateStyle = .none
            timeOnly.timeStyle = .short
            return "\(start) – \(timeOnly.string(from: endsAt))"
        }
        return start
    }

    // MARK: - Leave-by smart reminder

    private var leaveByLabel: String? {
        guard let iso = rsvpResult?.reminder.leaveByISO else { return nil }
        guard let date = ISO8601DateFormatter().date(from: iso) else { return nil }
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: event.timeZone) ?? .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func leaveByPill(_ time: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "figure.walk")
                .imageScale(.small)
            Text("Leave by \(time)")
                .font(.caption.weight(.semibold))
            if let travel = rsvpResult?.reminder.travelMinutes {
                Text("· \(travel) min travel")
                    .font(.caption)
            }
        }
        .foregroundStyle(AmenTheme.Colors.statusInfo)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(AmenTheme.Colors.surfaceChip))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Smart reminder: leave by \(time)")
    }

    // MARK: - Actions row

    private var actionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                rsvpButton

                if rsvpResult != nil {
                    actionChip(title: "Add to Calendar", icon: "calendar.badge.plus") {
                        if let calendar = rsvpResult?.calendar {
                            onAddToCalendar(calendar)
                        }
                    }
                }

                if let reg = event.registrationUrl, let url = URL(string: reg) {
                    actionChip(title: "Register", icon: "person.badge.plus") { openURL(url) }
                }

                if let ticket = event.ticketing, ticket.isTicketed,
                   let urlString = ticket.url, let url = URL(string: urlString) {
                    actionChip(title: ticketLabel(ticket), icon: "ticket") { openURL(url) }
                }

                if event.geo != nil {
                    actionChip(title: "Map", icon: "map") { openMap() }
                }

                actionChip(title: "Share", icon: "square.and.arrow.up") { onShare(event) }
            }
        }
    }

    private var rsvpButton: some View {
        Button {
            Task { await toggleRsvp() }
        } label: {
            HStack(spacing: 6) {
                if rsvpInFlight {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: isGoing ? "checkmark.circle.fill" : "calendar.badge.checkmark")
                        .imageScale(.small)
                }
                Text(isGoing ? "Going" : "RSVP")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isGoing ? AmenTheme.Colors.buttonPrimaryText : AmenTheme.Colors.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(isGoing ? AmenTheme.Colors.buttonPrimary : AmenTheme.Colors.surfaceChip)
            )
        }
        .buttonStyle(.plain)
        .disabled(rsvpInFlight)
        .accessibilityLabel(isGoing ? "Going. Tap to cancel RSVP" : "RSVP to this event")
    }

    private func actionChip(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .imageScale(.small)
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(AmenTheme.Colors.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(AmenTheme.Colors.surfaceChip))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func ticketLabel(_ ticketing: CreatorHubTicketing) -> String {
        guard let cents = ticketing.priceCents, cents > 0 else { return "Tickets" }
        let amount = Double(cents) / 100
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = ticketing.currency ?? "USD"
        return formatter.string(from: NSNumber(value: amount)).map { "Tickets · \($0)" } ?? "Tickets"
    }

    // MARK: - Behavior

    private func toggleRsvp() async {
        let next = !isGoing
        rsvpInFlight = true
        rsvpError = nil
        defer { rsvpInFlight = false }
        do {
            let result = try await CreatorHubService.shared.rsvp(
                creatorId: creatorId,
                eventId: event.id,
                going: next
            )
            isGoing = next
            rsvpResult = next ? result : nil
        } catch {
            rsvpError = "Couldn't update your RSVP. Please try again."
        }
    }

    private func openMap() {
        guard let geo = event.geo else { return }
        let query = geo.locationName?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        var urlString = "http://maps.apple.com/?ll=\(geo.latitude),\(geo.longitude)"
        if let query, !query.isEmpty {
            urlString += "&q=\(query)"
        }
        if let url = URL(string: urlString) {
            openURL(url)
        }
    }
}
