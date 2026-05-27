import SwiftUI
import MapKit

struct ChurchDetailView: View {
    let result: SmartChurchSearchItem

    @State private var readiness = SmartChurchVisitReadiness.fallback
    @State private var isLoadingReadiness = false
    @State private var showGetReady = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    matchCard
                    serviceTimes
                    visitReadiness
                    contact
                    statementOfFaith
                }
                .padding(16)
            }
            .background(AmenTheme.Colors.backgroundGrouped.ignoresSafeArea())
            .navigationTitle(result.church.name)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                planButton
                    .padding(16)
                    .background(.ultraThinMaterial)
            }
            .task { await loadReadiness() }
            .sheet(isPresented: $showGetReady) {
                GetReadyView(vm: GetReadyViewModel(church: result.church.legacyChurch))
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(height: 190)
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.accentPrimary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.church.name)
                        .font(.title2.weight(.bold))
                    Text([result.church.denomination, result.church.shortLocation].filter { !$0.isEmpty }.joined(separator: " • "))
                        .font(.subheadline)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
                .padding(18)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(AmenTheme.Colors.glassStroke, lineWidth: 1)
            }
        }
    }

    private var matchCard: some View {
        detailCard("Why It Matches", systemImage: "sparkles") {
            Text(result.matchReason)
                .font(.body)
            Text(String(format: "Match score %.0f%% • %.1f miles away", result.score * 100, result.distanceMiles))
                .font(.caption)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
    }

    private var serviceTimes: some View {
        detailCard("Service Times", systemImage: "calendar") {
            if result.church.serviceTimes.isEmpty {
                Text("Service times are not verified yet.")
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            } else {
                ForEach(result.church.serviceTimes) { service in
                    HStack {
                        Text(service.day)
                        Spacer()
                        Text(service.time)
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    private var visitReadiness: some View {
        detailCard("What To Expect", systemImage: "figure.walk") {
            if isLoadingReadiness {
                ProgressView()
            }
            readinessRow("Dress", readiness.dress)
            readinessRow("Length", readiness.serviceLength)
            readinessRow("Parking", readiness.parking)
            readinessRow("Kids", readiness.kidsCheckIn)
            readinessRow("Bring", readiness.whatToBring)
        }
    }

    private var contact: some View {
        detailCard("Contact", systemImage: "phone") {
            Text(result.church.address)
            if let phone = result.church.phone, !phone.isEmpty { Text(phone) }
            if let website = result.church.website, let url = URL(string: website) {
                Link(website, destination: url)
            }
            Button {
                openDirections()
            } label: {
                Label("Open in Maps", systemImage: "map")
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var statementOfFaith: some View {
        if !result.church.statementOfFaith.isEmpty || !result.church.doctrinalTags.isEmpty {
            detailCard("Statement of Faith", systemImage: "book.closed") {
                if !result.church.statementOfFaith.isEmpty {
                    Text(result.church.statementOfFaith)
                        .font(.subheadline)
                }
                if !result.church.doctrinalTags.isEmpty {
                    FlowTagRow(tags: result.church.doctrinalTags.map { $0.replacingOccurrences(of: "_", with: " ").capitalized })
                }
            }
        }
    }

    private var planButton: some View {
        Button {
            showGetReady = true
        } label: {
            Label("Plan my visit", systemImage: "calendar.badge.plus")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(AmenTheme.Colors.accentPrimary)
    }

    private func detailCard<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AmenTheme.Colors.glassStroke, lineWidth: 1)
        }
    }

    private func readinessRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            Text(value)
                .font(.subheadline)
        }
    }

    private func loadReadiness() async {
        isLoadingReadiness = true
        defer { isLoadingReadiness = false }
        do {
            readiness = try await SmartChurchSearchService.shared.visitReadiness(churchId: result.church.id)
        } catch {
            readiness = .fallback
        }
    }

    private func openDirections() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: result.church.coordinate))
        item.name = result.church.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}

private struct FlowTagRow: View {
    let tags: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AmenTheme.Colors.surfaceChip, in: Capsule())
            }
        }
    }
}
