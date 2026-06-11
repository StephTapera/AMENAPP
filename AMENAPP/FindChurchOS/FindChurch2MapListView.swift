// FindChurch2MapListView.swift
// AMENAPP — Find Church 2.0, Wave 6 UI Refresh
//
// Mode toggle (List / Map / Saved / Visited) + content switcher.
//
// Design rules enforced:
//   - Segmented glass toggle — no glass-on-glass (toggle sits ABOVE content area)
//   - Selected segment: solid purple tint (no glass blur needed — clearly selected state)
//   - Unselected segment: .ultraThinMaterial, reduceTransparency → Color(.secondarySystemBackground)
//   - Luminous border: Color.white.opacity(0.45) strokeBorder 0.5pt
//   - reduceMotion guard on all transitions
//   - Bottom safe area: .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 80) }
//   - Flag gate: findChurch2_mapHybrid — if false, only .list shown in the toggle

import SwiftUI
import MapKit
import CoreLocation

// MARK: - FindChurch2MapListToggle

struct FindChurch2MapListToggle: View {

    // MARK: ViewMode

    enum ViewMode: String, CaseIterable, Identifiable {
        case list    = "List"
        case map     = "Map"
        case saved   = "Saved"
        case visited = "Visited"

        var id: String { rawValue }

        var iconName: String {
            switch self {
            case .list:    return "list.bullet"
            case .map:     return "map"
            case .saved:   return "bookmark.fill"
            case .visited: return "checkmark.seal.fill"
            }
        }
    }

    @Binding var mode: ViewMode

    // Feature flag: when false only .list is shown
    var mapHybridEnabled: Bool = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private static let selectedPurple = Color(red: 0.50, green: 0.22, blue: 0.88)

    private var visibleModes: [ViewMode] {
        mapHybridEnabled
            ? ViewMode.allCases
            : [.list]
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(visibleModes) { viewMode in
                    segmentButton(for: viewMode)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("View mode selector")
    }

    // MARK: Segment button

    @ViewBuilder
    private func segmentButton(for viewMode: ViewMode) -> some View {
        let isSelected = mode == viewMode

        Button {
            guard mode != viewMode else { return }
            if reduceMotion {
                mode = viewMode
            } else {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.80)) {
                    mode = viewMode
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: viewMode.iconName)
                    .font(.system(.caption).weight(.semibold))
                    .accessibilityHidden(true)
                Text(viewMode.rawValue)
                    .font(.system(.subheadline).weight(.semibold))
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(minHeight: 44)
            .background(segmentBackground(isSelected: isSelected))
            .overlay(segmentBorder)
            .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewMode.rawValue)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.10)
                : .spring(response: 0.26, dampingFraction: 0.80),
            value: isSelected
        )
    }

    @ViewBuilder
    private func segmentBackground(isSelected: Bool) -> some View {
        if isSelected {
            Capsule(style: .continuous)
                .fill(Self.selectedPurple)
        } else if reduceTransparency {
            Capsule(style: .continuous)
                .fill(Color(.secondarySystemBackground))
        } else {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
        }
    }

    private var segmentBorder: some View {
        Capsule(style: .continuous)
            .strokeBorder(
                Color.white.opacity(contrast == .increased ? 0.55 : 0.45),
                lineWidth: 0.5
            )
    }
}

// MARK: - FindChurch2MapListView

struct FindChurch2MapListView: View {
    @Binding var mode: FindChurch2MapListToggle.ViewMode
    let churches: [ChurchObject]
    var userLocation: CLLocationCoordinate2D?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch mode {
            case .list:
                listContent
                    .transition(contentTransition)
            case .map:
                mapContent
                    .transition(contentTransition)
            case .saved:
                savedContent
                    .transition(contentTransition)
            case .visited:
                visitedContent
                    .transition(contentTransition)
            }
        }
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .easeInOut(duration: 0.22),
            value: mode
        )
    }

    // MARK: Transitions

    private var contentTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .move(edge: .trailing))
    }

    // MARK: List

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(churches) { church in
                    FindChurch2SmartListRow(church: church, userLocation: userLocation)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 80)
        }
    }

    // MARK: Map

    private var mapContent: some View {
        FindChurch2MapRepresentable(churches: churches, userLocation: userLocation)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 80)
            }
            .ignoresSafeArea(edges: .bottom)
    }

    // MARK: Saved

    private var savedContent: some View {
        let savedChurches = churches.filter { $0.amenMemberCount > 0 }
        return Group {
            if savedChurches.isEmpty {
                emptyState(
                    icon: "bookmark",
                    title: "No saved churches",
                    message: "Churches you save will appear here."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(savedChurches) { church in
                            FindChurch2SmartListRow(church: church, userLocation: userLocation)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 80)
                }
            }
        }
    }

    // MARK: Visited

    private var visitedContent: some View {
        emptyState(
            icon: "checkmark.seal",
            title: "No visited churches yet",
            message: "Churches you've visited will appear here."
        )
    }

    // MARK: Empty state helper

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(.headline))
                .foregroundStyle(.primary)
            Text(message)
                .font(.system(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 80)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message)")
    }
}

