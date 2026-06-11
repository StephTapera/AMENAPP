//
//  AmenPulseSurfaceView.swift
//  AMEN — Amen Pulse (Personalized Daily Surface)
//
//  The opening surface. ONE bounded scroll: large title, glass chips, an
//  importance-selected card stack, and a visible terminus — "That's everything
//  for today." It is the only daily surface designed to be FINISHED. No feed,
//  no pagination, no pull-for-more, no streaks, no velocity framing.
//

import SwiftUI

// MARK: - Chips

enum PulseChip: String, CaseIterable, Identifiable {
    case all = "All"
    case spiritual = "Spiritual"
    case people = "People"
    case church = "Church"
    case community = "Community"

    var id: String { rawValue }
    var title: String { rawValue }
}

private extension PulseCardKind {
    /// Which filter chip a card belongs to. `.all` cards appear under every chip.
    var chip: PulseChip {
        switch self {
        case .dailyBriefHero, .whatsNew, .terminus: return .all
        case .scriptureHero, .sermon:               return .spiritual
        case .prayerFollowup, .occasion:            return .people
        case .churchEvent:                          return .church
        case .spaceActivity:                        return .community
        }
    }
}

// MARK: - View model

@MainActor
final class AmenPulseViewModel: ObservableObject {

    enum Phase: Equatable { case loading, loaded, empty, failed(String) }

    @Published private(set) var digest: PulseDigest?
    @Published private(set) var phase: Phase = .loading
    @Published var chip: PulseChip = .all

    private let service: PulseService
    private var observeTask: Task<Void, Never>?

    // nonisolated so the View's (nonisolated) init can use AmenPulseViewModel()
    // as a default argument. Body only assigns stored properties — safe.
    nonisolated init(service: PulseService = .shared, previewDigest: PulseDigest? = nil) {
        self.service = service
        if let previewDigest {
            self.digest = previewDigest
            self.phase = previewDigest.cards.isEmpty ? .empty : .loaded
        }
    }

    deinit { observeTask?.cancel() }

    /// Cards to render (bounded + filtered). Terminus is appended by the view.
    var visibleCards: [PulseCard] {
        guard let digest else { return [] }
        if digest.sabbath { return digest.cards }   // single still card; no chips
        let cap = max(PulseConfig.minUserCards, PulseConfig.defaultMaxCards)
        let bounded = Array(digest.cards.prefix(cap))
        return bounded.filter { chip == .all || $0.kind.chip == chip || $0.kind.chip == .all }
    }

    var isSabbath: Bool { digest?.sabbath ?? false }

