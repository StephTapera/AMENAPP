import Foundation
import FirebaseFirestore
import FirebaseFunctions

// MARK: - MediaGenerationService
//
// Polls `posts/{postId}/mediaMeta/{mediaId}` after a video post is published.
// When generated captions or key moments become available, it surfaces them
// via the `onSuggestionsReady` callback so the caller can apply them to
// its draft via `draft.applyGeneratedVideoSuggestions(...)`.
//
// Ownership rule enforced here (mirrors the backend rule):
//   The callback is only invoked when results arrive.
//   The caller is responsible for checking `videoDraft.userEdited` before
//   applying — `applyGeneratedVideoSuggestions` already enforces this internally.
//
// Usage in CreatePostView (after publish):
//
//   Task {
//       await MediaGenerationService.shared.startPolling(
//           postId: publishedPostId,
//           mediaId: videoMediaItem.id
//       ) { suggestions in
//           mediaMetadataDraft.applyGeneratedVideoSuggestions(
//               cues: suggestions.cues,
//               keyMoments: suggestions.keyMoments,
//               featuredFrameTime: suggestions.featuredFrameTime
//           )
//       }
//   }
//
// To retry a failed generation:
//   try await MediaGenerationService.shared.retryGeneration(postId:mediaId:)

// MARK: - Generated Suggestions Payload

struct GeneratedVideoSuggestions {
    let cues: [VideoCaptionCueDraft]
    let keyMoments: [KeyMomentDraft]
    let featuredFrameTime: TimeInterval
}

// MARK: - Poll State

enum GenerationPollState: Equatable {
    case idle
    case polling
    case complete
    case partiallyComplete  // at least one of captions/moments succeeded
    case failed(String)

    static func == (lhs: GenerationPollState, rhs: GenerationPollState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.polling, .polling),
             (.complete, .complete), (.partiallyComplete, .partiallyComplete):
            return true
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }

    var isTerminal: Bool {
        switch self {
        case .complete, .partiallyComplete, .failed: return true
        default: return false
        }
    }

    var statusLabel: String {
        switch self {
        case .idle:             return ""
        case .polling:          return "Generating captions..."
        case .complete:         return "Captions and moments ready"
        case .partiallyComplete: return "Generation partially complete"
        case .failed:           return "Generation unavailable"
        }
    }
}

// MARK: - Service

@MainActor
final class MediaGenerationService: ObservableObject {
    static let shared = MediaGenerationService()

    @Published var pollState: GenerationPollState = .idle
    @Published var captionsGenerationState: MediaGenerationState = .notRequested
    @Published var keyMomentsGenerationState: MediaGenerationState = .notRequested

    private var listener: ListenerRegistration?
    private let db = Firestore.firestore()
    private lazy var functions = Functions.functions()

    private init() {}

    // MARK: - Public API

    /// Start listening for generated metadata for a published video.
    ///
    /// - Parameters:
    ///   - postId:   The Firestore document ID of the published post.
    ///   - mediaId:  The media item ID within the post.
    ///   - onSuggestionsReady: Called on the main actor when generated data
    ///               is available. The caller applies it to the draft.
    func startPolling(
        postId: String,
        mediaId: String,
        onSuggestionsReady: @MainActor @escaping (GeneratedVideoSuggestions) -> Void
    ) {
        listener?.remove()
        pollState = .polling
        captionsGenerationState = .generating
        keyMomentsGenerationState = .generating

        let mediaMetaRef = db
            .collection("posts").document(postId)
            .collection("mediaMeta").document(mediaId)

        listener = mediaMetaRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }

            if error != nil {
                self.pollState = .failed("Could not connect to generation service")
                return
            }

            guard let data = snapshot?.data() else { return }

            let captionsRaw  = data["captionsGenerationState"] as? String ?? ""
            let momentsRaw   = data["keyMomentsGenerationState"] as? String ?? ""
            let captionsGen  = MediaGenerationState(rawValue: captionsRaw)  ?? .notRequested
            let momentsGen   = MediaGenerationState(rawValue: momentsRaw)   ?? .notRequested