// MARK: - FindChurch2SmartListRow (placeholder card)

/// Lightweight placeholder row. Replace with FindChurch2SmartChurchCard when wiring
/// the full card into this container.
private struct FindChurch2SmartListRow: View {
    let church: ChurchObject
    var userLocation: CLLocationCoordinate2D?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var distanceText: String? {
        guard let userLocation else { return nil }
        let userCL = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
        let miles = church.coordinate.distance(from: userCL)
        return String(format: "%.1f mi", miles)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(church.name)
                        .font(.system(.headline))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(church.city + (church.state.map { ", \($0)" } ?? ""))
                        .font(.system(.subheadline))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let distance = distanceText {
                    Text(distance)
                        .font(.system(.caption).weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            // Availability pills (gated — only show when cache is present)
            if let avail = church.availabilityCache {
                FindChurch2AvailabilityPillRow(status: avail)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .overlay(rowBorder)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel)
    }

    @ViewBuilder
    private var rowBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
        }
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(
                Color.white.opacity(contrast == .increased ? 0.55 : 0.45),
                lineWidth: 0.5
            )
    }

    private var rowAccessibilityLabel: String {
        var parts = [church.name]
        let cityState = church.city + (church.state.map { ", \($0)" } ?? "")
        if !cityState.isEmpty { parts.append(cityState) }
        if let distance = distanceText { parts.append(distance) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - FindChurch2MapRepresentable

/// Minimal MapKit wrapper. Renders pins for each ChurchObject.
/// Callout uses a small title-only accessory — full card callout can be added in a later wave.
struct FindChurch2MapRepresentable: UIViewRepresentable {
    let churches: [ChurchObject]
    var userLocation: CLLocationCoordinate2D?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = userLocation != nil
        mapView.mapType = .standard
        mapView.pointOfInterestFilter = .excludingAll

        // Center on user or first church if available
        if let loc = userLocation {
            let region = MKCoordinateRegion(
                center: loc,
                latitudinalMeters: 16_000,
                longitudinalMeters: 16_000
            )
            mapView.setRegion(region, animated: false)
        } else if let first = churches.first {
            let center = CLLocationCoordinate2D(
                latitude: first.coordinate.latitude,
                longitude: first.coordinate.longitude
            )
            let region = MKCoordinateRegion(
                center: center,
                latitudinalMeters: 16_000,
                longitudinalMeters: 16_000
            )
            mapView.setRegion(region, animated: false)
        }

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Remove stale annotations (keep MKUserLocation)
        let existing = mapView.annotations.filter { !($0 is MKUserLocation) }
        mapView.removeAnnotations(existing)

        // Add fresh annotations
        let annotations = churches.map { church -> FindChurch2Annotation in
            let ann = FindChurch2Annotation()
            ann.title = church.name
            ann.subtitle = church.city + (church.state.map { ", \($0)" } ?? "")
            ann.churchId = church.id
            ann.coordinate = CLLocationCoordinate2D(
                latitude: church.coordinate.latitude,
                longitude: church.coordinate.longitude
            )
            return ann
        }
        mapView.addAnnotations(annotations)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: Annotation model

    final class FindChurch2Annotation: NSObject, MKAnnotation {
        @objc dynamic var coordinate: CLLocationCoordinate2D = .init()
        var title: String?
        var subtitle: String?
        var churchId: String?
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        private static let reuseID = "FindChurch2Pin"

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }

            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: Self.reuseID
            ) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: Self.reuseID)

            view.annotation = annotation
            view.markerTintColor = UIColor(red: 0.50, green: 0.22, blue: 0.88, alpha: 1)
            view.glyphImage = UIImage(systemName: "cross.fill")
            view.canShowCallout = true

            // Small detail callout — church name is in title, city/state in subtitle
            // Full card callout deferred to a later wave
            view.rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
            return view
        }
    }
}

// MARK: - Preview

#if DEBUG
private let previewChurches: [ChurchObject] = []

#Preview("Toggle — mapHybrid enabled") {
    @Previewable @State var mode: FindChurch2MapListToggle.ViewMode = .list
    VStack {
        FindChurch2MapListToggle(mode: $mode, mapHybridEnabled: true)
        Text("Selected: \(mode.rawValue)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .padding()
}

#Preview("Toggle — mapHybrid disabled (list only)") {
    @Previewable @State var mode: FindChurch2MapListToggle.ViewMode = .list
    FindChurch2MapListToggle(mode: $mode, mapHybridEnabled: false)
        .padding()
}

#Preview("MapListView — empty visited") {
    @Previewable @State var mode: FindChurch2MapListToggle.ViewMode = .visited
    FindChurch2MapListView(mode: $mode, churches: [], userLocation: nil)
}
#endif
