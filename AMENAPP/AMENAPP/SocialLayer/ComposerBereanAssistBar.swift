// ComposerBereanAssistBar.swift
// AMENAPP — SocialLayer
//
// INTEGRATION NOTE (Phase 4 — CreatePostView wiring):
//   1. Add @State var bereanBarVisible = false to CreatePostView.
//   2. Add a "Berean" toolbar button that sets bereanBarVisible = true.
//   3. Embed the bar above the keyboard/toolbar:
//        if bereanBarVisible {
//            ComposerBereanAssistBar(
//                draft: $composerDraft,
//                isVisible: $bereanBarVisible,
//                onConvictionCheck: { result in
//                    // handle BereanConvictionResult — e.g. show inline warning
//                }
//            )
//            .transition(.move(edge: .bottom).combined(with: .opacity))
//        }
//   4. AmenMagicWordComposerObserver is intentionally NOT duplicated here:
//      that engine handles visual word reactions; this bar handles AI-driven
//      text refinement and tone analysis, which are separate concerns.
//   5. BereanConvictionResult is surfaced via onConvictionCheck callback so
//      CreatePostView can decide how to display the result (inline or modal).

import SwiftUI
import Combine
import FirebaseFunctions

// MARK: - BereanAssistViewModel

/// Internal state machine for the assist bar.
/// Isolated so tests can verify state transitions without needing a View.
@MainActor
private final class BereanAssistViewModel: ObservableObject {

    // MARK: Published state

    @Published var activeMode: BereanRefineMode? = nil
    @Published var isRefining: Bool = false
    @Published var refineResult: BereanRefineResult? = nil
    @Published var refineError: String? = nil

    @Published var isCheckingTone: Bool = false
    @Published var convictionResult: BereanConvictionResult? = nil
    @Published var convictionError: String? = nil

    // MARK: Private

    private let functions = Functions.functions(region: "us-central1")
    private var refineTask: Task<Void, Never>?
    private var convictionTask: Task<Void, Never>?

    // MARK: - Refine

    /// Call `bereanPostAssist` with the given mode and draft text.
    /// On success, updates `refineResult` and immediately triggers a
    /// conviction check on the refined text.
    func refine(text: String, mode: BereanRefineMode) {
        refineTask?.cancel()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        activeMode   = mode
        isRefining   = true
        refineResult = nil
        refineError  = nil

        refineTask = Task {
            let payload: [String: Any] = [
                "mode":    mode.rawValue,
                "content": text
            ]

            do {
                let result = try await functions.httpsCallable("bereanPostAssist").call(payload)
                guard !Task.isCancelled else { return }

                if let dict = result.data as? [String: Any],
                   let refined = dict["refined"] as? String {
                    let diff = Self.buildDiffLabel(original: text, refined: refined, mode: mode)
                    refineResult = BereanRefineResult(refined: refined, diff: diff, mode: mode)
                    isRefining = false

                    // Auto-run conviction check on refinement result
                    await checkConvictionInternal(text: refined)
                } else {
                    throw BereanAssistError.invalidResponse
                }
            } catch is CancellationError {
                isRefining = false
            } catch {
                guard !Task.isCancelled else { return }
                refineError = "Berean couldn't refine right now. Try again."
                isRefining  = false
            }
        }
    }

    // MARK: - Conviction Check

    /// Public entry: check original draft text (manual "Check tone" trigger).
    func checkConviction(text: String) {
        convictionTask?.cancel()
        convictionTask = Task {
            await checkConvictionInternal(text: text)
        }
    }

    /// Shared conviction check logic — called both on manual trigger and
    /// after a successful refinement.
    private func checkConvictionInternal(text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isCheckingTone  = true
        convictionError = nil

        let system = """
            You are a faith-based tone analyst for a Christian social app called AMEN.
            Analyze the tone of the following post draft.
            Return a JSON object with exactly these fields:
            {
              "hasConcerns": <true|false>,
              "suggestion": "<optional: gentle, faith-aligned suggestion if hasConcerns is true>",
              "tone": "<single word or short phrase describing the overall tone, e.g. 'encouraging', 'harsh', 'anxious'>"
            }
            Be gracious and faith-positive. Only flag genuine unkindness, despair, or divisiveness.
            """
        let user = "Post draft:\n\(text)"

        let payload: [String: Any] = [
            "systemPrompt": system,
            "userMessage":  user,
            "maxTokens":    512
        ]

        do {
            let result = try await functions.httpsCallable("bereanChatProxy").call(payload)
            guard !Task.isCancelled else { return }

            if let dict = result.data as? [String: Any],
               let rawText = dict["text"] as? String {
                let parsed = Self.parseConvictionJSON(rawText)
                convictionResult = parsed
                isCheckingTone   = false
            } else {
                throw BereanAssistError.invalidResponse
            }
        } catch is CancellationError {
            isCheckingTone = false
        } catch {
            guard !Task.isCancelled else { return }
            convictionError = "Tone check unavailable."
            isCheckingTone  = false
        }
    }

