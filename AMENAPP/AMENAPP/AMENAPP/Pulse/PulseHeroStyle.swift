//
//  PulseHeroStyle.swift
//  AMEN — Amen Pulse
//
//  Photo-grade CSS gradient catalog for card heroes (used when a card carries no
//  hero image). White/light Apple-native system; dark scrim heroes get a dark wash,
//  light heroes a soft top-light. Mirrors the prototype HEROES map.
//

import SwiftUI

enum PulseHeroStyle: String, CaseIterable {
    case brief, whatsnew, prayer, event, verse, occasion, space

    static func resolve(_ key: String) -> PulseHeroStyle {
        PulseHeroStyle(rawValue: key) ?? .verse
    }

    /// Default scrim when a card doesn't specify one.
    var scrim: PulseScrim {
        switch self {
        case .brief, .verse, .occasion: return .light
        case .whatsnew, .prayer, .event, .space: return .dark
        }
    }

    /// Ambient chrome tint sampled from the hero (drives the page wash).
    var tint: Color {
        switch self {
        case .brief:    return Color(hex: "D9E6FA")
        case .whatsnew: return Color(hex: "1B2538")
        case .prayer:   return Color(hex: "E8C3A8")
        case .event:    return Color(hex: "3B2F7A")
        case .verse:    return Color(hex: "CFE7D6")
        case .occasion: return Color(hex: "F8DCD9")
        case .space:    return Color(hex: "9CC4DE")
        }
    }

    /// Base linear wash + an accent radial bloom, layered to read photographic.
    @ViewBuilder
    func background() -> some View {
        ZStack {
            base
            accent
        }
        .drawingGroup(opaque: false)
    }

    private var base: some View {
        LinearGradient(colors: baseColors, startPoint: .top, endPoint: .bottom)
    }

    private var baseColors: [Color] {
        switch self {
        case .brief:    return [Color(hex: "F8FAFF"), Color(hex: "EEF3FB")]
        case .whatsnew: return [Color(hex: "1D2840"), Color(hex: "05070D")]
        case .prayer:   return [Color(hex: "B86A4B"), Color(hex: "7A3E33")]
        case .event:    return [Color(hex: "1E1640"), Color(hex: "0B0820")]
        case .verse:    return [Color(hex: "F2FAF4"), Color(hex: "E2F0E6")]
        case .occasion: return [Color(hex: "FFF6F2"), Color(hex: "FCEDEA")]
        case .space:    return [Color(hex: "25557A"), Color(hex: "143049")]
        }
    }

    @ViewBuilder
    private var accent: some View {
        switch self {
        case .brief:
            bloom(Color(hex: "FFE9C8"), at: .init(x: 0.8, y: 0.0))
            bloom(Color(hex: "CFE3FF"), at: .init(x: 0.1, y: 1.0))
        case .whatsnew:
            bloom(Color(hex: "2A3A60").opacity(0.9), at: .init(x: 0.5, y: 0.32), radius: 0.55)
        case .prayer:
            bloom(Color(hex: "FFD9B8"), at: .init(x: 0.85, y: 0.1))
        case .event:
            bloom(Color(hex: "4C3FA8"), at: .init(x: 0.5, y: 0.0))
            bloom(Color(hex: "AA8CFF").opacity(0.5), at: .init(x: 0.55, y: 0.12), radius: 0.4)
        case .verse:
            bloom(Color(hex: "DFF3E4"), at: .init(x: 0.2, y: 0.0))
            bloom(Color(hex: "B7D9C0"), at: .init(x: 0.9, y: 1.0))
        case .occasion:
            bloom(Color(hex: "FFD6E2"), at: .init(x: 0.75, y: 0.05))
            bloom(Color(hex: "FBE3C9"), at: .init(x: 0.1, y: 1.0))
        case .space:
            bloom(Color(hex: "CDE6F7"), at: .init(x: 0.8, y: 0.0))
        }
    }

    private func bloom(_ color: Color, at point: UnitPoint, radius: CGFloat = 0.95) -> some View {
        GeometryReader { geo in
            let dim = max(geo.size.width, geo.size.height)
            RadialGradient(
                colors: [color, color.opacity(0)],
                center: point,
                startRadius: 0,
                endRadius: dim * radius
            )
        }
    }
}

/// Scrim overlay placed over a hero so text/pills stay legible.
struct PulseScrimOverlay: View {
    let scrim: PulseScrim
    var body: some View {
        LinearGradient(
            colors: scrim == .dark
                ? [Color.black.opacity(0.06), Color.black.opacity(0.52)]
                : [Color.white.opacity(0.0), Color.white.opacity(0.55)],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }
}
