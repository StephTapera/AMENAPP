// AILProfileService.swift
// AMENAPP — Accessibility Intelligence Layer (AIL)
//
// Observable service owning the per-user A11yProfile. Mirrors the established
// AmenSimpleModeService pattern: @Observable singleton, UserDefaults for instant
// local state, Firestore sync to users/{uid}/settings/a11yProfile so the profile
// follows the account across installs (iron rule: profile portability).
//
// PRIVACY (iron rule 5): only A11yProfile.allowedKeys are ever written. No motor
// metrics, miss rates, input-timing, or inferred conditions touch the network.
// C9 calibration runs on-device only and lands as `largerTouchTargets` — a plain
// size preference, nothing more.
//
// No tier checks — accessibility is free at every tier.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@Observable
final class AILProfileService {

    static let shared = AILProfileService()

    /// The live profile. Mutations persist locally immediately and sync to
    /// Firestore (non-blocking) when signed in.
    var profile: A11yProfile = .default {
        didSet { persist() }
    }

    private let defaults = UserDefaults.standard
    private let storageKey = "ail.a11yProfile.v1"

    private init() {
        load()
    }

    // MARK: - Mutation convenience (keeps call sites terse + value-type-safe)

    func setReadingLevel(_ level: ReadingLevel) { profile.readingLevel = level }
    func setCalmMode(_ on: Bool) { profile.calmMode = on }
    func setToneHints(_ on: Bool) { profile.toneHintsEnabled = on }
    func setAutoTranslate(_ on: Bool) { profile.autoTranslate = on }
    func setVoiceNav(_ on: Bool) { profile.voiceNavEnabled = on }
    func setTouchTargets(_ value: A11yProfile.TouchTargets) { profile.largerTouchTargets = value }
    func setCaptionStyle(_ style: CaptionStyle) { profile.captionStyle = style }

    func toggleSensitivity(_ topic: SensitivityTopic) {
        if let idx = profile.sensitivityFilters.firstIndex(of: topic) {
            profile.sensitivityFilters.remove(at: idx)
        } else {
            profile.sensitivityFilters.append(topic)
        }
    }

    // MARK: - Persistence

    private func load() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(A11yProfile.self, from: data) {
            profile = decoded
        }
        // Pull the account copy in the background so multi-device stays consistent.
        Task { await fetchRemote() }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: storageKey)
        }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let payload = Self.firestorePayload(for: profile)
        Task.detached(priority: .utility) {
            try? await Firestore.firestore()
                .collection("users").document(uid)
                .collection("settings").document("a11yProfile")
                .setData(payload, merge: true)
        }
    }

    private func fetchRemote() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let ref = Firestore.firestore()
            .collection("users").document(uid)
            .collection("settings").document("a11yProfile")
        guard let snap = try? await ref.getDocument(), let data = snap.data() else { return }
        if let merged = Self.profile(from: data) {
            await MainActor.run { self.profile = merged }
        }
    }

    // MARK: - Forbidden-field-safe (de)serialization

    /// Writes ONLY allowed keys. A forbidden field can never reach Firestore.
    static func firestorePayload(for p: A11yProfile) -> [String: Any] {
        let captionStyle: [String: Any] = [
            "size": p.captionStyle.size.rawValue,
            "background": p.captionStyle.background.rawValue,
            "highContrast": p.captionStyle.highContrast,
            "speed": p.captionStyle.speed.rawValue,
            "placement": p.captionStyle.placement.rawValue,
        ]
        let payload: [String: Any] = [
            "readingLevel": p.readingLevel.rawValue,
            "autoTranslate": p.autoTranslate,
            "toneHintsEnabled": p.toneHintsEnabled,
            "captionStyle": captionStyle,
            "calmMode": p.calmMode,
            "largerTouchTargets": p.largerTouchTargets.rawValue,
            "sensitivityFilters": p.sensitivityFilters.map { $0.rawValue },
            "voiceNavEnabled": p.voiceNavEnabled,
        ]
        // Defensive: strip anything not allow-listed (mirrors the rules contract).
        return payload.filter { A11yProfile.allowedKeys.contains($0.key) }
    }

    static func profile(from data: [String: Any]) -> A11yProfile? {
        var p = A11yProfile.default
        if let v = data["readingLevel"] as? String, let level = ReadingLevel(rawValue: v) { p.readingLevel = level }
        if let v = data["autoTranslate"] as? Bool { p.autoTranslate = v }
        if let v = data["toneHintsEnabled"] as? Bool { p.toneHintsEnabled = v }
        if let v = data["calmMode"] as? Bool { p.calmMode = v }
        if let v = data["largerTouchTargets"] as? String, let t = A11yProfile.TouchTargets(rawValue: v) { p.largerTouchTargets = t }
        if let v = data["voiceNavEnabled"] as? Bool { p.voiceNavEnabled = v }
        if let arr = data["sensitivityFilters"] as? [String] {
            p.sensitivityFilters = arr.compactMap { SensitivityTopic(rawValue: $0) }
        }
        if let cs = data["captionStyle"] as? [String: Any] {
            var style = CaptionStyle()
            if let v = cs["size"] as? String, let s = CaptionStyle.Size(rawValue: v) { style.size = s }
            if let v = cs["background"] as? String, let b = CaptionStyle.Background(rawValue: v) { style.background = b }
            if let v = cs["highContrast"] as? Bool { style.highContrast = v }
            if let v = cs["speed"] as? String, let s = CaptionStyle.Speed(rawValue: v) { style.speed = s }
            if let v = cs["placement"] as? String, let pl = CaptionStyle.Placement(rawValue: v) { style.placement = pl }
            p.captionStyle = style
        }
        return p
    }
}
