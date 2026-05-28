//
//  BereanComposerBar.swift
//  AMENAPP
//
//  Safari-inspired floating Berean composer with progressive scroll collapse.
//

import SwiftUI
import FirebaseAnalytics

enum BereanComposerSurface {
    case home
    case messages
}

struct BereanCompactComposerBar: View {
    @ObservedObject var composerVM: BereanComposerViewModel
    @Binding var messageText: String
    @FocusState.Binding var isFocused: Bool

    let availableWidth: CGFloat
    var selectedMode: BereanPersonalityMode = .askBerean
    var surface: BereanComposerSurface = .home
    let onSend: () -> Void
    let onVoice: () -> Void
    let onAction: (BereanLiquidAction.ActionType) -> Void
    let onTools: () -> Void
    var onStop: (() -> Void)? = nil
    var onModeChange: ((BereanPersonalityMode) -> Void)? = nil
    var accentColor: Color? = nil
    var isVoiceEnabled = true
    /// Optional follow-up prompt chips shown above the composer bar after a Berean response.
    var followUpChips: [String] = []
    var onChipTap: ((String) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var showActions = false
    @State private var showModePicker = false
    @State private var detectedScriptureRef: String? = nil
    @State private var ghostDraft: String? = nil
    // Liquid Glass v1: BereanComposerTray draft intent
    @State private var currentDraftIntent: BereanDraftIntent = .empty
    @State private var streamingHapticTask: Task<Void, Never>? = nil
    @State private var keystrokeTimes: [Date] = []
    @State private var keystrokeDirections: [Bool] = []
    @State private var inferredMode: BereanPersonalityMode? = nil
    @State private var isSoaking = false
    @State private var soakingTask: Task<Void, Never>? = nil
    @State private var toneNudgeActive = false
    @State private var toneNudgeTask: Task<Void, Never>? = nil
    @State private var showToneChecker = false
    @State private var hasTrackedOpen = false
    private let compactPlaceholder = "Ask Berean..."

    private var resolvedAccent: Color { accentColor ?? Color.amenGold }

    private let quickActions: [BereanLiquidAction] = [
        BereanLiquidAction(icon: "text.quote", title: "Explain Simply", color: Color.black.opacity(0.78), action: .explainSimply),
        BereanLiquidAction(icon: "globe", title: "Explore Context", color: Color.black.opacity(0.74), action: .exploreContext),
        BereanLiquidAction(icon: "link", title: "Cross-reference", color: Color.black.opacity(0.74), action: .crossReference),
        BereanLiquidAction(icon: "hands.sparkles", title: "Prayer", color: Color.black.opacity(0.72), action: .prayer),
        BereanLiquidAction(icon: "book.pages", title: "Deep Study", color: Color.black.opacity(0.76), action: .deepStudy),
        BereanLiquidAction(icon: "photo", title: "Add Photo", color: Color.black.opacity(0.72), action: .addPhoto),
        BereanLiquidAction(icon: "doc", title: "Add File", color: Color.black.opacity(0.78), action: .addFile),
        BereanLiquidAction(icon: "square.and.pencil", title: "Create Note", color: Color.black.opacity(0.72), action: .createNote),
        BereanLiquidAction(icon: "note.text.badge.plus", title: "Save to Church Notes", color: Color.black.opacity(0.72), action: .saveToChurchNotes)
    ]

    var body: some View {
        let progress = effectiveCollapseProgress
        let cornerRadius: CGFloat = 30
        let innerSpacing: CGFloat = 8
        let shellWidth = min(availableWidth, 620)

        VStack(spacing: 0) {
            // Liquid Glass v1: capability-first adaptive tray with inline mode picker
            BereanComposerTray(
                draftText: $messageText,
                draftIntent: currentDraftIntent,
                selectedMode: selectedMode,
                onModeChange: { mode in
                    showModePicker = false
                    inferredMode = nil
                    onModeChange?(mode)
                    Analytics.logEvent("berean_mode_selected", parameters: ["mode": mode.rawValue])
                },
                onChipTap: { suggestion in
                    messageText = suggestion
                },
                onActionTap: handleToolSelection
            )
            .padding(.bottom, 8)
            .transition(.opacity.combined(with: .move(edge: .bottom)))

            if let ghost = ghostDraft, messageText.isEmpty {
                ghostDraftChip(ghost: ghost)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if !followUpChips.isEmpty, let chipsHandler = onChipTap {
                BereanSmartFollowUpChips(chips: followUpChips, onSelect: chipsHandler)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if let status = composerVM.statusPill {
                floatingStatusPill(status)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(alignment: .bottom, spacing: 0) {
                utilityButton(progress: progress)
                    .padding(.trailing, innerSpacing)

                ComposerTextField(
                    text: $messageText,
                    isFocused: $isFocused,
                    collapseProgress: 1,
                    expandedPlaceholder: placeholder(for: selectedMode),
                    compactPlaceholder: placeholder(for: selectedMode),
                    maxHeight: 104
                )

                rightControls(progress: progress)
                    .padding(.leading, innerSpacing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: shellWidth)
            .frame(minHeight: 56)
            .background(
                LiquidGlassCapsuleBackground(
                    cornerRadius: cornerRadius,
                    glassOpacity: reduceTransparency ? 0.0 : 0.07,
                    shadowOpacity: 0.06,
                    highlightOpacity: reduceTransparency ? 0.0 : 0.10
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(isFocused ? 0.72 : 0.46), lineWidth: 0.75)
            }
            .ambientGlow(
                composerVM.state == .streaming ? .breathing : .edgeLitCapsule,
                surface: .berean,
                intensity: isFocused ? .focused : .whisper,
                isActive: isFocused || composerVM.state == .streaming,
                cornerRadius: cornerRadius
            )
            .animation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.88), value: isFocused)
            .animation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.88), value: messageText)
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showActions) {
            BereanComposerToolSheet(
                actions: quickActions,
                isVoiceEnabled: isVoiceEnabled,
                onSelect: handleToolSelection
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showModePicker) {
            BereanModePickerSheet(
                currentMode: selectedMode,
                inferredMode: inferredMode,
                onSelect: { mode in
                    showModePicker = false
                    inferredMode = nil
                    onModeChange?(mode)
                    Analytics.logEvent("berean_mode_selected", parameters: ["mode": mode.rawValue])
                }
            )
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(24)
        }
        .sheet(isPresented: $showToneChecker) {
            ToneCheckerSheet(
                text: messageText,
                context: "berean_composer:\(selectedMode.rawValue)",
                isRestModeActive: false,
                onAcceptRewrite: { rewrite in messageText = rewrite },
                onKeepOriginal: {},
                onSaveForMonday: nil
            )
        }
        .onAppear {
            guard !hasTrackedOpen else { return }
            hasTrackedOpen = true
            Analytics.logEvent("berean_composer_opened", parameters: ["mode": selectedMode.rawValue])
            Task {
                ghostDraft = await BereanDraftStore.shared.load(surface: surface, mode: selectedMode)
            }
        }
        .onDisappear {
            let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                Task { await BereanDraftStore.shared.save(draft: text, surface: surface, mode: selectedMode) }
            }
            streamingHapticTask?.cancel()
            soakingTask?.cancel()
            toneNudgeTask?.cancel()
        }
        .onChange(of: composerVM.state) { _, state in
            streamingHapticTask?.cancel()
            if state == .streaming && !UIAccessibility.isReduceMotionEnabled {
                streamingHapticTask = Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(1.4))
                        guard !Task.isCancelled else { break }
                        BereanHapticCoordinator.shared.fireSentencePulse()
                    }
                }
            }
        }
        .onChange(of: messageText) { oldValue, newValue in
            if !newValue.isEmpty && composerVM.state == .idle {
                composerVM.setState(.typing)
            } else if newValue.isEmpty && composerVM.state == .typing {
                composerVM.setState(.idle)
            }
            if !newValue.isEmpty { ghostDraft = nil }
            detectScripturePaste(in: newValue)
            trackKeystrokeRhythm(oldLength: oldValue.count, newLength: newValue.count)
            manageSoakingState(text: newValue)
            manageToneNudge(text: newValue)
            // Liquid Glass v1: update draft intent for BereanComposerTray
            currentDraftIntent = computeDraftIntent(text: newValue)
        }
        .onChange(of: isFocused) { _, focused in
            let isOverridable = composerVM.state == .idle
                || composerVM.state == .scrollingCompact
                || composerVM.state == .expandedActions
            if focused && isOverridable {
                composerVM.setState(.focused)
            } else if !focused && composerVM.state == .focused {
                composerVM.setState(.idle)
            }
        }
    }

    // MARK: - Derived Values

    private var effectiveCollapseProgress: CGFloat {
        if isFocused {
            return min(composerVM.collapseProgress, 0.45)
        }
        return composerVM.collapseProgress
    }

    private var currentScreenHeight: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .screen.bounds.height ?? 844
    }

    private func interpolatedWidth(for progress: CGFloat) -> CGFloat {
        let expanded = min(availableWidth, 620)
        let compact = max(min(availableWidth * 0.88, 520), 304)
        return interpolate(expanded, compact, progress)
    }

    private func interpolate(_ start: CGFloat, _ end: CGFloat, _ progress: CGFloat) -> CGFloat {
        start + (end - start) * min(max(progress, 0), 1)
    }

    private func placeholder(for mode: BereanPersonalityMode) -> String {
        if let ref = detectedScriptureRef {
            return "What would you like to explore in \(ref)?"
        }
        if surface == .messages {
            return "Message, pray, attach…"
        }
        if let liturgical = LiturgicalCalendar.composerPlaceholder() {
            return liturgical
        }
        switch mode {
        case .scriptureStudy:
            return "Ask about Scripture..."
        case .prayerCompanion:
            return "Bring a prayer..."
        case .deepStudy, .scholar:
            return "Ask a deeper question..."
        default:
            return compactPlaceholder
        }
    }

    private func handleToolSelection(_ action: BereanLiquidAction.ActionType) {
        showActions = false
        composerVM.setState(.idle)
        Analytics.logEvent("berean_tool_opened", parameters: ["tool": action.analyticsName])
        onAction(action)
    }

    // Liquid Glass v1: compute BereanDraftIntent from existing detection state
    private func computeDraftIntent(text: String) -> BereanDraftIntent {
        if text.isEmpty { return .empty }
        if let ref = detectedScriptureRef { return .scriptureRef(ref) }
        let lower = text.lowercased()
        if lower.contains("pray") || lower.contains("prayer") {
            return .prayer
        }
        if lower.contains("scripture") || lower.contains("verse") || lower.contains("bible") {
            return .modeKeyword(.scriptureStudy)
        }
        if text.contains("?") || lower.hasPrefix("why") || lower.hasPrefix("what") || lower.hasPrefix("how") {
            return .question
        }
        return .empty
    }

    // MARK: - Utility Button

    private func utilityButton(progress: CGFloat) -> some View {
        Button {
            showActions = true
            composerVM.setState(.expandedActions)
            Analytics.logEvent("berean_tool_opened", parameters: ["tool": "sheet"])
            HapticManager.impact(style: .light)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(BereanColor.textPrimary)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().fill(Color.white.opacity(0.13)))
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.055), lineWidth: 0.6))
                        .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More Berean tools")
        .accessibilityHint("Opens Explain Simply, Explore Context, Cross-reference, Prayer, Deep Study, and attachment tools")
    }

    // inputField logic extracted to ComposerTextField.swift

    // MARK: - Right Controls

    private func rightControls(progress: CGFloat) -> some View {
        let hasText = !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return HStack(spacing: interpolate(6, 4, progress)) {
            toolsButton(progress: progress)
            if composerVM.state == .streaming {
                stopButton(progress: progress)
            } else if composerVM.state == .voiceReady {
                voicePrayerPulse
            } else if hasText {
                sendButton(progress: progress)
            } else {
                micButton(progress: progress)
            }
        }
    }

    private func toolsButton(progress: CGFloat) -> some View {
        Button {
            if toneNudgeActive {
                toneNudgeActive = false
                showToneChecker = true
            } else {
                showModePicker = true
            }
            HapticManager.impact(style: .light)
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(toneNudgeActive ? resolvedAccent : BereanColor.textPrimary.opacity(0.58))
                .frame(width: 38, height: 38)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().fill(Color.white.opacity(0.10)))
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.045), lineWidth: 0.6))
                )
                .ambientGlow(
                    toneNudgeActive ? .breathing : .edgeLitCapsule,
                    surface: .berean,
                    intensity: toneNudgeActive ? .subtle : .whisper,
                    isActive: toneNudgeActive,
                    cornerRadius: 20
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Berean mode picker")
        .accessibilityHint(toneNudgeActive
            ? "Berean noticed something — tap to check your tone"
            : "Opens Scripture, Prayer, and Deep Study modes")
    }

    private func micButton(progress: CGFloat) -> some View {
        Button {
            guard isVoiceEnabled else {
                onVoice()
                HapticManager.impact(style: .light)
                return
            }
            onVoice()
            HapticManager.impact(style: .light)
        } label: {
            Image(systemName: "mic.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isVoiceEnabled ? resolvedAccent : BereanColor.textPrimary.opacity(0.38))
                .frame(width: 38, height: 38)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().fill(Color.white.opacity(0.12)))
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.045), lineWidth: 0.6))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Voice input")
        .accessibilityHint(isVoiceEnabled ? "Starts voice input for Berean" : "Turn on voice input in Berean settings")
    }

    private func sendButton(progress: CGFloat) -> some View {
        let canSend = !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && composerVM.state != .streaming

        return Button {
            guard canSend else { return }
            onSend()
            HapticManager.impact(style: .medium)
        } label: {
            ZStack {
                Circle()
                    .fill(canSend ? resolvedAccent : resolvedAccent.opacity(0.18))
                    .frame(width: 38, height: 38)
                    .shadow(color: canSend ? resolvedAccent.opacity(0.32) : .clear, radius: 9, y: 3)
                    .ambientGlow(
                        isSoaking ? .breathing : .edgeLitCapsule,
                        surface: .berean,
                        intensity: isSoaking ? .focused : .subtle,
                        isActive: canSend,
                        cornerRadius: 20
                    )

                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .accessibilityLabel("Send message")
        .accessibilityHint("Sends your message to Berean")
    }

    private func stopButton(progress: CGFloat) -> some View {
        Button {
            onStop?()
            HapticManager.impact(style: .medium)
        } label: {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.82))
                    .frame(width: 38, height: 38)

                Image(systemName: "stop.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop generation")
        .accessibilityHint("Stops Berean's current response")
    }

    private var voicePrayerPulse: some View {
        ComposerVoicePrayerPulse(isActive: composerVM.state == .voiceReady, size: 32)
            .accessibilityLabel("Voice prayer listening")
    }

    // MARK: - Voice Attached Panel

    private var voiceAttachedPanel: some View {
        HStack(spacing: 10) {
            ComposerVoicePrayerPulse(isActive: true, size: 28)

            Text("Listening…")
                .font(AMENFont.medium(13))
                .foregroundStyle(BereanColor.textPrimary.opacity(0.70))

            Spacer(minLength: 0)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    composerVM.setState(.idle)
                }
                HapticManager.impact(style: .light)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.26))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel voice input")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.white.opacity(0.34)))
                .overlay(
                    Capsule().strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.60), Color.white.opacity(0.20)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
                )
                .shadow(color: .black.opacity(0.055), radius: 10, x: 0, y: 3)
        )
        .ambientGlow(.breathing, surface: .berean, intensity: .focused, cornerRadius: 24)
        .frame(width: min(availableWidth * 0.82, 420))
    }

    // MARK: - Status Pill

    private func floatingStatusPill(_ type: BereanStatusPillType) -> some View {
        HStack(spacing: 8) {
            Image(systemName: type.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BereanColor.textPrimary)

            Text(type.text)
                .font(AMENFont.medium(13))
                .foregroundStyle(BereanColor.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.white.opacity(0.40)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.50), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
        )
        .ambientGlow(.edgeLitCapsule, surface: .berean, intensity: .whisper, cornerRadius: 18)
    }

    // MARK: - Feature Helpers

    private func ghostDraftChip(ghost: String) -> some View {
        let preview = String(ghost.prefix(42))
        let label = "Continue: \"\(preview)\(ghost.count > 42 ? "…" : "")\""
        return HStack(spacing: 8) {
            Image(systemName: "text.quote")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BereanColor.textPrimary.opacity(0.54))
            Text(label)
                .font(AMENFont.regular(13))
                .foregroundStyle(BereanColor.textPrimary.opacity(0.62))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                withAnimation(.easeOut(duration: 0.18)) { ghostDraft = nil }
                Task { await BereanDraftStore.shared.clear(surface: surface, mode: selectedMode) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BereanColor.textPrimary.opacity(0.38))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss draft")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.white.opacity(0.36)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.48), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        )
        .frame(width: min(availableWidth - 32, 580))
        .contentShape(Capsule())
        .onTapGesture {
            messageText = ghost
            ghostDraft = nil
        }
        .accessibilityLabel("Resume draft: \(preview)")
        .accessibilityHint("Tap to restore your previous message")
    }

    private func detectScripturePaste(in text: String) {
        guard !text.isEmpty else { detectedScriptureRef = nil; return }
        let pattern = #"\b(Genesis|Exodus|Leviticus|Numbers|Deuteronomy|Joshua|Judges|Ruth|Samuel|Kings|Chronicles|Ezra|Nehemiah|Esther|Job|Psalms|Psalm|Proverbs|Ecclesiastes|Isaiah|Jeremiah|Lamentations|Ezekiel|Daniel|Hosea|Joel|Amos|Obadiah|Jonah|Micah|Nahum|Habakkuk|Zephaniah|Haggai|Zechariah|Malachi|Matthew|Mark|Luke|John|Acts|Romans|Corinthians|Galatians|Ephesians|Philippians|Colossians|Thessalonians|Timothy|Titus|Philemon|Hebrews|James|Peter|Jude|Revelation)\s+\d+:\d+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else {
            detectedScriptureRef = nil
            return
        }
        let ref = String(text[range])
        if detectedScriptureRef != ref {
            detectedScriptureRef = ref
            onModeChange?(.scriptureStudy)
        }
    }

    private func trackKeystrokeRhythm(oldLength: Int, newLength: Int) {
        keystrokeTimes.append(Date())
        keystrokeDirections.append(newLength >= oldLength)
        if keystrokeTimes.count > 8 { keystrokeTimes.removeFirst() }
        if keystrokeDirections.count > 8 { keystrokeDirections.removeFirst() }
        guard keystrokeTimes.count >= 4 else { return }
        let intervals = zip(keystrokeTimes, keystrokeTimes.dropFirst()).map { $1.timeIntervalSince($0) }
        let avgInterval = intervals.reduce(0, +) / Double(intervals.count)
        let backspaceDensity = Double(keystrokeDirections.filter { !$0 }.count) / Double(keystrokeDirections.count)
        if avgInterval > 0.8 {
            inferredMode = .prayerCompanion
        } else if backspaceDensity > 0.25 {
            inferredMode = .deepStudy
        } else {
            inferredMode = nil
        }
    }

    private func manageSoakingState(text: String) {
        soakingTask?.cancel()
        isSoaking = false
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        soakingTask = Task {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            isSoaking = true
        }
    }

    private func manageToneNudge(text: String) {
        toneNudgeTask?.cancel()
        let lower = text.lowercased()
        guard lower.count > 40 else { toneNudgeActive = false; return }
        toneNudgeTask = Task {
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled else { return }
            let selfCondemnation = ["i'm so stupid", "i always fail", "god must hate", "i'm worthless",
                                    "i can't do anything right", "i hate myself", "god doesn't love me"]
            let bypassing = ["everything happens for a reason", "just have faith", "god has a plan",
                             "thoughts and prayers", "just pray harder"]
            let hasConcern = selfCondemnation.contains(where: { lower.contains($0) }) ||
                             bypassing.contains(where: { lower.contains($0) })
            if hasConcern { toneNudgeActive = true }
        }
    }
}

