// NISEditorBridge.swift
// AMEN — Notes Intelligence System
// NIS placeholder — Lane F/G/H replaces in Wave 2
//
// This bridge wires NISService into the editor surface.
// Entry point: NISEditorBridge.shared, consumed by ChurchNoteSemanticEditorView

import Foundation
import SwiftUI

/// Bridges `NISService` into the editor surface.
/// Consumed by `ChurchNoteSemanticEditorView` via `@StateObject`.
/// All surfaces are gated behind `AMENFeatureFlags.shared.nisDetectionLayerEnabled`.
@MainActor
final class NISEditorBridge: ObservableObject {

    // MARK: Shared instance (optional — views may also inject a custom service)
    static let shared = NISEditorBridge()

    // MARK: Published state
    @Published var detections: [NISDetection] = []
    @Published var processingState: NISProcessingState = .idle

    // MARK: Private
    private let service: NISService
    private var detectionTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

    // MARK: Init
    init(service: NISService = FirebaseNISService.shared) {
        self.service = service
    }

    // MARK: - Observe a note

    /// Starts observing detections and processing state for `noteId`.
    /// Gated: does nothing unless `nisDetectionLayerEnabled` is true.
    func observe(noteId: String) {
        guard AMENFeatureFlags.shared.nisDetectionLayerEnabled else { return }

        // Cancel any prior observation
        detectionTask?.cancel()
        pollTask?.cancel()

        // Stream live detections
        detectionTask = Task { [weak self] in
            guard let self else { return }
            for await batch in self.service.detections(for: noteId) {
                guard !Task.isCancelled else { break }
                self.detections = batch
            }
        }

        // Poll processingState — NISService.processingState is synchronous (cache-backed),
        // so we pull it on a short interval until the note is .done or .error.
        // Lane F/G/H will replace this with a proper Combine/AsyncStream publisher in Wave 2.
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let state = self.service.processingState(for: noteId)
                self.processingState = state
                // Stop polling once a terminal state is reached
                switch state {
                case .done, .error: return
                case .idle, .processing: break
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 s
            }
        }
    }

    // MARK: - Resolve a detection

    /// Resolves a detection with the given action.
    /// Gated: does nothing unless `nisDetectionLayerEnabled` is true.
    func resolve(noteId: String, detectionId: String, action: NISResolutionAction) async throws {
        guard AMENFeatureFlags.shared.nisDetectionLayerEnabled else { return }
        try await service.resolveDetection(noteId: noteId, detectionId: detectionId, action: action)
    }

    // MARK: - Cleanup

    func stopObserving() {
        detectionTask?.cancel()
        pollTask?.cancel()
        detectionTask = nil
        pollTask = nil
    }

    deinit {
        detectionTask?.cancel()
        pollTask?.cancel()
    }
}
