import SwiftUI

// MARK: - SafetyComposerState
//
// Reusable ObservableObject that drives safety features in any UGC composer:
//   - Debounced tone check (0.8s after user stops typing)
//   - Content warning detection when borderline content is submitted
//   - Text rewrite panel when content is hard-blocked
//
// Usage:
//   @StateObject private var safety = SafetyComposerState()
//
//   // In onChange(of: text):
//   safety.onTextChange(text, contentType: "post")
//
//   // Before submit:
//   let ok = await safety.checkBeforeSubmit(text: text, contentType: "post")
//   if ok { submit() }
//
//   // In body, above the composer:
//   if let suggestion = safety.toneCheckSuggestion {
//       ToneCheckBanner(
//           suggestion: suggestion,
//           onApply: { text = safety.applyToneSuggestion($0) },
//           onDismiss: { safety.dismissToneSuggestion() }
//       )
//   }
//
//   // Below composer or as a sheet:
//   if safety.showRewritePanel {
//       TextRewriteView(
//           blockedText: $body,
//           harmCategoryId: safety.blockedCategoryId ?? "harassment",
//           contentType: "post"
//       ) { accepted in safety.onRewriteDecision(accepted, harmCategoryId: safety.blockedCategoryId ?? "harassment", contentType: "post") }
//   }

@MainActor
final class SafetyComposerState: ObservableObject {
    @Published var toneCheckSuggestion: String? = nil
    @Published var contentWarning: String? = nil
    @Published var showRewritePanel: Bool = false
    @Published var blockedCategoryId: String? = nil
    @Published var isCheckingTone: Bool = false

    private let safetyService = AmenSafetyOSClientService.shared
    private var toneDebounceTask: Task<Void, Never>? = nil

    // MARK: - Tone Check (Debounced)

    /// Call on every text change. Debounces 0.8s before hitting the backend.
    func onTextChange(_ text: String, contentType: String) {
        toneDebounceTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20 else {
            toneCheckSuggestion = nil
            return
        }
        toneDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            isCheckingTone = true
            defer { isCheckingTone = false }
            do {
                let result = try await safetyService.getToneCheckSuggestion(
                    text: trimmed,
                    contentType: contentType
                )
                toneCheckSuggestion = result.suggestion
            } catch {
                // Non-fatal: tone check failure doesn't block composing
            }
        }
    }

    /// Dismiss the tone suggestion without applying it.
    func dismissToneSuggestion() {
        toneCheckSuggestion = nil
        toneDebounceTask?.cancel()
    }

    /// Apply a tone suggestion to the text. Returns the new text.
    func applyToneSuggestion(_ suggestion: String) -> String {
        toneCheckSuggestion = nil
        return suggestion
    }

    // MARK: - Pre-Submit Check

    /// Call this before submitting content. Returns true if submission should proceed.
    /// Handles borderline (content warning) and blocked (rewrite panel) cases.
    func checkBeforeSubmit(text: String, contentType: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        do {
            let result = try await safetyService.moderateText(
                text: trimmed,
                contentType: contentType
            )
            if result.allowed {
                if result.moderationStatus == "borderline" {
                    // Backend adds the content warning at publish time;
                    // surface a local notice but still allow submit.
                    contentWarning = result.userFacingMessage
                }
                return true
            } else {
                blockedCategoryId = result.harmCategoryId
                showRewritePanel = true
                return false
            }
        } catch {
            // If moderation check fails, allow submit — backend will re-check at write time.
            return true
        }
    }

    // MARK: - Rewrite Decision

    /// Call when user accepts or dismisses a rewrite suggestion.
    func onRewriteDecision(_ accepted: Bool, harmCategoryId: String, contentType: String) {
        showRewritePanel = false
        blockedCategoryId = nil
        // Outcome telemetry is handled server-side via the rewrite callable result.
    }

    // MARK: - Reset

    func reset() {
        toneDebounceTask?.cancel()
        toneCheckSuggestion = nil
        contentWarning = nil
        showRewritePanel = false
        blockedCategoryId = nil
        isCheckingTone = false
    }
}
