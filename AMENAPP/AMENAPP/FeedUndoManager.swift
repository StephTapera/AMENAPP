import Foundation
import SwiftUI

@MainActor
final class FeedUndoManager: ObservableObject {
    static let shared = FeedUndoManager()
    @Published private(set) var pendingUndo: SubmitFeedDirectionResponse? = nil
    private var undoTask: Task<Void, Never>?
    private init() {}

    func registerForUndo(_ response: SubmitFeedDirectionResponse) {
        pendingUndo = response
        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000) // 8 seconds
            guard !Task.isCancelled else { return }
            pendingUndo = nil
        }
    }

    func undo() {
        guard let response = pendingUndo else { return }
        undoTask?.cancel()
        pendingUndo = nil
        FeedDirectionAnalytics.undoTapped(signalId: response.signalId)
        Task {
            try? await AmenFeedDirectionService.shared.resetFeedPreference(scope: .temporary)
        }
    }

    func dismiss() {
        undoTask?.cancel()
        pendingUndo = nil
    }
}
