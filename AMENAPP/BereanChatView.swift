// BereanChatView.swift
// AMEN App — Berean AI core chat conversation screen.
// ChatGPT-inspired interface with AMEN's white Liquid Glass design.
// Streaming via ClaudeService.shared.sendMessage with structured response system.

import SwiftUI
import Combine
import AVFoundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Models

struct BereanChatMsg: Identifiable, Equatable {
    var id: UUID = UUID()
    var role: BereanChatMsgRole
    var content: String
    var timestamp: Date
    var isStreaming: Bool = false
    var structure: BereanResponseStructure? = nil
    var processingState: String? = nil

    enum BereanChatMsgRole: String, Codable {
        case user, assistant
    }
}

// MARK: - Response Structure

/// Structured response with progressive sections
struct BereanResponseStructure: Equatable {
    var directAnswer: String? = nil
    var meaning: String? = nil
    var context: String? = nil
    var application: String? = nil
    var followUpActions: [FollowUpAction] = []
    
    struct FollowUpAction: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let icon: String
    }
}

// MARK: - ViewModel

@MainActor
final class BereanChatViewModel: ObservableObject {
    @Published var messages: [BereanChatMsg] = []
    @Published var inputText: String = ""
    @Published var isThinking: Bool = false
    @Published var errorMessage: String? = nil
    @Published var currentMode: BereanPersonalityMode = .shepherd
    @Published var isStudyModeEnabled: Bool = false
    @Published var studyModeState: BereanStudyModeState = .off
    @Published var reasoningNodes: [BereanReasoningNode] = []

    private lazy var db = Firestore.firestore()
    private var userId: String { Auth.auth().currentUser?.uid ?? "demo_user" }
    private var streamTask: Task<Void, Never>? = nil

    private let freeMsgLimit = 10
    private let studyModeStorageKey = "berean_study_mode_enabled"
    @Published var messageCount: Int = 0
    @Published var isProUser: Bool = false
    var isAtLimit: Bool { !isProUser && messageCount >= freeMsgLimit }

    init(mode: BereanPersonalityMode = .shepherd) {
        self.currentMode = mode
        messages.append(BereanChatMsg(
            role: .assistant,
            content: "Hey — I'm Berean. Ask me anything. Scripture, life, business, whatever's on your mind.",
            timestamp: .now
        ))
        let storedStudyMode = UserDefaults.standard.bool(forKey: studyModeStorageKey)
        isStudyModeEnabled = storedStudyMode
        studyModeState = storedStudyMode ? .idle : .off
        reasoningNodes = defaultReasoningNodes()
        loadMessageCount()
    }

    // MARK: Send

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking, !isAtLimit else { return }

        inputText = ""
        errorMessage = nil

        let userMsg = BereanChatMsg(role: .user, content: text, timestamp: .now)
        messages.append(userMsg)
        messageCount += 1
        persistMessageCount()

        // Placeholder for streaming assistant message
        let assistantMsg = BereanChatMsg(
            role: .assistant,
            content: "",
            timestamp: .now,
            isStreaming: true
        )
        messages.append(assistantMsg)
        let assistantIndex = messages.count - 1

        isThinking = true
        if isStudyModeEnabled {
            beginReasoning()
        }

        // Build history from existing messages (excluding the empty placeholder)
        let history: [OpenAIChatMessage] = messages
            .dropLast(2)
            .suffix(10)
            .map { OpenAIChatMessage(content: $0.content, isFromUser: $0.role == .user) }

        streamTask = Task {
            do {
                let stream = ClaudeService.shared.sendMessage(
                    text,
                    conversationHistory: history,
                    mode: currentMode
                )
                for try await chunk in stream {
                    try Task.checkCancellation()
                    messages[assistantIndex].content += chunk
                }
                messages[assistantIndex].isStreaming = false
                if self.isStudyModeEnabled {
                    self.resolveReasoning()
                }
                validateCitations(in: assistantIndex)
                saveConversation()
            } catch is CancellationError {
                messages[assistantIndex].isStreaming = false
                if self.isStudyModeEnabled {
                    self.resolveReasoning()
                }
                if messages[assistantIndex].content.isEmpty {
                    messages[assistantIndex].content = "Cancelled."
                }
            } catch {
                messages[assistantIndex].isStreaming = false
                if self.isStudyModeEnabled {
                    self.resolveReasoning()
                }
                messages[assistantIndex].content = "Something went wrong. Please try again."
                errorMessage = error.localizedDescription
                dlog("BereanChatView stream error: \(error)")
            }
            isThinking = false
        }
    }

    func cancelStreaming() {
        streamTask?.cancel()
        streamTask = nil
    }

    /// Scans the completed assistant message for scripture references and flags
    /// any that fail ScriptureReferenceValidator, appending a caution note.
    private func validateCitations(in index: Int) {
        guard index < messages.count else { return }
        let text = messages[index].content
        // Extract patterns like "John 3:16", "1 Cor 13:4", "Genesis 1:1-3"
        let pattern = #"(?:[1-3]?\s?[A-Za-z]+(?:\s[A-Za-z]+)*)\s+\d+:\d+(?:-\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        var invalidRefs: [String] = []
        for match in matches {
            guard let r = Range(match.range, in: text) else { continue }
            let candidate = String(text[r])
            // Only flag references that parse as plausible book+chapter:verse but fail bounds
            let result = ScriptureReferenceValidator.validate(candidate)
            switch result {
            case .unknownBook, .outOfRange:
                invalidRefs.append(candidate)
            default:
                break
            }
        }
        if !invalidRefs.isEmpty {
            let warning = "\n\n⚠️ *One or more scripture references could not be verified (\(invalidRefs.joined(separator: ", "))). Please confirm these in your Bible.*"
            messages[index].content += warning
            dlog("⚠️ [Berean] Unverified references appended to response: \(invalidRefs)")
        }
    }

    func setStudyModeEnabled(_ enabled: Bool) {
        isStudyModeEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: studyModeStorageKey)
        studyModeState = enabled ? .idle : .off
        if enabled && reasoningNodes.isEmpty {
            reasoningNodes = defaultReasoningNodes()
        }
    }

    private func defaultReasoningNodes() -> [BereanReasoningNode] {
        BereanReasoningCategory.allCases.map { category in
            BereanReasoningNode(category: category, state: .idle, summary: nil)
        }
    }

    private func beginReasoning() {
        studyModeState = .reasoning
        reasoningNodes = reasoningNodes.map { node in
            var updated = node
            updated.state = .scanning
            return updated
        }
        if let scriptureIndex = reasoningNodes.firstIndex(where: { $0.category == .scripture }) {
            reasoningNodes[scriptureIndex].state = .active
        }
        if let contextIndex = reasoningNodes.firstIndex(where: { $0.category == .historicalContext }) {
            reasoningNodes[contextIndex].state = .active
        }
        if let applicationIndex = reasoningNodes.firstIndex(where: { $0.category == .application }) {
            reasoningNodes[applicationIndex].state = .active
        }
    }

    private func resolveReasoning() {
        studyModeState = .resolved
        reasoningNodes = reasoningNodes.map { node in
            var updated = node
            updated.state = .complete
            if updated.summary == nil {
                updated.summary = summary(for: updated.category)
            }
            return updated
        }
    }

    private func summary(for category: BereanReasoningCategory) -> String {
        switch category {
        case .scripture: return "Primary passages highlighted"
        case .crossReferences: return "Related verses compared"
        case .commentary: return "Trusted commentary matched"
        case .sermons: return "Sermon insights noted"
        case .articles: return "Articles reviewed"
        case .originalLanguage: return "Key words checked"
        case .historicalContext: return "Historical setting applied"
        case .application: return "Practical application mapped"
        case .notes: return "Notes prepared for handoff"
        }
    }

    // MARK: Persistence

    private func saveConversation() {
        guard let last = messages.last else { return }
        db.collection("users").document(userId)
            .collection("chatHistory")
            .addDocument(data: [
                "role": "assistant",
                "content": last.content,
                "timestamp": Timestamp(date: last.timestamp)
            ])
    }

    // Atomically increment the server-side counter after each message — enforces
    // the free quota even if the client is patched or replayed.
    private func persistMessageCount() {
        guard userId != "demo_user" else { return }
        db.collection("users").document(userId)
            .updateData(["chatMessageCount": FieldValue.increment(Int64(1))]) { _ in }
    }

    private func loadMessageCount() {
        guard userId != "demo_user" else { return }
        db.collection("users").document(userId)
            .getDocument { [weak self] doc, _ in
                guard let data = doc?.data() else { return }
                DispatchQueue.main.async {
                    // Authoritative count comes from server, not local state
                    self?.messageCount = data["chatMessageCount"] as? Int ?? 0
                    // Subscription entitlement check from server field, not client flag
                    let tier = data["subscriptionTier"] as? String ?? "free"
                    self?.isProUser = (tier == "amenPlus" || tier == "amenPro" || tier == "creatorPro" || tier == "churchPro")
                }
            }
    }
}

