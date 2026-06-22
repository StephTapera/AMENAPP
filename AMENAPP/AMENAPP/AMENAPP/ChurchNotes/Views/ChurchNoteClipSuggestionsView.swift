import SwiftUI
import FirebaseFirestore

/// Clip-suggestions surface — only displays clip ranges that come from REAL
/// uploaded/recorded media segments. No fake clips are ever fabricated.
///
/// Read flow:
///  - Subscribes to `churchNotes/{noteId}/processingJobs/{jobId}` and reads:
///    * `keyMoments`: [{startSeconds, endSeconds, title, source, confidence}]
///      — populated by Whisper segment timestamps (real, not synthesized).
///    * `storagePath` and `sourceType` (must be audio/video) — used as the
///      source media reference for the share payload.
///  - Drops any moment without `startSeconds` < `endSeconds` (defensive).
///
/// Share flow:
///  - User taps a clip → ShareLink emits the source storage path + timestamp
///    range. Downstream surfaces (e.g. the playback view) are responsible for
///    seeking the *original* media to that range.
struct ChurchNoteClipSuggestionsView: View {
    let noteId: String
    let jobId: String

    @StateObject private var loader = ClipSuggestionsLoader()

    var body: some View {
        List {
            sourceAttribution
            clipsSection
            if let err = loader.errorMessage {
                Section { errorLabel(err) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Clip suggestions")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loader.start(noteId: noteId, jobId: jobId) }
        .onDisappear { loader.stop() }
    }

    @ViewBuilder
    private var sourceAttribution: some View {
        if let source = loader.sourceLabel {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: loader.sourceSymbol)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(source)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Source: \(source)")
            } footer: {
                Text("Clips reference your original recording at the timestamps shown — no new video is generated.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var clipsSection: some View {
        if loader.isLoading {
            Section { ProgressView("Loading suggestions…") }
        } else if loader.clips.isEmpty {
            Section {
                ContentUnavailableView(
                    "No clip moments yet",
                    systemImage: "scissors",
                    description: Text("Clip suggestions appear once your audio or video is transcribed.")
                )
                .padding(.vertical, 12)
            }
        } else {
            Section("Suggested clips") {
                ForEach(loader.clips) { clip in
                    clipRow(clip)
                }
            }
        }
    }

    @ViewBuilder
    private func clipRow(_ clip: ChurchNoteClipSuggestion) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(clip.title)
                    .font(.body)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .accessibilityHidden(true)
                    Text("\(formatTimestamp(clip.startSeconds)) – \(formatTimestamp(clip.endSeconds))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let confidence = clip.confidence {
                        Text(confidenceLabel(confidence))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()

            if let payload = clip.sharePayload {
                ShareLink(item: payload, subject: Text(clip.title)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.callout)
                        .padding(8)
                        .background(Color(.secondarySystemFill), in: Circle())
                }
                .accessibilityLabel("Share clip from \(formatTimestamp(clip.startSeconds)) to \(formatTimestamp(clip.endSeconds))")
                .accessibilityHint("Shares the source media reference with this timestamp range")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(clip.title), \(formatTimestamp(clip.startSeconds)) to \(formatTimestamp(clip.endSeconds))")
    }

    private func errorLabel(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
            .accessibilityLabel("Error: \(text)")
    }

    private func formatTimestamp(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    private func confidenceLabel(_ value: Double) -> String {
        switch value {
        case ..<0.5: return "• Low confidence"
        case ..<0.75: return "• Moderate"
        default: return "• High"
        }
    }
}

@MainActor
final class ClipSuggestionsLoader: ObservableObject {

    @Published private(set) var clips: [ChurchNoteClipSuggestion] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var sourceLabel: String?
    @Published private(set) var sourceSymbol: String = "waveform"

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    deinit { listener?.remove() }

    func start(noteId: String, jobId: String) {
        stop()
        isLoading = true
        errorMessage = nil
        listener = db.collection("churchNotes")
            .document(noteId)
            .collection("processingJobs")
            .document(jobId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isLoading = false
                    if let error {
                        self.errorMessage = "Could not load clips: \(error.localizedDescription)"
                        return
                    }
                    guard let data = snapshot?.data() else {
                        self.clips = []
                        return
                    }
                    let sourceType  = (data["sourceType"] as? String) ?? ""
                    let storagePath = (data["storagePath"] as? String) ?? ""
                    self.sourceLabel  = ClipSuggestionsLoader.makeSourceLabel(sourceType: sourceType, storagePath: storagePath)
                    self.sourceSymbol = sourceType == "video" ? "video.fill" : "waveform"
                    self.clips        = ClipSuggestionsLoader.parseClips(
                        data: data,
                        storagePath: storagePath,
                        sourceType: sourceType
                    )
                }
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    private static func makeSourceLabel(sourceType: String, storagePath: String) -> String? {
        guard sourceType == "audio" || sourceType == "video", !storagePath.isEmpty else { return nil }
        let filename = (storagePath as NSString).lastPathComponent
        return "\(sourceType.capitalized) — \(filename)"
    }

    /// Parses `keyMoments` (real Whisper-derived timestamps) into renderable
    /// clip suggestions. Drops any item without a valid timestamp range or
    /// whose source isn't a real uploaded media artifact.
    private static func parseClips(
        data: [String: Any],
        storagePath: String,
        sourceType: String
    ) -> [ChurchNoteClipSuggestion] {
        guard sourceType == "audio" || sourceType == "video",
              storagePath.hasPrefix("churchNotes/") else {
            return []
        }
        let rawMoments = (data["keyMoments"] as? [[String: Any]]) ?? []
        return rawMoments.compactMap { moment -> ChurchNoteClipSuggestion? in
            guard let start = (moment["startSeconds"] as? NSNumber)?.doubleValue ?? (moment["startSeconds"] as? Double),
                  let end   = (moment["endSeconds"]   as? NSNumber)?.doubleValue ?? (moment["endSeconds"]   as? Double),
                  end > start, start >= 0 else {
                return nil
            }
            let title = ((moment["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "Clip from \(Int(start.rounded()))s"
            let confidence = (moment["confidence"] as? NSNumber)?.doubleValue ?? (moment["confidence"] as? Double)
            let payload = "amen-clip://\(storagePath)?start=\(Int(start.rounded()))&end=\(Int(end.rounded()))"
            return ChurchNoteClipSuggestion(
                id: "\(start)-\(end)",
                title: title,
                startSeconds: start,
                endSeconds: end,
                confidence: confidence,
                sharePayload: payload
            )
        }
    }
}

struct ChurchNoteClipSuggestion: Identifiable, Equatable {
    let id: String
    let title: String
    let startSeconds: Double
    let endSeconds: Double
    let confidence: Double?
    /// Share payload: a deep-link reference to the source media + timestamp range.
    /// No video is fabricated; the receiver seeks the original recording.
    let sharePayload: String?
}
