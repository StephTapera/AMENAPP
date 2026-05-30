// ComposerSmartFeatures.swift
// AMENAPP
//
// All smart features for the AMEN post composer in one file.
// Features: scripture auto-detection, Berean assist bar, conviction check,
// post type picker, AI topic suggestions, draft autosave, accessibility.
//
// DO NOT re-declare types from ComposerContract.swift or Motion.swift.
// All Firebase callable function calls follow BereanGrokService.swift patterns.

import SwiftUI
import FirebaseFunctions

// MARK: ─────────────────────────────────────────────────────────────────────
// FEATURE 1: Scripture Auto-Detection
// ─────────────────────────────────────────────────────────────────────────

// MARK: ScriptureAutoDetector

@MainActor
final class ScriptureAutoDetector {

    // Full canonical book regex — covers abbreviations and full names.
    private static let bookPattern = #"(?i)(genesis|gen|exodus|exod|ex|leviticus|lev|numbers|num|deuteronomy|deut|joshua|josh|judges|judg|ruth|1\s*samuel|1sam|2\s*samuel|2sam|1\s*kings|1kings|2\s*kings|2kings|ezra|nehemiah|neh|esther|est|job|psalms?|ps|proverbs?|prov|ecclesiastes|ecc|isaiah?|isa|jeremiah?|jer|lamentations?|lam|ezekiel?|ezek|daniel|dan|hosea|hos|joel|amos|obadiah|obad|jonah|micah|mic|nahum|nah|habakkuk|hab|zephaniah|zeph|haggai|hag|zechariah?|zech|malachi|mal|matthew|matt|mark|luke|john|acts|romans?|rom|1\s*corinthians?|1cor|2\s*corinthians?|2cor|galatians?|gal|ephesians?|eph|philippians?|phil|colossians?|col|1\s*thessalonians?|1thess|2\s*thessalonians?|2thess|1\s*timothy|1tim|2\s*timothy|2tim|titus|philemon|phlm|hebrews?|heb|james|jas|1\s*peter|1pet|2\s*peter|2pet|1\s*john|2\s*john|3\s*john|jude|revelation|rev)\s+\d+(?::\d+(?:-\d+)?)?"#

    /// Detects scripture references in the given text and returns ComposerScriptureRef values.
    static func detect(in text: String) -> [ComposerScriptureRef] {
        guard let regex = try? NSRegularExpression(pattern: bookPattern, options: []) else {
            return []
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: range)

        return matches.map { match in
            let matchRange = match.range
            let reference = nsText.substring(with: matchRange)
            return ComposerScriptureRef(
                id: UUID(),
                reference: reference,
                text: "",
                translation: "NIV",
                rangeLocation: matchRange.location,
                rangeLength: matchRange.length
            )
        }
    }
}

// MARK: ScriptureDetectionBar

struct ScriptureDetectionBar: View {
    let refs: [ComposerScriptureRef]
    let onTap: (ComposerScriptureRef) -> Void

    @State private var selectedRef: ComposerScriptureRef? = nil
    @State private var showTranslationPicker = false
    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if !refs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(refs) { ref in
                            scriptureChip(ref)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(
            reduceMotion
                ? .easeInOut(duration: 0.16)
                : Motion.adaptive(Motion.springPress),
            value: refs.isEmpty
        )
        .sheet(item: $selectedRef) { ref in
            TranslationPickerSheet(reference: ref) { selectedTranslation in
                var updated = ref
                updated.translation = selectedTranslation
                onTap(updated)
            }
        }
    }

    @ViewBuilder
    private func scriptureChip(_ ref: ComposerScriptureRef) -> some View {
        Button {
            selectedRef = ref
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "book.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.amenGold)
                Text(ref.reference)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(AmenTheme.Colors.surfaceChip)
                    .overlay(
                        Capsule()
                            .strokeBorder(AmenTheme.Colors.amenGold.opacity(0.6), lineWidth: 1)
                    )
            )
        }
        .amenPress()
        .accessibilityLabel("Scripture reference: \(ref.reference)")
        .accessibilityHint("Tap to choose translation")
    }
}

