//
//  AdaptiveColorEngine.swift
//  AMEN — Adaptive Ambient UI System (Phase 2A)
//
//  Actor-isolated palette extraction with NSCache. Never touches the main thread (C7).
//  Engine failure / missing media / extraction timeout ⇒ neutral(for:) — fail-closed (C5).
//  Contrast enforcement is fail-closed: textPrimary vs background ≥ 4.5:1 always (C1).
//

import SwiftUI
import UIKit
import CoreGraphics

/// Actor-isolated palette extraction with NSCache. Never touches the main thread.
public actor AdaptiveColorEngine {

    public static let shared = AdaptiveColorEngine()

    private let cache = NSCache<NSString, CachedPalettePair>()
    private init() { cache.countLimit = 256 }

    final class CachedPalettePair {
        let light: AmbientPalette
        let dark: AmbientPalette
        init(light: AmbientPalette, dark: AmbientPalette) { self.light = light; self.dark = dark }
    }

    // MARK: Public API

    /// Primary entry point. Returns cached palette instantly when available.
    /// `image` should be a thumbnail (engine downsamples regardless, but pass ≤ 600px to save IO).
    public func palette(
        for image: UIImage,
        key: AmbientSourceKey,
        colorScheme: ColorScheme
    ) async -> AmbientPalette {
        if let hit = cache.object(forKey: key.cacheKey as NSString) {
            return colorScheme == .dark ? hit.dark : hit.light
        }
        guard let cg = image.cgImage ?? image.ciImageBackedCG() else {
            return .neutral(for: colorScheme)                       // C5 fail-closed
        }
        let raw = Self.extract(from: cg)
        guard let raw else { return .neutral(for: colorScheme) }    // C5 fail-closed
        let pair = CachedPalettePair(
            light: Self.derive(raw, scheme: .light),
            dark: Self.derive(raw, scheme: .dark)
        )
        cache.setObject(pair, forKey: key.cacheKey as NSString)
        return colorScheme == .dark ? pair.dark : pair.light
    }

    public func invalidate(_ key: AmbientSourceKey) {
        cache.removeObject(forKey: key.cacheKey as NSString)
    }

    // MARK: - Extraction (downsample → weighted histogram → candidate clusters)

    struct RGB: Equatable {
        var r: Double; var g: Double; var b: Double
        var luminance: Double { // WCAG relative luminance
            func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        }
        var saturation: Double {
            let mx = max(r, g, b), mn = min(r, g, b)
            return mx == 0 ? 0 : (mx - mn) / mx
        }
        func distance(to o: RGB) -> Double {
            let dr = r - o.r, dg = g - o.g, db = b - o.b
            return sqrt(dr * dr + dg * dg + db * db)
        }
    }

    struct RawPalette {
        var dominant: RGB
        var accent: RGB
        var meanLuminance: Double
    }

    static func contrastRatio(_ a: RGB, _ b: RGB) -> Double {
        let l1 = max(a.luminance, b.luminance), l2 = min(a.luminance, b.luminance)
        return (l1 + 0.05) / (l2 + 0.05)
    }

    private static func extract(from cg: CGImage) -> RawPalette? {
        let side = 48
        guard let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = ctx.data else { return nil }
        let px = data.bindMemory(to: UInt8.self, capacity: side * side * 4)

        // 4-bit/channel histogram = 4096 buckets, center-weighted (faces/subjects live center-frame).
        var weight = [Double](repeating: 0, count: 4096)
        var sumR = [Double](repeating: 0, count: 4096)
        var sumG = [Double](repeating: 0, count: 4096)
        var sumB = [Double](repeating: 0, count: 4096)
        var lumSum = 0.0, lumW = 0.0
        let c = Double(side - 1) / 2

        for y in 0..<side {
            for x in 0..<side {
                let i = (y * side + x) * 4
                let a = Double(px[i + 3]) / 255
                guard a > 0.5 else { continue }
                let r = Double(px[i]) / 255, g = Double(px[i + 1]) / 255, b = Double(px[i + 2]) / 255
                let dx = (Double(x) - c) / c, dy = (Double(y) - c) / c
                let w = 1.0 + 1.2 * max(0, 1 - sqrt(dx * dx + dy * dy))   // center pixels up to 2.2x
                let bucket = (Int(px[i]) >> 4 << 8) | (Int(px[i + 1]) >> 4 << 4) | (Int(px[i + 2]) >> 4)
                weight[bucket] += w; sumR[bucket] += r * w; sumG[bucket] += g * w; sumB[bucket] += b * w
                lumSum += RGB(r: r, g: g, b: b).luminance * w; lumW += w
            }
        }
        guard lumW > 0 else { return nil }

        // Rank buckets, take top candidates with minimum perceptual separation.
        let ranked = weight.indices
            .filter { weight[$0] > 0 }
            .sorted { weight[$0] > weight[$1] }
            .prefix(24)
            .map { i in RGB(r: sumR[i] / weight[i], g: sumG[i] / weight[i], b: sumB[i] / weight[i]) }

        guard let dominant = ranked.first else { return nil }

        // Accent: most saturated candidate that is distinct from dominant and not near-black/white.
        let accent = ranked.dropFirst()
            .filter { $0.distance(to: dominant) > 0.18 && $0.luminance > 0.08 && $0.luminance < 0.92 }
            .max(by: { $0.saturation < $1.saturation })
            ?? dominant

        return RawPalette(dominant: dominant, accent: accent, meanLuminance: lumSum / lumW)
    }

    // MARK: - Role derivation (clamping, contrast enforcement)

    private static func derive(_ raw: RawPalette, scheme: ColorScheme) -> AmbientPalette {
        let isDarkContent = raw.meanLuminance < 0.45

        // Background: dominant hue, desaturated, luminance clamped to scheme band. (Rules §3)
        var bg = raw.dominant
        bg = adjust(bg, saturationScale: 0.55,
                    targetLuminance: scheme == .dark || isDarkContent
                        ? clampD(bgLum(bg), 0.08, 0.16)     // soft dark wash
                        : clampD(bgLum(bg), 0.86, 0.94))    // soft light wash

        // Accent: clamp saturation/brightness into a usable control range.
        var accent = raw.accent
        accent = adjust(accent, saturationScale: min(1.0, 0.85 / max(accent.saturation, 0.01)),
                        targetLuminance: clampD(accent.luminance, 0.28, 0.62))

        // Text: pick white/black per contrast; force-fix if both fail (C1 fail-closed).
        let white = RGB(r: 1, g: 1, b: 1), black = RGB(r: 0.04, g: 0.04, b: 0.05)
        let useWhite = contrastRatio(white, bg) >= contrastRatio(black, bg)
        var text = useWhite ? white : black
        if contrastRatio(text, bg) < 4.5 {
            // push background further toward its band edge until contrast holds
            bg = adjust(bg, saturationScale: 0.8,
                        targetLuminance: useWhite ? 0.10 : 0.92)
            text = useWhite ? white : black
        }
        let textSecondary = useWhite
            ? RGB(r: 1, g: 1, b: 1)   // alpha handled at Color level
            : RGB(r: 0.1, g: 0.1, b: 0.12)

        let shadow = adjust(raw.dominant, saturationScale: 0.7, targetLuminance: 0.06)

        return AmbientPalette(
            dominant: color(raw.dominant),
            background: color(bg),
            accent: color(accent),
            textPrimary: color(text),
            textSecondary: color(textSecondary).opacity(useWhite ? 0.72 : 0.6),
            glassTint: color(raw.dominant).opacity(0.0),  // alpha applied per-surface × intensity
            shadow: color(shadow).opacity(scheme == .dark ? 0.5 : 0.25),
            isDarkContent: isDarkContent
        )
    }

    // MARK: helpers
    private static func bgLum(_ c: RGB) -> Double { c.luminance }
    private static func clampD(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }

    private static func adjust(_ c: RGB, saturationScale: Double, targetLuminance: Double) -> RGB {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        s = CGFloat(min(1, Double(s) * saturationScale))
        // brightness ≈ luminance for our purposes after desaturation; binary-search exact luminance
        var lo: CGFloat = 0, hi: CGFloat = 1, out = c
        for _ in 0..<8 {
            let mid = (lo + hi) / 2
            let probe = UIColor(hue: h, saturation: s, brightness: mid, alpha: 1)
            var pr: CGFloat = 0, pg: CGFloat = 0, pb: CGFloat = 0
            probe.getRed(&pr, green: &pg, blue: &pb, alpha: &a)
            out = RGB(r: pr, g: pg, b: pb)
            if out.luminance < targetLuminance { lo = mid } else { hi = mid }
        }
        return out
    }

    private static func color(_ c: RGB) -> Color { Color(red: c.r, green: c.g, blue: c.b) }
}

private extension UIImage {
    func ciImageBackedCG() -> CGImage? {
        guard let ci = ciImage else { return nil }
        return CIContext(options: nil).createCGImage(ci, from: ci.extent)
    }
}