    func load() async {
        if digest != nil, phase == .loaded { return }   // preview-seeded
        phase = .loading
        do {
            let loaded = try await service.loadToday()
            digest = loaded
            phase = loaded.cards.isEmpty ? .empty : .loaded
            startObserving()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func startObserving() {
        observeTask?.cancel()
        guard let stream = try? service.observeToday() else { return }
        observeTask = Task { [weak self] in
            for await update in stream {
                guard let self, let update else { continue }
                await MainActor.run {
                    self.digest = update
                    self.phase = update.cards.isEmpty ? .empty : .loaded
                }
            }
        }
    }
}

// MARK: - Surface

struct AmenPulseSurfaceView: View {
    @StateObject private var viewModel: AmenPulseViewModel
    @Namespace private var morph
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedCard: PulseCard?
    @State private var whatsNewStoryId: String?
    @State private var showArchive = false
    @State private var showPrefs = false

    init(viewModel: AmenPulseViewModel = AmenPulseViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    private var ambientTint: Color {
        let key = viewModel.visibleCards.first?.hero.style ?? "verse"
        return PulseHeroStyle.resolve(key).tint
    }

    var body: some View {
        ZStack {
            Color(hex: "F2F2F7").ignoresSafeArea()
            ambientWash

            Group {
                switch viewModel.phase {
                case .loading:
                    ProgressView().tint(Color(hex: "8A8A8E"))
                case .failed(let message):
                    errorState(message)
                case .empty, .loaded:
                    surfaceScroll
                }
            }
            .scaleEffect(selectedCard != nil && !reduceMotion ? 0.94 : 1)
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: selectedCard)

            expandedOverlay
        }
        .task { await viewModel.load() }
        .sheet(isPresented: $showPrefs) { PulsePrefsView() }
        .fullScreenCover(isPresented: $showArchive) {
            NavigationStack { WhatsNewArchiveView() }
        }
        .fullScreenCover(item: $whatsNewStoryId.mappedToIdentifiable()) { boxed in
            WhatsNewStoryView(storyId: boxed.id)
        }
    }

    private var ambientWash: some View {
        VStack {
            RadialGradient(colors: [ambientTint.opacity(0.55), Color(hex: "F2F2F7").opacity(0)],
                           center: .top, startRadius: 0, endRadius: 320)
                .frame(height: 280)
                .animation(.easeInOut(duration: 0.9), value: ambientTint)
            Spacer()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: Scroll surface

    private var surfaceScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if viewModel.isSabbath {
                    sabbathBody
                } else {
                    if !viewModel.visibleCards.contains(where: { $0.kind != .terminus }) && viewModel.phase == .empty {
                        emptyState
                    } else {
                        chipsRow
                        cardStack
                    }
                }
            }
            .padding(.bottom, 40)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.dateEyebrow().uppercased())
                    .font(.system(size: 13, weight: .semibold)).tracking(0.4)
                    .foregroundColor(Color(hex: "8A8A8E"))
                Text("Pulse")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundColor(Color(hex: "1C1C1E"))
            }
            Spacer()
            HStack(spacing: 10) {
                topButton("sparkles") { showArchive = true }
                    .accessibilityLabel(Text("What’s New"))
                topButton("slider.horizontal.3") { showPrefs = true }
                    .accessibilityLabel(Text("Customize Pulse"))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    private func topButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color(hex: "1C1C1E"))
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.white.opacity(0.62)))
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PulseChip.allCases) { chip in
                    let active = viewModel.chip == chip
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { viewModel.chip = chip }
                    } label: {
                        Text(chip.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(active ? .white : Color(hex: "1C1C1E"))
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .background(
                                Capsule()
                                    .fill(active ? Color(hex: "1C1C1E").opacity(0.86) : Color.white.opacity(0.62))
                                    .background(Capsule().fill(.ultraThinMaterial))
                            )
                            .overlay(Capsule().stroke(Color.white.opacity(active ? 0 : 0.7), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }

    private var cardStack: some View {
        LazyVStack(spacing: 18) {
            ForEach(Array(viewModel.visibleCards.enumerated()), id: \.element.id) { _, card in
                PulseHeroCardView(
                    card: card,
                    namespace: morph,
                    isSourceForMorph: selectedCard == nil,
                    isHidden: selectedCard?.id == card.id,
                    onOpen: { open(card) }
                )
            }
            terminusCard
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var terminusCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(Color(hex: "8A8A8E"))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color(hex: "1C1C1E").opacity(0.05)))
            Text("That’s everything for today.")
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(Color(hex: "1C1C1E"))
            Text("Be still. Go be with people.")
                .font(.system(size: 14.5))
                .foregroundColor(Color(hex: "8A8A8E"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44).padding(.horizontal, 28)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [Color.white, Color(hex: "F7F6F3")], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.06), radius: 10, y: 6)
        )
        .padding(.top, 14)
        .accessibilityElement(children: .combine)
    }

    // MARK: Sabbath

    private var sabbathBody: some View {
        VStack(spacing: 16) {
            if let card = viewModel.digest?.cards.first {
                PulseHeroCardView(card: card, namespace: morph, isSourceForMorph: true, isHidden: false, onOpen: {})
                    .padding(.horizontal, 16)
                    .allowsHitTesting(false)
            }
            Text("Rest today. Pulse is quiet on your Sabbath.")
                .font(.system(size: 14.5))
                .foregroundColor(Color(hex: "8A8A8E"))
                .padding(.top, 8)
        }
        .padding(.top, 12)
    }

    // MARK: Empty / error

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "wind").font(.system(size: 26)).foregroundColor(Color(hex: "8A8A8E"))
            Text("Nothing needs you right now.")
                .font(.system(size: 18, weight: .bold)).foregroundColor(Color(hex: "1C1C1E"))
            Text("Pulse will be here tomorrow morning.")
                .font(.system(size: 14.5)).foregroundColor(Color(hex: "8A8A8E"))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 24)).foregroundColor(Color(hex: "8A8A8E"))
            Text("Pulse couldn’t load.").font(.system(size: 17, weight: .bold)).foregroundColor(Color(hex: "1C1C1E"))
            Text(message).font(.system(size: 13)).foregroundColor(Color(hex: "8A8A8E")).multilineTextAlignment(.center)
            Button("Try Again") { Task { await viewModel.load() } }
                .font(.system(size: 14, weight: .semibold)).padding(.top, 4)
        }
        .padding(40)
    }

    // MARK: Expanded overlay

    @ViewBuilder
    private var expandedOverlay: some View {
        if let card = selectedCard {
            Color.black.opacity(0.3).ignoresSafeArea()
                .onTapGesture { close() }
                .transition(.opacity)

            PulseExpandedCardView(
                card: card,
                namespace: morph,
                onClose: { close() },
                onAction: { handleAction($0) },
                onOpenWhatsNew: { storyId in
                    close()
                    whatsNewStoryId = storyId
                }
            )
            .zIndex(2)
        }
    }

    // MARK: Actions

    private func open(_ card: PulseCard) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82)) {
            selectedCard = card
        }
    }

    private func close() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82)) {
            selectedCard = nil
        }
    }

    private func handleAction(_ card: PulseCard) {
        if card.kind == .whatsNew {
            close()
            whatsNewStoryId = card.whatsNewStoryId ?? card.id
            return
        }
        PulseActionRouter.shared.route(card)
        close()
    }

    // MARK: Helpers

    private static func dateEyebrow() -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date())
    }
}

// MARK: - String → Identifiable box for fullScreenCover(item:)

private struct IdentifiableString: Identifiable { let id: String }

private extension Binding where Value == String? {
    func mappedToIdentifiable() -> Binding<IdentifiableString?> {
        Binding<IdentifiableString?>(
            get: { wrappedValue.map(IdentifiableString.init) },
            set: { wrappedValue = $0?.id }
        )
    }
}

#if DEBUG
#Preview("Amen Pulse") {
    AmenPulseSurfaceView(viewModel: AmenPulseViewModel(previewDigest: .previewSeed))
}
#endif