// MARK: TranslationPickerSheet

struct TranslationPickerSheet: View {
    let reference: ComposerScriptureRef
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTranslation: String

    private let translations = ["NIV", "KJV", "ESV", "NKJV", "NLT", "MSG", "AMP"]

    init(reference: ComposerScriptureRef, onSelect: @escaping (String) -> Void) {
        self.reference = reference
        self.onSelect = onSelect
        _selectedTranslation = State(initialValue: reference.translation)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Choose Translation")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 8)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)

                Text(reference.reference)
                    .font(.subheadline)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                Divider()
                    .padding(.horizontal, 20)

                ForEach(translations, id: \.self) { translation in
                    translationRow(translation)
                    Divider().padding(.leading, 20)
                }

                Spacer()

                Button {
                    onSelect(selectedTranslation)
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(AmenTheme.Colors.amenGold))
                        .foregroundStyle(AmenTheme.Colors.amenBlack)
                }
                .amenPress()
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .accessibilityLabel("Confirm translation \(selectedTranslation)")
            }
            .navigationBarHidden(true)
        }
        .presentationDetents([.fraction(0.4)])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func translationRow(_ translation: String) -> some View {
        Button {
            selectedTranslation = translation
        } label: {
            HStack {
                Text(translation)
                    .font(.body)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Spacer()
                if selectedTranslation == translation {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.amenGold)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Translation: \(translation)")
        .accessibilityAddTraits(selectedTranslation == translation ? [.isSelected] : [])
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// FEATURE 2: Berean Assist Bar
// ─────────────────────────────────────────────────────────────────────────

// MARK: BereanAssistService

@MainActor
final class BereanAssistService: ObservableObject {
    @Published var isLoading = false
    @Published var result: BereanRefineResult? = nil
    @Published var error: String? = nil

    private let functions = Functions.functions()

    func refine(_ text: String, mode: BereanRefineMode) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isLoading = true
        error = nil
        result = nil
        do {
            let callable = functions.httpsCallable("bereanRefinePost")
            let callResult = try await callable.call(["text": text, "mode": mode.rawValue])
            guard let data = callResult.data as? [String: Any],
                  let refined = data["refined"] as? String,
                  let diff = data["diff"] as? String else {
                error = "Berean couldn't refine that right now."
                isLoading = false
                return
            }
            result = BereanRefineResult(refined: refined, diff: diff, mode: mode)
        } catch {
            self.error = "Berean couldn't refine that right now."
        }
        isLoading = false
    }
}

// MARK: BereanAssistBar

struct BereanAssistBar: View {
    @Binding var draft: ComposerDraft
    @StateObject private var service = BereanAssistService()
    @State private var activeMode: BereanRefineMode? = nil
    @State private var showPreview = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "book.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.amenPurple)
                Text("Refine with Berean")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AmenTheme.Colors.amenPurple)
                Spacer()
                if service.isLoading {
                    ProgressView()
                        .scaleEffect(0.75)
                        .accessibilityLabel("Berean is refining your post")
                }
            }

            HStack(spacing: 8) {
                ForEach(BereanRefineMode.allCases, id: \.rawValue) { mode in
                    refineModeButton(mode)
                }
            }

            if let errorMsg = service.error {
                Text(errorMsg)
                    .font(.caption)
                    .foregroundStyle(AmenTheme.Colors.statusError)
                    .padding(.top, 2)
                    .accessibilityLabel("Error: \(errorMsg)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall)
                .fill(AmenTheme.Colors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall)
                        .strokeBorder(AmenTheme.Colors.amenPurple.opacity(0.25), lineWidth: 1)
                )
        )
        .sheet(isPresented: $showPreview) {
            if let result = service.result {
                BereanRefinePreviewSheet(result: result, draft: $draft)
            }
        }
        .onChange(of: service.result) { _, newResult in
            if newResult != nil {
                showPreview = true
            }
        }
    }

    @ViewBuilder
    private func refineModeButton(_ mode: BereanRefineMode) -> some View {
        let isActive = activeMode == mode

        Button {
            activeMode = mode
            Task {
                await service.refine(draft.text, mode: mode)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: mode.icon)
                    .font(.caption.weight(.semibold))
                Text(mode.displayName)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isActive ? AmenTheme.Colors.amenPurple : AmenTheme.Colors.surfaceChip)
            )
            .foregroundStyle(isActive ? .white : AmenTheme.Colors.textPrimary)
        }
        .disabled(service.isLoading)
        .amenPress()
        .animation(
            reduceMotion ? .easeInOut(duration: 0.16) : Motion.adaptive(Motion.popToggle),
            value: isActive
        )
        .accessibilityLabel(mode.displayName)
        .accessibilityHint("Refine your post with Berean: \(mode.displayName)")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

