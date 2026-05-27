import SwiftUI

struct SmartChurchBereanTurn: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    var text: String
    var results: [SmartChurchSearchItem]
    var isError = false
}

@MainActor
final class SmartChurchBereanFinderViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var turns: [SmartChurchBereanTurn] = []
    @Published private(set) var isStreaming = false
    @Published private(set) var statusMessage: String?

    private let service: SmartChurchSearchService
    private let locationProvider: ChurchSearchLocationProviding
    private let radiusMiles: Double

    init(
        seedQuery: String? = nil,
        service: SmartChurchSearchService = .shared,
        locationProvider: ChurchSearchLocationProviding = ChurchSearchLocationProvider.shared,
        radiusMiles: Double = 15
    ) {
        self.service = service
        self.locationProvider = locationProvider
        self.radiusMiles = radiusMiles

        if let seedQuery, !seedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Task { await submit(seedQuery) }
        }
    }

    func submitCurrentQuery() {
        Task { await submit(query) }
    }

    func submit(_ rawQuery: String) async {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        query = ""
        statusMessage = nil
        turns.append(SmartChurchBereanTurn(role: .user, text: trimmed, results: []))
        isStreaming = true
        defer {
            isStreaming = false
            statusMessage = nil
        }

        do {
            let location = try await locationProvider.currentCoordinate()
            var receivedResults = false
            for try await event in service.bereanChurchChat(query: trimmed, userLocation: location, radiusMiles: radiusMiles) {
                switch event.kind {
                case "status":
                    statusMessage = event.message
                case "results":
                    receivedResults = true
                    turns.append(SmartChurchBereanTurn(
                        role: .assistant,
                        text: event.results.isEmpty ? "I did not find a grounded match in that radius." : "Here are grounded church matches I found.",
                        results: event.results
                    ))
                case "message":
                    if let message = event.message, !message.isEmpty {
                        turns.append(SmartChurchBereanTurn(role: .assistant, text: message, results: []))
                    }
                case "error":
                    turns.append(SmartChurchBereanTurn(role: .assistant, text: event.message ?? "Berean church search failed.", results: [], isError: true))
                default:
                    break
                }
            }
            if !receivedResults {
                turns.append(SmartChurchBereanTurn(role: .assistant, text: "I did not receive church results. Try again with a wider radius or a clearer priority.", results: [], isError: true))
            }
        } catch {
            turns.append(SmartChurchBereanTurn(role: .assistant, text: error.localizedDescription, results: [], isError: true))
        }
    }
}

struct SmartChurchBereanFinderView: View {
    @StateObject private var viewModel: SmartChurchBereanFinderViewModel
    @State private var detailResult: SmartChurchSearchItem?
    @FocusState private var composerFocused: Bool

    init(seedQuery: String? = nil) {
        _viewModel = StateObject(wrappedValue: SmartChurchBereanFinderViewModel(seedQuery: seedQuery))
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if viewModel.turns.isEmpty {
                            welcome
                        }
                        ForEach(viewModel.turns) { turn in
                            turnView(turn)
                                .id(turn.id)
                        }
                        if viewModel.isStreaming {
                            streamingStatus
                                .id("streamingStatus")
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 84)
                }
                .onChange(of: viewModel.turns.count) { _, _ in
                    if let id = viewModel.turns.last?.id {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.statusMessage) { _, _ in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        proxy.scrollTo("streamingStatus", anchor: .bottom)
                    }
                }
            }
            .background(AmenTheme.Colors.backgroundGrouped.ignoresSafeArea())
            .navigationTitle("Berean Church Finder")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                composer
                    .padding(16)
                    .background(.ultraThinMaterial)
            }
            .sheet(item: $detailResult) { result in
                ChurchDetailView(result: result)
            }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Find a Church", systemImage: "sparkles")
                .font(.title3.weight(.semibold))
            suggestionChips([
                "Charismatic non-denom with young adults near me",
                "Small church with strong Bible teaching",
                "Family-friendly with Spanish service",
                "Recovery community welcoming to newcomers",
            ])
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AmenTheme.Colors.glassStroke, lineWidth: 1)
        }
    }

    private func suggestionChips(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button {
                    Task { await viewModel.submit(item) }
                } label: {
                    Text(item)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(AmenTheme.Colors.surfaceChip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isStreaming)
            }
        }
    }

    @ViewBuilder
    private func turnView(_ turn: SmartChurchBereanTurn) -> some View {
        VStack(alignment: turn.role == .user ? .trailing : .leading, spacing: 10) {
            Text(turn.text)
                .font(.subheadline)
                .foregroundStyle(turn.isError ? .red : AmenTheme.Colors.textPrimary)
                .padding(12)
                .background(turn.role == .user ? AmenTheme.Colors.surfaceChip : Color.clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .frame(maxWidth: .infinity, alignment: turn.role == .user ? .trailing : .leading)

            ForEach(turn.results) { result in
                Button {
                    detailResult = result
                } label: {
                    ChurchResultCard(result: result)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var streamingStatus: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(viewModel.statusMessage ?? "Searching grounded church profiles...")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Refine your church search...", text: $viewModel.query, axis: .vertical)
                .focused($composerFocused)
                .lineLimit(1...3)
                .submitLabel(.send)
                .onSubmit { viewModel.submitCurrentQuery() }
            Button {
                viewModel.submitCurrentQuery()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(AmenTheme.Colors.accentPrimary)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isStreaming)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AmenTheme.Colors.glassStroke, lineWidth: 1)
        }
    }
}
