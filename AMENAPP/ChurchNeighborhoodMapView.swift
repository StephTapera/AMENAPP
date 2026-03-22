// ChurchNeighborhoodMapView.swift
// AMENAPP
//
// Neighborhood density layer on church detail screen:
//   - Opt-in: stores user's zip code anonymously (aggregated count only)
//   - Map with semi-transparent circles centered on zip centroids
//   - Requires >= 10 total member zip entries before showing
//   - Privacy info button: no individual locations tracked

import SwiftUI
import Combine
import MapKit
import FirebaseAuth
import FirebaseFirestore

// MARK: - Models

struct ZipData: Identifiable {
    let id: String  // zip code as ID
    let zip: String
    let count: Int
    let coordinate: CLLocationCoordinate2D
    
    init(zip: String, count: Int, coordinate: CLLocationCoordinate2D) {
        self.id = zip
        self.zip = zip
        self.count = count
        self.coordinate = coordinate
    }
}

// MARK: - ChurchNeighborhoodService

@MainActor
final class ChurchNeighborhoodService: ObservableObject {
    @Published var zipData: [ZipData] = []
    @Published var isLoading = false
    @Published var topNeighborhoodName: String?

    private let db = Firestore.firestore()

    var totalCount: Int { zipData.reduce(0) { $0 + $1.count } }

    func load(churchId: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let snap = try await db.collection("churches/\(churchId)/memberZips").getDocuments()
            var entries: [(zip: String, count: Int)] = snap.documents.compactMap { doc in
                guard let count = doc.data()["count"] as? Int else { return nil }
                return (zip: doc.documentID, count: count)
            }
            guard entries.reduce(0, { $0 + $1.count }) >= 10 else { return }
            // Geocode zip codes to coordinates
            var results: [ZipData] = []
            for entry in entries.prefix(20) {
                if let coord = await geocodeZip(entry.zip) {
                    results.append(ZipData(zip: entry.zip, count: entry.count, coordinate: coord))
                }
            }
            zipData = results
            // Reverse geocode top zip for neighborhood name
            if let top = results.max(by: { $0.count < $1.count }) {
                topNeighborhoodName = await reverseGeocodeNeighborhood(top.coordinate)
            }
        } catch {
            print("ChurchNeighborhoodService error: \(error)")
        }
    }

    // Opt-in: write user's zip to Firestore (aggregated count)
    func shareZip(churchId: String) async {
        guard let uid = Auth.auth().currentUser?.uid,
              let zip = await fetchUserZip(uid: uid) else { return }
        try? await db.collection("churches/\(churchId)/memberZips").document(zip)
            .setData(["count": FieldValue.increment(Int64(1))], merge: true)
    }

    private func fetchUserZip(uid: String) async -> String? {
        try? await db.document("users/\(uid)").getDocument().data()?["neighborhoodZip"] as? String
    }

    private func geocodeZip(_ zip: String) async -> CLLocationCoordinate2D? {
        await withCheckedContinuation { cont in
            CLGeocoder().geocodeAddressString(zip) { placemarks, _ in
                cont.resume(returning: placemarks?.first?.location?.coordinate)
            }
        }
    }

    private func reverseGeocodeNeighborhood(_ coord: CLLocationCoordinate2D) async -> String? {
        let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        return await withCheckedContinuation { cont in
            CLGeocoder().reverseGeocodeLocation(loc) { placemarks, _ in
                let name = placemarks?.first?.subLocality
                    ?? placemarks?.first?.locality
                    ?? placemarks?.first?.administrativeArea
                cont.resume(returning: name)
            }
        }
    }
}

// MARK: - ChurchNeighborhoodMapView

struct ChurchNeighborhoodMapView: View {
    let church: ChurchEntity
    @StateObject private var service = ChurchNeighborhoodService()
    @State private var showPrivacyInfo = false
    @State private var region: MKCoordinateRegion

    init(church: ChurchEntity) {
        self.church = church
        _region = State(initialValue: MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude:  church.coordinate.latitude,
                longitude: church.coordinate.longitude
            ),
            span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
        ))
    }

    var body: some View {
        if service.zipData.isEmpty && !service.isLoading {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Community Map")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(.label))
                    Spacer()
                    Button {
                        showPrivacyInfo = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(.secondaryLabel))
                    }
                }
                .padding(.horizontal, 20)

                // Map
                Map(coordinateRegion: $region, annotationItems: service.zipData) { entry in
                    MapAnnotation(coordinate: entry.coordinate) {
                        let maxCount = service.zipData.max(by: { $0.count < $1.count })?.count ?? 1
                        let size     = CGFloat(60 + (entry.count * 40 / maxCount))
                        Circle()
                            .fill(Color.accentColor.opacity(0.3))
                            .frame(width: size, height: size)
                    }
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)

                // Caption
                if !service.zipData.isEmpty {
                    let neighborhood = service.topNeighborhoodName ?? "nearby areas"
                    Text("Members live across \(service.zipData.count) neighborhoods · Most concentrated in \(neighborhood)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(.secondaryLabel))
                        .padding(.horizontal, 20)
                }
            }
            .alert("About this map", isPresented: $showPrivacyInfo) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This map shows approximate areas where members live. No individual locations are tracked.")
            }
            .task { await service.load(churchId: church.id) }
        }
    }
}
