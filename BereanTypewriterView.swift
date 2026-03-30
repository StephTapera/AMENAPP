//
//  BereanTypewriterView.swift
//  AMENAPP
//
//  Premium streaming text components for Berean AI.
//  Provides ChatGPT-style chunk-by-chunk streaming with fade-in, blinking cursor,
//  paragraph micro-pauses, and smooth auto-scroll — all SwiftUI-native.
//

import SwiftUI

// MARK: - BereanStreamingTextView

/// Displays live-streamed AI text with word-chunk fade-in, a blinking inline cursor,
/// paragraph micro-pauses (120 ms), and a clean finish state.
///
/// **Integration:** Pass the full `text` string and toggle `isStreaming` off when the
/// Cloud Function stream completes. The view manages all internal chunk animation state
/// based on new characters arriving in `text`.
///
/// ```swift
/// BereanStreamingTextView(
///     text: message.content,
///     isStreaming: isGenerating && message.id == activeMessageId
/// )
/// ```
struct BereanStreamingTextView: View {

    /// The full accumulated text from the stream (grows as chunks arrive).
    let text: String

    /// `true` while the backend stream is active; `false` once complete.
    var isStreaming: Bool = false

    var font: Font = .system(size: 16, weight: .regular)
    var textColor: Color = Color(white: 0.14)
    var lineSpacing: CGFloat = 9

    // MARK: Internal animation state

    /// Segments that have been committed to the stable rendered region.
    @State private var stableText: String = ""
    /// The single in-flight chunk currently fading in.
    @State private var pendingChunk: String = ""
    @State private var pendingOpacity: Double = 0

    /// Buffer of chunks waiting to be displayed, consumed one-at-a-time.
    @State private var chunkQueue: [String] = []
    /// Whether the chunk animation pipeline is currently running.
    @State private var isAnimating: Bool = false

    // Cursor
    @State private var cursorOpacity: Double = 1
    @State private var cursorBlinkTask: Task<Void, Never>?

