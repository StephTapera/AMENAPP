// ONETokens.swift
// ONE — Design System Tokens
// P0-A | FROZEN after initial definition; amendments require RUNLOG entry.
//
// Rules:
//   • Additive only. Never redefine or shadow AmenTheme tokens.
//   • Glass surfaces: dock, capture button, headers, privacy pill, composer, media controls ONLY.
//   • Feed cells are always matte (no glassEffect).
//   • Every animation must respect accessibilityReduceMotion.

import SwiftUI

// MARK: - ONE Namespace

enum ONE {

    // MARK: Colors

    enum Colors {
        // PURGED: glassWarm (amber tint, red:1.0 green:0.94 blue:0.78 opacity:0.15) → neutral glass per C3 design contract
        // Glass must be white/clear, not gold-tinted.
        static let glassWarm = Color(uiColor: .secondarySystemBackground).opacity(0.15)

        // Cool chrome glass tint — world zone / public surfaces
        // Acceptable for zone indicators only (not brand decoration), per C3 §11
        static let glassCool = Color(red: 0.78, green: 0.86, blue: 1.0, opacity: 0.12)

        // PURGED: decayAmber previously used AmenTheme.Colors.amenGold (gold #C9A84C) → Color.orange per C3 design contract
        static let decayAmber = Color.orange.opacity(0.60)

        // PURGED: witnessGold = Color(red:0.831, green:0.643, blue:0.263) → Color.accentColor per C3 design contract
        static let witnessGold = Color.accentColor

        // PURGED: privateIndigo = Color(red:0.294, green:0.369, blue:0.776) → Color.accentColor per C3 design contract
        static let privateIndigo = Color.accentColor

        // Ephemeral countdown timer — retained (semantic red)
        static let ephemeralRed = Color(red: 0.851, green: 0.357, blue: 0.290)

        // PURGED: subscriberGold = Color(red:0.788, green:0.635, blue:0.153) → Color.accentColor per C3 design contract
        static let subscriberGold = Color.accentColor

        // Repair flow — constructive tone; retained (semantic green)
        static let repairGreen = Color(red: 0.259, green: 0.694, blue: 0.451)
    }

    // MARK: Radii

    enum Radius {
        static let pill:   CGFloat = 24   // Privacy Contract pill + dock buttons
        static let card:   CGFloat = 16   // content cards
        static let sheet:  CGFloat = 28   // bottom sheets
        static let camera: CGFloat = 20   // capture surface controls
    }

    // MARK: Spacing

    enum Spacing {
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 16
        static let lg:  CGFloat = 24
        static let xl:  CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: Animation

    enum Motion {
        /// Standard spring — use when reduceMotion is false.
        static let spring = Animation.spring(response: 0.38, dampingFraction: 0.82)

        /// Accessible fallback — always safe to use.
        static let accessible = Animation.easeOut(duration: 0.15)

        /// Returns the correct animation given the system accessibility setting.
        static func adaptive(reduceMotion: Bool) -> Animation {
            reduceMotion ? accessible : spring
        }
    }

    // MARK: Zone

    enum Zone: String, CaseIterable, Identifiable {
        case people   = "people"
        case moments  = "moments"
        case world    = "world"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .people:  "person.2.fill"
            case .moments: "camera.fill"
            case .world:   "globe"
            }
        }

        var label: String {
            switch self {
            case .people:  "People"
            case .moments: "Moments"
            case .world:   "World"
            }
        }

        var accessibilityHint: String {
            switch self {
            case .people:  "Private messages, groups, and close connections"
            case .moments: "Capture and share moments with your privacy contract"
            case .world:   "Discover communities and public content"
            }
        }
    }

    // MARK: Feature Flags (Remote Config keys — all default OFF)

    enum FeatureFlag {
        static let enabled              = "one_enabled"
        static let csamScanEnabled      = "one_csam_scan_enabled"    // gate: NCMEC partnership required
        static let sealedSender         = "one_sealed_sender"        // gate: post-ship
        static let livingThreadsAI      = "one_living_threads_ai"
        static let repairFlow           = "one_repair_flow"
        static let legacyDirectives     = "one_legacy_directives"
        static let memoryVault          = "one_memory_vault"
        static let reachBudget          = "one_reach_budget"
        static let provenanceLabels     = "one_provenance_labels"
    }
}

// MARK: - Glass view modifier helpers (iOS 26+)

@available(iOS 26.0, *)
extension View {

    /// Applies a ONE-standard privacy pill glass shape.
    /// Use ONLY on Privacy Contract pill and related chrome surfaces.
    @ViewBuilder
    func onePillGlass(tint: Color = ONE.Colors.glassWarm) -> some View {
        self
            .amenGlassEffect(in: Capsule())
    }

    /// Applies ONE card glass — for dock action buttons, not feed cells.
    @ViewBuilder
    func oneCardGlass(cornerRadius: CGFloat = ONE.Radius.card) -> some View {
        self
            .amenGlassEffect(in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}
