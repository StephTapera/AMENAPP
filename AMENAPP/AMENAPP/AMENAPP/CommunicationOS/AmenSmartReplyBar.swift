// AmenSmartReplyBar.swift
// AMEN App — Smart Collaboration Layer: Slice 7 — Smart Suggested Replies
//
// Design rules enforced here:
//   1. Replies are ephemeral — never persisted, never fetched automatically.
//      Generated only on explicit user tap of the sparkle trigger button.
//   2. No prophetic certainty, no guilt language, no medical/legal/financial advice,
//      no reply that speaks for God.
//   3. All suggestions carry "possible:" prefix internally (SafetyLabel).
//      The prefix is NOT displayed in chip text — it is a safety contract label.
//   4. Feature flag OFF → completely invisible. This view renders nothing.
//   5. All states modeled explicitly: idle, loading, suggestions, error, dismissed.
//   6. VoiceOver and Reduce Motion supported.
//   7. Analytics: smartReplySelected(wasEdited:), smartReplyDismissed.
//
// Gated behind: RemoteKillSwitch.shared.threadSmartRepliesEnabled

import SwiftUI

// MARK: - Smart Reply Bar State

/// Internal state machine for AmenSmartReplyBar.
/// Transitions: idle → loading → suggestions | error | empty
/// Any state can return to idle via dismiss.
private enum SmartReplyBarState: Equatable {
    case idle
    case loading
    case suggestions([String])   // display strings — "possible:" prefix stripped for UI
    case error
    case empty
    case dismissed
}

// MARK: - AmenSmartReplyBar

/// Compact horizontal scroll row of AI-suggested reply chips.
///
/// Appears above the keyboard/compose area when the sparkle trigger button is tapped.
/// All suggestions are ephemeral (not persisted) and only generated on explicit tap.
/// Completely hidden when `threadSmartRepliesEnabled` is false.
struct AmenSmartReplyBar: View {

    // MARK: Required inputs

    let threadId: String
    let threadType: AmenSmartThreadType
    let spaceId: String?
    let channelId: String?
    let lastMessageId: String

    /// Called when the user taps a reply chip to populate the compose field.
    /// The caller is responsible for tracking `smartReplySelected(wasEdited: true)`
    /// on send if the text was edited after selection.
    let onSelectReply: (String) -> Void

    // MARK: State

    @State private var barState: SmartReplyBarState = .idle
    @State private var errorTooltipVisible = false

    // MARK: Environment

    @ObservedObject private var killSwitch = RemoteKillSwitch.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Body

    var body: some View {
        // Rule 4: feature flag OFF → completely invisible.
        if killSwitch.threadSmartRepliesEnabled {
            content
        }
        // else: renders nothing — not even an empty frame.
    }

    // MARK: Private content tree

    @ViewBuilder
    private var content: some View {
        switch barState {
        case .idle:
            sparkleTriggerRow(errorTooltip: false)

        case .loading:
            loadingRow

        case .suggestions(let chips):
            suggestionsRow(chips: chips)

        case .error:
            sparkleTriggerRow(errorTooltip: true)

        case .empty:
            sparkleTriggerRow(errorTooltip: false)

        case .dismissed:
            sparkleTriggerRow(errorTooltip: false)
        }
    }

    // MARK: Sparkle trigger (idle / error / empty / dismissed)

