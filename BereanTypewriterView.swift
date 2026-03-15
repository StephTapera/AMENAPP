//
//  BereanTypewriterView.swift
//  AMENAPP
//
//  A production-ready, reduce-motion-safe typewriter text component for Berean AI.
//

import SwiftUI

// MARK: - TypewriterTextView

/// Reveals text character-by-character with an optional blinking cursor.
/// Respects `accessibilityReduceMotion` — when active, text appears instantly.
struct TypewriterTextView: View {

    let text: String
    var font: Font = .system(size: 36, weight: .bold, design: .default)
    var textColor: Color = Color(.label)
    var typingInterval: TimeInterval = 0.045
    var cursorVisible: Bool = true
    var onComplete: (() -> Void)? = nil

    @State private var displayedCharCount: Int = 0
    @State private var cursorOpacity: Double = 0
    @State private var isComplete: Bool = false
    @State private var typingTask: Task<Void, Never>? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var displayedText: String {
        String(text.prefix(displayedCharCount))
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 1) {
            Text(displayedText)
                .font(font)
                .foregroundColor(textColor)
                .lineLimit(nil)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if cursorVisible && !isComplete {
                Rectangle()
                    .frame(width: 2.5, height: cursorHeight)
                    .foregroundColor(textColor.opacity(0.7))
                    .opacity(cursorOpacity)
                    .animation(
                        .easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                        value: cursorOpacity
                    )
            }
        }
        .onAppear { startTyping() }
        .onChange(of: text) { _, _ in restartTyping() }
        .onDisappear { typingTask?.cancel() }
        .accessibilityLabel(text)
    }

    // MARK: - Private

    private var cursorHeight: CGFloat {
        // Approximate cap height for the given font size
        switch font {
        case .largeTitle: return 32
        default: return 28
        }
    }

    private func startTyping() {
        typingTask?.cancel()
        displayedCharCount = 0
        isComplete = false

        if reduceMotion {
            // Instant reveal — no animation
            displayedCharCount = text.count
            isComplete = true
            onComplete?()
            return
        }

        // Start cursor blink
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            cursorOpacity = 1
        }

        typingTask = Task {
            for i in 1...max(1, text.count) {
                guard !Task.isCancelled else { return }
                await MainActor.run { displayedCharCount = i }
                // Slightly vary timing: punctuation gets a longer pause
                let char = text[text.index(text.startIndex, offsetBy: min(i - 1, text.count - 1))]
                let delay: TimeInterval
                if ".!?,;:".contains(char) {
                    delay = typingInterval * 4.5
                } else if char == " " {
                    delay = typingInterval * 0.6
                } else {
                    delay = typingInterval
                }
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            await MainActor.run {
                isComplete = true
                // Cursor fades out after short blink period
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        cursorOpacity = 0
                    }
                }
                onComplete?()
            }
        }
    }

    private func restartTyping() {
        typingTask?.cancel()
        displayedCharCount = 0
        isComplete = false
        startTyping()
    }
}

// MARK: - BereanHeroGreetingView

/// Two-line hero: greeting types in, then follow-up fades up beneath it.
struct BereanHeroGreetingView: View {

    let greeting: BereanGreeting

    /// Set false to suppress animation replay in same session (re-set true on reopen).
    var shouldAnimate: Bool = true

    var onSequenceComplete: (() -> Void)? = nil

    @State private var greetingComplete = false
    @State private var followUpVisible = false
    @State private var subtitleVisible = false
    @State private var heroOffset: CGFloat = 18

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            // — Greeting line —
            TypewriterTextView(
                text: greeting.greeting,
                font: .system(size: 42, weight: .bold, design: .default),
                textColor: Color(.label),
                typingInterval: shouldAnimate ? 0.055 : 0,
                cursorVisible: shouldAnimate,
                onComplete: {
                    guard shouldAnimate else { return }
                    // Brief pause, then reveal follow-up
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
                        withAnimation(.easeOut(duration: 0.52)) {
                            followUpVisible = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                            withAnimation(.easeOut(duration: 0.45)) {
                                subtitleVisible = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                onSequenceComplete?()
                            }
                        }
                    }
                }
            )
            .multilineTextAlignment(.center)

            // — Follow-up question —
            Text(greeting.followUp)
                .font(.system(size: 20, weight: .regular, design: .default))
                .foregroundColor(Color(.secondaryLabel))
                .multilineTextAlignment(.center)
                .opacity(shouldAnimate ? (followUpVisible ? 1 : 0) : 1)
                .offset(y: shouldAnimate ? (followUpVisible ? 0 : 8) : 0)

            // — Subtitle —
            Text(BereanGreetingManager.subtitle)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(Color(.tertiaryLabel))
                .multilineTextAlignment(.center)
                .padding(.top, 4)
                .opacity(shouldAnimate ? (subtitleVisible ? 1 : 0) : 1)
                .offset(y: shouldAnimate ? (subtitleVisible ? 0 : 6) : 0)
        }
        .padding(.horizontal, 32)
        .offset(y: heroOffset)
        .onAppear {
            if shouldAnimate && !reduceMotion {
                withAnimation(.spring(response: 0.62, dampingFraction: 0.82)) {
                    heroOffset = 0
                }
            } else {
                heroOffset = 0
                followUpVisible = true
                subtitleVisible = true
            }
        }
        .onChange(of: shouldAnimate) { _, newValue in
            if newValue {
                // Reset for re-animation on reopen
                followUpVisible = false
                subtitleVisible = false
                heroOffset = 18
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Morning") {
    BereanHeroGreetingView(
        greeting: BereanGreeting(greeting: "Good morning.", followUp: "How can I help today?"),
        shouldAnimate: true
    )
    .padding()
}

#Preview("Evening — no animate") {
    BereanHeroGreetingView(
        greeting: BereanGreeting(greeting: "Good evening.", followUp: "What wisdom are you seeking?"),
        shouldAnimate: false
    )
    .padding()
}
#endif
