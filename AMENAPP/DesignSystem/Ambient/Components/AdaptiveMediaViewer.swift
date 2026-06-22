//
//  AdaptiveMediaViewer.swift
//  AMEN — Adaptive Ambient UI System (Phase 2B)
//
//  Full-screen media pager. Swipes crossfade the ambient palette; controls float in glass pills.
//  Video drives ambient via AmbientVideoSampler at a safe 3s cadence — never per frame.
//

import SwiftUI
import AVKit

public struct AdaptiveMediaViewer: View {
    public struct Item: Identifiable {
        public let id: String
        public let revision: String
        public let image: UIImage?            // photo or video poster
        public let player: AVPlayer?          // non-nil ⇒ video
        public let asset: AVAsset?
        public init(id: String, revision: String, image: UIImage?,
                    player: AVPlayer? = nil, asset: AVAsset? = nil) {
            self.id = id; self.revision = revision; self.image = image
            self.player = player; self.asset = asset
        }
    }

    let items: [Item]
    @State private var selection: String
    @StateObject private var videoSampler = AmbientVideoSampler()
    @ObservedObject var coordinator: AmbientCoordinator
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ambientPalette) private var palette

    public init(items: [Item], coordinator: AmbientCoordinator) {
        self.items = items
        self.coordinator = coordinator
        _selection = State(initialValue: items.first?.id ?? "")
    }

    public var body: some View {
        ZStack {
            AdaptiveAmbientBackground(bleedImage: current?.image, bleedHeight: 560)

            TabView(selection: $selection) {
                ForEach(items) { item in
                    Group {
                        if let player = item.player {
                            VideoPlayer(player: player).tint(palette.accent) // accent from content
                        } else if let img = item.image {
                            Image(uiImage: img).resizable().scaledToFit()
                        }
                    }
                    .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack {
                Spacer()
                AdaptiveGlassContainer {
                    HStack(spacing: 28) {
                        Image(systemName: "heart")
                        Image(systemName: "bubble.right")
                        Image(systemName: "square.and.arrow.up")
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 22).padding(.vertical, 12)
                }
                .padding(.bottom, 24)
            }
        }
        .onChange(of: selection) { _, _ in driveCurrent() }
        .onChange(of: videoSampler.currentFrame) { _, frame in
            guard let frame, let cur = current, cur.player != nil else { return }
            coordinator.drive(with: frame,
                              key: .init(id: cur.id,
                                         revision: "\(cur.revision)-live-\(Int(Date().timeIntervalSince1970))"),
                              scheme: scheme, reduceMotion: reduceMotion)
        }
        .onAppear { driveCurrent() }
        .onDisappear { videoSampler.detach() }
        .statusBarHidden(false)
        .preferredColorScheme(palette.isDarkContent ? .dark : nil)
    }

    private var current: Item? { items.first { $0.id == selection } }

    private func driveCurrent() {
        guard let cur = current else { return }
        coordinator.drive(with: cur.image,
                          key: .init(id: cur.id, revision: cur.revision),
                          scheme: scheme, reduceMotion: reduceMotion)
        videoSampler.detach()
        if let player = cur.player, let asset = cur.asset {
            videoSampler.attach(to: player, asset: asset)
        }
    }
}
