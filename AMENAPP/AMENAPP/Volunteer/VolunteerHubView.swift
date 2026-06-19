//  VolunteerHubView.swift
//  AMEN — Smart Volunteer Board · Wave 0 entry surface.
//
//  Lists the events the user leads or is serving, opens each event's Smart Volunteer Board,
//  and (for leaders) creates an event + declares staffing needs. Entirely flag-gated:
//  when volunteer_scheduling_enabled is OFF (default) this renders a disabled notice and the
//  Connect-hub entry point never appears.

import SwiftUI

struct VolunteerHubView: View {
    let currentUserId: String

    @StateObject private var service = VolunteerBoardService.shared
    @ObservedObject private var flags = VolunteerFlagService.shared

    @State private var events: [VolunteerEventRef] = []
    @State private var isLoading = true
    @State private var showCreate = false

    var body: some View {
        NavigationStack {
            Group {
                if !flags.isEnabled(.scheduling) {
                    ContentUnavailableCompat(
                        title: "Volunteer scheduling is off",
                        message: "This surface turns on once your church enables it.")
                } else {
                    list
                }
            }
            .navigationTitle("Volunteer")
            .toolbar {
                if flags.isEnabled(.scheduling) {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showCreate = true } label: { Image(systemName: "plus") }
                            .accessibilityLabel("Create a volunteer event")
                    }
                }
            }
            .sheet(isPresented: $showCreate, onDismiss: { Task { await reload() } }) {
                CreateEventSheet(service: service)
            }
            .task { await reload() }
        }
    }

    private var list: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if events.isEmpty {
                ContentUnavailableCompat(
                    title: "No events yet",
                    message: "Create an event, then add the roles you need filled.")
            } else {
                List(events) { ref in
                    NavigationLink {
                        SmartVolunteerBoardView(
                            event: ref.event,
                            volunteerId: currentUserId,
                            isLeader: ref.isLeader)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ref.event.title).font(.headline)
                            Text(ref.event.location).font(.subheadline).foregroundStyle(.secondary)
                            if ref.isLeader {
                                Text("You lead this").font(.caption).foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
        }
    }

    private func reload() async {
        guard flags.isEnabled(.scheduling) else { isLoading = false; return }
        isLoading = true
        events = await service.listMyEvents()
        isLoading = false
    }
}

// MARK: - Create event (leader) + first staffing need

private struct CreateEventSheet: View {
    let service: VolunteerBoardService
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var location = ""
    @State private var startUTC = ""        // ISO8601, e.g. 2026-06-28T16:00:00Z
    @State private var timezone = "America/New_York"
    @State private var firstRole = ""
    @State private var firstCount = 2
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField("Title", text: $title)
                    TextField("Location", text: $location)
                    TextField("Start (ISO8601 UTC, e.g. 2026-06-28T16:00:00Z)", text: $startUTC)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Timezone (IANA)", text: $timezone)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section("First role (optional)") {
                    TextField("Role, e.g. Greeter", text: $firstRole)
                    Stepper("Needed: \(firstCount)", value: $firstCount, in: 1...100)
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            .navigationTitle("New event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                        .disabled(working || title.isEmpty || startUTC.isEmpty || location.isEmpty)
                }
            }
        }
    }

    private func create() async {
        working = true
        defer { working = false }
        guard let event = await service.createEvent(
            title: title, startUTC: startUTC, timezone: timezone, location: location) else {
            error = "Couldn't create the event. Check the start time format."
            return
        }
        if !firstRole.isEmpty {
            _ = await service.addNeed(eventId: event.id, role: firstRole, countNeeded: firstCount)
        }
        dismiss()
    }
}

// MARK: - Back-compat empty state (avoids hard dependency on ContentUnavailableView availability)

private struct ContentUnavailableCompat: View {
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