typealias BereanComposerBar = BereanCompactComposerBar

private struct BereanComposerToolSheet: View {
    let actions: [BereanLiquidAction]
    let isVoiceEnabled: Bool
    let onSelect: (BereanLiquidAction.ActionType) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(actions) { action in
                        toolButton(action)
                    }
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Berean tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func toolButton(_ action: BereanLiquidAction) -> some View {
        let disabled = action.action == .voiceNote && !isVoiceEnabled

        return Button {
            guard !disabled else { return }
            dismiss()
            onSelect(action.action)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: action.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(action.color)
                    .frame(width: 18)

                Text(action.title)
                    .font(AMENFont.medium(14))
                    .foregroundStyle(BereanColor.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(minHeight: 54, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(reduceTransparency ? Color(uiColor: .secondarySystemBackground) : Color.white.opacity(0.62))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.54), lineWidth: 0.7)
                    )
            )
            .opacity(disabled ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(action.title)
        .accessibilityHint(disabled ? "Turn on voice input in Berean settings" : "Uses this Berean tool")
    }
}

// MARK: - Mode Picker Sheet

private struct BereanModePickerSheet: View {
    let currentMode: BereanPersonalityMode
    var inferredMode: BereanPersonalityMode? = nil
    let onSelect: (BereanPersonalityMode) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let studyModes: [BereanPersonalityMode] = [.scriptureStudy, .prayerCompanion, .deepStudy]

