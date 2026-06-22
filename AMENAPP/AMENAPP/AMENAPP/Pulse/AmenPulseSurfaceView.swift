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
import UIKit

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

    /// The user-steered card cap (lower-only). Loaded from PulsePrefs; defaults to the
    /// config maximum until prefs resolve. The client honors a LOWERED cap immediately so
    /// the "show fewer" control has visible effect even before the next server regeneration.
    @Published private(set) var userMaxCards: Int = PulseConfig.defaultMaxCards

    private let service: PulseService
    private var observeTask: Task<Void, Never>?

    init(service: PulseService, previewDigest: PulseDigest? = nil) {
        self.service = service
        _digest = Published(initialValue: previewDigest)
        _phase = Published(initialValue: previewDigest.map { $0.cards.isEmpty ? .empty : .loaded } ?? .loading)
    }

    convenience init(previewDigest: PulseDigest? = nil) {
        self.init(service: PulseService.shared, previewDigest: previewDigest)
    }

    deinit { observeTask?.cancel() }

    /// Cards to render (bounded + filtered). Terminus is appended by the view.
    var visibleCards: [PulseCard] {
        guard let digest else { return [] }
        if digest.sabbath { return digest.cards }   // single still card; no chips
        let bounded = Array(digest.cards.prefix(userMaxCards))
        return bounded.filter { chip == .all || $0.kind.chip == chip || $0.kind.chip == .all }
    }

    var isSabbath: Bool { digest?.sabbath ?? false }

    /// Loads the user-steered card cap from PulsePrefs and clamps it to the allowed
    /// range. Called on initial load and whenever the prefs sheet is dismissed so a
    /// lowered cap takes effect immediately. Resilient: any failure keeps the default.
    func loadPrefsCap() async {
        guard let prefs = try? await service.loadPrefs() else { return }
        let raw = prefs.maxCards ?? PulseConfig.defaultMaxCards
        userMaxCards = min(max(raw, PulseConfig.minUserCards), PulseConfig.defaultMaxCards)
    }

    func load() async {
        if digest != nil, phase == .loaded { return }   // preview-seeded
        phase = .loading
        await loadPrefsCap()
        do {
            let loaded = try await service.loadToday()
            #if DEBUG
            // In DEBUG on simulator there's no real digest yet — fall back to preview seed.
            if loaded.cards.isEmpty {
                digest = .previewSeed
                phase = .loaded
                return
            }
            #endif
            digest = loaded
            phase = loaded.cards.isEmpty ? .empty : .loaded
            startObserving()
        } catch {
            #if DEBUG
            digest = .previewSeed
            phase = .loaded
            #else
            phase = .failed(error.localizedDescription)
            #endif
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

    @MainActor
    init(viewModel: AmenPulseViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? AmenPulseViewModel())
    }

    private var ambientTint: Color {
        let key = viewModel.visibleCards.first?.hero.style ?? "verse"
        return PulseHeroStyle.resolve(key).tint
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [PulseInk.canvasTop, PulseInk.canvasBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
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
        .sheet(isPresented: $showPrefs, onDismiss: { Task { await viewModel.loadPrefsCap() } }) {
            PulsePrefsView()
        }
        .fullScreenCover(isPresented: $showArchive) {
            NavigationStack { WhatsNewArchiveView() }
        }
        .fullScreenCover(item: $whatsNewStoryId.mappedToIdentifiable()) { boxed in
            WhatsNewStoryView(storyId: boxed.id)
        }
    }

    private var ambientWash: some View {
        VStack {
            RadialGradient(colors: [ambientTint.opacity(0.55), Color(.systemGroupedBackground).opacity(0)],
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
                        chipBar
                        pulseStack
                    }
                }
            }
            .padding(.bottom, 40)
        }
    }

    private var header: some View {
        AmenPulseHeader(greeting: Self.greeting(),
                        subtitle: Self.dateSubtitle(),
                        onSettings: { showPrefs = true })
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }

    /// Floating glass filter chips. Selection narrows the bounded visible set; the editorial
    /// stack derives from the filtered cards, so picking a chip reshapes the whole surface.
    private var chipBar: some View {
        PulseGlassChipBar(selection: $viewModel.chip)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    // MARK: Redesigned ivory-glass stack

    /// The redesigned morning surface: editorial hero, status row, verse + reflection +
    /// community cards, then the remaining timely cards and the visible terminus.
    private var pulseStack: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let hero = heroCard {
                PulseHeroCard(
                    card: hero,
                    namespace: nil,
                    onBegin: { open(hero) },
                    onInfo: { open(hero) }
                )
            }

            PulseStatusRow(
                verseStatus: verseStatusText,
                prayerStatus: prayerStatusText,
                communityStatus: communityStatusText,
                onVerse: { if let v = verseCard { open(v) } },
                onPrayer: { routeFirst(.prayerFollowup) },
                onCommunity: { openCommunity() }
            )

            if let verse = verseCard {
                DailyVerseCard(
                    reference: verseReference(verse),
                    verse: verseText(verse),
                    translationChip: verseTranslation(verse),
                    onSave: { softHaptic() },
                    onShare: { shareCard(verse) },
                    onStudy: { open(verse) },
                    onListen: { softHaptic() }
                )
            }

            PulseReflectionCard(
                prompt: reflectionPrompt,
                onReflect: { if let c = reflectionAnchorCard { open(c) } },
                onPray: { routeFirst(.prayerFollowup) },
                onJournal: { softHaptic() },
                onDiscuss: { routeFirst(.spaceActivity) }
            )

            if !communityLines.isEmpty {
                CommunityPulseCard(lines: communityLines, onViewPulse: { openCommunity() })
            }

            secondaryCardStack
            terminusCard
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    /// Timely cards not already represented by the hero or verse card (event, occasion,
    /// space, prayer, what's new). These keep the matched-geometry expand behavior.
    private var secondaryCardStack: some View {
        let shownIds = Set([heroCard?.id, verseCard?.id].compactMap { $0 })
        let cards = viewModel.visibleCards.filter { $0.kind != .terminus && !shownIds.contains($0.id) }
        return LazyVStack(spacing: 18) {
            ForEach(cards) { card in
                PulseHeroCardView(
                    card: card,
                    namespace: morph,
                    isSourceForMorph: selectedCard == nil,
                    isHidden: selectedCard?.id == card.id,
                    onOpen: { open(card) }
                )
            }
        }
    }

    // MARK: Derived content (no model mutation — presentation only)

    private var heroCard: PulseCard? {
        viewModel.visibleCards.first(where: { $0.kind == .dailyBriefHero })
            ?? viewModel.visibleCards.first(where: { $0.kind == .scriptureHero })
            ?? viewModel.visibleCards.first(where: { $0.kind != .terminus })
    }

    private var verseCard: PulseCard? {
        viewModel.visibleCards.first(where: { $0.kind == .scriptureHero })
    }

    /// The card a "Reflect" tap opens into (verse if present, else the hero).
    private var reflectionAnchorCard: PulseCard? { verseCard ?? heroCard }

    private var prayerCount: Int {
        viewModel.visibleCards.filter { $0.kind == .prayerFollowup }.count
    }

    private var communityCount: Int {
        viewModel.visibleCards.filter { [.spaceActivity, .occasion, .churchEvent].contains($0.kind) }.count
    }

    private var verseStatusText: String {
        verseCard == nil ? String(localized: "—") : String(localized: "Ready")
    }

    private var prayerStatusText: String {
        prayerCount == 0 ? String(localized: "Quiet")
            : "\(prayerCount) " + (prayerCount == 1 ? String(localized: "prompt") : String(localized: "prompts"))
    }

    private var communityStatusText: String {
        communityCount == 0 ? String(localized: "Quiet")
            : "\(communityCount) " + (communityCount == 1 ? String(localized: "update") : String(localized: "updates"))
    }

    /// Community lines are COUNTS / non-private signals only — never quoted private content.
    private var communityLines: [CommunityPulseLine] {
        var lines: [CommunityPulseLine] = []
        let prayers = viewModel.visibleCards.filter { $0.kind == .prayerFollowup }.count
        if prayers > 0 {
            lines.append(.init(systemImage: "hands.sparkles",
                               text: "\(prayers) " + (prayers == 1 ? String(localized: "prayer request from your groups")
                                                                    : String(localized: "prayer requests from your groups"))))
        }
        if let space = viewModel.visibleCards.first(where: { $0.kind == .spaceActivity }) {
            lines.append(.init(systemImage: "bubble.left.and.bubble.right", text: space.title))
        }
        if let occasion = viewModel.visibleCards.first(where: { $0.kind == .occasion }) {
            lines.append(.init(systemImage: "heart", text: occasion.title))
        }
        if let church = viewModel.visibleCards.first(where: { $0.kind == .churchEvent }) {
            lines.append(.init(systemImage: "building.columns", text: church.title))
        }
        return lines
    }

    /// A gentle, non-doctrinal reflection question derived from today's verse/hero.
    private var reflectionPrompt: String {
        if let verse = verseCard, let subtitle = verse.subtitle, !subtitle.isEmpty {
            return String(localized: "Sit with this for a moment — where might it meet your day before the list, the inbox, the plans?")
        }
        return String(localized: "What would it look like to begin today with God before everything else?")
    }

    private func verseReference(_ card: PulseCard) -> String {
        // The scripture card's subtitle carries the reference; fall back to the eyebrow.
        if let subtitle = card.subtitle, let ref = subtitle.split(separator: "—").first {
            return ref.trimmingCharacters(in: .whitespaces)
        }
        return card.eyebrow
    }

    private func verseText(_ card: PulseCard) -> String { card.title }

    private func verseTranslation(_ card: PulseCard) -> String {
        if let subtitle = card.subtitle, let ref = subtitle.split(separator: "—").first {
            return ref.trimmingCharacters(in: .whitespaces)
        }
        return card.eyebrow
    }

    private func routeFirst(_ kind: PulseCardKind) {
        guard let card = viewModel.visibleCards.first(where: { $0.kind == kind }) else { return }
        if PulseActionRouter.shared.canRoute(card) {
            PulseActionRouter.shared.route(card)
        } else {
            open(card)
        }
    }

    private func openCommunity() {
        if let space = viewModel.visibleCards.first(where: { $0.kind == .spaceActivity }) {
            if PulseActionRouter.shared.canRoute(space) { PulseActionRouter.shared.route(space); return }
            open(space)
        } else {
            softHaptic()
        }
    }

    private func shareCard(_ card: PulseCard) {
        softHaptic()
        PulseActionRouter.shared.route(card)
    }

    private func softHaptic() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private static func greeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return String(localized: "Good morning, Friend.")
        case 12..<17: return String(localized: "Good afternoon, Friend.")
        case 17..<22: return String(localized: "Good evening, Friend.")
        default:      return String(localized: "Peace to you, Friend.")
        }
    }

    private static func dateSubtitle() -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date()) + " · " + String(localized: "Your daily rhythm is ready.")
    }

    private var terminusCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(Color(hex: "8A8A8E"))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color(.label).opacity(0.05)))
            Text("That’s everything for today.")
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(Color(.label))
            Text("Be still. Go be with people.")
                .font(.system(size: 14.5))
                .foregroundColor(Color(hex: "8A8A8E"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44).padding(.horizontal, 28)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
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
                .font(.system(size: 18, weight: .bold)).foregroundColor(Color(.label))
            Text("Pulse will be here tomorrow morning.")
                .font(.system(size: 14.5)).foregroundColor(Color(hex: "8A8A8E"))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 24)).foregroundColor(Color(hex: "8A8A8E"))
            Text("Pulse couldn’t load.").font(.system(size: 17, weight: .bold)).foregroundColor(Color(.label))
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

// MARK: - Filter chips

/// Floating glass filter chips (All · Spiritual · People · Church · Community). These are
/// chrome — floating controls over the canvas, not card surfaces — so the no-glass-on-glass
/// rule holds. Selection drives the bounded, filtered visible set.
private struct PulseGlassChipBar: View {
    @Binding var selection: PulseChip
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PulseChip.allCases) { chip in
                    chipButton(chip)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private func chipButton(_ chip: PulseChip) -> some View {
        let active = selection == chip
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.8)) {
                selection = chip
            }
        } label: {
            Text(chip.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(active ? .white : Color(.label))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(active ? Color(.label).opacity(0.86) : Color.white.opacity(0.62))
                        .background(Capsule().fill(.ultraThinMaterial))
                )
                .overlay(Capsule().stroke(Color.white.opacity(active ? 0 : 0.7), lineWidth: 0.5))
                .shadow(color: .black.opacity(active ? 0.18 : 0.06), radius: active ? 10 : 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
    }
}

#if DEBUG
#Preview("Amen Pulse") {
    AmenPulseSurfaceView(viewModel: AmenPulseViewModel(previewDigest: .previewSeed))
}
#endif
