// AILEmotionalSafetyFilter.swift
// AMENAPP — Accessibility Intelligence Layer (AIL) · Protection Surface (A6)
//
// C12 Emotional Safety Filter. A ViewModifier that optionally blurs content matching
// the user's own sensitivity filters (grief / conflict / politics / trauma / graphic),
// behind a gentle tap-to-reveal scrim. This is a SELF-chosen comfort filter, not a
// moderation gate.
//
// IRON RULES (encoded here, in code AND behavior):
//   • Protection SUGGESTS; moderation DECIDES. Shares ZERO code path with NeMo /
//     Guardian / ModerationGatewayService — only the fail-open AILTransformService.
//   • FAIL OPEN: if the sensitivity classify transform fails open, we do NOT blur —
//     content is always shown. A failed classifier never hides anything.
//   • CRISIS-HELP IS NEVER BLURRED: when `isCrisisHelp == true` the content always
//     shows, unconditionally, and we never even call the classifier. Someone reaching
//     for help must never hit a curtain.
//   • Only topics the USER has opted into (profile.sensitivityFilters) can blur.
//   • Reduce Transparency → opaque scrim (no see-through blur). Reduce Motion → no
//     reveal animation.
//   • NO tier checks — accessibility is free at every tier.

import SwiftUI

/// Applies a self-chosen sensitivity blur with tap-to-reveal. See `ailSensitivityBlur`.
struct AILSensitivityBlur: ViewModifier {

    /// The text whose sensitivity is being evaluated against the user's filters.
    let text: String
    /// When true, this content is crisis-HELP and must NEVER be blurred.
    let isCrisisHelp: Bool

    // The six UI states of the filter, as an explicit phase enum.
    private enum Phase: Equatable {
        case idle          // not yet classified
        case classifying   // classify transform in flight
        case clear         // classified → no matching filters → show content
        case blurred       // classified → matched filters → curtain shown
        case revealed      // user tapped to view through the curtain
        case failOpen      // classify failed → show content (never hide on failure)
    }

    @State private var phase: Phase = .idle
    @State private var matchedTopics: [SensitivityTopic] = []

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var profileService: AILProfileService { .shared }

    func body(content: Content) -> some View {
        ZStack {
            content
                // Blur the underlying pixels while curtained — but ONLY a true visual
                // blur when Reduce Transparency is off; with it on the opaque scrim
                // does the hiding so we don't double-process.
                .blur(radius: contentBlurRadius)
                // Hide raw content from assistive tech while the curtain is up.
                .accessibilityHidden(phase == .blurred)

            if phase == .blurred {
                curtain
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: phase)
        .task(id: classifyKey) { await classifyIfNeeded() }
    }

    /// Re-classify when the text or the user's chosen filters change. Crisis-help is
    /// folded into the key so flipping it to true immediately clears any curtain.
    private var classifyKey: String {
        let filters = profileService.profile.sensitivityFilters.map(\.rawValue).sorted().joined(separator: ",")
        return "\(isCrisisHelp ? "crisis" : "normal")|\(filters)|\(text.hashValue)"
    }

    // MARK: - Curtain (tap-to-reveal)

    private var curtain: some View {
        Button {
            phase = .revealed
        } label: {
            ZStack {
                scrim
                VStack(spacing: 6) {
                    Image(systemName: "eye.slash")
                        .font(.title3)
                        .accessibilityHidden(true)
                    Text(curtainLabel)
                        .font(.footnote.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text("Tap to view.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(curtainLabel))
        .accessibilityHint(Text("Double tap to reveal sensitive content."))
        .accessibilityAddTraits(.isButton)
    }

    /// Visual blur radius applied to the underlying content while curtained. With
    /// Reduce Transparency on, the opaque scrim hides everything so no blur is needed.
    private var contentBlurRadius: CGFloat {
        guard phase == .blurred, !reduceTransparency else { return 0 }
        return 18
    }

    /// Reduce Transparency → opaque scrim. Otherwise a soft blur-style material.
    @ViewBuilder
    private var scrim: some View {
        if reduceTransparency {
            Rectangle().fill(Color(.secondarySystemBackground))
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
    }

    private var curtainLabel: String {
        let names = matchedTopics.map(\.displayName)
        let list = names.isEmpty ? "Sensitive" : names.joined(separator: ", ")
        return "Sensitive: \(list)."
    }

    // MARK: - Classification

    private func classifyIfNeeded() async {
        // CRISIS-HELP IS NEVER BLURRED. Short-circuit before any classify call.
        if isCrisisHelp {
            await MainActor.run { phase = .clear }
            return
        }

        // If the user has chosen no filters, there is nothing to blur — show content.
        let chosen = profileService.profile.sensitivityFilters
        guard !chosen.isEmpty else {
            await MainActor.run { phase = .clear }
            return
        }

        await MainActor.run { phase = .classifying }

        let result = await AILTransformService.shared.transform(
            task: .sensitivityClassify,
            input: text,
            originalRef: ""
        )

        // FAIL OPEN — a failed classifier never hides content.
        guard !result.failOpen else {
            await MainActor.run { phase = .failOpen }
            return
        }

        let matched = Self.matchedTopics(in: result.text, against: chosen)
        await MainActor.run {
            if matched.isEmpty {
                phase = .clear
            } else {
                matchedTopics = matched
                phase = .blurred
            }
        }
    }

    /// Parse the classifier output (a comma/space list of topic raw values) and
    /// intersect it with the topics the user actually opted into. Only user-chosen
    /// topics can ever blur.
    static func matchedTopics(in classifierOutput: String?, against chosen: [SensitivityTopic]) -> [SensitivityTopic] {
        guard let output = classifierOutput?.lowercased(), !output.isEmpty else { return [] }
        let chosenSet = Set(chosen)
        return SensitivityTopic.allCases.filter { topic in
            chosenSet.contains(topic) && output.contains(topic.rawValue)
        }
    }
}

// MARK: - View extension

extension View {

    /// Apply a self-chosen emotional-safety blur to this content.
    ///
    /// - Parameters:
    ///   - text: the content text classified against the user's sensitivity filters.
    ///   - isCrisisHelp: when true, the content is NEVER blurred (crisis-help always shows).
    func ailSensitivityBlur(text: String, isCrisisHelp: Bool = false) -> some View {
        modifier(AILSensitivityBlur(text: text, isCrisisHelp: isCrisisHelp))
    }
}
