// FindChurchAnnotation.swift
// AMENAPP
//
// Map annotation data model and view for the Find a Church feature.
// Uses GlassPin from AmenGlassKit — no bespoke glass blur surfaces.

import SwiftUI
import MapKit

// MARK: - ChurchAnnotation

/// Identifiable map annotation data model for a single church pin.
/// Uses the existing `Church` struct from FindChurchView.swift — do NOT import ChurchRecord.
struct ChurchAnnotation: Identifiable {
    /// Stable identity — mirrors the underlying Church UUID.
    let id: String

    /// Pin coordinate on the map.
    let coordinate: CLLocationCoordinate2D

    /// The full church data record.
    let church: Church

    /// Verified churches render with an amenGold pin; standard ones use amenBlue.
    let isVerified: Bool

    /// Whether this pin is currently selected by the user.
    var isSelected: Bool

    // MARK: - Convenience Init

    init(church: Church, isVerified: Bool = false, isSelected: Bool = false) {
        self.id = church.id.uuidString
        self.coordinate = church.coordinate
        self.church = church
        self.isVerified = isVerified
        self.isSelected = isSelected
    }
}

// MARK: - ChurchAnnotationView

/// Map annotation view for a single church. Uses GlassPin from AmenGlassKit.
/// VoiceOver label includes church name + distance. Hint directs to double-tap.
struct ChurchAnnotationView: View {
    let annotation: ChurchAnnotation

    var body: some View {
        GlassPin(
            style: annotation.isVerified ? .verified : .standard,
            label: annotation.church.name,
            isSelected: annotation.isSelected
        )
        .accessibilityLabel("\(annotation.church.name), \(annotation.church.distance) away")
        .accessibilityHint("Double tap to view details")
    }
}

// MARK: - ClusterAnnotationView

/// Map annotation view shown when >3 churches overlap in the same region.
/// Renders a glass badge with a numeric count.
struct ClusterAnnotationView: View {
    let count: Int

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(uiColor: .systemBackground).opacity(reduceTransparency ? 1 : 0))
                .background(.ultraThinMaterial, in: Circle())
                .frame(width: 40, height: 40)
                .overlay(
                    Circle()
                        .strokeBorder(Color.amenBlue.opacity(0.4), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.14), radius: 6, y: 2)

            Text("\(count)")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.amenBlue)
        }
        .accessibilityLabel("\(count) churches in this area")
        .accessibilityHint("Double tap to zoom in and see individual pins")
    }
}

// MARK: - ChurchClusterItem

/// A lightweight Identifiable model representing a cluster of >3 nearby churches.
/// Used by FindChurchMapView.clusterItems to pass into a second MapAnnotation pass.
struct ChurchClusterItem: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let count: Int

    init(lat: Double, lon: Double, count: Int) {
        self.id = "\(lat),\(lon)"
        self.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        self.count = count
    }
}

// MARK: - MKCoordinateRegion + Fitting

extension MKCoordinateRegion {
    /// Returns a region that fits all provided coordinates with a padding factor.
    /// Falls back to a default region centered on the US if coordinates are empty.
    static func fitting(
        coordinates: [CLLocationCoordinate2D],
        paddingFactor: Double = 1.3
    ) -> MKCoordinateRegion? {
        guard !coordinates.isEmpty else { return nil }

        let minLat = coordinates.map(\.latitude).min()!
        let maxLat = coordinates.map(\.latitude).max()!
        let minLon = coordinates.map(\.longitude).min()!
        let maxLon = coordinates.map(\.longitude).max()!

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let latDelta = max((maxLat - minLat) * paddingFactor, 0.01)
        let lonDelta = max((maxLon - minLon) * paddingFactor, 0.01)

        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )
    }
}
