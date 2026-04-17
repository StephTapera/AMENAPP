//
//  BereanWallpaperManager.swift
//  AMENAPP
//
//  Wallpaper selection + contrast-safe rendering for Berean chat.
//

import SwiftUI

struct BereanWallpaperPreset: Identifiable {
    let id: String
    let name: String
    let gradient: LinearGradient
    let brightness: BereanWallpaperBrightness
    let complexity: BereanWallpaperComplexity
}

extension BereanWallpaperPreset: Equatable {
    static func == (lhs: BereanWallpaperPreset, rhs: BereanWallpaperPreset) -> Bool {
        lhs.id == rhs.id
    }
}

enum BereanWallpaperStyle: Equatable {
    case none
    case curated(String)
}

@MainActor
final class BereanWallpaperManager: ObservableObject {
    @Published var selection: BereanWallpaperStyle {
        didSet { persistSelection() }
    }

    private let presets: [BereanWallpaperPreset] = [
        BereanWallpaperPreset(
            id: "linen",
            name: "Linen",
            gradient: LinearGradient(
                colors: [Color(red: 0.98, green: 0.97, blue: 0.95), Color(red: 0.95, green: 0.95, blue: 0.93)],
                startPoint: .top,
                endPoint: .bottom
            ),
            brightness: .light,
            complexity: .calm
        ),
        BereanWallpaperPreset(
            id: "dawn",
            name: "Dawn",
            gradient: LinearGradient(
                colors: [Color(red: 0.98, green: 0.96, blue: 0.93), Color(red: 0.93, green: 0.94, blue: 0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            brightness: .mixed,
            complexity: .calm
        ),
        BereanWallpaperPreset(
            id: "stone",
            name: "Stone",
            gradient: LinearGradient(
                colors: [Color(red: 0.92, green: 0.93, blue: 0.95), Color(red: 0.88, green: 0.90, blue: 0.94)],
                startPoint: .top,
                endPoint: .bottom
            ),
            brightness: .light,
            complexity: .calm
        ),
        BereanWallpaperPreset(
            id: "midnight",
            name: "Midnight",
            gradient: LinearGradient(
                colors: [Color(red: 0.12, green: 0.13, blue: 0.18), Color(red: 0.18, green: 0.20, blue: 0.28)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            brightness: .dark,
            complexity: .calm
        )
    ]

    init() {
        let saved = UserDefaults.standard.string(forKey: "berean_wallpaper_selection") ?? "none"
        if saved == "none" {
            self.selection = .none
        } else {
            self.selection = .curated(saved)
        }
    }

    var availablePresets: [BereanWallpaperPreset] {
        presets
    }

    func preset(for selection: BereanWallpaperStyle) -> BereanWallpaperPreset? {
        switch selection {
        case .none:
            return nil
        case .curated(let id):
            return presets.first { $0.id == id }
        }
    }

    var contrastStyle: BereanContrastStyle {
        guard let preset = preset(for: selection) else {
            return BereanContrastEngine.style(for: .light, complexity: .calm)
        }
        return BereanContrastEngine.style(for: preset.brightness, complexity: preset.complexity)
    }

    @ViewBuilder
    func wallpaperView() -> some View {
        if let preset = preset(for: selection) {
            preset.gradient
        } else {
            BereanColor.background
        }
    }

    private func persistSelection() {
        switch selection {
        case .none:
            UserDefaults.standard.set("none", forKey: "berean_wallpaper_selection")
        case .curated(let id):
            UserDefaults.standard.set(id, forKey: "berean_wallpaper_selection")
        }
    }
}
