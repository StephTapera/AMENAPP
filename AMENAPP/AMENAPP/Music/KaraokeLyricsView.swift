// MUSIC FEATURE — Agent C
import SwiftUI

struct KaraokeLyricsView: View {
    let track: MusicAttachment

    @ObservedObject private var player = AudioPlaybackManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var syncEngine: LyricsSyncEngine

    init(track: MusicAttachment) {
        self.track = track
        // Safe: callers must guard track.lyrics != nil before init
        self.syncEngine = LyricsSyncEngine(track: track.lyrics ?? LyricsTrack(lines: [], isWordSynced: false))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(track.lyrics?.lines ?? []) { line in
                        lyricLineRow(line: line)
                            .id(line.id)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            }
            .frame(maxHeight: 240)
            .clipped()
            .onChange(of: player.currentTimeMs) { _, newTime in
                if let activeIndex = syncEngine.activeLineIndex(atMs: newTime) {
                    let animation: Animation? = reduceMotion ? nil : .easeInOut(duration: 0.3)
                    if let anim = animation {
                        withAnimation(anim) {
                            proxy.scrollTo(activeIndex, anchor: .center)
                        }
                    } else {
                        proxy.scrollTo(activeIndex, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func lyricLineRow(line: LyricLine) -> some View {
        let currentMs = player.currentTimeMs
        let isActive = syncEngine.activeLineIndex(atMs: currentMs) == line.id
        let isPast = line.startMs < currentMs && !isActive

        Group {
            if isActive && (track.lyrics?.isWordSynced == true) && !reduceMotion,
               let progress = syncEngine.wordProgress(atMs: currentMs),
               progress.line == line.id {
                let revealed = String(line.text.prefix(progress.charsRevealed))
                let hidden = String(line.text.dropFirst(min(progress.charsRevealed, line.text.count)))
                HStack(spacing: 0) {
                    Text(revealed)
                        .foregroundStyle(.primary)
                    Text(hidden)
                        .foregroundStyle(.primary.opacity(0.35))
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.glassLyricHighlight)
                )
            } else {
                Text(line.text)
                    .font(isActive ? .body.weight(.semibold) : .body)
                    .foregroundStyle(isActive ? AnyShapeStyle(.primary) : (isPast ? AnyShapeStyle(.primary.opacity(0.35)) : AnyShapeStyle(.primary.opacity(0.5))))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, isActive ? 12 : 0)
                    .padding(.vertical, isActive ? 6 : 0)
                    .background {
                        if isActive {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.glassLyricHighlight)
                        }
                    }
            }
        }
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.2), value: isActive)
    }
}