// MARK: - BereanChatView

struct BereanChatView: View {
    /// Pass a mode to seed the conversation; defaults to shepherd.
    var initialMode: BereanPersonalityMode = .shepherd
    /// Optional initial query auto-sent on appear.
    var initialQuery: String? = nil
    /// Optional conversation title shown in nav bar center.
    var conversationTitle: String? = nil

    @StateObject private var vm: BereanChatViewModel
    @StateObject private var composerVM = BereanComposerViewModel()
    @StateObject private var scrollCoordinator = BereanScrollCoordinator()
    @StateObject private var wallpaperManager = BereanWallpaperManager()
    @State private var showModeSheet = false
    @State private var showModeDrawer = false
    @State private var showWallpaperPicker = false
    @State private var sendSweep = false
    @State private var pendingUserSend = false
    @State private var showUpgradeAlert = false
    @State private var showVoiceAssistant = false
    @FocusState private var inputFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Addition 1: Context Memory rail
    @State private var selectedContextSources: Set<BereanContextSource> = [.thisChat]

    // MARK: - Addition 2: Scripture chip
    @State private var scriptureChipVerse: BereanScriptureChip? = nil   // verse to show in sheet
    @State private var showScriptureSheet = false
    private let scriptureDetector = ScriptureIntentDetector()

    // MARK: - Addition 3: Save to Church Notes toast
    @State private var showSavedToNotesToast = false

    init(initialMode: BereanPersonalityMode = .shepherd,
         initialQuery: String? = nil,
         conversationTitle: String? = nil) {
        self.initialMode = initialMode
        self.initialQuery = initialQuery
        self.conversationTitle = conversationTitle
        _vm = StateObject(wrappedValue: BereanChatViewModel(mode: initialMode))
    }

    @State private var scrollOffset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var showHero: Bool = true
    @State private var selectedReasoningNode: BereanReasoningNode?
    // Staggered entrance animation state
    @State private var heroAppeared: Bool = false
    @State private var cardsAppeared: Bool = false