    // Paragraph pause tracking — we watch for \n\n in incoming deltas
    @State private var lastRenderedLength: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Stable committed text + in-flight chunk + cursor in one layout pass.
            // Built via AttributedString to keep line-wrapping consistent and
            // prevent layout jank from a multi-view stack that recalculates on each chunk.
            composedTextView
                .font(font)
                .foregroundColor(textColor)
                .lineSpacing(lineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: text) { _, newText in
            handleTextUpdate(newText)
        }
        .onChange(of: isStreaming) { _, streaming in
            if !streaming {
                finalizeStream()
            }
        }
        .onAppear {
            if !text.isEmpty {
                handleTextUpdate(text)
            }
            startCursorBlink()
        }
        .onDisappear {
            cursorBlinkTask?.cancel()
        }
        .accessibilityLabel(text)
    }

    // MARK: - Text assembly

    /// Builds a single Text from stable + pending-chunk + cursor segments using
    /// AttributedString composition, avoiding the deprecated Text.+ operator (iOS 26).
    private var composedTextView: Text {
        var result = AttributedString(stableText)

        // Pending chunk with fade-in opacity
        if !pendingChunk.isEmpty {
            var chunk = AttributedString(pendingChunk)
            chunk.foregroundColor = UIColor(textColor.opacity(pendingOpacity))
            result.append(chunk)
        }

        // Blinking cursor
        if isStreaming || isAnimating {
            var cursor = AttributedString("▊")
            cursor.foregroundColor = UIColor(textColor.opacity(cursorOpacity * 0.55))
            result.append(cursor)
        }

        return Text(result)
    }

    // MARK: - Stream processing

    /// Called every time `text` grows. Computes the new delta and enqueues chunks.
    private func handleTextUpdate(_ newText: String) {
        guard newText.count > lastRenderedLength else { return }

        let delta = String(newText.dropFirst(lastRenderedLength))
        lastRenderedLength = newText.count

        if reduceMotion {
            // Instant mode — commit everything immediately, no animation.
            stableText = newText
            pendingChunk = ""
            return
        }

        // Tokenize delta into natural display chunks.
        let chunks = tokenize(delta)
        chunkQueue.append(contentsOf: chunks)
        if !isAnimating {
            drainQueue()
        }
    }

    /// Splits a raw text delta into word-sized display chunks.
    /// Preserves whitespace, punctuation, and paragraph breaks correctly.
    private func tokenize(_ delta: String) -> [String] {
        var chunks: [String] = []
        var current = ""

        var i = delta.startIndex
        while i < delta.endIndex {
            let ch = delta[i]

            // Paragraph break — emit as its own chunk to allow micro-pause logic.
            if ch == "\n" {
                if !current.isEmpty {
                    chunks.append(current)
                    current = ""
                }
                // Collect consecutive newlines as a single paragraph-break chunk.
                var newlines = ""
                while i < delta.endIndex && delta[i] == "\n" {
                    newlines.append(delta[i])
                    i = delta.index(after: i)
                }
                chunks.append(newlines)
                continue
            }

            // Word boundary: emit when we hit a space after non-space content.
            if ch == " " {
                current.append(ch)
                // Include trailing spaces as part of the previous word token.
                while i < delta.endIndex,
                      delta.index(after: i) < delta.endIndex,
                      delta[delta.index(after: i)] == " " {
                    i = delta.index(after: i)
                    current.append(delta[i])
                }
                chunks.append(current)
                current = ""
            } else {
                current.append(ch)
            }

            i = delta.index(after: i)
        }

        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    /// Consumes the chunk queue one item at a time, animating each in.
    private func drainQueue() {
        guard !chunkQueue.isEmpty else {
            isAnimating = false
            return
        }

        isAnimating = true
        let chunk = chunkQueue.removeFirst()
        let isParagraphBreak = chunk.allSatisfy { $0 == "\n" } && chunk.count >= 2

        Task { @MainActor in
            // Micro-pause before rendering paragraph breaks.
            if isParagraphBreak {
                try? await Task.sleep(nanoseconds: 120_000_000) // 120 ms
            }

            guard !Task.isCancelled else { return }

            // Show the new chunk with a fade-in.
            pendingChunk = chunk
            pendingOpacity = 0

            withAnimation(.easeOut(duration: 0.08)) {
                pendingOpacity = 1
            }

            // After the fade, commit to stable and advance.
            try? await Task.sleep(nanoseconds: 85_000_000) // slightly past fade duration
            guard !Task.isCancelled else { return }

            stableText += pendingChunk
            pendingChunk = ""
            pendingOpacity = 0

            // Continue draining without recursion overhead.
            drainQueue()
        }
    }

    /// Called when `isStreaming` transitions to `false` — flush remaining queue
    /// and fade the cursor out cleanly.
    private func finalizeStream() {
        // If reduce motion, nothing queued — just ensure cursor is gone.
        if reduceMotion {
            stableText = text
            pendingChunk = ""
            return
        }

        // Let the queue drain naturally; once it's empty isAnimating becomes false
        // and the cursor view returns Text(""). Then we fade it out.
        Task { @MainActor in
            // Wait for queue to drain (poll cheaply).
            while isAnimating {
                try? await Task.sleep(nanoseconds: 30_000_000) // 30 ms poll
            }
            // Flush any residual (safety).
            if !pendingChunk.isEmpty {
                stableText += pendingChunk
                pendingChunk = ""
            }
            // Cursor fade-out.
            withAnimation(.easeOut(duration: 0.3)) {
                cursorOpacity = 0
            }
            cursorBlinkTask?.cancel()
        }
    }

    // MARK: - Cursor blink

    private func startCursorBlink() {
        cursorBlinkTask?.cancel()
        cursorBlinkTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 530_000_000) // ~0.53 s half-period
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        cursorOpacity = cursorOpacity > 0.5 ? 0.0 : 1.0
                    }
                }
            }
        }
    }
}

