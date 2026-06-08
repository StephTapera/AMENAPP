//
//  AMENTypography.swift
//  AMENAPP
//
//  Premium animated typography components for AMEN.
//  All animation is calm, Apple-quality, and spiritually grounded.
//  Prioritises readability — motion is brief and purposeful.
//
//  Components:
//    AnimatedHeadlineView    — per-line stagger reveal (onboarding, empty states)
//    StaggeredWordRevealView — per-word cascade for short emphasis text
//    MaskedSlideUpText       — fade + lift + soft blur for moment-of-truth reveals
//
//  Usage notes:
//    - Every component respects accessibilityReduceMotion automatically.
//    - `triggerKey` on AnimatedHeadlineView lets you re-fire the animation when
//       the content changes (e.g. onboarding step transitions).
//    - Keep body/paragraph text static — animate only headlines and key moments.
//

import SwiftUI

// MARK: - AnimatedHeadlineView
//
// Reveals a headline line-by-line with a staggered spring entrance.
// Lines are split by "\n" so multi-line strings work naturally.
// Trigger re-animation by changing `triggerKey`.
//
// Example:
//   AnimatedHeadlineView("Built different.")
//   AnimatedHeadlineView("Your data,\nyour rules.", delay: 0.08)
//   AnimatedHeadlineView("Step complete.", triggerKey: AnyHashable(step))

public struct AnimatedHeadlineView: View {

    public let text: String
    public var font: Font = .systemScaled(42, weight: .black)
    public var color: Color = Color(.label)
    public var lineSpacing: CGFloat = 1
    public var lineDelay: Double = 0.09   // stagger per additional line
    public var initialDelay: Double = 0.0
    public var triggerKey: AnyHashable = AnyHashable(0)

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        _ text: String,
        font: Font = .systemScaled(42, weight: .black),
        color: Color = Color(.label),
        lineSpacing: CGFloat = 1,
        lineDelay: Double = 0.09,
        delay: Double = 0.0,
        triggerKey: AnyHashable = AnyHashable(0)
    ) {
        self.text = text
        self.font = font
        self.color = color
        self.lineSpacing = lineSpacing
        self.lineDelay = lineDelay
        self.initialDelay = delay
        self.triggerKey = triggerKey
    }

    public var body: some View {
        let lines = text.components(separatedBy: "\n")
        VStack(alignment: .leading, spacing: lineSpacing) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .font(font)
                    .foregroundColor(color)
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(y: appeared ? 0 : 14)
                    .opacity(appeared ? 1 : 0)
                    .animation(
                        reduceMotion ? .none :
                            .spring(response: 0.52, dampingFraction: 0.84)
                            .delay(initialDelay + Double(index) * lineDelay),
                        value: appeared
                    )
            }
        }
        .onAppear { fire() }
        .onChange(of: triggerKey) { _, _ in reset() }
    }

    private func fire() {
        guard !reduceMotion else { appeared = true; return }
        if initialDelay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay) { appeared = true }
        } else {
            appeared = true
        }
    }

    private func reset() {
        appeared = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { appeared = true }
    }
}

// MARK: - StaggeredWordRevealView
//
// Reveals each word individually with a soft fade + upward lift,
// cascading from left to right at a configurable interval.
//
// Best for short emphasis phrases (up to ~6 words).
// For longer or multi-line text, prefer AnimatedHeadlineView.
//
// Example:
//   StaggeredWordRevealView("Ask with clarity.")
//   StaggeredWordRevealView("Good morning.", font: .systemScaled(20))

public struct StaggeredWordRevealView: View {

    public let text: String
    public var font: Font = .systemScaled(36, weight: .bold)
    public var color: Color = Color(.label)
    public var wordInterval: Double = 0.07   // delay between consecutive words
    public var initialDelay: Double = 0.0

    @State private var revealedCount = 0
    @State private var revealTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Word tokens — split preserving spaces after words so rejoin is exact.
    private var tokens: [String] {
        var result: [String] = []
        var current = ""
        for ch in text {
            if ch == " " {
                if !current.isEmpty { result.append(current + " "); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    public init(
        _ text: String,
        font: Font = .systemScaled(36, weight: .bold),
        color: Color = Color(.label),
        wordInterval: Double = 0.07,
        delay: Double = 0.0
    ) {
        self.text = text
        self.font = font
        self.color = color
        self.wordInterval = wordInterval
        self.initialDelay = delay
    }

    public var body: some View {
        // Invisible full text sets the frame so layout never jumps.
        ZStack(alignment: .topLeading) {
            Text(text)
                .font(font)
                .foregroundColor(.clear)
                .fixedSize(horizontal: false, vertical: true)

            // Revealed words — rendered inline using Text concatenation.
            // Each word is added as soon as its reveal slot fires.
            Text(revealedText)
                .font(font)
                .foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { startReveal() }
        .onDisappear { revealTask?.cancel() }
        .accessibilityLabel(text)
    }

    private var revealedText: String {
        tokens.prefix(revealedCount).joined()
    }

    private func startReveal() {
        if reduceMotion { revealedCount = tokens.count; return }
        revealTask?.cancel()
        revealedCount = 0
        revealTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(initialDelay * 1_000_000_000))
            for i in 1...max(1, tokens.count) {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.12)) { revealedCount = i }
                }
                try? await Task.sleep(nanoseconds: UInt64(wordInterval * 1_000_000_000))
            }
        }
    }
}