// MARK: BereanRefinePreviewSheet

struct BereanRefinePreviewSheet: View {
    let result: BereanRefineResult
    @Binding var draft: ComposerDraft
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack(spacing: 8) {
                        Image(systemName: "book.fill")
                            .foregroundStyle(AmenTheme.Colors.amenPurple)
                        Text("Berean Suggestion")
                            .font(.headline)
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                        Spacer()
                        Text(result.mode.displayName)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(AmenTheme.Colors.amenPurple.opacity(0.15)))
                            .foregroundStyle(AmenTheme.Colors.amenPurple)
                    }

                    // Original (strikethrough, red)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Original")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                        Text(draft.text)
                            .font(.body)
                            .strikethrough(true, color: AmenTheme.Colors.statusError.opacity(0.7))
                            .foregroundStyle(AmenTheme.Colors.statusError.opacity(0.8))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall)
                                    .fill(AmenTheme.Colors.statusError.opacity(0.06))
                            )
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Original text: \(draft.text)")

                    // Refined (green)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Berean Suggestion")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                        Text(result.refined)
                            .font(.body)
                            .foregroundStyle(AmenTheme.Colors.statusSuccess)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall)
                                    .fill(AmenTheme.Colors.statusSuccess.opacity(0.08))
                            )
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Berean suggestion: \(result.refined)")

                    Spacer(minLength: 20)

                    // Actions
                    VStack(spacing: 10) {
                        Button {
                            draft.text = result.refined
                            dismiss()
                        } label: {
                            Text("Use this version")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Capsule().fill(AmenTheme.Colors.amenPurple))
                                .foregroundStyle(.white)
                        }
                        .amenPress()
                        .accessibilityLabel("Use Berean's refined version")
                        .accessibilityHint("Replaces your draft text with Berean's suggestion")

                        Button {
                            dismiss()
                        } label: {
                            Text("Keep original")
                                .font(.body.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    Capsule()
                                        .strokeBorder(AmenTheme.Colors.separatorSubtle, lineWidth: 1)
                                )
                                .foregroundStyle(AmenTheme.Colors.textSecondary)
                        }
                        .amenPress()
                        .accessibilityLabel("Keep original text")
                        .accessibilityHint("Dismisses Berean's suggestion and keeps your original post")
                    }
                }
                .padding(20)
            }
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// FEATURE 3: Conviction Check
// ─────────────────────────────────────────────────────────────────────────

// MARK: ComposerConvictionChecker

@MainActor
final class ComposerConvictionChecker: ObservableObject {
    @Published var result: BereanConvictionResult? = nil
    @Published var isChecking = false

    private let functions = Functions.functions()