// MARK: - TypewriterTextView
// Retained for the BereanHeroGreetingView landing animation (greeting line).
// This component handles a *fixed* string typed in once — distinct from live streaming.

/// Reveals a fixed string word-by-word with a subtle fade-in per word.
/// Used exclusively for the landing hero greeting animation.
/// Respects `accessibilityReduceMotion`.
struct TypewriterTextView: View {

    let text: String
    var font: Font = .system(size: 36, weight: .bold, design: .default)
    var textColor: Color = Color(.label)
    var typingInterval: TimeInterval = 0.07   // per-word interval
    var cursorVisible: Bool = true
    var onComplete: (() -> Void)? = nil

    @State private var displayedWordCount: Int = 0
    @State private var cursorOpacity: Double = 0
    @State private var isComplete: Bool = false
    @State private var typingTask: Task<Void, Never>? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var words: [String] { splitWords(text) }

    private var displayedText: String {
        words.prefix(displayedWordCount).joined()
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
                    .frame(width: 2.5, height: cursorBlockHeight)
                    .foregroundColor(textColor.opacity(0.65))
                    .opacity(cursorOpacity)
                    .animation(
                        .easeInOut(duration: 0.48).repeatForever(autoreverses: true),
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

    private var cursorBlockHeight: CGFloat {
        switch font {
        case .largeTitle: return 32
        default:          return 28
        }
    }

    /// Splits text into word-sized tokens preserving whitespace so rejoined text is exact.
    private func splitWords(_ s: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for ch in s {
            if ch == " " {
                if !current.isEmpty {
                    tokens.append(current + " ")
                    current = ""
                }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private func startTyping() {
        typingTask?.cancel()
        displayedWordCount = 0
        isComplete = false

        if reduceMotion || typingInterval == 0 {
            displayedWordCount = words.count
            isComplete = true
            onComplete?()
            return
        }

        // Start cursor blink
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            cursorOpacity = 1
        }

        typingTask = Task {
            for i in 1...max(1, words.count) {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.10)) {
                        displayedWordCount = i
                    }
                }
                try? await Task.sleep(nanoseconds: UInt64(typingInterval * 1_000_000_000))
            }
            await MainActor.run {
                isComplete = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        cursorOpacity = 0
                    }
                }
                onComplete?()
            }
        }
    }

    private func restartTyping() {
        typingTask?.cancel()
        displayedWordCount = 0
        isComplete = false
        startTyping()
    }
}

// MARK: - BereanHeroGreetingView

/// Landing screen hero: greeting word-types in, follow-up fades up beneath it.
/// Centered vertically and horizontally. Subtitle removed for cleaner UI.
struct BereanHeroGreetingView: View {

    let greeting: BereanGreeting

    /// Set false to suppress animation replay in the same session.
    var shouldAnimate: Bool = true

    var onSequenceComplete: (() -> Void)? = nil

    @State private var followUpVisible = false
    @State private var heroOpacity: Double = 0
    @State private var heroOffset: CGFloat = 16

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            // — Greeting line —
            TypewriterTextView(
                text: greeting.greeting,
                font: .system(size: 42, weight: .bold, design: .default),
                textColor: Color(.label),
                typingInterval: shouldAnimate ? 0.055 : 0,
                cursorVisible: shouldAnimate,
                onComplete: {
                    guard shouldAnimate else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                        withAnimation(.easeOut(duration: 0.48)) {
                            followUpVisible = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) {
                            onSequenceComplete?()
                        }
                    }
                }
            )
            .multilineTextAlignment(.center)

            // — Follow-up question —
            Text(greeting.followUp)
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(Color(.secondaryLabel))
                .multilineTextAlignment(.center)
                .opacity(shouldAnimate ? (followUpVisible ? 1 : 0) : 1)
                .offset(y: shouldAnimate ? (followUpVisible ? 0 : 7) : 0)
                .animation(
                    .spring(response: 0.50, dampingFraction: 0.85),
                    value: followUpVisible
                )
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .opacity(heroOpacity)
        .offset(y: heroOffset)
        .onAppear {
            if shouldAnimate && !reduceMotion {
                withAnimation(.spring(response: 0.60, dampingFraction: 0.82)) {
                    heroOpacity = 1
                    heroOffset = 0
                }
            } else {
                heroOpacity = 1
                heroOffset = 0
                followUpVisible = true
            }
        }
        .onChange(of: shouldAnimate) { _, newValue in
            if newValue {
                followUpVisible = false
                heroOpacity = 0
                heroOffset = 16
            }
        }
    }
}

