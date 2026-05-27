import SwiftUI

struct SmartCommunitySearchView: View {
    @StateObject private var viewModel: SmartCommunitySearchViewModel
    @StateObject private var locationManager = SmartCommunityLocationManager.shared
    @EnvironmentObject private var featureFlags: AMENFeatureFlags

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @FocusState private var searchFocused: Bool

    init(surface: SmartSearchSurface = .findChurch) {
        _viewModel = StateObject(wrappedValue: SmartCommunitySearchViewModel(surface: surface))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // Search bar — Liquid Glass layer
                searchBarLayer

                // Content area — plain white cards
                contentArea
            }
        }
        .navigationTitle("Ask Amen")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $viewModel.showLocationPrompt) {
            SmartCommunityLocationPrompt(
                onAllow: { viewModel.proceedWithLocation() },
                onSkip: { viewModel.proceedWithoutLocation() },
                onManualEntry: {
                    viewModel.showLocationPrompt = false
                    viewModel.isShowingManualLocationEntry = true
                }
            )
            .presentationDetents([.height(420)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $viewModel.isShowingManualLocationEntry) {
            manualLocationSheet
        }
    }

    // MARK: - Search bar with Liquid Glass background

    private var searchBarLayer: some View {
        VStack(spacing: 10) {
            SmartCommunitySearchBar(
                text: $viewModel.queryText,
                isLoading: viewModel.uiState == .loading,
                onSubmit: { viewModel.submitSearch() },
                onClear: { viewModel.clearSearch() }
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Refinement chips when results are showing
            if case .results = viewModel.uiState, !viewModel.refinementSuggestions.isEmpty {
                SmartCommunityRefinementChips(
                    chips: viewModel.refinementSuggestions,
                    onChipTapped: { viewModel.applyRefinement($0) }
                )
            }
        }
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        switch viewModel.uiState {
        case .idle:
            idleState
        case .loading:
            loadingState
        case .results(let results):
            resultsView(results)
        case .empty(let query):
            SmartCommunitySearchEmptyState(
                query: query,
                suggestions: viewModel.refinementSuggestions,
                onSuggestionTapped: { viewModel.applyRefinement($0) }
            )
        case .error:
            SmartCommunitySearchErrorState(
                message: "Search failed",
                onRetry: { viewModel.retrySearch() }
            )
        case .crisis:
            SmartCommunityCrisisState()
        }
    }

    // MARK: - Idle state

    private var idleState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Spacer(minLength: 20)

                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 36))
                        .foregroundStyle(.accentColor)

                    Text("Ask Amen")
                        .font(.title2.weight(.bold))

                    Text("Describe what kind of church, group, or community you're looking for.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Try asking")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)

                    ForEach(idleExamples, id: \.self) { example in
                        Button { viewModel.queryText = example } label: {
                            HStack {
                                Image(systemName: "sparkle")
                                    .foregroundStyle(.accentColor)
                                    .font(.caption)
                                Text(example)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .foregroundStyle(.tertiary)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .accessibilityLabel("Try: \(example)")
                    }
                }

                Spacer(minLength: 40)
            }
        }
    }

    // MARK: - Loading state

    private var loadingState: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
                .accessibilityLabel("Searching for communities")
            Text("Finding the right community for you...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Results

    private func resultsView(_ results: [SmartCommunityRankedResult]) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(results) { result in
                    SmartCommunityResultCard(
                        result: result,
                        onAction: { action in viewModel.handleAction(action, result: result) },
                        onAskBerean: { _ in /* Berean integration point */ }
                    )
                    .padding(.horizontal, 16)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Manual location sheet

    private var manualLocationSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Enter your location")
                    .font(.headline)

                Text("Enter your ZIP code or city name to find nearby communities.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextField("ZIP code or city name", text: $locationManager.manualLocationText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .submitLabel(.done)
                    .onSubmit {
                        locationManager.applyManualLocation()
                        viewModel.isShowingManualLocationEntry = false
                        viewModel.submitSearch()
                    }

                Button("Search with This Location") {
                    locationManager.applyManualLocation()
                    viewModel.isShowingManualLocationEntry = false
                    viewModel.submitSearch()
                }
                .font(.subheadline.weight(.semibold))
                .disabled(locationManager.manualLocationText.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer()
            }
            .padding(.top, 24)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.isShowingManualLocationEntry = false
                    }
                }
            }
        }
        .presentationDetents([.height(320)])
    }

    // MARK: - Helpers

    private var idleExamples: [String] {
        [
            "Young adult church near me with worship",
            "Church with small groups and strong community",
            "Family-friendly with childcare and Sunday school",
            "Recovery ministry and support groups",
            "Diverse congregation, Spanish service",
        ]
    }
}