    func check(_ text: String) async {
        guard text.count >= 20 else { return }
        isChecking = true
        do {
            let callable = functions.httpsCallable("bereanConvictionCheck")
            let callResult = try await callable.call(["text": text])
            guard let data = callResult.data as? [String: Any],
                  let hasConcerns = data["hasConcerns"] as? Bool,
                  let tone = data["tone"] as? String else {
                isChecking = false
                return
            }
            let suggestion = data["suggestion"] as? String
            result = BereanConvictionResult(
                hasConcerns: hasConcerns,
                suggestion: suggestion,
                tone: tone
            )
        } catch {
            // Silently fail — conviction check is advisory, never blocking.
        }
        isChecking = false
    }
}

// MARK: ConvictionCheckSheet

struct ConvictionCheckSheet: View {
    let result: BereanConvictionResult
    @Binding var draft: ComposerDraft
    /// Set to true when user chooses to post as-is (caller can observe to proceed with post).
    @Binding var isPostConfirmed: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                // Title
                HStack(spacing: 8) {
                    Text("A gentle thought")
                        .font(.headline)
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                    Text("🕊️")
                        .font(.headline)
                }

                // Tone description
                Text("This post reads as \(result.tone). Berean suggests a softer approach:")
                    .font(.subheadline)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)

                // Suggestion box
                if let suggestion = result.suggestion {
                    Text(suggestion)
                        .font(.body)
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall)
                                .fill(AmenTheme.Colors.surfaceCard)
                                .overlay(
                                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall)
                                        .strokeBorder(AmenTheme.Colors.amenGold.opacity(0.5), lineWidth: 1.5)
                                )
                        )
                        .accessibilityLabel("Berean suggestion: \(suggestion)")
                }

                Spacer()

                VStack(spacing: 10) {
                    // Use suggestion
                    if let suggestion = result.suggestion {
                        Button {
                            draft.text = suggestion
                            dismiss()
                        } label: {
                            Text("Use suggestion")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Capsule().fill(AmenTheme.Colors.amenGold))
                                .foregroundStyle(AmenTheme.Colors.amenBlack)
                        }
                        .amenPress()
                        .accessibilityLabel("Use Berean's suggested revision")
                        .accessibilityHint("Replaces your post text with Berean's gentler suggestion")
                    }

                    // Post as-is (outlined, no fill — less prominent)
                    Button {
                        isPostConfirmed = true
                        dismiss()
                    } label: {
                        Text("Post as-is")
                            .font(.body.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                Capsule()
                                    .strokeBorder(AmenTheme.Colors.separator, lineWidth: 1)
                            )
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                    }
                    .amenPress()
                    .accessibilityLabel("Post as-is")
                    .accessibilityHint("Proceeds with your original post text as written")

                    // Edit more
                    Button {
                        dismiss()
                    } label: {
                        Text("Edit more")
                            .font(.body.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                    }
                    .amenPress()
                    .accessibilityLabel("Edit more")
                    .accessibilityHint("Dismisses this sheet so you can continue editing your post")
                }
            }
            .padding(20)
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// FEATURE 4: Post Type Picker
// ─────────────────────────────────────────────────────────────────────────

struct ComposerPostTypePicker: View {
    @Binding var postType: ComposerPostType
    @Binding var isAnonymousPrayer: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Horizontal pill picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ComposerPostType.allCases, id: \.rawValue) { type in
                        postTypePill(type)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }

            // Anonymous toggle — only for prayer requests
            if postType == .prayerRequest {
                HStack {
                    Toggle("Post anonymously", isOn: $isAnonymousPrayer)
                        .font(.subheadline)
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .tint(AmenTheme.Colors.amenBlue)
                        .padding(.horizontal, 16)
                        .accessibilityLabel("Post anonymously")
                        .accessibilityHint("When on, your name will not be shown with this prayer request")
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(
                    reduceMotion ? .easeInOut(duration: 0.16) : Motion.adaptive(Motion.popToggle),
                    value: postType == .prayerRequest
                )
            }
        }
    }

    @ViewBuilder
    private func postTypePill(_ type: ComposerPostType) -> some View {
        let isActive = postType == type

        Button {
            withAnimation(
                reduceMotion ? .easeInOut(duration: 0.16) : Motion.adaptive(Motion.popToggle)
            ) {
                postType = type
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.caption.weight(.semibold))
                Text(type.displayName)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isActive ? type.tintColor : AmenTheme.Colors.surfaceChip)
            )
            .foregroundStyle(isActive ? .white : AmenTheme.Colors.textSecondary)
            .animation(
                reduceMotion ? .easeInOut(duration: 0.16) : Motion.adaptive(Motion.popToggle),
                value: isActive
            )
        }
        .amenPress()
        .accessibilityLabel(type.displayName)
        .accessibilityHint("Set post type to \(type.displayName)")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// FEATURE 5: AI Topic Suggestions
