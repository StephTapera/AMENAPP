import SwiftUI
import MapKit

// MARK: - Intent model (file-private, referenced by ChurchSearchViewModel.quickIntents)
struct QuickChurchIntent {
    let label: String
    let icon: String
    let query: String
}

struct ChurchSearchView: View {
    @StateObject private var viewModel = ChurchSearchViewModel()
    @State private var detailResult: SmartChurchSearchItem?
    @State private var showBereanFinder = false
    @State private var bereanSeedQuery: String?
    @State private var mapProvider: ChurchMapProvider = .apple

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                searchBar
                if viewModel.results.isEmpty && !viewModel.isLoading {
                    intentChips
                }
                if viewModel.displayMode == .map && !viewModel.results.isEmpty {
                    MapProviderPicker(provider: $mapProvider)
                }
                modePicker
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .background(AmenTheme.Colors.backgroundGrouped.ignoresSafeArea())
            .navigationTitle("Find a Church")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showBereanFinder = true
                    } label: {
                        Label("Berean Finder", systemImage: "sparkles")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(AmenTheme.Colors.accentPrimary)
                    }
                    .accessibilityLabel("Berean Church Finder — conversational AI church search")
                }
            }
            .sheet(item: $detailResult) { result in
                SmartChurchDetailView(result: result)
            }
            .sheet(isPresented: $showBereanFinder) {
                SmartChurchBereanFinderView(seedQuery: bereanSeedQuery)
            }
            .alert("Location Access Needed", isPresented: $viewModel.showLocationPrompt) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("AMEN uses your location to find churches nearby. Enable location access in Settings to see suggestions.")
            }
            .onAppear { viewModel.loadNearby() }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            TextField("Describe the church you're looking for…", text: $viewModel.query, axis: .vertical)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.search)
                .lineLimit(1...3)
                .onSubmit { viewModel.search() }
            Button {
                viewModel.search()
            } label: {
                Image(systemName: "arrow.forward.circle.fill")
                    .font(.title3)
                    .foregroundStyle(AmenTheme.Colors.accentPrimary)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AmenTheme.Colors.glassStroke, lineWidth: 1)
        }
    }

    private var intentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ChurchSearchViewModel.quickIntents, id: \.query) { intent in
                    Button {
                        viewModel.query = intent.query
                        viewModel.search()
                    } label: {
                        Label(intent.label, systemImage: intent.icon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AmenTheme.Colors.surfaceChip, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var modePicker: some View {
        Picker("View", selection: $viewModel.displayMode) {
            Label("List", systemImage: "list.bullet").tag(ChurchSearchViewModel.DisplayMode.list)
            Label("Map", systemImage: "map").tag(ChurchSearchViewModel.DisplayMode.map)
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Spacer()
        } else if let message = viewModel.errorMessage, viewModel.results.isEmpty {
            Spacer()
            ContentUnavailableView("No Results", systemImage: "building.columns", description: Text(message))
            Spacer()
        } else if viewModel.displayMode == .map {
            ChurchDualMapView(
                results: viewModel.results,
                provider: $mapProvider,
                selectedResult: $viewModel.selectedResult,
                camera: $viewModel.mapCamera,
                onOpen: { detailResult = $0 }
            )
        } else if !viewModel.results.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text(viewModel.isNearbySearch ? "Suggested near you" : "Results for your search")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .padding(.top, 4)
                    ForEach(viewModel.results) { result in
                        Button {
                            detailResult = result
                        } label: {
                            ChurchResultCard(result: result) { church in
                                bereanSeedQuery = "Tell me more about \(church.name) — \(church.denomination.isEmpty ? "" : "\(church.denomination), ")\(church.shortLocation)"
                                showBereanFinder = true
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
}

struct ChurchResultCard: View {
    let result: SmartChurchSearchItem
    var onAskBerean: ((SmartChurchSummary) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                thumbnail
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(result.church.name)
                            .font(.headline)
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                        if result.score > 0 {
                            scoreBadge
                        }
                        Spacer()
                    }
                    Text(distanceLine)
                        .font(.subheadline)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                    Text(result.matchReason)
                        .font(.subheadline)
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            chipRow
            actionRow
                .padding(.top, 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AmenTheme.Colors.glassStroke, lineWidth: 1)
        }
    }

    // MARK: - Subviews

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AmenTheme.Colors.surfaceChip)
            Image(systemName: "building.columns.fill")
                .font(.title3)
                .foregroundStyle(AmenTheme.Colors.accentPrimary)
        }
        .frame(width: 54, height: 54)
    }

    private var scoreBadge: some View {
        Text(String(format: "%.0f%%", result.score * 100))
            .font(.caption2.weight(.bold))
            .foregroundStyle(scoreColor(result.score))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(scoreColor(result.score).opacity(0.12), in: Capsule())
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if !result.church.denomination.isEmpty {
                    chip(result.church.denomination)
                }
                ForEach(result.church.worshipStyles.prefix(3), id: \.self) { chip($0.replacingOccurrences(of: "_", with: " ")) }
                ForEach(result.church.ministries.prefix(3), id: \.self) { chip($0.replacingOccurrences(of: "_", with: " ")) }
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            // Dual directions: Apple Maps or Google Maps (action sheet)
            ChurchDirectionsButton(church: result.church)

            if let website = result.church.website, !website.isEmpty {
                actionButton(icon: "safari.fill", label: "Website") {
                    if let url = URL(string: website) {
                        UIApplication.shared.open(url)
                    }
                }
                .accessibilityLabel("Visit website for \(result.church.name)")
            }

            actionButton(icon: "sparkles", label: "Ask Berean") {
                onAskBerean?(result.church)
            }
            .accessibilityLabel("Ask Berean about \(result.church.name)")
            .opacity(onAskBerean != nil ? 1 : 0.4)
            .disabled(onAskBerean == nil)
        }
    }

    // MARK: - Helpers

    private var distanceLine: String {
        let distance = result.distanceMiles > 0 ? String(format: "%.1f mi", result.distanceMiles) : "Distance unavailable"
        return [distance, result.church.shortLocation].filter { !$0.isEmpty }.joined(separator: " • ")
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 0.8 {
            return AmenTheme.Colors.amenGold
        } else if score >= 0.6 {
            return AmenTheme.Colors.accentPrimary
        } else {
            return AmenTheme.Colors.textSecondary
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text.capitalized)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AmenTheme.Colors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AmenTheme.Colors.surfaceChip, in: Capsule())
    }

    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(label)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(AmenTheme.Colors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AmenTheme.Colors.surfaceChip, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

