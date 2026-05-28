import SwiftUI
import MapKit

struct ChurchSearchView: View {
    @StateObject private var viewModel = ChurchSearchViewModel()
    @State private var detailResult: SmartChurchSearchItem?
    @State private var showBereanFinder = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                searchBar
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
                SmartChurchBereanFinderView()
            }
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
            ChurchMapView(
                results: viewModel.results,
                selectedResult: $viewModel.selectedResult,
                camera: $viewModel.mapCamera,
                onOpen: { detailResult = $0 }
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.results) { result in
                        Button {
                            detailResult = result
                        } label: {
                            ChurchResultCard(result: result)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                thumbnail
                VStack(alignment: .leading, spacing: 6) {
                    Text(result.church.name)
                        .font(.headline)
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
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
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AmenTheme.Colors.glassStroke, lineWidth: 1)
        }
    }

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

    private var distanceLine: String {
        let distance = result.distanceMiles > 0 ? String(format: "%.1f mi", result.distanceMiles) : "Distance unavailable"
        return [distance, result.church.shortLocation].filter { !$0.isEmpty }.joined(separator: " • ")
    }

    private func chip(_ text: String) -> some View {
        Text(text.capitalized)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AmenTheme.Colors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AmenTheme.Colors.surfaceChip, in: Capsule())
    }
}

struct ChurchMapView: View {
    let results: [SmartChurchSearchItem]
    @Binding var selectedResult: SmartChurchSearchItem?
    @Binding var camera: MapCameraPosition
    var onOpen: (SmartChurchSearchItem) -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $camera, selection: $selectedResult) {
                ForEach(results) { result in
                    Marker(result.church.name, systemImage: "building.columns.fill", coordinate: result.church.coordinate)
                        .tag(result)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            if let selectedResult {
                Button { onOpen(selectedResult) } label: {
                    ChurchResultCard(result: selectedResult)
                        .padding(12)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