    private func icon(for mode: BereanPersonalityMode) -> String {
        switch mode {
        case .scriptureStudy: return "book.closed"
        case .prayerCompanion: return "hands.sparkles"
        case .deepStudy: return "magnifyingglass.circle"
        default: return "questionmark"
        }
    }

    private func label(for mode: BereanPersonalityMode) -> String {
        switch mode {
        case .scriptureStudy: return "Scripture Study"
        case .prayerCompanion: return "Prayer Companion"
        case .deepStudy: return "Deep Study"
        default: return "Ask Berean"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Color.black.opacity(0.14))
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 20)

            Text("Study mode")
                .font(AMENFont.semiBold(15))
                .foregroundStyle(BereanColor.textPrimary)
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

            VStack(spacing: 8) {
                ForEach(studyModes, id: \.self) { mode in
                    Button {
                        onSelect(mode)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: icon(for: mode))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(BereanColor.textPrimary.opacity(0.70))
                                .frame(width: 24)

                            Text(label(for: mode))
                                .font(AMENFont.medium(15))
                                .foregroundStyle(BereanColor.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if mode == currentMode {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(BereanColor.textPrimary.opacity(0.54))
                            } else if mode == inferredMode {
                                Text("Suggested")
                                    .font(AMENFont.regular(11))
                                    .foregroundStyle(Color.amenGold.opacity(0.82))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.amenGold.opacity(0.10), in: Capsule())
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(reduceTransparency
                                    ? Color(.secondarySystemBackground)
                                    : (mode == currentMode ? Color.black.opacity(0.06) : Color.white.opacity(0.52)))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.46), lineWidth: 0.6)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(label(for: mode))
                    .accessibilityAddTraits(mode == currentMode ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)

            Spacer(minLength: 0)
        }
        .background(Color(uiColor: .systemBackground))
    }
}

