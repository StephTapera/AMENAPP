// EventDetailView.swift — AMEN IntegrationOS
// SwiftUI event detail with RSVP and attendee list.

import SwiftUI
import MapKit

@MainActor
final class EventDetailViewModel: ObservableObject {
    @Published var event: AmenEvent
    @Published var myRSVP: EventRSVP?
    @Published var attendees: [EventAttendee] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = AmenEventService.shared

    init(event: AmenEvent) {
        self.event = event
    }

    func load() async {
        isLoading = true
        async let rsvpTask = service.myRSVP(eventId: event.id)
        async let attendeesTask = (try? await service.fetchAttendees(eventId: event.id)) ?? []
        let (r, a) = await (rsvpTask, attendeesTask)
        myRSVP = r
        attendees = a
        isLoading = false
    }

    func rsvp(status: RSVPStatus) async {
        do {
            try await service.rsvp(eventId: event.id, status: status)
            myRSVP = EventRSVP(eventId: event.id, userId: "", status: status, respondedAt: Date(), notes: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct EventDetailView: View {
    @StateObject private var viewModel: EventDetailViewModel
    @Environment(\.colorScheme) private var colorScheme

    init(event: AmenEvent) {
        _viewModel = StateObject(wrappedValue: EventDetailViewModel(event: event))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let coverURL = viewModel.event.coverImageURL, let url = URL(string: coverURL) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Color.accentColor.opacity(0.2))
                    }
                    .frame(height: 200)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.event.title)
                        .font(.title2.weight(.bold))

                    Label(
                        "\(viewModel.event.startDate.formatted(date: .abbreviated, time: .shortened)) – \(viewModel.event.endDate.formatted(time: .shortened))",
                        systemImage: "calendar"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    if let loc = viewModel.event.location {
                        Label(loc.isVirtual ? "Virtual · \(loc.name)" : loc.name, systemImage: "location")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Label("Hosted by \(viewModel.event.hostName)", systemImage: "person.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                rsvpSection

                if let desc = viewModel.event.description {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("About").font(.headline)
                        Text(desc).font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                if !viewModel.attendees.isEmpty {
                    attendeesSection
                }
            }
            .padding()
        }
        .navigationTitle("Event")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: { Text(viewModel.errorMessage ?? "") }
    }

    private var rsvpSection: some View {
        VStack(spacing: 10) {
            if let rsvp = viewModel.myRSVP {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("You responded: \(rsvp.status.rawValue.capitalized)")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                }
            }

            HStack(spacing: 12) {
                ForEach([RSVPStatus.going, .interested, .notGoing], id: \.self) { status in
                    Button {
                        Task { await viewModel.rsvp(status: status) }
                    } label: {
                        Text(status.rawValue.capitalized)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(viewModel.myRSVP?.status == status ? Color.accentColor : Color(.systemGray5))
                            .foregroundStyle(viewModel.myRSVP?.status == status ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(colorScheme == .dark ? Color(.systemGray5) : Color(.systemGray6)))
    }

    private var attendeesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attendees (\(viewModel.attendees.count))")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.attendees.prefix(10)) { attendee in
                        VStack(spacing: 4) {
                            Circle()
                                .fill(Color.accentColor.opacity(0.3))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Text(String(attendee.displayName.prefix(1)))
                                        .font(.headline)
                                        .foregroundStyle(.accentColor)
                                )
                            Text(attendee.displayName.components(separatedBy: " ").first ?? "")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }
}
