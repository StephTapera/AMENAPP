// AppearanceController.swift
// AMEN — Settings/Safety system · Design System
//
// Holds the user's AppearancePrefs and applies them app-wide. Fast-path persistence
// via UserDefaults; durable sync to users/{uid}/settings/preferences (under an
// "appearance" map so it never clobbers GeneralPrefs written by Lane D).
//
// Reduce Transparency: the SYSTEM accessibility setting is honored independently by
// glass surfaces via @Environment(\.accessibilityReduceTransparency). This controller
// additionally exposes the user's in-app preference (reduceTransparencyPreferred) and
// glassIntensity so surfaces that opt in can consult them.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class AppearanceController: ObservableObject {

    static let shared = AppearanceController()

    @Published var prefs: AppearancePrefs

    private let defaults = UserDefaults.standard
    private enum Key {
        static let mode = "amen_appearance_mode"
        static let accent = "amen_appearance_accent"
        static let glassIntensity = "amen_appearance_glass_intensity"
        static let reduceTransparency = "amen_appearance_reduce_transparency"
    }

    private init() {
        let mode = AppearanceMode(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .system
        let accent = AccentColor(rawValue: defaults.string(forKey: Key.accent) ?? "") ?? .default
        let glass = defaults.object(forKey: Key.glassIntensity) as? Double ?? AppearancePrefs.defaultValue.glassIntensity
        let reduce = defaults.object(forKey: Key.reduceTransparency) as? Bool ?? AppearancePrefs.defaultValue.reduceTransparency
        prefs = AppearancePrefs(mode: mode, accent: accent, glassIntensity: glass, reduceTransparency: reduce)
        Task { await loadFromFirestore() }
    }

    // MARK: - Applied values

    var preferredColorScheme: ColorScheme? {
        switch prefs.mode {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var accentColor: Color { prefs.accent.color }

    /// User in-app "reduce transparency" preference (separate from the system setting).
    var reduceTransparencyPreferred: Bool { prefs.reduceTransparency }

    /// 0…1 glass material intensity for surfaces that opt in.
    var glassIntensity: Double { prefs.glassIntensity }

    // MARK: - Mutation

    func update(_ newPrefs: AppearancePrefs) {
        prefs = newPrefs
        persistLocal()
        Task { await persistRemote() }
    }

    // MARK: - Persistence

    private func persistLocal() {
        defaults.set(prefs.mode.rawValue, forKey: Key.mode)
        defaults.set(prefs.accent.rawValue, forKey: Key.accent)
        defaults.set(prefs.glassIntensity, forKey: Key.glassIntensity)
        defaults.set(prefs.reduceTransparency, forKey: Key.reduceTransparency)
    }

    private func persistRemote() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let payload: [String: Any] = [
            "appearance": [
                "mode": prefs.mode.rawValue,
                "accent": prefs.accent.rawValue,
                "glassIntensity": prefs.glassIntensity,
                "reduceTransparency": prefs.reduceTransparency
            ]
        ]
        do {
            try await Firestore.firestore()
                .document(SettingsFirestorePath.preferences(uid: uid))
                .setData(payload, merge: true)
        } catch {
            dlog("[Appearance] remote persist failed: \(error)")
        }
    }

    private func loadFromFirestore() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let snap = try await Firestore.firestore()
                .document(SettingsFirestorePath.preferences(uid: uid))
                .getDocument()
            guard let data = snap.data(), let a = data["appearance"] as? [String: Any] else { return }
            let mode = AppearanceMode(rawValue: a["mode"] as? String ?? "") ?? prefs.mode
            let accent = AccentColor(rawValue: a["accent"] as? String ?? "") ?? prefs.accent
            let glass = a["glassIntensity"] as? Double ?? prefs.glassIntensity
            let reduce = a["reduceTransparency"] as? Bool ?? prefs.reduceTransparency
            prefs = AppearancePrefs(mode: mode, accent: accent, glassIntensity: glass, reduceTransparency: reduce)
            persistLocal()
        } catch {
            dlog("[Appearance] remote load failed: \(error)")
        }
    }
}

// MARK: - App-wide application

struct SettingsAppearanceModifier: ViewModifier {
    @ObservedObject private var controller = AppearanceController.shared

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(controller.preferredColorScheme)
            .tint(controller.accentColor)
    }
}

extension View {
    /// Applies the user's appearance (light/dark/system + accent tint) to a view subtree.
    /// Attach near the app root. Glass-intensity / reduce-transparency preferences are
    /// exposed on AppearanceController.shared for opt-in surfaces.
    func settingsAppearance() -> some View {
        modifier(SettingsAppearanceModifier())
    }
}