// ─────────────────────────────────────────────────────────────────────────

// MARK: BereanTopicSuggestionsService

@MainActor
final class BereanTopicSuggestionsService: ObservableObject {
    @Published var suggestions: [BereanTopicSuggestion] = []
    private let functions = Functions.functions()
    private var debounceTask: Task<Void, Never>?

    /// Debounced entry point: cancels any pending task and waits 2 s before fetching.
    func debouncedSuggest(_ text: String) {
        debounceTask?.cancel()
        debounceTask = Task {
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 s
            } catch {
                return // task was cancelled
            }
            await suggest(text)
        }
    }

    func suggest(_ text: String) async {
        guard !Task.isCancelled else { return }
        do {
            let callable = functions.httpsCallable("bereanTopicSuggestions")
            let callResult = try await callable.call(["text": text])
            guard let data = callResult.data as? [String: Any],
                  let topicsRaw = data["topics"] as? [[String: Any]] else {
                suggestions = []
                return
            }
            suggestions = topicsRaw.compactMap { dict -> BereanTopicSuggestion? in
                guard let id = dict["id"] as? String,
                      let name = dict["name"] as? String else { return nil }
                return BereanTopicSuggestion(
                    id: id,
                    name: name,
                    communityId: dict["communityId"] as? String
                )
            }
        } catch {
            suggestions = []
        }
    }
}

// MARK: BereanTopicSuggestionBar

struct BereanTopicSuggestionBar: View {
    @Binding var draft: ComposerDraft
    @StateObject private var service = BereanTopicSuggestionsService()
    @State private var isLoading = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let minTextLength = 30
    private let maxChips = 3

    var body: some View {
        Group {
            if isLoading {
                shimmerRow
            } else if !service.suggestions.isEmpty {
                chipRow
            }
        }
        .onChange(of: draft.text) { _, newText in
            if newText.count > minTextLength {
                isLoading = true
                service.debouncedSuggest(newText)
            } else {
                isLoading = false
                service.suggestions = []
            }
        }
        .onChange(of: service.suggestions) { _, _ in
            withAnimation(
                reduceMotion ? .easeInOut(duration: 0.16) : Motion.adaptive(Motion.appearEase)
            ) {
                isLoading = false
            }
        }
    }

    // Horizontal chip row with staggered reveal
    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(service.suggestions.prefix(maxChips).enumerated()), id: \.element.id) { index, suggestion in
                    topicChip(suggestion, index: index)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    // Loading shimmer placeholder
    private var shimmerRow: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 20)
                    .fill(AmenTheme.Colors.shimmerBase)
                    .frame(width: 90, height: 30)
                    .shimmerEffect()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .accessibilityLabel("Loading topic suggestions")
    }

    @ViewBuilder
    private func topicChip(_ suggestion: BereanTopicSuggestion, index: Int) -> some View {
        Button {
            draft.taggedCommunity = CommunityTag(
                id: suggestion.id,
                name: suggestion.name,
                type: suggestion.communityId != nil ? .community : .topic
            )
        } label: {
            HStack(spacing: 4) {
                Text("#")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AmenTheme.Colors.amenPurple)
                Text(suggestion.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(
                        draft.taggedCommunity?.id == suggestion.id
                            ? AmenTheme.Colors.amenPurple.opacity(0.15)
                            : AmenTheme.Colors.surfaceChip
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                draft.taggedCommunity?.id == suggestion.id
                                    ? AmenTheme.Colors.amenPurple.opacity(0.5)
                                    : Color.clear,
                                lineWidth: 1
                            )
                    )
            )
        }
        .amenPress()
        .staggeredReveal(index: index, baseDelay: 0.06, maxDelay: 0.18)
        .accessibilityLabel("Topic: \(suggestion.name)")
        .accessibilityHint("Tag your post with \(suggestion.name)")
        .accessibilityAddTraits(draft.taggedCommunity?.id == suggestion.id ? [.isSelected] : [])
    }
}

