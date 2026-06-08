// CalendarConsentView.swift — AMEN IntegrationOS
// SwiftUI calendar permission request and upcoming events list.

import SwiftUI
import EventKit

@MainActor
final class CalendarConsentViewModel: ObservableObject {
    @Published var isAuthorized = false
    @Published var upcomingEvents: [EKEvent] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = AmenCalendarService.shared

    func checkAndRequest() async {
        isLoading = true
        do {
            try await service.requestAccess()
            isAuthorized = await service.isAuthorized
            if isAuthorized { await loadEvents() }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadEvents() async {
        let start = Date()
        let end = Date().addingTimeInterval(7 * 86400)
        upcomingEvents = (try? await service.fetchEvents(from: start, to: end)) ?? []
    }
}

struct CalendarConsentView: View {
    @StateObject private var viewModel = CalendarConsentViewModel()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isAuthorized {
                    authorizedContent
                } else {
                    permissionPrompt
                }
            }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.large)
            .task { await viewModel.checkAndRequest() }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var permissionPrompt: some View {
        VStack(spacing: 24) {
            Image(systemName: "calendar.badge.plus")
                .font(.systemScaled(56))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("Calendar Access")
                    .font(.title2.weight(.bold))
                Text("AMEN needs calendar access to add church events and devotionals to your schedule.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button {
                Task { await viewModel.checkAndRequest() }
            } label: {
                Group {
                    if viewModel.isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Allow Calendar Access")
                            .font(.body.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(viewModel.isLoading)
            .padding(.horizontal)
        }
        .padding()
    }

    private var authorizedContent: some View {
        List {
            Section("This Week") {
                if viewModel.upcomingEvents.isEmpty {
                    Text("No upcoming events.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.upcomingEvents, id: \.eventIdentifier) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title ?? "Untitled Event")
                                .font(.subheadline.weight(.medium))
                            Text(event.startDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .refreshable { await viewModel.loadEvents() }
    }
}
