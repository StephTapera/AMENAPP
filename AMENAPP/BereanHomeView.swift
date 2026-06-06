// BereanHomeView.swift
// AMEN App — Berean AI premium landing surface.
//
// Design: ChatGPT usability · Claude calmness · Safari bottom behavior · Apple restraint · AMEN brand
//
// Architecture:
//   BereanHomeView              — root container + aura + scroll + pinned composer
//   AmenHeroMarkView            — floating AMEN glass medallion (replaces B monogram)
//   SmartIntroPromptView        — eyebrow + adaptive question + support line
//   ModeSelectorView            — Scripture | Prayer | Deep Study pill selector
//   PromptSuggestionChipRow     — horizontally scrollable smart chip row
//   SmartContextRow             — mode-aware aura info card
//   BereanPremiumComposerBar    — pinned capsule composer overlay
//   ComposerPlusButton          — left circular plus button
//   ComposerInputField          — center capsule text field
//   ComposerPrimaryActionButton — right black action button (voice→send)

import SwiftUI
import Foundation
import FirebaseAuth
import Combine
import Network

// MARK: - BereanAuraMode

/// Three-mode aura system controlling ambient tints, chip hints, and composer tone.
enum BereanAuraMode: String, CaseIterable, Hashable {
    case scripture = "Scripture"
    case prayer    = "Prayer"
    case study     = "Deep Study"

    var personalityMode: BereanPersonalityMode {
        switch self {
        case .scripture: return .scholar
        case .prayer:    return .shepherd
        case .study:     return .scholar
        }
    }

    // Low-opacity ambient blobs behind the top zone and composer
    var auraColor1: Color {
        switch self {
        case .scripture: return Color(red: 0.98, green: 0.95, blue: 0.84)
        case .prayer:    return Color(red: 0.88, green: 0.88, blue: 0.98)
        case .study:     return Color(red: 0.90, green: 0.92, blue: 0.95)
        }
    }
    var auraColor2: Color {
        switch self {
        case .scripture: return Color(red: 0.99, green: 0.97, blue: 0.90)
        case .prayer:    return Color(red: 0.92, green: 0.90, blue: 0.99)
        case .study:     return Color(red: 0.93, green: 0.94, blue: 0.97)
        }
    }
    var auraColor3: Color {
        switch self {
        case .scripture: return Color(red: 0.96, green: 0.93, blue: 0.86)
        case .prayer:    return Color(red: 0.90, green: 0.91, blue: 0.99)
        case .study:     return Color(red: 0.88, green: 0.91, blue: 0.95)
        }
    }

    /// Subtle tint applied inside the composer capsule background
    var composerTint: Color {
        switch self {
        case .scripture: return Color(red: 0.99, green: 0.97, blue: 0.90).opacity(0.12)
        case .prayer:    return Color(red: 0.92, green: 0.90, blue: 0.99).opacity(0.14)
        case .study:     return Color(red: 0.90, green: 0.92, blue: 0.97).opacity(0.16)
        }
    }

    var contextLabel: String {
        switch self {
        case .scripture: return "Scripture aura"
        case .prayer:    return "Prayer aura"
        case .study:     return "Deep study aura"
        }
    }
    var contextHelper: String {
        switch self {
        case .scripture: return "Warm ivory tones respond to verse-led conversation."
        case .prayer:    return "Calmer indigo glass softens the whole conversation layer."
        case .study:     return "Cool graphite tones keep analytical reading focused and premium."
        }
    }
}

// MARK: - BereanHomeMode (kept for session compatibility)