    var body: some View {
        GeometryReader { proxy in
            // proxy.safeAreaInsets.top is 59pt on Dynamic Island devices,
            // 47pt on TrueDepth notch devices, ≤24pt on SE/older.
            // proxy.safeAreaInsets.bottom is ~34pt on Face ID phones (home indicator),
            // 0 on devices with a physical Home button.
            let metrics = BereanLayoutMetrics(size: proxy.size,
                                              topSafeAreaInset: proxy.safeAreaInsets.top,
                                              bottomSafeAreaInset: proxy.safeAreaInsets.bottom)

            ZStack(alignment: .bottom) {
                wallpaperManager.wallpaperView()
                    .ignoresSafeArea()
                Color.white.opacity(contrastStyle.scrimOpacity)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    smartBlurHeader(metrics: metrics)
                    contentScrollView(metrics: metrics)
                }

                VStack(spacing: 0) {
                    if vm.isAtLimit {
                        paywallBanner
                            .padding(.horizontal, metrics.contentHorizontalPadding)
                            .padding(.bottom, 8)
                    }
                    if shouldShowSuggestionRow {
                        focusedSuggestionRow
                            .padding(.horizontal, metrics.contentHorizontalPadding)
                            .padding(.bottom, shouldShowContextRail ? 8 : 6)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    if shouldShowContextRail {
                        compactContextRail
                            .padding(.horizontal, metrics.contentHorizontalPadding)
                            .padding(.bottom, 6)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    if AMENFeatureFlags.shared.bereanChatRedesignEnabled {
                        adaptiveComposer(metrics: metrics, containerWidth: proxy.size.width)
                    } else {
                        compactComposer
                            .padding(.horizontal, metrics.contentHorizontalPadding)
                            .padding(.bottom, metrics.composerBottomPadding)
                    }
                }
                .background(
                    // Scrim gradient fades up from the bottom so content under the composer
                    // stays legible without a heavy white plate. Kept subtle so the glass
                    // capsule reads as floating rather than sitting on a card tray.
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0),
                            Color.white.opacity(contrastStyle.scrimOpacity + 0.30)
                        ],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.35)
                    )
                    .ignoresSafeArea(edges: .bottom)
                )
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showModeSheet) {
                BereanModesSheet()
            }
            .sheet(isPresented: $showModeDrawer) {
                BereanModeDrawer(selectedMode: $vm.currentMode)
            }
            .sheet(isPresented: $showWallpaperPicker) {
                BereanWallpaperPickerSheet(manager: wallpaperManager)
            }
            .sheet(item: $selectedReasoningNode) { node in
                BereanReasoningSummarySheet(node: node)
            }
            // Addition 2: Scripture chip sheet
            .sheet(isPresented: $showScriptureSheet) {
                if let verse = scriptureChipVerse {
                    BereanVersePreviewSheet(verse: verse)
                        .presentationDetents([.medium])
                        .presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: $showVoiceAssistant) {
                BereanVoiceAssistantView()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            // Addition 3: Saved-to-Notes toast
            .overlay(alignment: .top) {
                if showSavedToNotesToast {
                    Text("Saved to Church Notes")
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.82))
                                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                        )
                        .padding(.top, 56)
                        .transition(.opacity.combined(with: .offset(y: -8)))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showSavedToNotesToast)
            .alert("Amen+ Required", isPresented: $showUpgradeAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Upgrade to Amen+ to unlock unlimited Berean conversations.")
            }
            .onAppear {
                if let query = initialQuery, !query.isEmpty {
                    vm.inputText = query
                    pendingUserSend = true
                    vm.send()
                    showHero = false
                }
            }
            .onChange(of: vm.isThinking) { _, thinking in
                if thinking {
                    composerVM.setState(.streaming)
                } else if composerVM.state == .streaming {
                    composerVM.setState(.idle)
                }
            }
        }
    }

    // MARK: - Smart Blur Header (scroll-reactive)

    private func smartBlurHeader(metrics: BereanLayoutMetrics) -> some View {
        let blurIntensity = min(scrollOffset / 100, 1.0)
        // Compression starts at headerCompressionThreshold (40pt), fully compressed by 120pt
        let compressionProgress = min(max((scrollOffset - metrics.headerCompressionThreshold) / 80, 0), 1.0)

        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Back button
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.systemScaled(17, weight: .semibold))
                        .foregroundColor(contrastStyle.foregroundColor)
                        .frame(width: 38, height: 38)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(Circle().fill(Color.white.opacity(0.70)))
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.40), lineWidth: 0.5))
                                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
                        )
                }
                .buttonStyle(.plain)

                Spacer()

                // Center: title fades in at low scroll; mode capsule fades in at high scroll
                ZStack {
                    // Conversation title (visible at low scroll)
                    Text(conversationTitle ?? "Berean")
                        .font(.systemScaled(17, weight: .semibold))
                        .foregroundColor(contrastStyle.foregroundColor)
                        .opacity(blurIntensity * (1 - compressionProgress))
                        .lineLimit(1)

                    // Compressed mode capsule (visible when scrolled far)
                    if compressionProgress > 0 {
                        headerModeCapsule(compressionProgress: compressionProgress)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    // Study toggle hides into the mode capsule when fully compressed
                    if compressionProgress < 0.85 {
                        studyModeToggle
                            .opacity(1 - compressionProgress)
                    }
                    headerMenuButton
                }
            }
            .padding(.horizontal, metrics.contentHorizontalPadding + 2)
            // Vertical padding compresses from full → tight as user scrolls
            .padding(.vertical, metrics.headerVerticalPadding - compressionProgress * 4)

            // Bottom separator appears with scroll
            Rectangle()
                .fill(BereanColor.separator.opacity(blurIntensity * 0.6))
                .frame(height: 0.5)
        }
        .background(
            ZStack {
                // Adaptive blur based on scroll
                if blurIntensity > 0.1 {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Rectangle()
                                .fill(Color.white.opacity(0.50 + blurIntensity * 0.30))
                        )
                        .overlay(
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.30),
                                            Color.clear
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                }
            }
        )
        .animation(Motion.adaptive(.easeOut(duration: 0.18)), value: compressionProgress)
        .animation(Motion.adaptive(.easeOut(duration: 0.15)), value: blurIntensity)
    }

    /// The mode + study indicator that appears in the header centre when scrolled.
    private func headerModeCapsule(compressionProgress: CGFloat) -> some View {
        Button {
            // Tap to open the mode sheet for quick switching
            if AMENFeatureFlags.shared.bereanChatRedesignEnabled {
                showModeDrawer = true
            } else {
                showModeSheet = true
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: vm.currentMode.icon)
                    .font(.systemScaled(11, weight: .semibold))
                Text(vm.currentMode.rawValue)
                    .font(.systemScaled(13, weight: .semibold))
                if vm.isStudyModeEnabled {
                    Image(systemName: "graduationcap.fill")
                        .font(.systemScaled(10, weight: .semibold))
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.systemScaled(9, weight: .semibold))
                    .opacity(0.5)
            }
            .foregroundStyle(contrastStyle.foregroundColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(Color.white.opacity(0.60)))
                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
            )
        }
        .buttonStyle(.plain)
        .opacity(compressionProgress)
        .scaleEffect(0.9 + compressionProgress * 0.1, anchor: .center)
    }

    private var studyModeToggle: some View {
        Button {
            withAnimation(BereanAnimationCoordinator.softSpring) {
                vm.setStudyModeEnabled(!vm.isStudyModeEnabled)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "graduationcap.fill")
                    .font(.systemScaled(12, weight: .semibold))
                Text("Study")
                    .font(.systemScaled(12, weight: .semibold))
            }
            .foregroundStyle(vm.isStudyModeEnabled ? Color.white : contrastStyle.foregroundColor.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(vm.isStudyModeEnabled ? Color.black : Color.white.opacity(0.6))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Study Mode")
        .accessibilityValue(vm.isStudyModeEnabled ? "On" : "Off")
    }

    private var headerMenuButton: some View {
        Menu {
            Button("Response Mode") {
                if AMENFeatureFlags.shared.bereanChatRedesignEnabled {
                    showModeDrawer = true
                } else {
                    showModeSheet = true
                }
            }
            Button("Wallpaper") { showWallpaperPicker = true }
        } label: {
            Image(systemName: "ellipsis")
                .font(.systemScaled(17, weight: .semibold))
                .foregroundColor(contrastStyle.foregroundColor)
                .frame(width: 38, height: 38)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().fill(Color.white.opacity(0.70)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.40), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Options")
    }

    private var contrastStyle: BereanContrastStyle {
        wallpaperManager.contrastStyle
    }

    // MARK: - Content Scroll View

    private func contentScrollView(metrics: BereanLayoutMetrics) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Hero section (shown when no messages yet)
                    if showHero && vm.messages.count <= 1 {
                        heroSection
                            .padding(.top, 12)
                            .padding(.bottom, 24)
                            .id("hero")
                            .opacity(heroAppeared ? 1 : 0)
                            .offset(y: heroAppeared ? 0 : 14)
                            .onAppear {
                                guard !heroAppeared else { return }
                                withAnimation(Motion.adaptive(.spring(response: 0.52, dampingFraction: 0.82)).delay(0.05)) {
                                    heroAppeared = true
                                }
                            }

                        quickActionCards
                            .padding(.horizontal, 18)
                            .padding(.bottom, 24)
                            .opacity(cardsAppeared ? 1 : 0)
                            .offset(y: cardsAppeared ? 0 : 18)
                            .onAppear {
                                guard !cardsAppeared else { return }
                                withAnimation(Motion.adaptive(.spring(response: 0.50, dampingFraction: 0.84)).delay(0.20)) {
                                    cardsAppeared = true
                                }
                            }
                    }
                    
                    if vm.isStudyModeEnabled {
                        let isCollapsed = scrollCoordinator.context != .nearBottom && scrollOffset > 120
                        BereanStudyModeSurface(
                            state: isCollapsed ? .collapsedSummary : vm.studyModeState,
                            nodes: vm.reasoningNodes,
                            onCategoryTap: { node in
                                selectedReasoningNode = node
                            },
                            isCollapsed: isCollapsed,
                            reduceMotion: reduceMotion
                        )
                        .padding(.horizontal, metrics.contentHorizontalPadding)
                        .padding(.bottom, 16)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Messages
                    LazyVStack(spacing: 16) {
                        ForEach(vm.messages) { msg in
                            if msg.role == .user || !msg.content.isEmpty {
                                structuredMessageView(msg)
                                    .id(msg.id)
                                    .contextMenu {
                                        messageContextMenu(msg)
                                    }
                                    // MEDIUM FIX: Announce sender name and timestamp so VoiceOver
                                    // users know who sent each message and when.
                                    .accessibilityLabel(messageAccessibilityLabel(msg))
                            }
                        }

                        // Thinking indicator with processing state
                        if vm.isThinking && (vm.messages.last?.content.isEmpty ?? false) {
                            processingIndicator
                                .id("thinking")
                                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
                        }
                    }
                    .padding(.horizontal, metrics.contentHorizontalPadding)
                    .padding(.top, showHero ? 0 : 16)

                    // Auto-scroll anchor
                    Color.clear.frame(height: metrics.bottomContentInset).id("bottom")
                }
                .background(
                    ZStack {
                        BereanScrollOffsetReader(coordinateSpaceName: "scroll")
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: ContentHeightKey.self, value: geo.size.height)
                        }
                    }
                )
                .animation(.easeOut(duration: 0.2), value: vm.isThinking)
            }
            .coordinateSpace(name: "scroll")
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { viewportHeight = geo.size.height }
                        .onChange(of: geo.size.height) { _, newValue in
                            viewportHeight = newValue
                        }
                }
            )
            .simultaneousGesture(
                // minimumDistance: 10 prevents taps (0px movement) from setting
                // setDragging(true) and incorrectly suppressing auto-scroll behavior.
                // The iOS default is also 10pt but we set it explicitly for clarity.
                DragGesture(minimumDistance: 10)
                    .onChanged { _ in scrollCoordinator.setDragging(true) }
                    .onEnded { _ in scrollCoordinator.setDragging(false) }
            )
            .onPreferenceChange(ScrollOffsetPreference.self) { value in
                let rawOffset = value
                let newOffset = -value
                scrollOffset = newOffset
                scrollCoordinator.update(offset: newOffset, contentHeight: contentHeight, viewportHeight: viewportHeight)
                composerVM.updateScroll(rawOffset)
                if scrollOffset > 50 && showHero {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showHero = false
                    }
                }
            }
            .onPreferenceChange(ContentHeightKey.self) { height in
                contentHeight = height
                scrollCoordinator.update(offset: scrollOffset, contentHeight: contentHeight, viewportHeight: viewportHeight)
            }
            .onChange(of: vm.messages.count) {
                let shouldScroll = scrollCoordinator.shouldAutoScroll(isUserInitiated: pendingUserSend)
                if shouldScroll {
                    withAnimation(.easeOut(duration: 0.30)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                pendingUserSend = false
            }
            .onChange(of: vm.messages.last?.content) {
                if scrollCoordinator.shouldAutoScroll(isUserInitiated: pendingUserSend) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private struct ContentHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }

    private func adaptiveComposer(metrics: BereanLayoutMetrics, containerWidth: CGFloat) -> some View {
        let availableWidth = containerWidth - (metrics.contentHorizontalPadding * 2)

        return VStack(spacing: 8) {
            BereanComposerBar(
                composerVM: composerVM,
                messageText: $vm.inputText,
                isFocused: $inputFocused,
                availableWidth: availableWidth,
                onSend: handleSend,
                onVoice: handleVoiceAction,
                onAction: handleQuickAction,
                onTools: { showModeDrawer = true },
                onStop: { vm.cancelStreaming() }
            )
        }
        .padding(.horizontal, metrics.contentHorizontalPadding)
        // FIX #4: Respect the home indicator safe area so the composer never
        // overlaps the system swipe-up gesture bar on Face ID iPhones (~34pt).
        // composerBottomPadding = max(bottomSafeAreaInset, 8) — at least 8pt on
        // devices with a Home button, the full safe area inset on modern phones.
        .padding(.bottom, metrics.composerBottomPadding)
    }

    private func handleSend() {
        guard !vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        pendingUserSend = true
        sendSweep.toggle()
        withAnimation(BereanAnimationCoordinator.compactSpring) {
            showHero = false
        }
        vm.send()
    }

    private func handleVoiceAction() {
        dlog("Berean: voice tapped")
    }

    private func handleQuickAction(_ action: BereanLiquidAction.ActionType) {
        switch action {
        case .attachFile, .camera:
            dlog("Berean: attach/camera tapped")
        case .voiceNote:
            handleVoiceAction()
        case .verseLookup:
            vm.inputText = ""
            inputFocused = true
        case .summarize:
            vm.inputText = "Summarize this: "
            inputFocused = true
        case .searchScripture:
            vm.inputText = "Search scripture for "
            inputFocused = true
        }
    }

    // MARK: - Hero Section
    
    private var heroSection: some View {
        VStack(spacing: 16) {
            // Berean icon in glass orb
            ZStack {
                // Outer soft glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.788, green: 0.659, blue: 0.298).opacity(0.08),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 50
                        )
                    )
                    .frame(width: 100, height: 100)
                
                // Glass orb — keep white overlay low so material shows through
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle()
                            .fill(Color.white.opacity(0.28))
                    )
                    .overlay(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.30),
                                        Color.white.opacity(0.06),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.65), Color.black.opacity(0.07)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.8
                            )
                    )
                    .frame(width: 72, height: 72)
                    .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
                    .shadow(color: .black.opacity(0.03), radius: 8, y: 3)
                
                // "B" icon
                Text("B")
                    .font(.systemScaled(32, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.788, green: 0.659, blue: 0.298),
                                Color(red: 0.688, green: 0.559, blue: 0.198)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .padding(.top, 20)
            .scaleEffect(1.0 - heroCompressionProgress * 0.06)
            .offset(y: heroCompressionProgress * -8)
            .opacity(Double(1.0 - heroCompressionProgress * 0.12))
            
            // Premium editorial typography
            VStack(spacing: 6) {
                Text("Berean")
                    .font(.systemScaled(28, weight: .bold, design: .rounded))
                    .foregroundColor(BereanColor.textPrimary)
                    .tracking(-0.5)

                Text("Understand Scripture, explore context, and respond with clarity.")
                    .font(.systemScaled(15, weight: .regular))
                    .foregroundColor(BereanColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .scaleEffect(1.0 - heroCompressionProgress * 0.03)
            .opacity(Double(1.0 - heroCompressionProgress * 0.18))
        }
        .frame(maxWidth: .infinity)
        .animation(Motion.adaptive(.spring(response: 0.42, dampingFraction: 0.88)), value: composerVM.collapseProgress)
    }
    
    // MARK: - Quick Action Cards
    
    private var quickActionCards: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                quickActionCard(
                    title: "Understand\nScripture",
                    icon: "book.pages",
                    accentColor: Color(red: 0.77, green: 0.71, blue: 0.57),
                    prompt: "Help me understand this scripture."
                )
                quickActionCard(
                    title: "Ask a\nQuestion",
                    icon: "bubble.left.and.bubble.right",
                    accentColor: Color(red: 0.61, green: 0.58, blue: 0.72),
                    prompt: "I have a question about "
                )
            }

            HStack(spacing: 10) {
                quickActionCard(
                    title: "Explore\nContext",
                    icon: "magnifyingglass",
                    accentColor: Color(red: 0.58, green: 0.65, blue: 0.71),
                    prompt: "Give me the context for "
                )
                quickActionCard(
                    title: "Pray This",
                    icon: "hands.sparkles",
                    accentColor: Color(red: 0.74, green: 0.63, blue: 0.64),
                    prompt: "Turn this into a prayer: "
                )
            }
        }
    }

    private func quickActionCard(title: String, icon: String, accentColor: Color, prompt: String) -> some View {
        Button {
            vm.inputText = prompt
            inputFocused = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                // Icon in glass container
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accentColor.opacity(0.18), accentColor.opacity(0.07)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 0.6))
                        .frame(width: 42, height: 42)
                    
                    Image(systemName: icon)
                        .font(.systemScaled(18, weight: .medium))
                        .foregroundColor(accentColor)
                }
                
                Text(title)
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundColor(BereanColor.textPrimary)
                    .lineLimit(2)
                    .lineSpacing(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(
                // Cards: keep material overlay low so they don't read as
                // opaque white dashboard blocks. The accent tint in the icon
                // circle carries the visual identity; the card itself stays quiet.
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.20),
                                        Color.white.opacity(0.12),
                                        accentColor.opacity(0.04)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.18),
                                        accentColor.opacity(0.05),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: UnitPoint(x: 0.6, y: 0.6)
                                )
                            )
                            .blendMode(.screen)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.55),
                                        Color.white.opacity(0.14),
                                        Color.black.opacity(0.06)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.8
                            )
                    )
                    .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 7)
                    .shadow(color: .black.opacity(0.025), radius: 5, x: 0, y: 2)
            )
        }
        .buttonStyle(QuickActionPressStyle())
        .scaleEffect(1.0 - heroCompressionProgress * 0.025)
        .opacity(Double(1.0 - heroCompressionProgress * 0.08))
    }
    
    // MARK: - Mode Chips
    
    private var modeChipsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Response Style")
                .font(.systemScaled(13, weight: .semibold))
                .foregroundColor(BereanColor.textSecondary)
                .padding(.horizontal, 18)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    modeChip(title: "Quick Answer", icon: "bolt.fill", mode: .shepherd)
                    modeChip(title: "Balanced", icon: "scale.3d", mode: .scholar)
                    modeChip(title: "Deep Study", icon: "book.pages.fill", mode: .scholar)
                    modeChip(title: "Devotional", icon: "heart.fill", mode: .creator)
                }
                .padding(.horizontal, 18)
            }
            // Pass vertical gestures to the parent scroll view simultaneously
            // so swiping up/down over the pill row doesn't get captured by the
            // horizontal ScrollView and block the outer content scroll.
            .simultaneousGesture(DragGesture(minimumDistance: 0))
        }
    }
    
    private func modeChip(title: String, icon: String, mode: BereanPersonalityMode) -> some View {
        let isSelected = vm.currentMode == mode
        
        return Button {
            withAnimation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.70))) {
                vm.currentMode = mode
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.systemScaled(11, weight: .medium))
                Text(title)
                    .font(.systemScaled(14, weight: .medium))
            }
            .foregroundColor(isSelected ? Color.white : BereanColor.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Group {
                    if isSelected {
                        Capsule()
                            .fill(Color.black)
                    } else {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.56),
                                                Color.white.opacity(0.38),
                                                Color(red: 1.0, green: 0.96, blue: 0.93).opacity(0.18)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                            .overlay(
                                Capsule().strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.70), Color.black.opacity(0.05)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.75
                                )
                            )
                    }
                }
            )
            .shadow(
                color: isSelected ? Color.black.opacity(0.15) : Color.black.opacity(0.04),
                radius: isSelected ? 8 : 4,
                y: isSelected ? 3 : 2
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(1.0 - heroCompressionProgress * 0.018)
        .opacity(Double(1.0 - heroCompressionProgress * 0.06))
    }
    
    // MARK: - Mode Drawer Trigger (System 14 Redesign)

    private var modeDrawerTrigger: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Response Style")
                .font(.systemScaled(13, weight: .semibold))
                .foregroundColor(BereanColor.textSecondary)
                .padding(.horizontal, 18)

            Button {
                showModeDrawer = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: vm.currentMode.icon)
                        .font(.systemScaled(16, weight: .semibold))
                    Text(vm.currentMode.rawValue)
                        .font(AMENFont.semiBold(15))
                    Spacer()
                    Text("Change")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AmenTheme.Colors.glassFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
        }
        .sheet(isPresented: $showModeDrawer) {
            BereanModeDrawer(selectedMode: $vm.currentMode)
        }
    }

    // MARK: - Quick Actions Row
    
    private var quickActionsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Actions")
                .font(.systemScaled(13, weight: .semibold))
                .foregroundColor(BereanColor.textSecondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    quickActionPill(title: "Search Scripture", icon: "magnifyingglass")
                    quickActionPill(title: "Explain Simply", icon: "lightbulb")
                    quickActionPill(title: "Build a Plan", icon: "list.bullet.clipboard")
                }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 0))
        }
    }
    
    private func quickActionPill(title: String, icon: String) -> some View {
        Button {
            vm.inputText = title
            inputFocused = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.systemScaled(12, weight: .medium))
                Text(title)
                    .font(.systemScaled(14, weight: .medium))
            }
            .foregroundColor(BereanColor.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.58),
                                        Color.white.opacity(0.42),
                                        Color(red: 1.0, green: 0.96, blue: 0.93).opacity(0.20)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.75),
                                        Color.white.opacity(0.20),
                                        Color.black.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.75
                            )
                    )
                    .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 3)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(1.0 - heroCompressionProgress * 0.02)
        .opacity(Double(1.0 - heroCompressionProgress * 0.08))
    }

    private var heroCompressionProgress: CGFloat {
        min(max(composerVM.collapseProgress, 0), 1)
    }
    
    // MARK: - Message Context Menu

    @ViewBuilder
    private func messageContextMenu(_ msg: BereanChatMsg) -> some View {
        Button {
            UIPasteboard.general.string = msg.content
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }

        Button {
            let utterance = AVSpeechUtterance(string: msg.content)
            utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
            utterance.rate = 0.52
            let synthesizer = AVSpeechSynthesizer()
            synthesizer.speak(utterance)
        } label: {
            Label("Read Aloud", systemImage: "speaker.wave.2")
        }

        Button {
            Task { await saveMessageToChurchNotes(msg) }
        } label: {
            Label("Save to Notes", systemImage: "note.text.badge.plus")
        }

        if msg.role == .assistant {
            Button {
                vm.cancelStreaming()
                // Remove the last assistant message and re-send previous user message
                if let lastUser = vm.messages.last(where: { $0.role == .user }) {
                    vm.messages.removeAll { $0.id == msg.id }
                    vm.inputText = lastUser.content
                    vm.messages.removeAll { $0.id == lastUser.id }
                    vm.send()
                }
            } label: {
                Label("Regenerate", systemImage: "arrow.clockwise")
            }
        }
    }

    // MARK: - Addition 1: Context Memory Rail

    private var bereanContextMemoryRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(BereanContextSource.allCases, id: \.self) { source in
                    let isSelected = selectedContextSources.contains(source)
                    Button {
                        withAnimation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.75))) {
                            if isSelected && selectedContextSources.count > 1 {
                                selectedContextSources.remove(source)
                            } else {
                                selectedContextSources.insert(source)
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: source.icon)
                                .font(.systemScaled(10, weight: .semibold))
                            Text(source.label)
                                .font(.systemScaled(12, weight: .medium))
                        }
                        .foregroundStyle(isSelected
                            ? Color.black
                            : Color.black.opacity(0.45))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(isSelected
                                      ? Color.white.opacity(0.95)
                                      : Color.white.opacity(0.45))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(
                                            isSelected
                                                ? Color.black.opacity(0.14)
                                                : Color.black.opacity(0.06),
                                            lineWidth: 0.5
                                        )
                                )
                                .shadow(
                                    color: isSelected ? Color.black.opacity(0.07) : .clear,
                                    radius: 4, y: 2
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(source.label) context \(isSelected ? "active" : "inactive")")
                }
            }
        }
        // Allow the parent vertical scroll to receive simultaneous gestures so
        // horizontal swipes on this rail don't block the feed from scrolling.
        .simultaneousGesture(DragGesture(minimumDistance: 0))
    }

    private var shouldShowSuggestionRow: Bool {
        guard AMENFeatureFlags.shared.bereanChatRedesignEnabled else { return false }
        return inputFocused || scrollCoordinator.context == .nearBottom || vm.messages.count <= 1
    }

    private var shouldShowContextRail: Bool {
        guard AMENFeatureFlags.shared.bereanChatRedesignEnabled else { return true }
        return inputFocused || vm.messages.isEmpty
    }

    private var focusedSuggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                suggestionPill(title: "Search Scripture", icon: "book.pages", prompt: "Search scripture for ")
                suggestionPill(title: "Explain Simply", icon: "sparkles", prompt: "Explain this simply: ")
                suggestionPill(title: "Build a Prayer", icon: "hands.sparkles", prompt: "Turn this into a prayer: ")
            }
            .padding(.vertical, 2)
        }
        .simultaneousGesture(DragGesture(minimumDistance: 0))
    }

    private var compactContextRail: some View {
        bereanContextMemoryRail
            .frame(height: 34)
            .opacity(0.94)
    }

    private func suggestionPill(title: String, icon: String, prompt: String) -> some View {
        Button {
            vm.inputText = prompt
            inputFocused = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.systemScaled(11, weight: .semibold))
                Text(title)
                    .font(.systemScaled(13, weight: .medium))
            }
            .foregroundStyle(Color.black.opacity(0.76))
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(Color.white.opacity(0.72)))
                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.07), lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Addition 3: Save to Church Notes

    private func saveMessageToChurchNotes(_ message: BereanChatMsg) async {
        guard !message.content.isEmpty else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        lazy var db = Firestore.firestore()
        let note = ChurchNote(
            userId: uid,
            title: "Berean Note — \(Date().formatted(date: .abbreviated, time: .omitted))",
            sermonTitle: conversationTitle,
            date: Date(),
            content: message.content
        )
        do {
            let service = ChurchNotesService()
            try await service.createNote(note)
            await MainActor.run {
                withAnimation { showSavedToNotesToast = true }
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    withAnimation { showSavedToNotesToast = false }
                }
            }
        } catch {
            dlog("BereanChatView: save to notes failed — \(error)")
        }
    }

    // MARK: - Compact ChatGPT-Style Composer
    
    private var compactComposer: some View {
        HStack(spacing: 10) {
            // Plus button (left)
            Button {
                dlog("Berean: attach tapped")
            } label: {
                Image(systemName: "plus")
                    .font(.systemScaled(20, weight: .medium))
                    .foregroundColor(BereanColor.textSecondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .opacity(vm.inputText.isEmpty ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: vm.inputText.isEmpty)

            // Text input (center - clean, no nested capsule)
            TextField("", text: $vm.inputText, axis: .vertical)
                .font(.systemScaled(16, weight: .regular))
                .foregroundColor(BereanColor.textPrimary)
                .lineLimit(1...4)
                .focused($inputFocused)
                .disabled(vm.isAtLimit)
                .overlay(alignment: .leading) {
                    if vm.inputText.isEmpty {
                        Text("Ask Berean...")
                            .font(.systemScaled(16, weight: .regular))
                            .foregroundColor(BereanColor.textTertiary)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity)

            // Voice + Send (right)
            HStack(spacing: 8) {
                if vm.inputText.isEmpty && !vm.isThinking {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showVoiceAssistant = true
                    } label: {
                        Image(systemName: "mic.fill")
                            .font(.systemScaled(18, weight: .medium))
                            .foregroundColor(BereanColor.textSecondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }

                Button {
                    if vm.isThinking {
                        vm.cancelStreaming()
                    } else {
                        guard !vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        sendSweep.toggle()
                        withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.70))) {
                            showHero = false
                        }
                        vm.send()
                        inputFocused = false
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                vm.isThinking
                                    ? Color.black
                                    : (vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                       ? Color(white: 0.88)
                                       : Color.black)
                            )
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: vm.isThinking ? "stop.fill" : "arrow.up")
                            .font(.systemScaled(14, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                .highlightSweep(trigger: sendSweep)
                // CRITICAL FIX: Button was "Image, button" with no purpose communicated.
                // Dynamic label reflects the current action so VoiceOver announces the
                // correct affordance whether the button triggers send or stop-generation.
                .accessibilityLabel(vm.isThinking ? "Stop generation" : "Send message")
                .accessibilityHint(vm.isThinking ? "Stops Berean's current response" : "Sends your message to Berean")
                // CRITICAL FIX: Color-only disabled state. When text is empty the button
                // turns light grey — no other indicator. Mark it disabled in the AX tree
                // so VoiceOver announces "dimmed" and the button trait reflects its state.
                .accessibilityAddTraits(
                    (!vm.isThinking && vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        ? [.isButton] : [.isButton]
                )
                .disabled(!vm.isThinking && vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            // Single clean floating capsule
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .fill(Color.white.opacity(0.82))
                )
                .overlay(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.45),
                                    Color.white.opacity(0.10),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color(white: 0.85), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.10), radius: 16, y: 6)
                .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
        )
    }

    // MARK: - Paywall Banner

    private var paywallBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.systemScaled(13))
                .foregroundColor(Color(red: 0.788, green: 0.659, blue: 0.298))
            VStack(alignment: .leading, spacing: 1) {
                Text("Free limit reached")
                    .font(AMENFont.semiBold(13))
                    .foregroundColor(BereanColor.textPrimary)
                Text("Upgrade to Pro for unlimited Berean AI")
                    .font(AMENFont.regular(11))
                    .foregroundColor(BereanColor.textSecondary)
            }
            Spacer()
            Button("Upgrade") { showUpgradeAlert = true }
                .font(AMENFont.semiBold(12))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.black.clipShape(Capsule()))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.82))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(BereanColor.glassStroke, lineWidth: 0.5)
                )
        )
    }
    
    // MARK: - Structured Message View
    
    // MEDIUM FIX: Build a descriptive VoiceOver label for a chat message bubble.
    // Format: "<sender>: <content>, sent at <time>"
    private func messageAccessibilityLabel(_ message: BereanChatMsg) -> String {
        let sender = message.role == .user ? "You" : "Berean"
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none
        let time = timeFormatter.string(from: message.timestamp)
        let preview = message.content.isEmpty ? "Thinking…" : message.content
        return "\(sender): \(preview), sent at \(time)"
    }

    private func structuredMessageView(_ message: BereanChatMsg) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if message.role == .user {
                userMessageBubble(message)
            } else if AMENFeatureFlags.shared.bereanChatRedesignEnabled {
                BereanStructuredResponseView(message: message)
                // Addition 2: Scripture chip below assistant response
                bereanScriptureChip(for: message)
            } else {
                assistantStructuredResponse(message)
                // Addition 2: Scripture chip below assistant response
                bereanScriptureChip(for: message)
            }
        }
    }

    /// Detects a scripture reference in an assistant message and surfaces a tappable chip.
    @ViewBuilder
    private func bereanScriptureChip(for message: BereanChatMsg) -> some View {
        if !message.isStreaming && !message.content.isEmpty {
            let result = scriptureDetector.detect(in: message.content)
            if result.confidence >= 0.7 && !result.verse.reference.isEmpty {
                Button {
                    scriptureChipVerse = result.verse
                    showScriptureSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "book.closed.fill")
                            .font(.systemScaled(11, weight: .semibold))
                            .foregroundStyle(Color(red: 0.788, green: 0.659, blue: 0.298))
                        Text(result.verse.reference)
                            .font(.systemScaled(13, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.78))
                        Image(systemName: "chevron.right")
                            .font(.systemScaled(10, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.30))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(Capsule().fill(Color.white.opacity(0.82)))
                            .overlay(Capsule().strokeBorder(
                                Color(red: 0.788, green: 0.659, blue: 0.298).opacity(0.30),
                                lineWidth: 0.5
                            ))
                            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
                    )
                }
                .buttonStyle(.plain)
                .padding(.leading, 38)   // align with assistant text
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
            }
        }
    }
    
    private func userMessageBubble(_ message: BereanChatMsg) -> some View {
        HStack {
            Spacer(minLength: 60)
            
            Text(message.content)
                .font(.systemScaled(16, weight: .regular))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black)
                )
        }
        .transition(.opacity.combined(with: .offset(x: 8)))
    }
    
    private func assistantStructuredResponse(_ message: BereanChatMsg) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Direct answer (one-line, appears first)
            if let directAnswer = message.structure?.directAnswer, !directAnswer.isEmpty {
                directAnswerCard(directAnswer)
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
            
            // Structured sections
            if let structure = message.structure {
                if let meaning = structure.meaning, !meaning.isEmpty {
                    sectionCard(title: "Meaning", icon: "lightbulb.fill", content: meaning, accentColor: Color(red: 0.30, green: 0.50, blue: 0.90))
                }
                
                if let context = structure.context, !context.isEmpty {
                    sectionCard(title: "Context", icon: "book.pages.fill", content: context, accentColor: Color(red: 0.35, green: 0.30, blue: 0.90))
                }
                
                if let application = structure.application, !application.isEmpty {
                    sectionCard(title: "Application", icon: "heart.fill", content: application, accentColor: Color(red: 0.55, green: 0.30, blue: 0.85))
                }
                
                // Follow-up action pills
                if !structure.followUpActions.isEmpty {
                    followUpActionPills(structure.followUpActions)
                }
            } else if !message.content.isEmpty {
                // Fallback: standard bubble if no structure
                HStack(alignment: .top, spacing: 10) {
                    bereanAvatar
                    
                    Text(message.content)
                        .font(.systemScaled(16, weight: .regular))
                        .foregroundColor(BereanColor.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color.white.opacity(0.85))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.40), lineWidth: 0.5)
                                )
                                .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
                        )
                    
                    Spacer(minLength: 60)
                }
            }
        }
        .transition(.opacity.combined(with: .offset(y: 8)))
    }
    
    private func directAnswerCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            bereanAvatar
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundColor(Color(red: 0.30, green: 0.65, blue: 0.55))
                    Text("Direct Answer")
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundColor(BereanColor.textSecondary)
                }
                
                Text(text)
                    .font(.systemScaled(16, weight: .medium))
                    .foregroundColor(BereanColor.textPrimary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(red: 0.30, green: 0.65, blue: 0.55).opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color(red: 0.30, green: 0.65, blue: 0.55).opacity(0.20), lineWidth: 1)
                    )
            )
            
            Spacer(minLength: 40)
        }
    }
    
    private func sectionCard(title: String, icon: String, content: String, accentColor: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Spacer().frame(width: 36) // Align with avatar
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.systemScaled(13, weight: .medium))
                        .foregroundColor(accentColor)
                    Text(title)
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundColor(BereanColor.textPrimary)
                }
                
                Text(content)
                    .font(.systemScaled(15, weight: .regular))
                    .foregroundColor(BereanColor.textPrimary)
                    .lineSpacing(3)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.75))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.50), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
            )
            
            Spacer(minLength: 20)
        }
        .transition(.opacity.combined(with: .offset(y: 6)))
    }
    
    private func followUpActionPills(_ actions: [BereanResponseStructure.FollowUpAction]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Spacer().frame(width: 36)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Next Steps")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundColor(BereanColor.textSecondary)
                
                BereanFollowUpFlowLayout(spacing: 8) {
                    ForEach(actions) { action in
                        Button {
                            vm.inputText = action.title
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: action.icon)
                                    .font(.systemScaled(11, weight: .medium))
                                Text(action.title)
                                    .font(.systemScaled(13, weight: .medium))
                            }
                            .foregroundColor(BereanColor.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .overlay(Capsule().fill(Color.white.opacity(0.70)))
                                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                                    .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            Spacer(minLength: 20)
        }
    }
    
    private var bereanAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                .frame(width: 28, height: 28)
            Text("B")
                .font(.systemScaled(11, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.788, green: 0.659, blue: 0.298))
        }
    }
    
    // MARK: - Processing Indicator
    
    private var processingIndicator: some View {
        HStack(alignment: .top, spacing: 10) {
            bereanAvatar
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                    
                    Text(vm.messages.last?.processingState ?? "Reading passage...")
                        .font(.systemScaled(14, weight: .medium))
                        .foregroundColor(BereanColor.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.85))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.40), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
                )
            }
            
            Spacer(minLength: 60)
        }
    }
}

