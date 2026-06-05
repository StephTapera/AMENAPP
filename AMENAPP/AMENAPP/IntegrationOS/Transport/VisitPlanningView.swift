// VisitPlanningView.swift — AMEN IntegrationOS
// SwiftUI visit planner combining transport options + carpool with maps.

import SwiftUI
import MapKit

struct VisitPlanningView: View {
    let destination: MKMapItem
    let churchName: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedProvider: TransportProvider = .appleMaps
    @State private var showCarpoolForm = false
    @State private var carpoolRequests: [CarpoolRequest] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            List {
                Section("Get There") {
                    ForEach(TransportProvider.allCases, id: \.self) { provider in
                        Button {
                            Task { await TransportCoordinatorService.shared.openRideshare(provider: provider, destination: destination) }
                        } label: {
                            HStack {
                                Label(provider.displayName, systemImage: transportIcon(provider))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }

                Section("Community Carpool") {
                    if isLoading {
                        ProgressView("Loading carpools...")
                    } else if carpoolRequests.isEmpty {
                        Text("No open carpools yet for this church.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(carpoolRequests) { request in
                            CarpoolRow(request: request)
                        }
                    }

                    Button {
                        showCarpoolForm = true
                    } label: {
                        Label("Offer or Request a Carpool", systemImage: "car.2.fill")
                    }
                }
            }
            .navigationTitle("Get to \(churchName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await loadCarpools() }
            .sheet(isPresented: $showCarpoolForm) {
                CarpoolFormSheet(churchId: destination.identifier?.rawValue ?? "unknown")
            }
        }
    }

    private func loadCarpools() async {
        isLoading = true
        carpoolRequests = (try? await TransportCoordinatorService.shared.fetchCarpoolRequests(
            for: destination.identifier?.rawValue ?? ""
        )) ?? []
        isLoading = false
    }

    private func transportIcon(_ provider: TransportProvider) -> String {
        switch provider {
        case .uber: return "car.fill"
        case .lyft: return "car.2.fill"
        case .appleMaps: return "map.fill"
        }
    }
}

private struct CarpoolRow: View {
    let request: CarpoolRequest
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(request.departureTime.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline.weight(.medium))
            HStack {
                Label("\(request.seats) seat\(request.seats == 1 ? "" : "s")", systemImage: "person.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let notes = request.notes, !notes.isEmpty {
                    Text("· \(notes)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct CarpoolFormSheet: View {
    let churchId: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var departureTime = Date().addingTimeInterval(86400)
    @State private var seats = 2
    @State private var notes = ""
    @State private var isPosting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Departure") {
                    DatePicker("Time", selection: $departureTime, displayedComponents: [.date, .hourAndMinute])
                    Stepper("Seats: \(seats)", value: $seats, in: 1...7)
                    TextField("Notes", text: $notes)
                }
            }
            .navigationTitle("Post Carpool")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Post") {
                        Task {
                            isPosting = true
                            try? await TransportCoordinatorService.shared.postCarpoolRequest(
                                churchId: churchId,
                                departureCoordinate: GeoPoint(latitude: 0, longitude: 0),
                                departureTime: departureTime,
                                seats: seats,
                                notes: notes.isEmpty ? nil : notes
                            )
                            isPosting = false
                            dismiss()
                        }
                    }
                    .disabled(isPosting)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
