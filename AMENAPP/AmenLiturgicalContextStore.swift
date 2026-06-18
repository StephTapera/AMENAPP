import SwiftUI

@MainActor
final class AmenLiturgicalContextStore: ObservableObject {
    static let shared = AmenLiturgicalContextStore()

    @Published private(set) var updatedAt = Date()

    private init() {}

    func refresh() {
        updatedAt = Date()
    }
}

private struct SeasonAmbientModifier: ViewModifier {
    @ObservedObject var contextStore: AmenLiturgicalContextStore
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
    }
}

extension View {
    func seasonAmbient(
        contextStore: AmenLiturgicalContextStore,
        isEnabled: Bool
    ) -> some View {
        modifier(SeasonAmbientModifier(contextStore: contextStore, isEnabled: isEnabled))
    }
}
