// TranslationSettingsManager.swift
// AMEN App — Translation System
//
// Manages user language preferences:
//   - Persists to Firestore users/{uid}/languagePreferences
//   - Local UserDefaults mirror for offline/fast reads
//   - Exposes @Published state consumed by TranslationService

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class TranslationSettingsManager: ObservableObject {

    static let shared = TranslationSettingsManager()

    // MARK: - Published State

    @Published private(set) var preferences: UserLanguagePreferences = .default
    @Published private(set) var isLoaded = false

    // MARK: - Private

    private let db = Firestore.firestore()
    private let localKey = "amen.translation.preferences"
    private var listenerRegistration: ListenerRegistration?

    // MARK: - Init

    private init() {
        loadLocalPreferences()
        Task { await loadFromFirestore() }
    }

    // MARK: - Public API

    /// Returns the user's primary language code (e.g. "en"), falling back to device locale.
    var userLanguageCode: String {
        preferences.appLanguage
    }

    /// Whether to auto-translate a post with the given detected language.
    func shouldAutoTranslate(detectedLang: String, contentType: TranslatableContentType) -> Bool {
        guard TranslationFeatureFlags.shared.isEnabled(for: contentType) else { return false }

        let userLang = preferences.appLanguage
        guard detectedLang != userLang else { return false }

        // Never auto-translate if user understands the language
        if preferences.understoodLanguages.contains(detectedLang) { return false }

        switch preferences.contentTranslationMode {
        case .auto:
            switch contentType {
            case .post, .testimony, .prayerRequest:
                return preferences.autoTranslatePosts
            case .comment, .reply:
                return preferences.autoTranslateComments
            case .message:
                return false  // DMs always require explicit tap
            default:
                return preferences.autoTranslatePosts
            }
        case .onRequest, .never:
            return false
        }
    }

    /// Whether to show the "See Translation" button at all.
    func shouldOfferTranslation(detectedLang: String, contentType: TranslatableContentType) -> Bool {
        guard TranslationFeatureFlags.shared.isEnabled(for: contentType) else { return false }
        guard preferences.contentTranslationMode != .never else { return false }
        let userLang = preferences.appLanguage
        guard detectedLang != userLang else { return false }
        if preferences.understoodLanguages.contains(detectedLang) { return false }
        return true
    }

    // MARK: - Preference Updates

    func update(appLanguage: String) async {
        var updated = preferences
        updated.appLanguage = appLanguage
        updated.updatedAt = Date()
        await persist(updated)
    }

    func update(mode: ContentTranslationMode) async {
        var updated = preferences
        updated.contentTranslationMode = mode
        updated.updatedAt = Date()
        await persist(updated)
    }

    func update(autoTranslatePosts: Bool) async {
        var updated = preferences
        updated.autoTranslatePosts = autoTranslatePosts
        updated.updatedAt = Date()
        await persist(updated)
    }

    func update(autoTranslateComments: Bool) async {
        var updated = preferences
        updated.autoTranslateComments = autoTranslateComments
        updated.updatedAt = Date()
        await persist(updated)
    }

    func update(showOriginalAlongTranslation: Bool) async {
        var updated = preferences
        updated.showOriginalAlongTranslation = showOriginalAlongTranslation
        updated.updatedAt = Date()
        await persist(updated)
    }

    func addUnderstoodLanguage(_ code: String) async {
        guard !preferences.understoodLanguages.contains(code) else { return }
        var updated = preferences
        updated.understoodLanguages.append(code)
        updated.updatedAt = Date()
        await persist(updated)
    }

    func removeUnderstoodLanguage(_ code: String) async {
        var updated = preferences
        updated.understoodLanguages.removeAll(where: { $0 == code })
        updated.updatedAt = Date()
        await persist(updated)
    }

    // MARK: - Persistence

    private func persist(_ prefs: UserLanguagePreferences) async {
        preferences = prefs
        saveLocalPreferences(prefs)

        guard let uid = Auth.auth().currentUser?.uid else { return }

        do {
            let encoded = try Firestore.Encoder().encode(prefs)
            try await db
                .collection("users")
                .document(uid)
                .setData(["languagePreferences": encoded], merge: true)
        } catch {
            // Non-fatal: local copy is already updated
            print("[TranslationSettings] Firestore persist failed: \(error)")
        }
    }

    private func loadFromFirestore() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            isLoaded = true
            return
        }

        do {
            let doc = try await db.collection("users").document(uid).getDocument()
            if let data = doc.data(),
               let prefMap = data["languagePreferences"] as? [String: Any] {
                let decoded = try Firestore.Decoder().decode(
                    UserLanguagePreferences.self,
                    from: prefMap
                )
                preferences = decoded
                saveLocalPreferences(decoded)
            }
        } catch {
            print("[TranslationSettings] Firestore load failed: \(error)")
        }

        isLoaded = true
    }

    // MARK: - Local Mirror

    private func saveLocalPreferences(_ prefs: UserLanguagePreferences) {
        if let data = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(data, forKey: localKey)
        }
    }

    private func loadLocalPreferences() {
        guard let data = UserDefaults.standard.data(forKey: localKey),
              let decoded = try? JSONDecoder().decode(UserLanguagePreferences.self, from: data)
        else { return }
        preferences = decoded
    }
}