// MARK: - MaskedSlideUpText
//
// Premium one-shot reveal: text fades in while lifting gently from below.
// A soft blur at the start adds a sense of depth — the text appears to
// surface from stillness rather than pop in.
//
// Best for:
//   - Moment-of-truth headlines (Church Notes title, reflection cards)
//   - Empty-state primary messages
//   - Any single line where maximum intentionality is needed
//
// Example:
//   MaskedSlideUpText("You're All Caught Up", font: .systemScaled(20, weight: .bold))
//   MaskedSlideUpText("Note Title", delay: 0.1)

public struct MaskedSlideUpText: View {

    public let text: String
    public var font: Font = .systemScaled(20, weight: .bold)
    public var color: Color = Color(.label)
    public var delay: Double = 0.0
    public var liftDistance: CGFloat = 20   // how far the text starts below its resting place
    public var useSoftBlur: Bool = true     // adds depth-blur at start for premium feel

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        _ text: String,
        font: Font = .systemScaled(20, weight: .bold),
        color: Color = Color(.label),
        delay: Double = 0.0,
        liftDistance: CGFloat = 20,
        softBlur: Bool = true
    ) {
        self.text = text
        self.font = font
        self.color = color
        self.delay = delay
        self.liftDistance = liftDistance
        self.useSoftBlur = softBlur
    }

    public var body: some View {
        Text(text)
            .font(font)
            .foregroundColor(color)
            .fixedSize(horizontal: false, vertical: true)
            // Lift
            .offset(y: appeared ? 0 : liftDistance)
            // Fade
            .opacity(appeared ? 1 : 0)
            // Soft depth-blur — fades from 2pt to 0 as text arrives
            .blur(radius: (useSoftBlur && !reduceMotion) ? (appeared ? 0 : 2.5) : 0)
            .animation(
                reduceMotion ? .none :
                    .spring(response: 0.58, dampingFraction: 0.84).delay(delay),
                value: appeared
            )
            .onAppear {
                if reduceMotion { appeared = true; return }
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { appeared = true }
            }
    }
}

// MARK: - ONBAnimatedHeadline
//
// Convenience wrapper for onboarding headlines.
// Fires automatically on appear; no triggerKey needed because
// ONBStepTransition creates a new view instance for each step.

struct ONBAnimatedHeadline: View {
    let text: String
    var delay: Double = 0.0

    var body: some View {
        AnimatedHeadlineView(
            text,
            font: .systemScaled(42, weight: .black),
            color: Color(UIColor.label),
            lineSpacing: 2,
            delay: delay
        )
    }
}

// MARK: - ReflectionRevealCard
//
// Animated container for featured reflection text (e.g. CaughtUpCard prompt).
// Headline uses MaskedSlideUpText; body fades in softly below.

struct ReflectionRevealCard<Content: View>: View {
    let headline: String
    var headlineFont: Font = .systemScaled(20, weight: .bold)
    var headlineDelay: Double = 0.0
    @ViewBuilder var body_: () -> Content

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            MaskedSlideUpText(
                headline,
                font: headlineFont,
                color: Color(.label),
                delay: headlineDelay
            )
            .multilineTextAlignment(.center)

            body_()
                .opacity(1)  // body content is static per design rules
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("AnimatedHeadlineView") {
    struct Demo: View {
        @State private var step = 0
        let headlines = [
            "Built different.",
            "Make it yours.",
            "Your data,\nyour rules.",
            "What matters\nto you?"
        ]
        var body: some View {
            VStack(spacing: 32) {
                AnimatedHeadlineView(
                    headlines[step],
                    triggerKey: AnyHashable(step)
                )
                .padding(.horizontal, 24)
                Button("Next step") { step = (step + 1) % headlines.count }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(UIColor.systemBackground))
        }
    }
    return Demo()
}

#Preview("StaggeredWordRevealView") {
    VStack(spacing: 20) {
        StaggeredWordRevealView("Ask with clarity.", font: .systemScaled(36, weight: .bold))
        StaggeredWordRevealView("Good morning.", font: .systemScaled(36, weight: .bold), wordInterval: 0.10)
        StaggeredWordRevealView("You're All Caught Up", font: .systemScaled(20, weight: .bold), wordInterval: 0.06)
    }
    .padding(24)
}

#Preview("MaskedSlideUpText") {
    VStack(spacing: 24) {
        MaskedSlideUpText("You're All Caught Up", font: .systemScaled(20, weight: .bold))
        MaskedSlideUpText("Romans 8", font: .systemScaled(32, weight: .medium), delay: 0.12)
        MaskedSlideUpText(
            "Consider spending a few minutes in prayer.",
            font: .systemScaled(15, weight: .regular),
            color: Color(.secondaryLabel),
            delay: 0.22,
            softBlur: false
        )
    }
    .padding(24)
}
#endif
