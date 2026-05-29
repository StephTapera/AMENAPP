import SwiftUI
import MapKit

// MARK: - Map Provider

enum ChurchMapProvider: String, CaseIterable {
    case apple   = "Apple Maps"
    case google  = "Google Maps"

    var icon: String {
        switch self {
        case .apple:  return "map.fill"
        case .google: return "globe"
        }
    }
}

// MARK: - Dual-Provider Map View

/// Shows either the native MapKit map or Google Maps depending on `provider`.
/// Google Maps requires the `GoogleMaps` SDK added via Xcode → Package Dependencies:
///   URL: https://github.com/googlemaps/ios-maps-sdk
/// and a key set in Info.plist under `AMEN_GOOGLE_MAPS_API_KEY`.
/// When the SDK is not present this view renders the Apple Maps fallback automatically.
struct ChurchDualMapView: View {
    let results: [SmartChurchSearchItem]
    @Binding var provider: ChurchMapProvider
    @Binding var selectedResult: SmartChurchSearchItem?
    @Binding var camera: MapCameraPosition
    var onOpen: (SmartChurchSearchItem) -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            mapContent
            if let selected = selectedResult {
                Button { onOpen(selected) } label: {
                    ChurchResultCard(result: selected)
                        .padding(12)
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var mapContent: some View {
#if canImport(GoogleMaps)
        switch provider {
        case .apple:
            appleMapView
        case .google:
            ChurchGMSMapView(results: results, selectedResult: $selectedResult)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
#else
        appleMapView
#endif
    }

    private var appleMapView: some View {
        Map(position: $camera, selection: $selectedResult) {
            ForEach(results) { result in
                Marker(result.church.name,
                       systemImage: "building.columns.fill",
                       coordinate: result.church.coordinate)
                    .tag(result)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// MARK: - Google Maps UIViewRepresentable (compiled only when SDK is present)

#if canImport(GoogleMaps)
import GoogleMaps

struct ChurchGMSMapView: UIViewRepresentable {
    let results: [SmartChurchSearchItem]
    @Binding var selectedResult: SmartChurchSearchItem?

    func makeUIView(context: Context) -> GMSMapView {
        let camera = GMSCameraPosition.camera(
            withLatitude: results.first?.church.coordinate.latitude ?? 37.3318,
            longitude: results.first?.church.coordinate.longitude ?? -122.0312,
            zoom: 12
        )
        let mapView = GMSMapView(frame: .zero, camera: camera)
        mapView.settings.compassButton = true
        mapView.settings.myLocationButton = true
        mapView.isMyLocationEnabled = true
        mapView.delegate = context.coordinator
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        mapView.clear()
        for result in results {
            let marker = GMSMarker()
            marker.position = CLLocationCoordinate2D(
                latitude: result.church.coordinate.latitude,
                longitude: result.church.coordinate.longitude
            )
            marker.title = result.church.name
            marker.snippet = result.matchReason
            marker.userData = result
            marker.icon = GMSMarker.markerImage(with: UIColor(AmenTheme.Colors.amenGold))
            marker.map = mapView
        }

        // Fit camera to show all markers
        if !results.isEmpty {
            var bounds = GMSCoordinateBounds()
            for result in results {
                bounds = bounds.includingCoordinate(result.church.coordinate)
            }
            let update = GMSCameraUpdate.fit(bounds, withPadding: 60)
            mapView.animate(with: update)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: ChurchGMSMapView

        init(_ parent: ChurchGMSMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            if let result = marker.userData as? SmartChurchSearchItem {
                parent.selectedResult = result
            }
            return true
        }
    }
}
#endif

// MARK: - Directions Action Menu

/// A button that opens an action sheet offering both Apple Maps and Google Maps directions.
struct ChurchDirectionsButton: View {
    let church: SmartChurchSummary
    @State private var showPicker = false

    var body: some View {
        Button {
            showPicker = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.caption2)
                Text("Directions")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(AmenTheme.Colors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AmenTheme.Colors.surfaceChip, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Get directions to \(church.name)")
        .confirmationDialog("Open directions in…", isPresented: $showPicker, titleVisibility: .visible) {
            Button("Apple Maps") { openAppleMaps() }
            Button("Google Maps") { openGoogleMaps() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func openAppleMaps() {
        let encoded = church.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "maps://?daddr=\(encoded)") {
            UIApplication.shared.open(url)
        }
    }

    private func openGoogleMaps() {
        let encoded = church.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        // Try Google Maps app first; fall back to web if not installed
        if let appURL = URL(string: "comgooglemaps://?daddr=\(encoded)&directionsmode=driving"),
           UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
        } else if let webURL = URL(string: "https://maps.google.com/?daddr=\(encoded)") {
            UIApplication.shared.open(webURL)
        }
    }
}

// MARK: - Map Provider Picker Pill

struct MapProviderPicker: View {
    @Binding var provider: ChurchMapProvider

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ChurchMapProvider.allCases, id: \.self) { p in
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        provider = p
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: p.icon)
                            .font(.caption2)
                        Text(p.rawValue)
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        provider == p ? AmenTheme.Colors.accentPrimary : Color.clear,
                        in: Capsule()
                    )
                    .foregroundStyle(provider == p ? Color.white : AmenTheme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(AmenTheme.Colors.glassStroke, lineWidth: 1))
    }
}