enum BereanHomeMode: String, CaseIterable, Identifiable {
    case ask      = "Ask"
    case study    = "Study"
    case reflect  = "Reflect"
    case build    = "Build"
    case pray     = "Pray"
    case explore  = "Explore"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .ask:     return "bubble.left.and.bubble.right"
        case .study:   return "book.pages"
        case .reflect: return "sparkles"
        case .build:   return "hammer"
        case .pray:    return "hands.sparkles"
        case .explore: return "magnifyingglass"
        }
    }

    var personalityMode: BereanPersonalityMode {
        switch self {
        case .ask:     return .shepherd
        case .study:   return .scholar
        case .reflect: return .creator
        case .build:   return .builder
        case .pray:    return .shepherd
        case .explore: return .strategist
        }
    }

    var accentColor: Color {
        switch self {
        case .ask:     return Color(red: 0.30, green: 0.50, blue: 0.90)
        case .study:   return Color(red: 0.35, green: 0.30, blue: 0.90)
        case .reflect: return Color(red: 0.55, green: 0.30, blue: 0.85)
        case .build:   return Color(red: 0.85, green: 0.45, blue: 0.20)
        case .pray:    return Color(red: 0.30, green: 0.65, blue: 0.55)
        case .explore: return Color(red: 0.15, green: 0.55, blue: 0.75)
        }
    }
}

// MARK: - BereanHomeViewModel

@MainActor
final class BereanHomeViewModel: ObservableObject {
    @Published var selectedMode: BereanHomeMode = .ask
    @Published var auraMode: BereanAuraMode = .scripture
    @Published var recentSessions: [BereanChatSession] = []

    init() { loadRecentSessions() }

    func refreshSessions() {
        recentSessions = Array(BereanChatSessionManager.shared.sessions.prefix(8))
    }

    private func loadRecentSessions() {
        recentSessions = Array(BereanChatSessionManager.shared.sessions.prefix(8))
    }
}

// MARK: - Scroll Offset Preference Key

private struct BereanScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - BereanViewState

private enum BereanViewState {
    case empty
    case loading
    case populated
    case error(String)
    case emptyResult
    case offline
}

// MARK: - BereanHomeView

struct BereanHomeView: View {
    @StateObject private var viewModel          = BereanHomeViewModel()
    @StateObject private var resolver           = BereanContextResolver()
    @StateObject private var intelligenceEngine = BereanIntelligenceEngine()

    @State private var composerText    = ""
    @State private var scrollOffset: CGFloat = 0
    @State private var showNewChat     = false
    @State private var pendingQuery: String? = nil
    @State private var showSettings    = false
    @State private var composerFocused = false
    @State private var showDailyFormation = false

    // Chrome & container state
    @State private var showMenu = false
    @State private var showAvatarSheet = false
    @State private var showSafeShareSheet = false
    @State private var pendingShareDraft: BereanShareDraft? = nil
    @State private var showReflectionSheet = false
    @State private var pendingReflectionDraft: ReflectionDraft? = nil
    @State private var showActionTray = false
    @State private var showVoiceSession = false
    @State private var composerState = ComposerState()

    // View state & offline
    @State private var viewState: BereanViewState = .empty
    @State private var isOffline = false
    private let networkMonitor = NWPathMonitor()

    @Environment(\.dismiss) private var dismiss

    // 0 = resting, 1 = fully collapsed (scrolled down)
    private var collapseProgress: CGFloat {
        min(1, max(0, -scrollOffset / 110))
    }

    // Base background — very light warm gray
    private let bgColor = Color(red: 0.971, green: 0.971, blue: 0.969)

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    // Base background
                    bgColor.ignoresSafeArea()

                    // Ambient aura blobs (mode-aware, edge-only)
                    auraLayer

                    // Full-page scrollable content
                    scrollContent(safeBottom: proxy.safeAreaInsets.bottom)

                    // Bottom fade gradient — lets content read through
                    bottomFadeGradient

