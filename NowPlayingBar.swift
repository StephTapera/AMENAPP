// NowPlayingBar.swift — Persistent mini-player bar for Christian Media

import SwiftUI



struct NowPlayingBar: View {
    @ObservedObject var vm: ChristianMediaViewModel
    @State private var showPlayerSheet = false

    private let accentPurple = Color(red: 0.49, green: 0.23, blue: 0.93)

    var body: some View {
        if let item = vm.currentItem {
            VStack(spacing: 0) {
                // Live progress bar at top
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Color.primary.opacity(0.08)
                            .frame(height: 2)
                        accentPurple
                            .frame(width: geo.size.width * vm.progress, height: 2)
                            .animation(.linear(duration: 0.1), value: vm.progress)
                    }
                }
                .frame(height: 2)

                HStack(spacing: 12) {
                    // Thumbnail
                    AsyncImage(url: URL(string: item.thumbnailURL)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure, .empty:
                            Color(hex: item.dominantColor)
                        @unknown default:
                            Color(hex: item.dominantColor)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    // Title + Author
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(item.author)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Playback Controls
                    HStack(spacing: 20) {
                        Button(action: vm.previousItem) {
                            Image(systemName: "chevron.backward.2")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.primary)
                        }

                        Button(action: vm.togglePlayback) {
                            Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(.primary)
                        }

                        Button(action: vm.nextItem) {
                            Image(systemName: "chevron.forward.2")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(.trailing, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .onTapGesture {
                    showPlayerSheet = true
                }
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 0))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: -2)
            .sheet(isPresented: $showPlayerSheet) {
                MediaPlayerView(vm: vm)
            }
        }
    }
}
