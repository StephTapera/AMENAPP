import SwiftUI

struct AmenSpaceSemanticSearchView: View {
    let spaceId: String
    @State private var query: String

    init(spaceId: String, initialQuery: String = "") {
        self.spaceId = spaceId
        _query = State(initialValue: initialQuery)
    }
    @State private var results: [SmartSearchResult] = []
    @State private var rankingMode: SmartSearchRankingMode = .unknown
    @State private var isSearching = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                TextField("Search this Space", text: $query)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                Button("Search", systemImage: "magnifyingglass") { Task { await search() } }
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
            } footer: {
                Text(rankingMode.explanation)
            }
            if isSearching { ProgressView() }
            Section("Results") {
                if results.isEmpty && !isSearching {
                    Text("No results yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(results) { AmenSpaceSearchResultCard(result: $0) }
                }
            }
        }
        .navigationTitle("Space Search")
        .safeAreaInset(edge: .top) {
            HStack(spacing: 8) {
                Image(systemName: rankingMode == .vector ? "point.3.connected.trianglepath.dotted" : "text.magnifyingglass")
                    .font(.caption.weight(.semibold))
                Text(rankingMode.label)
                    .font(.caption.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.thinMaterial)
        }
        .alert("Search failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func search() async {
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            let response = try await AmenSmartMessageIntelligenceService.shared.semanticSearchResponse(spaceId: spaceId, query: query)
            rankingMode = response.rankingMode
            results = response.results
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AmenSpaceSearchResultCard: View {
    let result: SmartSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(result.title).font(.headline)
                Spacer()
                Text(result.sourceType).font(.caption).foregroundStyle(.secondary)
            }
            Text(result.snippet).font(.subheadline).foregroundStyle(.secondary)
            ProgressView(value: min(max(result.score, 0), 1))
                .accessibilityLabel("Match score")
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