            self.captionsGenerationState = captionsGen
            self.keyMomentsGenerationState = momentsGen

            let captionsDone = captionsGen == .ready || captionsGen == .failed
            let momentsDone  = momentsGen  == .ready || momentsGen  == .failed

            if captionsGen == .ready || momentsGen == .ready {
                Task { [weak self] in
                    await self?.fetchAndDeliver(
                        mediaMetaRef: mediaMetaRef,
                        captionsReady: captionsGen == .ready,
                        momentsReady: momentsGen == .ready,
                        onSuggestionsReady: onSuggestionsReady
                    )
                }
            }

            if captionsDone && momentsDone {
                self.listener?.remove()
                self.listener = nil
                let anyFailed = captionsGen == .failed || momentsGen == .failed
                self.pollState = anyFailed ? .partiallyComplete : .complete
            }
        }
    }

    func stopPolling() {
        listener?.remove()
        listener = nil
        pollState = .idle
    }

    /// Calls the `retryMediaGeneration` Cloud Function.
    /// After calling, restart polling to pick up the new results.
    func retryGeneration(postId: String, mediaId: String) async throws {
        pollState = .polling
        captionsGenerationState = .queued
        keyMomentsGenerationState = .queued
        _ = try await functions.httpsCallable("retryMediaGeneration").call([
            "postId": postId,
            "mediaId": mediaId,
        ])
    }

    // MARK: - Private

    private func fetchAndDeliver(
        mediaMetaRef: DocumentReference,
        captionsReady: Bool,
        momentsReady: Bool,
        onSuggestionsReady: @MainActor @escaping (GeneratedVideoSuggestions) -> Void
    ) async {
        var cues: [VideoCaptionCueDraft] = []
        var moments: [KeyMomentDraft] = []

        // Read generated caption track
        if captionsReady {
            let tracks = try? await mediaMetaRef
                .collection("captionTracks")
                .whereField("source", isEqualTo: "generated")
                .getDocuments()

            if let trackDoc = tracks?.documents.first {
                let d = trackDoc.data()
                let segments = d["segments"] as? [[String: Any]] ?? []
                cues = segments.compactMap { seg -> VideoCaptionCueDraft? in
                    guard let text = seg["text"] as? String,
                          !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                    return VideoCaptionCueDraft(
                        id: seg["cueId"] as? String ?? UUID().uuidString,
                        startTime: seg["startTime"] as? TimeInterval ?? 0,
                        endTime: seg["endTime"] as? TimeInterval ?? 0,
                        text: text
                    )
                }
            }
        }

        // Read generated key moments
        if momentsReady {
            let momentDocs = try? await mediaMetaRef
                .collection("keyMoments")
                .whereField("source", isEqualTo: "generated")
                .order(by: "sortOrder")
                .getDocuments()

            moments = momentDocs?.documents.compactMap { doc -> KeyMomentDraft? in
                let d = doc.data()
                guard let label   = d["label"]   as? String,
                      let kindRaw = d["kind"]     as? String,
                      let kind    = MediaKeyMomentKind(rawValue: kindRaw) else { return nil }
                return KeyMomentDraft(
                    id: d["momentId"] as? String ?? doc.documentID,
                    timestamp: d["time"] as? TimeInterval ?? 0,
                    label: label,
                    kind: kind,
                    source: .generated
                )
            } ?? []
        }

        guard !cues.isEmpty || !moments.isEmpty else { return }

        let metaDoc = try? await mediaMetaRef.getDocument()
        let featuredFrameTime = metaDoc?.data()?["featuredFrameTime"] as? TimeInterval ?? 0

        let suggestions = GeneratedVideoSuggestions(
            cues: cues,
            keyMoments: moments,
            featuredFrameTime: featuredFrameTime
        )

        await onSuggestionsReady(suggestions)
    }
}

// MARK: - MediaGenerationState terminal helper

private extension MediaGenerationState {
    var isTerminal: Bool {
        self == .ready || self == .failed
    }
}