                    // Action tray — slides up above composer when open
                    if showActionTray {
                        AmenActionTray(isPresented: $showActionTray, onSelect: { action in
                            showActionTray = false
                            handleTrayAction(action)
                        })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 80 + proxy.safeAreaInsets.bottom)
                    }

                    // Smart action pills — shown when intelligence engine detects relevant context
                    SmartActionPills(
                        actions: intelligenceEngine.suggestedActions,
                        onSelect: handleSmartAction
                    )
                    .padding(.bottom, 88 + proxy.safeAreaInsets.bottom)
                    .padding(.horizontal, 16)
                    .animation(.spring(response: 0.35, dampingFraction: 0.78), value: intelligenceEngine.suggestedActions.map(\.id))

                    // Pinned composer — always above everything
                    premiumComposer(safeBottom: proxy.safeAreaInsets.bottom)

                    // Floating header — pinned to the top of the ZStack
                    VStack(spacing: 0) {
                        BereanLiquidGlassHeader(
                            onMenu: { showMenu = true },
                            onAvatar: { showAvatarSheet = true },
                            onPulse: { showDailyFormation = true },
                            showPulsePill: true
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        Spacer()
                    }
                }
                .ignoresSafeArea(.keyboard)
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Berean assistant")
        .task {
            resolver.resolve(
                mode: viewModel.selectedMode,
                lastSession: BereanChatSessionManager.shared.sessions.first
            )
        }
        .onAppear {
            viewModel.refreshSessions()
            viewState = viewModel.recentSessions.isEmpty ? .empty : .populated

            networkMonitor.pathUpdateHandler = { path in
                DispatchQueue.main.async {
                    isOffline = path.status != .satisfied
                    if isOffline {
                        viewState = .offline
                    } else {
                        viewState = viewModel.recentSessions.isEmpty ? .empty : .populated
                    }
                }
            }
            networkMonitor.start(queue: DispatchQueue(label: "BereanNetworkMonitor"))
        }
        .onDisappear {
            networkMonitor.cancel()
        }
        .onChange(of: viewModel.recentSessions.count) { _, count in
            guard !isOffline else { return }
            viewState = count == 0 ? .empty : .populated
        }
        .onChange(of: intelligenceEngine.isProcessing) { _, processing in
            guard !isOffline else { return }
            if processing {
                viewState = .loading
            } else {
                viewState = viewModel.recentSessions.isEmpty ? .empty : .populated
            }
        }
        .onChange(of: viewModel.selectedMode) { _, mode in
            withAnimation(.easeInOut(duration: 0.35)) {
                resolver.resolve(mode: mode, lastSession: viewModel.recentSessions.first)
            }
        }
        .onChange(of: composerText) { _, text in
            resolver.updateFromInput(text)
            intelligenceEngine.analyze(text: text)
        }
        .sheet(isPresented: $showNewChat) {
            if let q = pendingQuery, !q.isEmpty {
                BereanChatView(initialQuery: q)
                    .onAppear { composerText = ""; pendingQuery = nil }
            } else {
                BereanChatView()
            }
        }
        .sheet(isPresented: $showSettings) {
            BereanAISettingsView()
        }
        .sheet(isPresented: $showDailyFormation) {
            BereanDailyFormationView()
        }
        .sheet(isPresented: $showMenu) {
            BereanMenuSheet(
                isPresented: $showMenu,
                onNewChat: { showNewChat = true },
                onSelectSession: { _ in showNewChat = true }
            )
        }
        .sheet(isPresented: $showAvatarSheet) {
            BereanProfileSheet(isPresented: $showAvatarSheet)
        }
        .sheet(isPresented: $showSafeShareSheet) {
            if let draft = pendingShareDraft {
                SafeSharePrompt(
                    payload: draft,
                    onApprove: { showSafeShareSheet = false },
                    onCancel: {
                        showSafeShareSheet = false
                        pendingShareDraft = nil
                    }
                )
            }
        }
        .sheet(isPresented: $showReflectionSheet) {
            if let draft = pendingReflectionDraft {
                ReflectionSaveSheet(
                    draft: draft,
                    onSave: { showReflectionSheet = false },
                    onCancel: {
                        showReflectionSheet = false
                        pendingReflectionDraft = nil
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $showVoiceSession) {
            BereanVoiceSessionView(isPresented: $showVoiceSession) { text in
                composerText = text
            }
        }
    }

    // MARK: - Aura layer

    /// Low-opacity ambient color blobs. Edge-only, never floods the reading surface.
    private var auraLayer: some View {
        ZStack {
            Circle()
                .fill(viewModel.auraMode.auraColor1)
                .frame(width: 300, height: 300)
                .blur(radius: 72)
                .offset(x: -90, y: -220)

            Circle()
                .fill(viewModel.auraMode.auraColor2)
                .frame(width: 260, height: 260)
                .blur(radius: 72)
                .offset(x: 110, y: 60)

            Circle()
                .fill(viewModel.auraMode.auraColor3)
                .frame(width: 250, height: 250)
                .blur(radius: 72)
                .offset(x: -40, y: 280)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.55), value: viewModel.auraMode)
        .allowsHitTesting(false)
    }

    // MARK: - Full-page scroll content

    private func scrollContent(safeBottom: CGFloat) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .center, spacing: 0) {

                // Scroll offset anchor — zero-height geometry reader at top of content
                GeometryReader { geo in
                    Color.clear.preference(
                        key: BereanScrollOffsetKey.self,
                        value: geo.frame(in: .named("bereanHome")).minY
                    )
                }
                .frame(height: 0)

                // Hero mark
                AmenHeroMarkView()
                    .padding(.top, 28)
                    .opacity(1.0 - collapseProgress * 0.65)
                    .offset(y: -collapseProgress * 22)

                // Title + subtitle
                VStack(spacing: 10) {
                    Text("Berean")
                        .font(.system(size: 44, weight: .semibold))
                        .tracking(-2.2)
                        .foregroundColor(.black)

                    Text("Scripture, context, prayer, and wisdom\nin a calmer assistant designed for AMEN.")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(.black.opacity(0.50))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 20)
                .padding(.horizontal, 28)
                .opacity(1.0 - collapseProgress * 0.70)
                .offset(y: -collapseProgress * 18)

                // Smart intro prompt
                SmartIntroPromptView(hasText: !composerText.isEmpty)
                    .padding(.top, 30)
                    .padding(.horizontal, 22)
                    .opacity(1.0 - collapseProgress * 0.78)
                    .offset(y: -collapseProgress * 14)

                // Mode selector
                ModeSelectorView(selectedMode: $viewModel.auraMode)
                    .padding(.top, 18)
                    .opacity(1.0 - collapseProgress * 0.60)

                // Chip row
                PromptSuggestionChipRow(chips: resolver.chips) { chip in
                    composerText = chip.text + " "
                    composerFocused = true
                }
                .padding(.top, 14)
                .opacity(1.0 - collapseProgress * 0.55)
                .offset(y: -collapseProgress * 7)

                // Smart context row — fades out earlier than chips
                SmartContextRow(mode: viewModel.auraMode)
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .opacity(max(0, 1.0 - collapseProgress * 2.0))

                // Deep content — recent sessions or placeholder cards
                deepContentSection
                    .padding(.horizontal, 18)
                    .padding(.top, 14)

                // Clearance for pinned composer + safe area
                Spacer().frame(height: 130 + safeBottom)
            }
        }
        .coordinateSpace(name: "bereanHome")
        .onPreferenceChange(BereanScrollOffsetKey.self) { value in
            scrollOffset = value
        }
    }

    // MARK: - Deep content section

    private var deepContentSection: some View {
        VStack(spacing: 12) {
            if let item = resolver.resumeItem {
                SmartResumeRow(item: item) { openResume(item) }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            switch viewState {
            case .empty, .emptyResult:
                BereanAssistantEmptyState(onOpenPulse: { showNewChat = true })
                    .frame(minHeight: 200)

            case .loading:
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Berean is thinking…")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)

            case .populated:
                ForEach(Array(viewModel.recentSessions.prefix(5))) { session in
                    recentSessionCard(session)
                }

            case .error(let msg):
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(Color(red: 1.0, green: 0.72, blue: 0.10))
                    Text(msg)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try again") {
                        viewState = .empty
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(glassCardBackground)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(glassCardBackground)

            case .offline:
                VStack(spacing: 14) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("You're offline. Berean will reconnect automatically.")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(glassCardBackground)
            }
        }
    }

    private func placeholderCard(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Smart content layer \(index + 1)")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.black)
            Text("The whole page scrolls together while the composer stays pinned at the bottom like Safari chrome adapted for AMEN.")
                .font(.system(size: 14))
                .foregroundColor(.black.opacity(0.54))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(glassCardBackground)
    }

    private func recentSessionCard(_ session: BereanChatSession) -> some View {
        Button {
            pendingQuery = nil
            showNewChat = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.35, green: 0.30, blue: 0.90).opacity(0.10))
                        .frame(width: 40, height: 40)
                    Text(String(session.displayTitle.prefix(1)).uppercased())
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(red: 0.35, green: 0.30, blue: 0.90))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black)
                        .lineLimit(1)
                    if let preview = session.lastAssistantMessage?.content, !preview.isEmpty {
                        Text(preview)
                            .font(.system(size: 13))
                            .foregroundColor(.black.opacity(0.52))
                            .lineLimit(1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(session.relativeTimestamp)
                        .font(.system(size: 11))
                        .foregroundColor(.black.opacity(0.32))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.black.opacity(0.28))
                }
            }
            .padding(16)
            .background(glassCardBackground)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reusable glass card background

    private var glassCardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.48))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.62), Color.white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.65), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
    }

    // MARK: - Bottom fade gradient

    private var bottomFadeGradient: some View {
        VStack(spacing: 0) {
            Spacer()
            LinearGradient(
                colors: [
                    bgColor.opacity(0),
                    bgColor.opacity(0.88),
                    bgColor
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Pinned composer

    private func premiumComposer(safeBottom: CGFloat) -> some View {
        BereanPremiumComposerBar(
            text: $composerText,
            auraMode: viewModel.auraMode,
            collapseProgress: collapseProgress,
            isFocused: $composerFocused,
            onSend: submitComposer,
            onAttach: {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                    showActionTray = true
                }
            },
            onMic: { showVoiceSession = true }
        )
        .padding(.bottom, max(safeBottom, 16))
    }

    // MARK: - Actions

    private func submitComposer() {
        let query = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        pendingQuery = query
        composerFocused = false
        showNewChat = true
    }

    private func openResume(_ item: BereanResumeItem) {
        pendingQuery = nil
        showNewChat = true
    }

    // MARK: - Tray Action Handler

    private func handleTrayAction(_ action: TrayAction) {
        switch action {
        case .addBibleVerse:
            composerText = "Verse: "
            composerFocused = true
        case .addPrayerRequest:
            composerText = "Prayer: "
            composerFocused = true
        case .addChurchNotes:
            showNewChat = true
        case .addPhotoSafely:
            // Moderation gated — tray handles the gate
            break
        case .addVoiceNote:
            composerText = ""
            composerFocused = true
            // Voice recording is initiated via the BereanComposerBar mic button
        case .addSermonClip:
            showNewChat = true
        case .addReminder:
            composerText = "Remind me to "
            composerFocused = true
        case .shareToSpace:
            // Moderation gated — tray handles the gate
            break
        }
    }

    // MARK: - Smart Action Handler

    private func handleSmartAction(_ action: SmartAction) {
        switch action {
        case .explainVerse:
            let prefix = "Explain this verse: "
            if composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                composerText = prefix
            } else {
                composerText = composerText + " " + prefix
            }
            composerFocused = true

        case .createPrayer:
            if composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                composerText = "Write a prayer: "
            } else {
                composerText = "Write a prayer about: " + composerText
            }
            showNewChat = true

        case .summarizeNotes:
            composerText = "Summarize my notes: "
            showNewChat = true

        case .compareTranslations:
            composerText = "Compare translations: "
            composerFocused = true

        case .saveReflection:
            pendingReflectionDraft = ReflectionDraft(text: composerText)
            showReflectionSheet = true

        case .startDiscussion:
            showNewChat = true

        case .shareSafely:
            guard !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            pendingShareDraft = BereanShareDraft(text: composerText)
            showSafeShareSheet = true
        }
    }
}

