// ComposerScriptureAutoDetect.swift
// AMENAPP — SocialLayer
//
// INTEGRATION NOTE (Phase 4 — CreatePostView wiring):
//   1. Instantiate ScriptureAutoDetectService as @StateObject in CreatePostView.
//   2. In the composer's .onChange(of: draftText) handler, call:
//        Task { await scriptureService.detect(in: newValue) }
//   3. Embed ScriptureAutoDetectRail directly above the keyboard toolbar:
//        ScriptureAutoDetectRail(service: scriptureService) { ref in
//            draft.scriptureRefs.append(ref)
//        }
//   4. When a ref is attached via onAttach, optionally also open a verse picker
//      to let the user choose a translation before attaching.
//   5. No edits needed to CreatePostView's post submission path — scriptureRefs
//      on ComposerDraft are already serialised by the existing draft encoder.

import SwiftUI
import Combine
import FirebaseFunctions

// MARK: - ScriptureAutoDetectService

/// Regex-based scripture reference detector with debounce, deduplication,
/// and lazy verse-text fetching via the `bereanChatProxy` Cloud Function.
///
/// Lifecycle: create once as @StateObject, call `detect(in:)` from every
/// text-change event (already debounced internally).
@MainActor
final class ScriptureAutoDetectService: ObservableObject {

    // MARK: Published

    @Published var detectedRefs: [ComposerScriptureRef] = []

    // MARK: Private

    private let functions = Functions.functions(region: "us-central1")
    /// In-memory cache: reference string → fetched verse text
    private var verseTextCache: [String: String] = [:]
    private var detectTask: Task<Void, Never>?

    // MARK: - Detection

    /// Detect all scripture references in `text`. Debounced 500 ms.
    /// Deduplicates against already-detected refs so rapid typing doesn't
    /// reset the rail mid-compose.
    func detect(in text: String) async {
        detectTask?.cancel()
        detectTask = Task {
            // 500 ms debounce
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }

            let matches = Self.extractRefs(from: text)

            // Deduplicate: keep existing detected refs whose reference string
            // still appears, add new ones that aren't already present.
            let existingRefs = Set(detectedRefs.map(\.reference))
            let newRefs = matches.filter { !existingRefs.contains($0.reference) }
            let stillRelevant = detectedRefs.filter { ref in
                matches.contains(where: { $0.reference == ref.reference })
            }

            withAnimation(Motion.adaptive(Motion.appearEase)) {
                detectedRefs = stillRelevant + newRefs
            }
        }
        await detectTask?.value
    }

    // MARK: - Verse Text Fetch

    /// Fetch verse text for a ref via `bereanChatProxy`.
    /// Returns an updated copy of `ref` with `.text` populated.
    /// Caches in-memory — safe to call multiple times for the same ref.
    func fetchVerseText(for ref: ComposerScriptureRef) async -> ComposerScriptureRef {
        if let cached = verseTextCache[ref.reference] {
            var updated = ref
            updated.text = cached
            return updated
        }

        let system = "You are a Bible reference lookup tool. Return ONLY the verse text, no commentary."
        let user   = "Return the NIV text for \(ref.reference). Reply with just the verse text."

        let payload: [String: Any] = [
            "systemPrompt": system,
            "userMessage": user,
            "maxTokens": 256
        ]

        do {
            let result = try await functions.httpsCallable("bereanChatProxy").call(payload)
            if let dict = result.data as? [String: Any],
               let text = dict["text"] as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                verseTextCache[ref.reference] = trimmed
                var updated = ref
                updated.text = trimmed
                return updated
            }
        } catch {
            // Non-fatal: ref will show with empty text; caller can retry
        }

        return ref
    }

    // MARK: - Regex Extraction

    private static let bookPattern: String = {
        let books = [
            "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy",
            "Joshua", "Judges", "Ruth",
            "(?:1|2)\\s*Samuel", "(?:1|2)\\s*Kings", "(?:1|2)\\s*Chronicles",
            "Ezra", "Nehemiah", "Esther", "Job",
            "Psalms?", "Proverbs", "Ecclesiastes",
            "Song\\s+of\\s+(?:Solomon|Songs)",
            "Isaiah", "Jeremiah", "Lamentations", "Ezekiel", "Daniel",
            "Hosea", "Joel", "Amos", "Obadiah", "Jonah", "Micah",
            "Nahum", "Habakkuk", "Zephaniah", "Haggai", "Zechariah", "Malachi",
            "Matthew", "Mark", "Luke", "John", "Acts", "Romans",
            "(?:1|2)\\s*Corinthians", "Galatians", "Ephesians", "Philippians",
            "Colossians", "(?:1|2)\\s*Thessalonians", "(?:1|2)\\s*Timothy",
            "Titus", "Philemon", "Hebrews", "James",
            "(?:1|2|3)\\s*Peter", "(?:1|2|3)\\s*John", "Jude", "Revelation"
        ]
        return books.joined(separator: "|")
    }()

    private static let scriptureRegex: NSRegularExpression? = {
        let pattern = "\\b(?:\(bookPattern))\\s+\\d+:\\d+(?:-\\d+)?"
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    /// Synchronous extraction — runs on the caller's task, off the hot path.
    static func extractRefs(from text: String) -> [ComposerScriptureRef] {
        guard let regex = scriptureRegex else { return [] }

        let nsText = text as NSString
        let range  = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: range)

        var seen = Set<String>()
        return matches.compactMap { match -> ComposerScriptureRef? in
            let nsRange   = match.range
            let reference = nsText.substring(with: nsRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !seen.contains(reference) else { return nil }
            seen.insert(reference)

            return ComposerScriptureRef(
                id:            UUID(),
                reference:     reference,
                text:          "",
                translation:   "NIV",
                rangeLocation: nsRange.location,
                rangeLength:   nsRange.length
            )
        }
    }
}

