import Foundation
import Combine

@MainActor
final class AmenMagicWordComposerObserver: ObservableObject {
    @Published private(set) var results: [AmenContextualReactionResult] = []

    private let engine: AmenContextualReactionEngine

    init(engine: AmenContextualReactionEngine? = nil) {
        self.engine = engine ?? .shared
    }

    func update(text: String) {
        results = engine.analyzeText(text)
    }

    func clear() {
        results = []
    }
}
