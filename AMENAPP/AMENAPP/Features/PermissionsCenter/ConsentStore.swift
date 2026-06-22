import Foundation

@MainActor
final class ConsentStore: ObservableObject {
    static let shared = ConsentStore()

    @Published private var states: [ConsentEdge: ConsentState]

    private let defaults: UserDefaults
    private let storageKey = "permissions_center_consent_states_v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([ConsentState].self, from: data) {
            states = Dictionary(uniqueKeysWithValues: decoded.map { ($0.edge, $0) })
        } else {
            let initial = ConsentState.defaults()
            states = Dictionary(uniqueKeysWithValues: initial.map { ($0.edge, $0) })
        }

        if states[.activityToRhythm]?.isEnabled != true {
            states[.activityToRhythm] = ConsentState(edge: .activityToRhythm, isEnabled: true, updatedAt: Date())
            persist()
        }
    }

    func isEnabled(_ edge: ConsentEdge) -> Bool {
        if edge == .activityToRhythm { return true }
        return states[edge]?.isEnabled ?? false
    }

    func setEnabled(_ edge: ConsentEdge, _ isEnabled: Bool) {
        let nextValue = edge == .activityToRhythm ? true : isEnabled
        states[edge] = ConsentState(edge: edge, isEnabled: nextValue, updatedAt: Date())
        persist()
    }

    private func persist() {
        let orderedStates = ConsentEdge.allCases.compactMap { states[$0] }
        guard let data = try? JSONEncoder().encode(orderedStates) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