// MARK: - InlineVerseCardChip

/// A small tappable chip representing a detected scripture reference.
/// Tapping "+" calls `onAttach`; tapping "✕" calls `onDismiss`.
struct InlineVerseCardChip: View {

    let ref: ComposerScriptureRef
    var onAttach: (ComposerScriptureRef) -> Void
    var onDismiss: (ComposerScriptureRef) -> Void

    @State private var appeared = false

    var body: some View {
        HStack(spacing: 6) {
            // Book icon
            Image(systemName: "book.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.amenGold)

            // Reference label
            Text(ref.reference)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .lineLimit(1)

            Divider()
                .frame(height: 14)
                .foregroundStyle(AmenTheme.Colors.separatorSubtle)

            // Attach button
            Button {
                withAnimation(Motion.adaptive(Motion.popToggle)) {
                    onAttach(ref)
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.amenBlue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Attach \(ref.reference)")
            .accessibilityHint("Adds this verse as a card to your post")

            // Dismiss button
            Button {
                withAnimation(Motion.adaptive(Motion.unpopToggle)) {
                    onDismiss(ref)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss \(ref.reference)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(AmenTheme.Colors.amenGold.opacity(0.12))
                .overlay(
                    Capsule()
                        .strokeBorder(AmenTheme.Colors.amenGold.opacity(0.35), lineWidth: 1)
                )
        )
        // Accessibility: whole chip announces the reference
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scripture detected: \(ref.reference)")
        .accessibilityHint("Double-tap to attach as verse card.")
        // Appear animation
        .scaleEffect(appeared ? 1 : 0.82)
        .opacity(appeared ? 1 : 0)
        .animation(Motion.adaptive(Motion.popToggle), value: appeared)
        .onAppear { appeared = true }
    }
}

// MARK: - ScriptureAutoDetectRail

/// Horizontal scrolling rail of `InlineVerseCardChip`s.
/// Hidden when no references have been detected.
///
/// INTEGRATION NOTE: embed above the keyboard toolbar or inside the
/// composer's bottom action strip.
struct ScriptureAutoDetectRail: View {

    @ObservedObject var service: ScriptureAutoDetectService
    var onAttach: (ComposerScriptureRef) -> Void

    var body: some View {
        if !service.detectedRefs.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                // Header label
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AmenTheme.Colors.amenGold)
                    Text("Scripture detected")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 4)

                // Chip rail
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(service.detectedRefs.enumerated()), id: \.element.id) { index, ref in
                            InlineVerseCardChip(
                                ref: ref,
                                onAttach: { attachedRef in
                                    onAttach(attachedRef)
                                    // Remove from rail after attach
                                    withAnimation(Motion.adaptive(Motion.unpopToggle)) {
                                        service.detectedRefs.removeAll { $0.id == attachedRef.id }
                                    }
                                },
                                onDismiss: { dismissedRef in
                                    withAnimation(Motion.adaptive(Motion.unpopToggle)) {
                                        service.detectedRefs.removeAll { $0.id == dismissedRef.id }
                                    }
                                }
                            )
                            .staggeredReveal(index: index, baseDelay: 0.06, maxDelay: 0.20)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
            }
            .background(
                AmenTheme.Colors.amenGold.opacity(0.05)
                    .ignoresSafeArea(edges: .horizontal)
            )
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal:   .opacity
            ))
        }
    }
}