// MARK: - ShimmerEffect (local helper, scoped to this file)

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            AmenTheme.Colors.shimmerBase,
                            AmenTheme.Colors.shimmerHighlight,
                            AmenTheme.Colors.shimmerBase
                        ],
                        startPoint: UnitPoint(x: phase - 0.4, y: 0.5),
                        endPoint: UnitPoint(x: phase + 0.4, y: 0.5)
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1.4
                }
            }
    }
}

private extension View {
    func shimmerEffect() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: ─────────────────────────────────────────────────────────────────────
// FEATURE 6: Draft Autosave
// ─────────────────────────────────────────────────────────────────────────

// MARK: ComposerDraftAutoSave

@MainActor
final class ComposerDraftAutoSave {
    static let shared = ComposerDraftAutoSave()
    private let key = "composerDraft_v2"
    private let maxAge: TimeInterval = 86_400 // 24 hours
    private var saveTask: Task<Void, Never>?

    private init() {}

    /// Schedule a debounced save (cancels any prior pending save, waits 2 s).
    func scheduleSave(_ draft: ComposerDraft) {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 s debounce
            } catch {
                return // cancelled
            }
            guard !Task.isCancelled else { return }
            var mutable = draft
            mutable.savedAt = Date()
            if let encoded = try? JSONEncoder().encode(mutable) {
                UserDefaults.standard.set(encoded, forKey: key)
            }
        }
    }

    /// Restore a draft saved within the last 24 hours. Returns nil if stale or absent.
    func restore() -> ComposerDraft? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let draft = try? JSONDecoder().decode(ComposerDraft.self, from: data) else {
            return nil
        }
        guard Date().timeIntervalSince(draft.savedAt) < maxAge else {
            clear()
            return nil
        }
        return draft
    }

    /// Remove the persisted draft from UserDefaults.
    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        saveTask?.cancel()
    }
}

// MARK: DraftRecoveryBanner

struct DraftRecoveryBanner: View {
    /// The date at which the draft was saved (for display).
    let savedAt: Date
    let onRestore: () -> Void
    let onDiscard: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.amenBlue)
                .accessibilityHidden(true)

            Text("You have a saved draft from \(timeAgo)")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .lineLimit(2)

            Spacer()

            HStack(spacing: 8) {
                Button("Restore", action: onRestore)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.amenBlue)
                    .amenPress()
                    .accessibilityLabel("Restore saved draft")
                    .accessibilityHint("Loads your previously saved draft into the composer")

                Button("Discard", action: onDiscard)
                    .font(.subheadline)
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
                    .amenPress()
                    .accessibilityLabel("Discard saved draft")
                    .accessibilityHint("Permanently discards the saved draft")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall)
                .fill(AmenTheme.Colors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusSmall)
                        .strokeBorder(AmenTheme.Colors.amenBlue.opacity(0.25), lineWidth: 1)
                )
        )
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(
            reduceMotion ? .easeInOut(duration: 0.16) : Motion.adaptive(Motion.springPress),
            value: true
        )
    }

    private var timeAgo: String {
        let interval = Date().timeIntervalSince(savedAt)
        switch interval {
        case ..<60:
            return "just now"
        case ..<3_600:
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        case ..<86_400:
            let hours = Int(interval / 3_600)
            return "\(hours)h ago"
        default:
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: savedAt)
        }
    }
}