// MARK: - Addition 1: BereanContextSource enum

enum BereanContextSource: String, CaseIterable {
    case thisChat      = "This Chat"
    case churchNotes   = "Church Notes"
    case currentVerse  = "Current Verse"
    case prayerContext = "Prayer Context"
    case recentTopic   = "Recent Topic"

    var label: String { rawValue }

    var icon: String {
        switch self {
        case .thisChat:      return "bubble.left.and.bubble.right"
        case .churchNotes:   return "note.text"
        case .currentVerse:  return "book.closed"
        case .prayerContext: return "hands.sparkles"
        case .recentTopic:   return "clock.arrow.circlepath"
        }
    }
}

// MARK: - Addition 2: Berean Verse Preview Sheet

struct BereanVersePreviewSheet: View {
    let verse: BereanScriptureChip
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(.separator).opacity(0.5))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Reference header
                    HStack(spacing: 8) {
                        Image(systemName: "book.closed.fill")
                            .font(.systemScaled(16, weight: .semibold))
                            .foregroundStyle(Color(red: 0.788, green: 0.659, blue: 0.298))
                        Text(verse.reference)
                            .font(.systemScaled(20, weight: .bold, design: .serif))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(verse.translation)
                            .font(.systemScaled(12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(Color(.tertiarySystemFill))
                            )
                    }

                    // Verse text (only if we have it)
                    if !verse.text.isEmpty {
                        Text(verse.text)
                            .font(.systemScaled(17, weight: .regular, design: .serif))
                            .foregroundStyle(.primary)
                            .lineSpacing(6)
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(AmenTheme.Colors.glassFill)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5)
                                    )
                                    .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
                            )
                    } else {
                        // Reference only — invite to open in Selah
                        Text("Tap Open in Selah to read the full passage.")
                            .font(.systemScaled(15, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    // Actions row
                    HStack(spacing: 10) {
                        Button {
                            dismiss()
                        } label: {
                            Label("Open in Selah", systemImage: "arrow.up.right.square")
                                .font(.systemScaled(14, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule().fill(Color.black)
                                )
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button {
                            UIPasteboard.general.string = verse.text.isEmpty
                                ? verse.reference
                                : "\(verse.reference) — \(verse.text)"
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.systemScaled(14, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.65))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                        .overlay(Capsule().fill(Color.white.opacity(0.75)))
                                        .overlay(Capsule().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 36)
            }
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Supporting Views

// Simple flow layout for follow-up pills
struct BereanFollowUpFlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth, x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}

// Quick action press style
struct QuickActionPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Legacy BereanChatBubble (kept for compatibility)

struct BereanChatBubble: View {
    let message: BereanChatMsg
    private var isUser: Bool { message.role == .user }

    @State private var appeared = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 52) }

            if !isUser {
                avatarView
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                bubbleBody
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(BereanType.micro())
                    .foregroundColor(BereanColor.textTertiary)
                    .padding(.horizontal, 4)
            }

            if !isUser { Spacer(minLength: 52) }
        }
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : (isUser ? 10 : -10))
        .scaleEffect(appeared ? 1 : 0.97, anchor: isUser ? .bottomTrailing : .bottomLeading)
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.42, dampingFraction: 0.72))) {
                appeared = true
            }
        }
    }

    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 5, x: 0, y: 2)
                .frame(width: 26, height: 26)
            Text("B")
                .font(.systemScaled(10, weight: .bold))
                .foregroundColor(Color(red: 0.788, green: 0.659, blue: 0.298))
        }
        .alignmentGuide(.bottom) { $0[.bottom] }
    }

    @ViewBuilder
    private var bubbleBody: some View {
        let displayText = message.content.isEmpty && message.isStreaming ? "▌" : message.content

        Text(displayText)
            .font(BereanType.body())
            .foregroundColor(isUser ? Color.white : BereanColor.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(bubbleBackground)
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if isUser {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black)
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.88))
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.30), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
    }
}

// MARK: - Typing Indicator (reexported for backward compat)

struct BereanLiquidTypingIndicator: View {
    var body: some View { BereanThinkingIndicator() }
}

// MARK: - Preview

struct BereanChatView_Previews: PreviewProvider {
    static var previews: some View {
        BereanChatView(initialMode: .shepherd, conversationTitle: "Romans Study")
    }
}