// MARK: - AmenHeroMarkView

/// Floating AMEN glass medallion. Replaces the old "B" monogram.
/// Subtle float animation when reduce motion is off.
struct AmenHeroMarkView: View {
    @State private var floating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Outer glass plate
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.white.opacity(0.42))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.70), lineWidth: 0.75)
                )
                .shadow(color: .black.opacity(0.07), radius: 26, y: 8)

            // Inner gradient layer
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            Color.white.opacity(0.36),
                            Color(red: 1.0, green: 0.94, blue: 0.96).opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(8)

            // Top glare highlight
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.42))
                .frame(width: 38, height: 10)
                .blur(radius: 7)
                .offset(x: -5, y: -28)

            // AMEN wordmark
            Text("AMEN")
                .font(.system(size: 18, weight: .semibold))
                .tracking(3.2)
                .foregroundColor(.black.opacity(0.82))
        }
        .frame(width: 94, height: 94)
        .offset(y: floating ? -4 : 0)
        .scaleEffect(floating ? 1.014 : 1.0)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: 5.5).repeatForever(autoreverses: true)
            ) {
                floating = true
            }
        }
        .accessibilityLabel("AMEN")
        .accessibilityAddTraits(.isImage)
    }
}

// MARK: - SmartIntroPromptView

/// Eyebrow + large adaptive question + support line.
/// Question softly adapts when text is typed into the composer.
struct SmartIntroPromptView: View {
    let hasText: Bool

