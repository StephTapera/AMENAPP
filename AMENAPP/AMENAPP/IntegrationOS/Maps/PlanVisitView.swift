// PlanVisitView.swift — AMEN IntegrationOS
// SwiftUI plan-a-visit form combining transport and calendar actions.

import SwiftUI
import MapKit

struct PlanVisitView: View {
    let churchName: String
    let mapItem: MKMapItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var visitDate = Date().addingTimeInterval(86400)
    @State private var notes = ""
    @State private var addedToCalendar = false
    @State private var isWorking = false
    @State private var showTransport = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Church") {
                    LabeledContent("Name", value: churchName)
                    LabeledContent("Address", value: mapItem.placemark.thoroughfare ?? "")
                }

                Section("Visit Details") {
                    DatePicker("Visit Date", selection: $visitDate, displayedComponents: [.date, .hourAndMinute])
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Button {
                        Task { await addToCalendar() }
                    } label: {
                        HStack {
                            Label(
                                addedToCalendar ? "Added to Calendar" : "Add to Calendar",
                                systemImage: addedToCalendar ? "checkmark.circle.fill" : "calendar.badge.plus"
                            )
                            Spacer()
                            if isWorking { ProgressView() }
                        }
                    }
                    .disabled(addedToCalendar || isWorking)
                    .foregroundStyle(addedToCalendar ? .green : .accentColor)

                    Button {
                        showTransport = true
                    } label: {
                        Label("Get Directions", systemImage: "car.fill")
                    }
                }

                Section {
                    Button {
                        openInMaps()
                    } label: {
                        Label("Open in Maps", systemImage: "map.fill")
                    }
                }
            }
            .navigationTitle("Plan Your Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showTransport) {
                VisitPlanningView(destination: mapItem, churchName: churchName)
            }
        }
    }

    private func addToCalendar() async {
        isWorking = true
        defer { isWorking = false }
        let calService = AmenCalendarService.shared
        do {
            try await calService.addEvent(
                title: "Visit \(churchName)",
                startDate: visitDate,
                endDate: visitDate.addingTimeInterval(5400),
                notes: notes
            )
            addedToCalendar = true
        } catch {
            // Calendar permission may not be granted yet — surface gracefully.
        }
    }

    private func openInMaps() {
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault
        ])
    }
}
