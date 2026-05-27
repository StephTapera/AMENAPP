import Foundation

actor BereanDraftStore {
    static let shared = BereanDraftStore()
    private init() {}

    private func key(surface: BereanComposerSurface, mode: BereanPersonalityMode) -> String {
        let surfaceKey: String
        switch surface {
        case .home: surfaceKey = "home"
        case .messages: surfaceKey = "messages"
        }
        return "berean_ghost_\(surfaceKey)_\(mode.rawValue)"
    }

    func save(draft: String, surface: BereanComposerSurface, mode: BereanPersonalityMode) {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UserDefaults.standard.set(trimmed, forKey: key(surface: surface, mode: mode))
    }

    func load(surface: BereanComposerSurface, mode: BereanPersonalityMode) -> String? {
        UserDefaults.standard.string(forKey: key(surface: surface, mode: mode))
    }

    func clear(surface: BereanComposerSurface, mode: BereanPersonalityMode) {
        UserDefaults.standard.removeObject(forKey: key(surface: surface, mode: mode))
    }
}