    private static let idlePrompts = [
        "What do you want help understanding today?",
        "Bring a passage, a prayer, or a hard question.",
        "Ask Berean to explore a verse or topic with you.",
    ]
    @State private var promptIndex = 0

    var body: some View {
        VStack(spacing: 10) {
            // Eyebrow
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.black.opacity(0.38))
                Text("AMEN INTELLIGENCE")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.8)
                    .foregroundColor(.black.opacity(0.38))
            }

            // Large adaptive question
            Text(hasText ? "Ask Berean anything." : Self.idlePrompts[promptIndex])
                .font(.system(size: 28, weight: .semibold))
                .tracking(-1.4)
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.32), value: hasText)
                .animation(.easeInOut(duration: 0.32), value: promptIndex)

            // Support line
            Text("Ask Berean to explain a verse, prayer prompt, or hard question.")
                .font(.system(size: 14))
                .foregroundColor(.black.opacity(0.46))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - ModeSelectorView

/// Three compact pill buttons: Scripture · Prayer · Deep Study.
/// Active pill is slightly brighter and more present.
struct ModeSelectorView: View {
    @Binding var selectedMode: BereanAuraMode

    var body: some View {
        HStack(spacing: 8) {
            ForEach(BereanAuraMode.allCases, id: \.self) { mode in
                modePill(mode)
            }
        }
        .padding(.horizontal, 18)
    }