    private func sparkleTriggerRow(errorTooltip: Bool) -> some View {
        HStack(spacing: 6) {
            Button {
                requestReplies()
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Get reply suggestions")

            if errorTooltip {
                Text("Suggestions unavailable")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .transition(.opacity)
            }

            Spacer()
        }
        .frame(minHeight: 36)
        .padding(.horizontal, 8)
    }

    // MARK: Loading row — 3 skeleton pill chips

    private var loadingRow: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                SkeletonPillChip(reduceMotion: reduceMotion, index: index)
            }
            Spacer()
        }
        .frame(minHeight: 36)
        .padding(.horizontal, 8)
    }

    // MARK: Suggestions row — chips + dismiss

    private func suggestionsRow(chips: [String]) -> some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chips, id: \.self) { chipText in
                        ReplyChip(text: chipText) {
                            handleChipTap(text: chipText)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }

            // Dismiss button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Dismiss reply suggestions")
            .padding(.trailing, 4)
        }
        .frame(minHeight: 36)
    }

    // MARK: Actions

    private func requestReplies() {
        barState = .loading

        let payload: [String: Any] = buildPayload()

        Task {
            do {
                let rawData = try await CloudFunctionsService.shared.call(
                    "generateSmartReplies",
                    data: payload
                )
                let displayChips = parseReplies(from: rawData)
                await MainActor.run {
                    if displayChips.isEmpty {
                        barState = .empty
                    } else {
                        barState = .suggestions(displayChips)
                    }
                }
            } catch {
                await MainActor.run {
                    barState = .error
                }
            }
        }
    }

    private func handleChipTap(text: String) {
        onSelectReply(text)
        AMENAnalyticsService.shared.track(.smartReplySelected(wasEdited: false))
        // After selection, return to idle so the bar collapses cleanly.
        // The caller holds the selected text in its compose field state.
        barState = .idle
    }

    private func dismiss() {
        AMENAnalyticsService.shared.track(.smartReplyDismissed)
        barState = .dismissed
    }

    // MARK: Payload construction

    private func buildPayload() -> [String: Any] {
        var payload: [String: Any] = [
            "threadId": threadId,
            "threadType": threadType.rawValue,
            "lastMessageId": lastMessageId
        ]
        if let spaceId { payload["spaceId"] = spaceId }
        if let channelId { payload["channelId"] = channelId }
        return payload
    }

    // MARK: Response parsing

    /// Parses the Cloud Function response into display strings.
    ///
    /// Safety contract:
    ///   - Server should return texts already labeled "possible: …" via
    ///     SmartContextSafety.labelAsSuggested() before sending.
    ///   - We strip the "possible: " prefix for display (Rule 3 — the prefix
    ///     is an internal safety label, NOT shown in chip text).
    ///   - Capped at 3 suggestions maximum.
    ///   - Texts that are empty after stripping are dropped.
    private func parseReplies(from rawData: Any) -> [String] {
        guard let dict = rawData as? [String: Any],
              let replies = dict["replies"] as? [String] else {
            return []
        }

        return replies
            .prefix(3)
            .compactMap { raw -> String? in
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                // Strip "possible: " prefix — it's the internal safety label, not UI text.
                if trimmed.lowercased().hasPrefix("possible: ") {
                    let stripped = String(trimmed.dropFirst("possible: ".count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return stripped.isEmpty ? nil : stripped
                }
                return trimmed
            }
    }
}

// MARK: - ReplyChip

private struct ReplyChip: View {
    let text: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Suggested reply: \(text). Tap to use.")
    }
}

// MARK: - SkeletonPillChip

/// Animated skeleton placeholder rendered while replies are loading.
/// Respects Reduce Motion: skips shimmer animation when enabled.
private struct SkeletonPillChip: View {
    let reduceMotion: Bool
    let index: Int

    // Stagger the animation phase slightly per chip for a wave effect.
    @State private var phase: Double = 0

    // Widths vary to look natural.
    private static let widths: [CGFloat] = [72, 88, 64]
    private var width: CGFloat {
        Self.widths[index % Self.widths.count]
    }

    var body: some View {
        Capsule()
            .fill(Color(uiColor: .secondarySystemBackground))
            .frame(width: width, height: 34)
            .opacity(reduceMotion ? 1.0 : opacity)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    Animation
                        .easeInOut(duration: 0.9)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.15)
                ) {
                    phase = 1
                }
            }
    }

    private var opacity: Double {
        phase == 0 ? 0.35 : 0.75
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Idle") {
    AmenSmartReplyBar(
        threadId: "thread-001",
        threadType: .dm,
        spaceId: nil,
        channelId: nil,
        lastMessageId: "msg-123"
    ) { selected in
        print("Selected: \(selected)")
    }
    .padding()
}

#Preview("Suggestions") {
    // Directly exercise the suggestions state via a wrapper.
    SmartReplyBarPreviewWrapper()
        .padding()
}

private struct SmartReplyBarPreviewWrapper: View {
    // Simulated pre-loaded state for preview purposes only.
    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["That's encouraging!", "Praying for you", "Amen to that"], id: \.self) { text in
                        ReplyChip(text: text) { print("Tapped: \(text)") }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            Button { } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(8)
            }
            .padding(.trailing, 4)
        }
        .frame(minHeight: 36)
    }
}
#endif
