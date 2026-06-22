//
//  AmbientVideoSampler.swift
//  AMEN — Adaptive Ambient UI System (Phase 2A)
//
//  Samples a playing video's palette at safe intervals — never per frame (Rules §5).
//  3s cadence + scene-change gate (Δluma > 0.06) kills churn on static shots.
//

import AVFoundation
import UIKit

/// Samples a playing video's palette at safe intervals — never per frame.
@MainActor
public final class AmbientVideoSampler: ObservableObject {
    @Published public private(set) var currentFrame: UIImage?

    private var generator: AVAssetImageGenerator?
    private var timeObserver: Any?
    private weak var player: AVPlayer?
    private var lastMean: Double = -1

    public init() {}

    public func attach(to player: AVPlayer, asset: AVAsset, interval: TimeInterval = 3.0) {
        detach()
        self.player = player
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 200, height: 200)   // thumbnail-class analysis only
        generator = gen

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: interval, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { await self?.sample(at: time) }
        }
    }

    public func detach() {
        if let o = timeObserver, let p = player { p.removeTimeObserver(o) }
        timeObserver = nil; generator = nil; player = nil
    }

    private func sample(at time: CMTime) async {
        guard let gen = generator else { return }
        let img: CGImage? = try? await gen.image(at: time).image
        guard let cg = img else { return }
        // Scene-change gate: skip palette churn when the frame barely changed.
        let mean = Self.meanLuma(cg)
        guard abs(mean - lastMean) > 0.06 else { return }
        lastMean = mean
        currentFrame = UIImage(cgImage: cg)
    }

    private static func meanLuma(_ cg: CGImage) -> Double {
        let s = 8
        guard let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8,
                                  bytesPerRow: s * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 0 }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: s, height: s))
        guard let d = ctx.data else { return 0 }
        let p = d.bindMemory(to: UInt8.self, capacity: s * s * 4)
        var sum = 0.0
        for i in stride(from: 0, to: s * s * 4, by: 4) {
            sum += (0.299 * Double(p[i]) + 0.587 * Double(p[i + 1]) + 0.114 * Double(p[i + 2])) / 255
        }
        return sum / Double(s * s)
    }
}