    private func modePill(_ mode: BereanAuraMode) -> some View {
        let isSelected = selectedMode == mode
        return Button {
            withAnimation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.74))) {
                selectedMode = mode
            }
        } label: {
            Text(mode.rawValue)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isSelected ? .black : .black.opacity(0.50))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(Capsule().fill(Color.white.opacity(isSelected ? 0.72 : 0.28)))
                        .overlay(
                            Capsule().strokeBorder(
                                Color.white.opacity(isSelected ? 0.80 : 0.46),
                                lineWidth: 0.5
                            )
                        )
                        .shadow(color: .black.opacity(isSelected ? 0.06 : 0), radius: 8, y: 2)
                )
        }
        .buttonStyle(.plain)
        .animation(Motion.adaptive(.easeInOut(duration: 0.2)), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - SmartContextRow

/// Compact mode-aware card showing the active aura label + one-line description.
/// Fades out earlier than other elements on downward scroll.
struct SmartContextRow: View {
    let mode: BereanAuraMode

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(mode.contextLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black)
                Text(mode.contextHelper)
                    .font(.system(size: 13))
                    .foregroundColor(.black.opacity(0.52))
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.black.opacity(0.45))
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().fill(Color.white.opacity(0.50)))
                        .overlay(
                            Circle().strokeBorder(Color.white.opacity(0.58), lineWidth: 0.5)
                        )
                )
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.62), Color.white.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.65), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
        )
        .contentTransition(.opacity)
        .animation(.easeInOut(duration: 0.30), value: mode)
    }
}