    // MARK: - Helpers

    private static func buildDiffLabel(
        original: String,
        refined: String,
        mode: BereanRefineMode
    ) -> String {
        let originalWords = original.split(separator: " ").count
        let refinedWords  = refined.split(separator: " ").count
        let delta         = refinedWords - originalWords

        switch mode {
        case .tighten:
            if delta < 0 {
                return "\(abs(delta)) word\(abs(delta) == 1 ? "" : "s") removed"
            } else {
                return "Wording refined"
            }
        case .addVerse:
            return "Verse added"
        case .softenTone:
            return "Tone softened"
        }
    }

    private static func parseConvictionJSON(_ raw: String) -> BereanConvictionResult {
        // Strip markdown code fences if present
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```",     with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Attempt JSON decode
        if let data = cleaned.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let hasConcerns  = dict["hasConcerns"]  as? Bool   ?? false
            let suggestion   = dict["suggestion"]   as? String
            let tone         = dict["tone"]         as? String ?? "neutral"
            return BereanConvictionResult(
                hasConcerns: hasConcerns,
                suggestion:  suggestion.flatMap { $0.isEmpty ? nil : $0 },
                tone:        tone
            )
        }

        // Fallback: assume safe if we can't parse
        return BereanConvictionResult(hasConcerns: false, suggestion: nil, tone: "neutral")
    }
}

private enum BereanAssistError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        "Berean returned an unexpected response."
    }
}

// MARK: - ComposerBereanAssistBar

/// Compact assist bar shown above the keyboard in the composer.
/// The bar renders:
///   1. Refine-mode chips (Tighten / Add a verse / Soften tone)
///   2. Loading indicator while Berean processes
///   3. Refined-text preview with diff label
///   4. Accept ("Use this") and Discard ("Keep mine") actions
///   5. Conviction / tone check inline
///
/// Use `isVisible` to show/hide with an animated transition from the parent.
struct ComposerBereanAssistBar: View {

    /// The live composer draft — `.text` is read for refinement input;
    /// replaced on "Use this".
    @Binding var draft: ComposerDraft

    /// Set to false to collapse the bar. The bar does NOT hide itself
    /// except via this binding so the parent controls the dismiss animation.
    @Binding var isVisible: Bool

    /// Called whenever a conviction check completes (auto or manual).
    var onConvictionCheck: (BereanConvictionResult) -> Void

    @StateObject private var vm = BereanAssistViewModel()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            // ── Header strip ─────────────────────────────────────
            header

            Divider()
                .opacity(0.4)

            // ── Mode chips ───────────────────────────────────────
            modeChipsRow
                .padding(.vertical, 10)

            // ── Loading / result / error ─────────────────────────
            if vm.isRefining {
                loadingRow
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if let result = vm.refineResult {
                resultSection(result)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if let error = vm.refineError {
                errorRow(error)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .transition(.opacity)
            }

            // ── Conviction / tone ────────────────────────────────
            convictionSection
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
        .background(assistBarBackground)
        .animation(Motion.adaptive(Motion.appearEase), value: vm.isRefining)
        .animation(Motion.adaptive(Motion.appearEase), value: vm.refineResult?.refined)
        .animation(Motion.adaptive(Motion.appearEase), value: vm.convictionResult?.hasConcerns)
        .onChange(of: vm.convictionResult) { _, newValue in
            if let result = newValue {
                onConvictionCheck(result)
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.amenGold)
            Text("Berean Assist")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Spacer()
            Button {
                withAnimation(Motion.adaptive(Motion.unpopToggle)) {
                    // Reset before dismiss
                    vm.refineResult = nil
                    vm.refineError  = nil
                    isVisible = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Berean Assist")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var modeChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BereanRefineMode.allCases, id: \.self) { mode in
                    refineModeChip(mode)
                }

                // Manual "Check tone" button
                Button {
                    vm.checkConviction(text: draft.text)
                } label: {
                    HStack(spacing: 5) {
                        if vm.isCheckingTone {
                            BereanTypingDots()
                                .frame(width: 24, height: 14)
                        } else {
                            Image(systemName: "waveform.and.magnifyingglass")
                                .font(.system(size: 12, weight: .medium))
                        }
                        Text("Check tone")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(AmenTheme.Colors.surfaceChip)
                    )
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
                .buttonStyle(AmenPressStyle(scale: 0.95))
                .disabled(vm.isCheckingTone || draft.text.isEmpty)
                .accessibilityLabel("Check post tone")
                .accessibilityHint("Berean will review your post for tone and flag any concerns")
            }
            .padding(.horizontal, 14)
        }
    }

    @ViewBuilder
    private func refineModeChip(_ mode: BereanRefineMode) -> some View {
        let isActive  = vm.activeMode == mode
        let isLoading = isActive && vm.isRefining

        Button {
            vm.refine(text: draft.text, mode: mode)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 5) {
                if isLoading {
                    BereanTypingDots()
                        .frame(width: 24, height: 14)
                } else {
                    Image(systemName: mode.icon)
                        .font(.system(size: 12, weight: .medium))
                }
                Text(mode.displayName)
                    .font(.system(size: 13, weight: isActive ? .semibold : .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isActive
                          ? AmenTheme.Colors.amenBlue.opacity(0.15)
                          : AmenTheme.Colors.surfaceChip)
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                isActive
                                    ? AmenTheme.Colors.amenBlue.opacity(0.6)
                                    : Color.clear,
                                lineWidth: 1
                            )
                    )
            )
            .foregroundStyle(isActive
                             ? AmenTheme.Colors.amenBlue
                             : AmenTheme.Colors.textSecondary)
        }
        .buttonStyle(AmenPressStyle(scale: 0.95))
        .disabled(vm.isRefining || draft.text.isEmpty)
        .animation(Motion.adaptive(Motion.springPress), value: isActive)
        .accessibilityLabel(mode.displayName)
        .accessibilityHint(accessibilityHint(for: mode))
    }

    private var loadingRow: some View {
        HStack(spacing: 8) {
            BereanTypingDots()
            Text("Berean is refining…")
                .font(.system(size: 13))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private func resultSection(_ result: BereanRefineResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Diff label
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(AmenTheme.Colors.statusSuccess)
                Text(result.diff)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
            .padding(.horizontal, 14)

            // Refined text preview
            Text(result.refined)
                .font(.system(size: 14))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: AmenTheme.CornerRadius.small, style: .continuous)
                        .fill(AmenTheme.Colors.surfaceInput)
                        .overlay(
                            RoundedRectangle(cornerRadius: AmenTheme.CornerRadius.small, style: .continuous)
                                .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.75)
                        )
                )
                .padding(.horizontal, 14)

            // Accept / Discard
            HStack(spacing: 10) {
                // "Use this"
                Button {
                    draft.text = result.refined
                    withAnimation(Motion.adaptive(Motion.springRelease)) {
                        vm.refineResult = nil
                        vm.activeMode   = nil
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    Text("Use this")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(
                            Capsule().fill(AmenTheme.Colors.amenBlue)
                        )
                }
                .buttonStyle(AmenPressStyle(scale: 0.96))
                .accessibilityLabel("Accept refinement")

                // "Keep mine"
                Button {
                    withAnimation(Motion.adaptive(Motion.unpopToggle)) {
                        vm.refineResult = nil
                        vm.activeMode   = nil
                    }
                } label: {
                    Text("Keep mine")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(
                            Capsule()
                                .fill(AmenTheme.Colors.surfaceChip)
                        )
                }
                .buttonStyle(AmenPressStyle(scale: 0.96))
                .accessibilityLabel("Discard refinement and keep original")

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private func errorRow(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(AmenTheme.Colors.statusWarning)
                .font(.system(size: 13))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            Spacer()
            Button("Retry") {
                if let mode = vm.activeMode {
                    vm.refine(text: draft.text, mode: mode)
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(AmenTheme.Colors.amenBlue)
        }
    }

    @ViewBuilder
    private var convictionSection: some View {
        if vm.isCheckingTone {
            HStack(spacing: 6) {
                BereanTypingDots()
                Text("Checking tone…")
                    .font(.system(size: 12))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
                Spacer()
            }
            .transition(.opacity)
        } else if let result = vm.convictionResult {
            HStack(spacing: 8) {
                if result.hasConcerns {
                    // Amber concern chip
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AmenTheme.Colors.statusWarning)
                        if let suggestion = result.suggestion {
                            Text(suggestion)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AmenTheme.Colors.textPrimary)
                                .lineLimit(2)
                        } else {
                            Text("Consider softening your tone")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AmenTheme.Colors.textPrimary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: AmenTheme.CornerRadius.small, style: .continuous)
                            .fill(AmenTheme.Colors.statusWarning.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: AmenTheme.CornerRadius.small, style: .continuous)
                                    .strokeBorder(AmenTheme.Colors.statusWarning.opacity(0.30), lineWidth: 1)
                            )
                    )
                    .accessibilityLabel("Tone concern: \(result.suggestion ?? "Consider softening your tone")")
                } else {
                    // Subtle green "Good to post" pill
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AmenTheme.Colors.statusSuccess)
                        Text("Good to post \u{2713}")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AmenTheme.Colors.statusSuccess)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(AmenTheme.Colors.statusSuccess.opacity(0.10))
                    )
                    .accessibilityLabel("Tone check passed. Good to post.")
                }

                // Tone label
                if !result.tone.isEmpty && result.tone != "neutral" {
                    Text("· \(result.tone)")
                        .font(.system(size: 12))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }

                Spacer()

                // Dismiss conviction result
                Button {
                    withAnimation(Motion.adaptive(Motion.unpopToggle)) {
                        vm.convictionResult = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AmenTheme.Colors.textQuaternary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss tone check result")
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else if let error = vm.convictionError {
            Text(error)
                .font(.system(size: 12))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .transition(.opacity)
        }
    }

    // MARK: - Background

    private var assistBarBackground: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            Rectangle()
                .fill(AmenTheme.Colors.amenGold.opacity(0.08))
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AmenTheme.Colors.separatorSubtle)
                .frame(height: 0.5)
        }
    }

    // MARK: - Helpers

    private func accessibilityHint(for mode: BereanRefineMode) -> String {
        switch mode {
        case .tighten:    return "Activate to get a tighter version of your post"
        case .addVerse:   return "Activate to add a relevant scripture verse to your post"
        case .softenTone: return "Activate to get a more gentle and encouraging version of your post"
        }
    }
}

// MARK: - ComposerPostTypeSelector (Bonus)

/// Horizontal chip selector for the 4 ComposerPostType cases.
/// Shows the active type with a filled background.
/// Includes an anonymous toggle when `.prayerRequest` is active.
///
/// INTEGRATION NOTE (Phase 4): embed near the top of CreatePostView,
/// bind to `draft.postType` and `draft.isAnonymousPrayer`.
struct ComposerPostTypeSelector: View {

    @Binding var postType: ComposerPostType
    @Binding var isAnonymous: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ComposerPostType.allCases, id: \.self) { type in
                        postTypeChip(type)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
            }

            // Anonymous toggle — only shown for prayer requests
            if postType == .prayerRequest {
                HStack(spacing: 8) {
                    Toggle(isOn: $isAnonymous) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.fill.questionmark")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AmenTheme.Colors.textSecondary)
                            Text("Post anonymously")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AmenTheme.Colors.textPrimary)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: AmenTheme.Colors.amenBlue))
                    .padding(.horizontal, 14)
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal:   .opacity
                ))
            }
        }
        .animation(Motion.adaptive(Motion.appearEase), value: postType)
    }

    @ViewBuilder
    private func postTypeChip(_ type: ComposerPostType) -> some View {
        let isActive = postType == type

        Button {
            withAnimation(Motion.adaptive(Motion.springPress)) {
                postType = type
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: type.icon)
                    .font(.system(size: 12, weight: .medium))
                Text(type.displayName)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(isActive ? .white : AmenTheme.Colors.textSecondary)
            .background(
                Capsule()
                    .fill(isActive
                          ? type.tintColor
                          : AmenTheme.Colors.surfaceChip)
            )
        }
        .buttonStyle(AmenPressStyle(scale: 0.95))
        .accessibilityLabel(type.displayName)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .animation(Motion.adaptive(Motion.springPress), value: isActive)
    }
}