// MARK: - Support

private struct ComposerVoicePrayerPulse: View {
    let isActive: Bool
    let size: CGFloat

    @State private var breathScale: CGFloat = 0.82
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.95, green: 0.78, blue: 0.38).opacity(isActive ? 0.22 : 0.10),
                            Color.white.opacity(isActive ? 0.42 : 0.24),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 1,
                        endRadius: size * 0.62
                    )
                )
                .frame(width: size, height: size)
                .scaleEffect(breathScale)

            Circle()
                .strokeBorder(Color.black.opacity(0.10), lineWidth: 0.7)
                .background(Circle().fill(Color.white.opacity(0.34)))
                .frame(width: size * 0.58, height: size * 0.58)

            Circle()
                .fill(Color.black.opacity(0.62))
                .frame(width: size * 0.16, height: size * 0.16)
        }
        .onChange(of: isActive) { _, active in
            updateBreath(active)
        }
        .onAppear {
            updateBreath(isActive)
        }
    }

    private func updateBreath(_ active: Bool) {
        guard !reduceMotion else {
            breathScale = active ? 0.96 : 0.82
            return
        }

        if active {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                breathScale = 1.08
            }
        } else {
            withAnimation(.easeOut(duration: 0.24)) {
                breathScale = 0.82
            }
        }
    }
}

#Preview {
    @Previewable @State var text = ""
    @Previewable @FocusState var focused: Bool
    @Previewable @StateObject var vm = BereanComposerViewModel()

    VStack {
        Spacer()

        BereanComposerBar(
            composerVM: vm,
            messageText: $text,
            isFocused: $focused,
            availableWidth: 390,
            selectedMode: .scholar,
            onSend: {},
            onVoice: {},
            onAction: { _ in },
            onTools: {},
            onStop: {}
        )
    }
    .padding(.bottom, 16)
    .background(Color.white)
}
