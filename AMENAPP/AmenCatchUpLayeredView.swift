// AmenCatchUpLayeredView.swift
// AMEN App — Layered Catch-Up Intelligence
//
// Four layers: Emotional / Organizational / Spiritual / Personal.
// Wraps the existing generateCatchUpRecap callable.
// Empty layers are hidden. Spiritual language is always humble.

import SwiftUI
import FirebaseFunctions

// MARK: - ViewModel

@MainActor
final class AmenCatchUpViewModel: ObservableObject {
    @Published private(set) var catchUp: AmenCatchUpIntelligence?
    @Published private(set) var conversationSummary: ConversationSummary?
    @Published private(set) var state: LoadState = .idle
    @Published var selectedLayer: AmenCatchUpLayer = .organizational

    enum LoadState: Equatable {
        case idle, loading, loaded, empty, error(String)
    }

    private let spaceId: String
    private let surface: ConversationOSSurface
    private let functions = Functions.functions()

    init(spaceId: String, surface: ConversationOSSurface = .amenSpaces) {
        self.spaceId = spaceId
        self.surface = surface
    }

    func load(lastVisitedAt: Date? = nil) async {
        guard AMENFeatureFlags.shared.catchUpIntelligenceEnabled
            || AMENFeatureFlags.shared.catchUpRecapsEnabled else {
            state = .empty
            return
        }
        state = .loading

        do {
            let callable = functions.httpsCallable("generateCatchUpRecap")
            var params: [String: Any] = ["spaceId": spaceId, "surface": surface.rawValue]
            if let date = lastVisitedAt {
                params["lastVisitedAt"] = ISO8601DateFormatter().string(from: date)
            }

            let result = try await callable.call(params)
            guard let data = result.data as? [String: Any] else {
                state = .empty
                return
            }

            // Parse ConversationSummary from the callable result
            let summaryData = try JSONSerialization.data(withJSONObject: data)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            conversationSummary = try? decoder.decode(ConversationSummary.self, from: summaryData)

            // Build layered catch-up from the summary
            catchUp = buildLayeredCatchUp(from: data)
            state = catchUp != nil ? .loaded : .empty

        } catch {
            state = .error(error.localizedDescription)
            dlog("[AmenCatchUpViewModel] load error: \(error)")
        }
    }

    private func buildLayeredCatchUp(from data: [String: Any]) -> AmenCatchUpIntelligence? {
        let messageCount = data["messageCount"] as? Int ?? 0
        guard messageCount > 0 else { return nil }

        let id = data["id"] as? String ?? UUID().uuidString
        let decisions = (data["actionItems"] as? [[String: Any]])?.compactMap { $0["title"] as? String } ?? []
        let blockers = (data["blockers"] as? [[String: Any]])?.compactMap { $0["description"] as? String } ?? []
        let unresolved = (data["unresolvedQuestions"] as? [[String: Any]])?.count ?? 0
        let clusters = (data["topicClusters"] as? [[String: Any]])?.compactMap { $0["title"] as? String } ?? []

        return AmenCatchUpIntelligence(
            id: id,
            spaceId: spaceId,
            userId: "",
            generatedAt: Date(),
            coverageWindowStart: Date(timeIntervalSinceNow: -7 * 24 * 3600),
            coverageWindowEnd: Date(),
            emotionalLayer: AmenCatchUpEmotionalLayer(
                urgencyLevel: blockers.isEmpty ? "" : "Blockers present",
                prayerIntensity: "",
                encouragementHighlights: [],
                tensionIndicators: blockers
            ),
            organizationalLayer: AmenCatchUpOrgLayer(
                decisions: decisions,
                blockers: blockers,
                deadlines: [],
                unresolvedItems: unresolved
            ),
            spiritualLayer: AmenCatchUpSpiritualLayer(
                scriptureThemes: clusters.filter { $0.lowercased().contains("scripture") || $0.lowercased().contains("prayer") },
                theologicalDevelopments: [],
                prayerOutcomes: [],
                recurringVerses: []
            ),
            personalLayer: AmenCatchUpPersonalLayer(
                mentionsForUser: [],
                closePeopleUpdates: [],
                unresolvedResponses: []
            ),
            confidence: data["confidence"] as? Double ?? 0.7,
            dismissed: false
        )
    }
}

// MARK: - Layered Catch-Up View

