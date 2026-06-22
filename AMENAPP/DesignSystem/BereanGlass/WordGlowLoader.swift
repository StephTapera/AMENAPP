// WordGlowLoader.swift
// AMEN — Berean Reading Surface: WordGlowLoader component (W1)
//
// Cycles LIGHT → WORD → TRUTH → GRACE → ABIDE → PEACE via async Task.
// One letter per word glows. ReduceMotion: static word, no glow, no cycle.
// Gate content transitions behind this only — not trivial network loads.
// VoiceOver announces "Loading" once; word cycling is hidden from screen reader.

import SwiftUI

/// Reverent transition indicator — cycles BereanGlowWord set with a glowing letter.
struct WordGlowLoader: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var wordIndex: Int = 0
    @State private var glowLetterIndex: Int = 0
    @State private var isGlowing: Bool = false

    private let words = BereanGlowWord.allCases

    var body: some View {
        Group {
            if reduceMotion {
                staticDisplay
            } else {
                animatedDisplay
                    .task { await cycleWords() }
            }
        }
    }

    private var staticDisplay: some View {
        Text(words[0].rawValue)
            .font(BereanReaderType.sectionHeader)
            .foregroundStyle(Color.bereanInk.opacity(0.45))
            .tracking(6)
            .accessibilityLabel("Loading")
    }

    private var animatedDisplay: some View {
        let word = words[wordIndex % words.count].rawValue
        let letters = Array(word)

        return HStack(spacing: 1) {
            ForEach(Array(letters.enumerated()), id: \.offset) { idx, char in
                Text(String(char))
                    .font(BereanReaderType.sectionHeader)
                    .foregroundStyle(letterColor(at: idx))
                    .shadow(
                        color: idx == glowLetterIndex ? Color.bereanInk.opacity(isGlowing ? 0.25 : 0) : .clear,
                        radius: 8, y: 0
                    )
            }
        }
        .tracking(6)
        .animation(.easeInOut(duration: 0.4), value: isGlowing)
        .animation(.easeInOut(duration: 0.25), value: wordIndex)
        .accessibilityLabel("Loading")
    }

    private func letterColor(at index: Int) -> Color {
        if index == glowLetterIndex {
            return Color.bereanInk.opacity(isGlowing ? 1.0 : 0.3)
        }
        return Color.bereanInk.opacity(0.35)
    }

    private func cycleWords() async {
        let word = words[wordIndex % words.count].rawValue
        glowLetterIndex = Int.random(in: 0..<max(1, word.count))

        withAnimation(.easeInOut(duration: 0.3)) { isGlowing = true }

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_700_000_000) // ~1.7s
            guard !Task.isCancelled else { break }

            withAnimation(.easeInOut(duration: 0.2)) { isGlowing = false }
            try? await Task.sleep(nanoseconds: 220_000_000)

            wordIndex = (wordIndex + 1) % words.count
            let newWord = words[wordIndex].rawValue
            glowLetterIndex = Int.random(in: 0..<max(1, newWord.count))

            try? await Task.sleep(nanoseconds: 100_000_000)
            withAnimation(.easeInOut(duration: 0.3)) { isGlowing = true }
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        WordGlowLoader()
        Text("Loading your study…")
            .font(BereanType.caption())
            .foregroundStyle(Color.bereanInk.opacity(0.4))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.bereanIvory)
}
