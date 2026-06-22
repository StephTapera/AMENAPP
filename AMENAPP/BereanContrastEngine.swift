//
//  BereanContrastEngine.swift
//  AMENAPP
//
//  Lightweight contrast logic for wallpaper-aware UI.
//

import SwiftUI

struct BereanContrastStyle: Equatable {
    let foregroundColor: Color
    let secondaryColor: Color
    let glassOpacity: Double
    let scrimOpacity: Double
    let inputOpacity: Double
}

enum BereanWallpaperBrightness: Equatable {
    case light
    case dark
    case mixed
}

enum BereanWallpaperComplexity: Equatable {
    case calm
    case busy
}

enum BereanContrastEngine {
    static func style(for brightness: BereanWallpaperBrightness, complexity: BereanWallpaperComplexity) -> BereanContrastStyle {
        switch (brightness, complexity) {
        case (.light, .calm):
            return BereanContrastStyle(
                foregroundColor: .black,
                secondaryColor: Color(white: 0.45),
                glassOpacity: 0.70,
                scrimOpacity: 0.08,
                inputOpacity: 0.16
            )
        case (.light, .busy):
            return BereanContrastStyle(
                foregroundColor: .black,
                secondaryColor: Color(white: 0.45),
                glassOpacity: 0.82,
                scrimOpacity: 0.16,
                inputOpacity: 0.20
            )
        case (.dark, .calm):
            return BereanContrastStyle(
                foregroundColor: Color(white: 0.98),
                secondaryColor: Color(white: 0.78),
                glassOpacity: 0.78,
                scrimOpacity: 0.18,
                inputOpacity: 0.22
            )
        case (.dark, .busy):
            return BereanContrastStyle(
                foregroundColor: Color(white: 0.98),
                secondaryColor: Color(white: 0.78),
                glassOpacity: 0.88,
                scrimOpacity: 0.28,
                inputOpacity: 0.26
            )
        case (.mixed, .calm):
            return BereanContrastStyle(
                foregroundColor: .black,
                secondaryColor: Color(white: 0.45),
                glassOpacity: 0.74,
                scrimOpacity: 0.12,
                inputOpacity: 0.18
            )
        case (.mixed, .busy):
            return BereanContrastStyle(
                foregroundColor: .black,
                secondaryColor: Color(white: 0.45),
                glassOpacity: 0.86,
                scrimOpacity: 0.22,
                inputOpacity: 0.22
            )
        }
    }
}