struct AmenCatchUpLayeredView: View {
    let spaceId: String
    var surface: ConversationOSSurface = .amenSpaces
    var onOpenFull: ((ConversationSummary) -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    @StateObject private var vm: AmenCatchUpViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(spaceId: String,
         surface: ConversationOSSurface = .amenSpaces,
         onOpenFull: ((ConversationSummary) -> Void)? = nil,
         onDismiss: (() -> Void)? = nil) {
        self.spaceId = spaceId
        self.surface = surface
        self.onOpenFull = onOpenFull
        self.onDismiss = onDismiss
        _vm = StateObject(wrappedValue: AmenCatchUpViewModel(spaceId: spaceId, surface: surface))
    }

    var body: some View {
        Group {
            switch vm.state {
            case .idle, .loading:   loadingView
            case .empty:            EmptyView()
            case .error:            EmptyView()
            case .loaded:           loadedView
            }
        }
        .task { await vm.load() }
    }

    // MARK: - Loaded View

    private var loadedView: some View {
        VStack(alignment: .leading, spacing: 0) {
            catchUpHeader
            layerTabRow
            layerContent
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.07), radius: 12, x: 0, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    private var catchUpHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Catch Me Up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.82))
                if let catchUp = vm.catchUp {
                    Text(catchUp.coverageWindowStart.catchUpLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.black.opacity(0.40))
                }
            }
            Spacer(minLength: 0)

            if let summary = vm.conversationSummary {
                Button { onOpenFull?(summary) } label: {
                    Text("View full")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.50))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
            }

            if onDismiss != nil {
                Button { onDismiss?() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.35))
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss catch-up")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var layerTabRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(visibleLayers, id: \.self) { layer in
                    layerTab(layer)
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.bottom, 10)
    }

    private func layerTab(_ layer: AmenCatchUpLayer) -> some View {
        let isSelected = vm.selectedLayer == layer
        return Button {
            withAnimation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.78)) {
                vm.selectedLayer = layer
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: layer.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(layer.displayName)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? Color.black : Color.black.opacity(0.45))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.black.opacity(0.08) : Color.black.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(layer.displayName) layer")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var layerContent: some View {
        if let catchUp = vm.catchUp {
            switch vm.selectedLayer {
            case .emotional:
                emotionalLayerContent(catchUp.emotionalLayer)
            case .organizational:
                orgLayerContent(catchUp.organizationalLayer)
            case .spiritual:
                spiritualLayerContent(catchUp.spiritualLayer)
            case .personal:
                personalLayerContent(catchUp.personalLayer)
            }
        }
    }

    @ViewBuilder
    private func emotionalLayerContent(_ layer: AmenCatchUpEmotionalLayer?) -> some View {
        if let layer, !layer.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if !layer.urgencyLevel.isEmpty {
                    catchUpRow(icon: "exclamationmark.circle", text: layer.urgencyLevel)
                }
                ForEach(layer.encouragementHighlights.prefix(2), id: \.self) { h in
                    catchUpRow(icon: "heart", text: h)
                }
                ForEach(layer.tensionIndicators.prefix(2), id: \.self) { t in
                    catchUpRow(icon: "exclamationmark.triangle", text: t)
                }
            }
        } else {
            emptyLayerView("No emotional signals detected.")
        }
    }

    @ViewBuilder
    private func orgLayerContent(_ layer: AmenCatchUpOrgLayer?) -> some View {
        if let layer, !layer.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(layer.decisions.prefix(3), id: \.self) { d in
                    catchUpRow(icon: "checkmark.seal", text: d)
                }
                ForEach(layer.blockers.prefix(2), id: \.self) { b in
                    catchUpRow(icon: "xmark.octagon", text: b)
                }
                if layer.unresolvedItems > 0 {
                    catchUpRow(icon: "questionmark.circle", text: "\(layer.unresolvedItems) unresolved item\(layer.unresolvedItems == 1 ? "" : "s")")
                }
            }
        } else {
            emptyLayerView("No organizational updates.")
        }
    }

    @ViewBuilder
    private func spiritualLayerContent(_ layer: AmenCatchUpSpiritualLayer?) -> some View {
        if let layer, !layer.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(layer.scriptureThemes.prefix(3), id: \.self) { t in
                    catchUpRow(icon: "sparkles", text: "A recurring theme appears to be: \(t)")
                }
                ForEach(layer.prayerOutcomes.prefix(2), id: \.self) { o in
                    catchUpRow(icon: "hands.sparkles", text: o)
                }
                ForEach(layer.recurringVerses.prefix(2), id: \.self) { v in
                    catchUpRow(icon: "book.closed", text: v)
                }
            }
        } else {
            emptyLayerView("No spiritual themes detected.")
        }
    }

    @ViewBuilder
    private func personalLayerContent(_ layer: AmenCatchUpPersonalLayer?) -> some View {
        if let layer, !layer.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(layer.mentionsForUser.prefix(3), id: \.self) { m in
                    catchUpRow(icon: "at", text: m)
                }
                ForEach(layer.closePeopleUpdates.prefix(2), id: \.self) { u in
                    catchUpRow(icon: "person.fill", text: u)
                }
            }
        } else {
            emptyLayerView("No personal updates.")
        }
    }

    private func catchUpRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.40))
                .frame(width: 16)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Color.black.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func emptyLayerView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Color.black.opacity(0.36))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }

    // MARK: - Loading

    private var loadingView: some View {
        HStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading summary…")
                .font(.system(size: 13))
                .foregroundStyle(Color.black.opacity(0.42))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }

    // MARK: - Helpers

    private var visibleLayers: [AmenCatchUpLayer] {
        guard let c = vm.catchUp else { return AmenCatchUpLayer.allCases }
        return AmenCatchUpLayer.allCases.filter { layer in
            switch layer {
            case .emotional:      return !(c.emotionalLayer?.isEmpty ?? true)
            case .organizational: return !(c.organizationalLayer?.isEmpty ?? true)
            case .spiritual:      return !(c.spiritualLayer?.isEmpty ?? true)
            case .personal:       return !(c.personalLayer?.isEmpty ?? true)
            }
        }
    }
}

private extension Date {
    var catchUpLabel: String {
        let days = Calendar.current.dateComponents([.day], from: self, to: Date()).day ?? 0
        if days == 0 { return "Since today" }
        if days == 1 { return "Since yesterday" }
        return "Past \(days) days"
    }
}
