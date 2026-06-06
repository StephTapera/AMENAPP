// ChurchDiscoveryView.swift — AMEN IntegrationOS
// SwiftUI map view with church pins and bottom sheet list.

import SwiftUI
import MapKit
import CoreLocation

@MainActor
final class ChurchDiscoveryViewModel: ObservableObject {
    @Published var churches: [ChurchDiscoveryService.ChurchResult] = []
    @Published var selectedChurch: ChurchDiscoveryService.ChurchResult?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.3318, longitude: -122.0312),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )

    private let service = ChurchDiscoveryService.shared
    private let locationManager = CLLocationManager()

    func loadNearby() async {
        isLoading = true
        errorMessage = nil
        do {
            let center = region.center
            churches = try await service.searchNearby(coordinate: center)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct ChurchDiscoveryView: View {
    @StateObject private var viewModel = ChurchDiscoveryViewModel()
    @Environment(\.colorScheme) private var colorScheme
    @State private var showPlanVisit = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(initialPosition: .region(viewModel.region)) {
                    ForEach(viewModel.churches) { church in
                        Annotation(church.name, coordinate: church.coordinate) {
                            churchPin(for: church)
                        }
                    }
                }
                .ignoresSafeArea(edges: .top)

                if viewModel.isLoading {
                    ProgressView("Finding churches nearby...")
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if let church = viewModel.selectedChurch {
                    ChurchDetailCard(church: church) {
                        showPlanVisit = true
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding()
                }
            }
            .navigationTitle("Find a Church")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.loadNearby() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task { await viewModel.loadNearby() }
            .sheet(isPresented: $showPlanVisit) {
                if let church = viewModel.selectedChurch {
                    PlanVisitView(churchName: church.name, mapItem: church.mapItem)
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private func churchPin(for church: ChurchDiscoveryService.ChurchResult) -> some View {
        IntegrationChurchMapPin(church: church, isSelected: viewModel.selectedChurch?.id == church.id)
            .onTapGesture {
                withAnimation(.spring(response: 0.35)) {
                    viewModel.selectedChurch = church
                }
            }
    }
}

private struct IntegrationChurchMapPin: View {
    let church: ChurchDiscoveryService.ChurchResult
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.accentColor : Color(.systemBackground))
                    .frame(width: isSelected ? 40 : 32, height: isSelected ? 40 : 32)
                    .shadow(radius: isSelected ? 6 : 3)
                Image(systemName: "building.columns.fill")
                    .font(.system(size: isSelected ? 18 : 14))
                    .foregroundStyle(isSelected ? .white : .accentColor)
            }
            if isSelected {
                Triangle()
                    .fill(Color.accentColor)
                    .frame(width: 12, height: 6)
            }
        }
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private struct ChurchDetailCard: View {
    let church: ChurchDiscoveryService.ChurchResult
    let onPlanVisit: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(church.name)
                        .font(.headline)
                    Text(church.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onPlanVisit) {
                    Text("Plan Visit")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