// MARK: - BereanPremiumComposerBar

/// Pinned bottom composer. Three-part layout:
///   [plus] ─── [capsule input] ─── [action]
/// Shrinks very subtly on downward scroll; returns to full presence on upward intent.
struct BereanPremiumComposerBar: View {
    @Binding var text: String
    let auraMode: BereanAuraMode
    let collapseProgress: CGFloat
    @Binding var isFocused: Bool
    let onSend: () -> Void
    let onAttach: () -> Void
    let onMic: () -> Void

    @FocusState private var fieldFocused: Bool

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Composer shrinks subtly as user scrolls — Safari bottom feel
    private var composerScale: CGFloat { 1.0 - collapseProgress * 0.022 }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ComposerPlusButton(action: onAttach)

            ComposerInputField(
                text: $text,
                auraMode: auraMode,
                fieldFocused: $fieldFocused,
                onMic: onMic
            )

            ComposerPrimaryActionButton(hasText: hasText) {
                if hasText { onSend() } else { onMic() }
            }
        }
        .padding(.horizontal, 14)
        .scaleEffect(composerScale, anchor: .bottom)
        .onChange(of: isFocused) { _, focused in
            if fieldFocused != focused { fieldFocused = focused }
        }
        .onChange(of: fieldFocused) { _, focused in
            isFocused = focused
        }
    }
}

// MARK: - ComposerPlusButton

/// Left glass circle button — opens attachment/context sheet.
struct ComposerPlusButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.black)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().fill(Color.white.opacity(0.58)))
                        .overlay(
                            Circle().strokeBorder(Color.white.opacity(0.64), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Attach")
    }
}

// MARK: - ComposerInputField

/// Center capsule text field with inline mic icon (visible when empty).
/// Inherits a subtle aura tint from the active mode.
struct ComposerInputField: View {
    @Binding var text: String
    let auraMode: BereanAuraMode
    @FocusState.Binding var fieldFocused: Bool
    let onMic: () -> Void

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Background capsule layers
            Capsule().fill(.ultraThinMaterial)
            Capsule().fill(Color.white.opacity(0.72))
            Capsule().fill(auraMode.composerTint)
            Capsule().fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.88), Color.white.opacity(0.30)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            Capsule().strokeBorder(Color.white.opacity(0.38), lineWidth: 0.5)

            // Content row
            HStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    // Custom placeholder
                    if !hasText {
                        Text("Ask Berean")
                            .font(.system(size: 16))
                            .foregroundColor(.black.opacity(0.34))
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }

                    TextField("", text: $text, axis: .vertical)
                        .font(.system(size: 16))
                        .foregroundColor(.black)
                        .tint(.black)
                        .lineLimit(1...5)
                        .focused($fieldFocused)
                        .frame(maxWidth: .infinity)
                }

                // Inline mic — tappable, visible only when empty
                if !hasText {
                    Button(action: onMic) {
                        Image(systemName: "mic")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(.black.opacity(0.36))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.82)))
                    .padding(.leading, 6)
                    .accessibilityLabel("Voice input")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
        .frame(minHeight: 50)
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        .animation(.easeInOut(duration: 0.16), value: hasText)
        .animation(.easeInOut(duration: 0.30), value: auraMode)
    }
}

// MARK: - ComposerPrimaryActionButton

