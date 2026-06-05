// ExternalIntegrationView.swift — AMEN IntegrationOS
// Hub/dashboard view for all external integrations.

import SwiftUI
import FirebaseRemoteConfig

@MainActor
final class ExternalIntegrationViewModel: ObservableObject {
    @Published var categories: [IntegrationCategory] = IntegrationCategory.allCases
    @Published var activeConnectionCount = 0

    private let registry = ProviderRegistry.shared
    private let remoteConfig = RemoteConfig.remoteConfig()

    var isEnabled: Bool {
        remoteConfig.configValue(forKey: "integration_os_enabled").booleanValue
    }

    func refreshCount() {
        activeConnectionCount = registry.adapters.count
    }
}

enum IntegrationCategory: String, CaseIterable, Identifiable {
    var id: String { rawValue }

    case maps        = "Maps & Directions"
    case calendar    = "Calendar"
    case transport   = "Transport & Carpool"
    case media       = "Sermon Media"
    case events      = "Events"
    case contacts    = "Find Friends"
    case health      = "Health & Wellness"
    case knowledge   = "Org Knowledge"
    case messaging   = "Broadcast"
    case career      = "Opportunities"

    var icon: String {
        switch self {
        case .maps:       return "map.fill"
        case .calendar:   return "calendar"
        case .transport:  return "car.fill"
        case .media:      return "play.circle.fill"
        case .events:     return "ticket.fill"
        case .contacts:   return "person.2.fill"
        case .health:     return "heart.fill"
        case .knowledge:  return "building.2.fill"
        case .messaging:  return "megaphone.fill"
        case .career:     return "briefcase.fill"
        }
    }

    var tint: Color {
        switch self {
        case .maps:       return .green
        case .calendar:   return .red
        case .transport:  return .blue
        case .media:      return .orange
        case .events:     return .purple
        case .contacts:   return .teal
        case .health:     return .pink
        case .knowledge:  return .indigo
        case .messaging:  return .yellow
        case .career:     return .brown
        }
    }

    var description: String {
        switch self {
        case .maps:       return "Find churches & get directions"
        case .calendar:   return "Add events to your calendar"
        case .transport:  return "Rideshare & community carpool"
        case .media:      return "Generate sermon study packets"
        case .events:     return "RSVP & discover events"
        case .contacts:   return "Find friends privately"
        case .health:     return "Whole-person wellness"
        case .knowledge:  return "Your org's knowledge base"
        case .messaging:  return "Send announcements & alerts"
        case .career:     return "Ministry & career openings"
        }
    }
}

struct ExternalIntegrationView: View {
    @StateObject private var viewModel = ExternalIntegrationViewModel()
    @Environment(\.colorScheme) private var colorScheme
    @State private var showConnections = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            Group {
                if !viewModel.isEnabled {
                    featureDisabledView
                } else {
                    integrationGrid
                }
            }
            .navigationTitle("Integrations")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showConnections = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                            if viewModel.activeConnectionCount > 0 {
                                Text("\(viewModel.activeConnectionCount)")
                                    .font(.caption.weight(.bold))
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showConnections) {
                ManageConnectionsView()
            }
            .onAppear { viewModel.refreshCount() }
        }
    }

    private var integrationGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(viewModel.categories) { category in
                    NavigationLink(destination: destinationView(for: category)) {
                        IntegrationCategoryTile(category: category)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()

            VStack(spacing: 4) {
                Divider()
                HStack {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text("All integrations are consent-gated and can be revoked at any time.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private func destinationView(for category: IntegrationCategory) -> some View {
        switch category {
        case .maps:       ChurchDiscoveryView()
        case .calendar:   CalendarConsentView()
        case .transport:  Text("Transport").navigationTitle("Transport")
        case .media:      MediaObjectComposerView()
        case .events:     EventsListView()
        case .contacts:   ContactDiscoveryView()
        case .health:     HealthWellnessView()
        case .knowledge:  OrgAssistantView(orgId: "")
        case .messaging:  Text("Messaging").navigationTitle("Messaging")
        case .career:     OpportunityFeedView()
        }
    }

    private var featureDisabledView: some View {
        ContentUnavailableView(
            "Integrations Coming Soon",
            systemImage: "link.badge.plus",
            description: Text("External integrations are being rolled out. Check back soon.")
        )
    }
}

private struct IntegrationCategoryTile: View {
    let category: IntegrationCategory
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(category.tint.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: category.icon)
                        .font(.title3)
                        .foregroundStyle(category.tint)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(category.rawValue)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(category.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(colorScheme == .dark ? Color(.systemGray5) : Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        )
    }
}

// MARK: - Events List Stub (full view in EventDetailView.swift)

private struct EventsListView: View {
    @State private var events: [AmenEvent] = []
    @State private var isLoading = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        List {
            if isLoading {
                ProgressView("Loading events…")
            } else if events.isEmpty {
                ContentUnavailableView("No Events", systemImage: "ticket", description: Text("No upcoming events found."))
            } else {
                ForEach(events) { event in
                    NavigationLink(destination: EventDetailView(event: event)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title).font(.subheadline.weight(.semibold))
                            Text(event.startDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Events")
        .task {
            isLoading = true
            events = (try? await AmenEventService.shared.fetchEvents()) ?? []
            isLoading = false
        }
    }
}