// MARK: - BereanStreamingScrollView

/// A scroll container that follows the bottom of streaming output while the user
/// is at or near the bottom. Once the user scrolls up, auto-follow pauses until
/// the stream completes or the user scrolls back down.
struct BereanStreamingScrollView<Content: View>: View {

    var isStreaming: Bool
    @ViewBuilder var content: () -> Content

    @State private var isNearBottom = true
    @State private var scrollProxy: ScrollViewProxy?

    private let anchorID = "streaming-bottom-anchor"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    content()
                    // Invisible anchor at the very bottom.
                    Color.clear
                        .frame(height: 1)
                        .id(anchorID)
                }
            }
            .onAppear { scrollProxy = proxy }
            .onChange(of: isStreaming) { _, streaming in
                // When stream ends, scroll to bottom one final time.
                if !streaming {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(anchorID, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    /// Call this whenever new content is appended to trigger a follow-scroll.
    func scrollToBottomIfNeeded() {
        guard isNearBottom, let proxy = scrollProxy else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo(anchorID, anchor: .bottom)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Morning — animated") {
    ZStack {
        Color(white: 0.96).ignoresSafeArea()
        VStack {
            Spacer()
            BereanHeroGreetingView(
                greeting: BereanGreeting(
                    greeting: "Good morning.",
                    followUp: "How can I help today?"
                ),
                shouldAnimate: true
            )
            Spacer()
        }
    }
}

#Preview("Evening — static") {
    ZStack {
        Color(white: 0.96).ignoresSafeArea()
        VStack {
            Spacer()
            BereanHeroGreetingView(
                greeting: BereanGreeting(
                    greeting: "Good evening.",
                    followUp: "What wisdom are you seeking?"
                ),
                shouldAnimate: false
            )
            Spacer()
        }
    }
}

#Preview("Streaming text") {
    struct PreviewContainer: View {
        @State private var text = ""
        @State private var isStreaming = false
        private let sample = "The book of Psalms is a rich collection of poetry and song that captures the full range of human emotion before God. From lament to praise, from despair to profound hope, the Psalms give us language for every season of the soul.\n\nPsalm 23 in particular reveals a God who is intimately present — not distant or indifferent, but actively shepherding those who trust Him."

        var body: some View {
            ZStack {
                Color(white: 0.97).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        BereanStreamingTextView(text: text, isStreaming: isStreaming)
                            .padding(24)
                    }
                }
                VStack {
                    Spacer()
                    Button(isStreaming ? "Stop" : "Start") {
                        if isStreaming {
                            isStreaming = false
                        } else {
                            text = ""
                            isStreaming = true
                            streamSample()
                        }
                    }
                    .padding()
                }
            }
        }

        private func streamSample() {
            var cursor = sample.startIndex
            Task {
                while cursor < sample.endIndex && isStreaming {
                    let end = sample.index(cursor, offsetBy: min(4, sample.distance(from: cursor, to: sample.endIndex)))
                    await MainActor.run { text += String(sample[cursor..<end]) }
                    cursor = end
                    try? await Task.sleep(nanoseconds: 35_000_000)
                }
                await MainActor.run { isStreaming = false }
            }
        }
    }
    return PreviewContainer()
}
#endif