/// Right black circular button. Morphs between waveform (idle) and send arrow (has text).
struct ComposerPrimaryActionButton: View {
    let hasText: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.black)
                    .shadow(color: .black.opacity(0.14), radius: 10, y: 4)

                if hasText {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .transition(.opacity.combined(with: .scale(scale: 0.72)))
                } else {
                    Image(systemName: "waveform")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.white)
                        .transition(.opacity.combined(with: .scale(scale: 0.72)))
                }
            }
            .frame(width: 44, height: 44)
            .animation(.spring(response: 0.22, dampingFraction: 0.70), value: hasText)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hasText ? "Send" : "Voice input")
    }
}

// MARK: - SmartResumeRow

/// Compact single-line resume surface. Shown only when context resolver finds a resumable session.
struct SmartResumeRow: View {
    let item: BereanResumeItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(BereanColor.textSecondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.label)
                        .font(AMENFont.semiBold(13))
                        .foregroundColor(BereanColor.textPrimary)
                        .lineLimit(1)
                    if let sub = item.sublabel {
                        Text(sub)
                            .font(AMENFont.regular(11))
                            .foregroundColor(BereanColor.textTertiary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.60))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(BereanColor.glassStroke, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PromptSuggestionChipRow

/// Horizontally scrollable row of smart context chips. Animates on chip set changes.
struct PromptSuggestionChipRow: View {
    let chips: [BereanSmartChip]
    let onSelect: (BereanSmartChip) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    Button { onSelect(chip) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: chip.icon)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.black.opacity(0.65))
                            Text(chip.text)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.black.opacity(0.74))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay(Capsule().fill(Color.white.opacity(0.50)))
                                .overlay(
                                    Capsule().strokeBorder(Color.white.opacity(0.65), lineWidth: 0.5)
                                )
                                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
                        )
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 4)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.80), value: chips.map(\.id))
    }
}

// MARK: - BereanSeal (legacy — kept for any external usages)

struct BereanSeal: View {
    var body: some View {
        ZStack {
            Circle().fill(Color(red: 0.96, green: 0.94, blue: 0.90))
            Circle().strokeBorder(
                Color(red: 0.82, green: 0.74, blue: 0.60).opacity(0.55),
                lineWidth: 0.75
            )
            Text("B")
                .font(AMENFont.bold(20))
                .foregroundColor(Color(red: 0.42, green: 0.32, blue: 0.18))
        }
    }
}

// MARK: - BereanHomeComposerBar (legacy — kept for any external usages)

struct BereanHomeComposerBar: View {
    @Binding var text: String
    let placeholder: String
    @Binding var isFocused: Bool
    let onSend: () -> Void
    let onAttach: () -> Void

    @FocusState private var fieldFocused: Bool

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button(action: onAttach) {
                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(BereanColor.textSecondary)
                    )
            }
            .buttonStyle(.plain)

            HStack(alignment: .bottom, spacing: 8) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .font(AMENFont.regular(16))
                    .foregroundColor(BereanColor.textPrimary)
                    .lineLimit(1...5)
                    .focused($fieldFocused)
                    .tint(.black)
                    .frame(maxWidth: .infinity)

                if !hasText {
                    Image(systemName: "mic")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(Color.white.opacity(0.80)))
                    .overlay(Capsule().strokeBorder(BereanColor.glassStroke, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            )
            .animation(.easeInOut(duration: 0.18), value: hasText)

            Button {
                if hasText { onSend() }
            } label: {
                ZStack {
                    Circle()
                        .fill(hasText ? Color.black : Color(.secondarySystemBackground))
                        .frame(width: 36, height: 36)
                    Image(systemName: hasText ? "arrow.up" : "waveform")
                        .font(.system(size: hasText ? 14 : 13, weight: .semibold))
                        .foregroundColor(hasText ? .white : BereanColor.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.18), value: hasText)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .onChange(of: fieldFocused) { _, val in isFocused = val }
        .onChange(of: isFocused) { _, val in
            if val != fieldFocused { fieldFocused = val }
        }
    }
}

// MARK: - Preview

#Preview {
    BereanHomeView()
}
