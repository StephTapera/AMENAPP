// MUSIC FEATURE — Agent C
import SwiftUI

struct MusicCardContainer: View {
    let track: MusicAttachment
    @Binding var displayMode: MusicCardMode

    var body: some View {
        switch displayMode {
        case .compact:
            MusicCardCompact(track: track) { displayMode = .expanded }
        case .expanded:
            MusicCardExpanded(track: track) { displayMode = .compact }
        case .vinyl:
            VinylMusicCard(track: track) { displayMode = .compact }
        }
    }
}
