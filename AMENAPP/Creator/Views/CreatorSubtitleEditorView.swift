import SwiftUI

struct CreatorSubtitleEditorView: View {
    let track: CreatorSubtitleTrack

    var body: some View {
        VStack(spacing: 8) {
            ForEach(track.segments.indices, id: \.self) { index in
                CreatorGlassCard {
                    Text(track.segments[index].text)
                        .font(AMENFont.medium(12))
                        .foregroundStyle(Color.black.opacity(0.7))
                }
            }
        }
    }
}
