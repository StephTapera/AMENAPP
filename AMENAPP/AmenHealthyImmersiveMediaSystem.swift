import AVKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import SwiftUI

// MARK: - Human-First Media Models

enum AmenMediaSourceSurface: String, Codable, CaseIterable {
    case feed
    case profile
    case church
    case discovery
    case selah
    case search
    case savedQueue
    case churchNotes
    case deepLink
}

enum AmenMediaQueueType: String, Codable, CaseIterable, Identifiable {
    case watchLater
    case prayerQueue
    case churchNotes
    case familyWatch
    case selahTonight
    case sermonStudy
    case testimonyArchive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .watchLater: return "Watch Later"
        case .prayerQueue: return "Prayer Queue"
        case .churchNotes: return "Church Notes"
        case .familyWatch: return "Family Watch"
        case .selahTonight: return "Selah Tonight"
        case .sermonStudy: return "Sermon Study"
        case .testimonyArchive: return "Testimony Archive"
        }
    }

    var systemImage: String {
        switch self {
        case .watchLater: return "clock"
        case .prayerQueue: return "hands.sparkles"
        case .churchNotes: return "note.text"
        case .familyWatch: return "person.3"
        case .selahTonight: return "moon.stars"
        case .sermonStudy: return "book"
        case .testimonyArchive: return "archivebox"
        }
    }
}

enum AmenMediaSessionType: String, Codable, CaseIterable, Identifiable {
    case morningInspiration
    case fiveMinuteSelah
    case prayerSafeTestimonies
    case churchNotesStudyPath
    case sermonClipReflection
    case familySafeWatch
    case localChurchUpdates
    case savedVideos
    case communityMoments
    case discoverFeed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morningInspiration: return "Morning Inspiration"
        case .fiveMinuteSelah: return "5-minute Selah"
        case .prayerSafeTestimonies: return "Prayer-safe Testimonies"
        case .churchNotesStudyPath: return "Church Notes Study Path"
        case .sermonClipReflection: return "Sermon Clip and Reflection"
        case .familySafeWatch: return "Family-safe Watch"
        case .localChurchUpdates: return "Local Church Updates"
        case .savedVideos: return "Saved Videos"
        case .communityMoments: return "Community Moments"
        case .discoverFeed: return "Discover"
        }
    }
}

enum AmenMediaSafetyMode: String, Codable, CaseIterable, Identifiable {
    case childSafe
    case griefSensitive
    case anxietySafe
    case traumaAware
    case familySafe
    case churchSafe
    case newBeliever
    case lowStimulation
    case sensitiveTestimony

    var id: String { rawValue }
}

enum AmenMediaCompletionAction: String, Codable, CaseIterable, Identifiable {
    case pray
    case reflect
    case saveToNotes
    case discuss
    case share
    case continueSession
    case takeBreak
    case endSession

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pray: return "Pray"
        case .reflect: return "Reflect"
        case .saveToNotes: return "Save to Notes"
        case .discuss: return "Discuss"
        case .share: return "Share"
        case .continueSession: return "Continue"
        case .takeBreak: return "Take Break"
        case .endSession: return "End Session"
        }
    }

    var systemImage: String {
        switch self {
        case .pray: return "hands.sparkles"
        case .reflect: return "text.bubble"
        case .saveToNotes: return "note.text.badge.plus"
        case .discuss: return "bubble.left.and.bubble.right"
        case .share: return "square.and.arrow.up"
        case .continueSession: return "arrow.right.circle"
        case .takeBreak: return "pause.circle"
        case .endSession: return "checkmark.circle"
        }
    }
}

enum LowBandwidthMediaMode: String, Codable, CaseIterable, Identifiable {
    case automatic
    case lowQualityVideo
    case audioOnly
    case transcriptOnly
    case wifiOnly

    var id: String { rawValue }
}

struct AmenMediaProgress: Codable, Equatable {
    let mediaId: String
    let postId: String
    let progressSeconds: TimeInterval
    let durationSeconds: TimeInterval
    let percentComplete: Double
    let completed: Bool
    let sourceSurface: AmenMediaSourceSurface
}

struct AmenMediaSessionItem: Identifiable, Codable, Equatable {
    let id: String
    let postId: String
    let mediaId: String
    let title: String?
    let order: Int
    let requiresInterruption: Bool
}

struct AmenMediaAccessibilitySettings: Codable, Equatable {
    var captionsDefaultOn: Bool = true
    var captionSize: Double = 1.0
    var highContrastCaptions: Bool = false
    var reduceMotion: Bool = false
    var reduceTransparency: Bool = false
    var autoplayDisabled: Bool = true
    var sensorySafeMode: Bool = false
    var audioDescriptionEnabled: Bool = false
    var simplifiedTranscript: Bool = false
    var preferredLanguage: String = "en"
    var slowerTransitions: Bool = false
    var hapticReduction: Bool = false
    var flashReduction: Bool = true
    var voiceControlLabels: Bool = true
    var persistentControls: Bool = false
    var largerTapTargets: Bool = false

    var payload: [String: Any] {
        [
            "captionsDefaultOn": captionsDefaultOn,
            "captionSize": captionSize,
            "highContrastCaptions": highContrastCaptions,
            "reduceMotion": reduceMotion,
            "reduceTransparency": reduceTransparency,
            "autoplayDisabled": autoplayDisabled,
            "sensorySafeMode": sensorySafeMode,
            "audioDescriptionEnabled": audioDescriptionEnabled,
            "simplifiedTranscript": simplifiedTranscript,
            "preferredLanguage": preferredLanguage,
            "slowerTransitions": slowerTransitions,
            "hapticReduction": hapticReduction,
            "flashReduction": flashReduction,
            "voiceControlLabels": voiceControlLabels,
            "persistentControls": persistentControls,
            "largerTapTargets": largerTapTargets
        ]
    }
}

enum AmenMediaFiniteSessionPolicy {
    static let defaultMinimumItems = 3
    static let defaultMaximumItems = 12
    static let checkpointItemInterval = 3
    static let checkpointSeconds = 8 * 60

    static func clampedItemCount(_ requested: Int?) -> Int {
        min(max(requested ?? defaultMinimumItems, defaultMinimumItems), defaultMaximumItems)
    }

    static func shouldShowCheckpoint(completedItems: Int, elapsedSeconds: TimeInterval, rapidSkips: Int, sensitiveContentAhead: Bool) -> Bool {
        completedItems > 0 && completedItems.isMultiple(of: checkpointItemInterval)
            || elapsedSeconds >= TimeInterval(checkpointSeconds)
            || rapidSkips >= 3
            || sensitiveContentAhead
    }
}

enum MediaSessionCheckpointReason {
    case itemsWatched
    case timeElapsed
    case rapidSkipping
    case sensitiveTransition
    case sensitiveContent
    case sessionEnd
}

struct MediaSessionCheckpoint: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let options: [CheckpointOption]

    struct CheckpointOption: Identifiable, Equatable {
        let id = UUID()
        let label: String
        let icon: String
        let action: Action

        enum Action: Equatable {
            case `continue`
            case reflect
            case journal
            case discuss
            case save
            case endSession
        }
    }

    static func checkpoint(for reason: MediaSessionCheckpointReason) -> MediaSessionCheckpoint {
        let copy: (String, String)
        switch reason {
        case .itemsWatched:
            copy = ("Take a moment?", "You have completed a few items. Reflect now or continue intentionally.")
        case .timeElapsed:
            copy = ("Pause here?", "You have been in this session for a while. Choose what feels useful next.")
        case .rapidSkipping:
            copy = ("Slow the pace?", "You moved through several items quickly. You can pause, reflect, or keep going.")
        case .sensitiveTransition, .sensitiveContent:
            copy = ("Sensitive moment ahead", "Continue intentionally or take a break before the next item.")
        case .sessionEnd:
            copy = ("Session complete", "Reflect on what was useful, save what matters, or end here intentionally.")
        }

        return MediaSessionCheckpoint(
            title: copy.0,
            message: copy.1,
            options: [
                CheckpointOption(label: "Continue", icon: "arrow.right.circle", action: .continue),
                CheckpointOption(label: "Reflect", icon: "text.bubble", action: .reflect),
                CheckpointOption(label: "Journal", icon: "square.and.pencil", action: .journal),
                CheckpointOption(label: "Discuss", icon: "bubble.left.and.bubble.right", action: .discuss),
                CheckpointOption(label: "Save for Later", icon: "bookmark", action: .save),
                CheckpointOption(label: "End Session", icon: "checkmark.circle", action: .endSession)
            ]
        )
    }
}

extension AmenMediaSession {
    var progressFraction: Double {
        guard !itemIds.isEmpty else { return 1 }
        return min(max(Double(currentIndex) / Double(itemIds.count), 0), 1)
    }

    var remainingCount: Int {
        max(itemIds.count - currentIndex, 0)
    }

    var isComplete: Bool {
        status == .completed || currentIndex >= itemIds.count
    }
}

extension AmenMediaSession.SessionType: CaseIterable {
    static var allCases: [AmenMediaSession.SessionType] {
        [
            .morningInspiration,
            .friendsAndFamily,
            .creativeDiscovery,
            .worshipAndMusic,
            .learningSession,
            .sermonHighlights,
            .selahReflection,
            .testimonies,
            .churchMoments,
            .encouragement,
            .custom
        ]
    }

    var displayName: String {
        switch self {
        case .morningInspiration: return "Morning Inspiration"
        case .friendsAndFamily: return "Friends & Family"
        case .creativeDiscovery: return "Creative Discovery"
        case .worshipAndMusic: return "Worship & Music"
        case .learningSession: return "Learning Session"
        case .sermonHighlights: return "Sermon Highlights"
        case .selahReflection: return "Selah Reflection"
        case .testimonies: return "Testimonies"
        case .churchMoments: return "Church Moments"
        case .encouragement: return "Encouragement"
        case .custom: return "Custom Session"
        }
    }

    var systemIcon: String {
        switch self {
        case .morningInspiration: return "sunrise"
        case .friendsAndFamily: return "person.3"
        case .creativeDiscovery: return "paintpalette"
        case .worshipAndMusic: return "music.note"
        case .learningSession: return "book"
        case .sermonHighlights: return "quote.bubble"
        case .selahReflection: return "moon.stars"
        case .testimonies: return "heart.text.square"
        case .churchMoments: return "building.columns"
        case .encouragement: return "hands.sparkles"
        case .custom: return "sparkles"
        }
    }

    var defaultMaxItems: Int {
        switch self {
        case .selahReflection: return 3
        case .learningSession, .sermonHighlights: return 5
        case .custom: return 6
        default: return 6
        }
    }
}

struct AIDisclosureRecord: Identifiable, Codable, Equatable {
    let id: String
    let postId: String
    let mediaId: String
    let ownerUid: String
    let actionType: String
    let modelProvider: String?
    let purpose: String
    let userVisibleLabel: String
    let userVisibleExplanation: String
    let confidence: Double
}

extension MediaProvenance {
    var requiresDisclosureBadge: Bool {
        disclosureRequired && !disclosureSatisfied
    }

    var isSafe: Bool {
        moderationStatus == "approved"
            && syntheticMediaStatus != .deepfakeRisk
            && syntheticMediaStatus != .aiGeneratedMedia
            && authenticityConfidence >= 0.5
    }
}

extension AuthenticityLabel {
    static func labels(for provenance: MediaProvenance) -> [AuthenticityLabel] {
        var labels: [AuthenticityLabel] = []

        if provenance.capturedOnDevice && provenance.syntheticMediaStatus == .clean {
            labels.append(
                AuthenticityLabel(
                    kind: .realMedia,
                    title: "Real Media",
                    detail: "Captured from a device source with no synthetic media risk currently detected.",
                    confident: provenance.authenticityConfidence >= 0.7
                )
            )
        }

        if provenance.contentCredentialsStatus == .verified {
            labels.append(
                AuthenticityLabel(
                    kind: .creatorVerified,
                    title: "Verified Origin",
                    detail: "Content credentials or provenance signals were verified.",
                    confident: true
                )
            )
        }

        switch provenance.syntheticMediaStatus {
        case .aiAssistedMetadata:
            labels.append(
                AuthenticityLabel(
                    kind: .aiAssistedCaptions,
                    title: "AI-Assisted Metadata",
                    detail: "AI helped with accessibility or descriptive metadata only.",
                    confident: true
                )
            )
        case .aiEditedMedia:
            labels.append(
                AuthenticityLabel(
                    kind: .editedRealFootage,
                    title: "Edited Real Footage",
                    detail: "The media may include editing while still representing real footage.",
                    confident: provenance.authenticityConfidence >= 0.6
                )
            )
        case .aiGeneratedMedia, .deepfakeRisk:
            labels.append(
                AuthenticityLabel(
                    kind: .syntheticWarning,
                    title: "Synthetic Risk",
                    detail: "This media requires review before it can be treated as authentic.",
                    confident: false
                )
            )
        case .clean, .unknown:
            break
        }

        if provenance.disclosureRequired && !provenance.disclosureSatisfied {
            labels.append(
                AuthenticityLabel(
                    kind: .pendingReview,
                    title: "Pending Disclosure",
                    detail: "AI disclosure is required before this metadata can be final.",
                    confident: false
                )
            )
        }

        return labels.isEmpty ? [
            AuthenticityLabel(
                kind: .pendingReview,
                title: "Pending Review",
                detail: "Amen is still checking provenance signals for this media.",
                confident: false
            )
        ] : labels
    }

    var systemIcon: String {
        switch kind {
        case .realMedia: return "camera"
        case .creatorVerified, .communityVerified, .churchMedia: return "checkmark.seal"
        case .editedRealFootage: return "slider.horizontal.3"
        case .aiAssistedCaptions, .aiAssistedTranslation: return "wand.and.stars"
        case .transcriptApproved: return "captions.bubble"
        case .pendingReview: return "clock"
        case .syntheticWarning: return "exclamationmark.triangle"
        }
    }
}

// MARK: - Callable Services

@MainActor
final class AmenMediaProgressService: ObservableObject {
    static let shared = AmenMediaProgressService()
    private let functions = Functions.functions()

    private init() {}

    func updateProgress(_ progress: AmenMediaProgress) async throws {
        let boundedDuration = max(progress.durationSeconds, 1)
        let boundedProgress = min(max(progress.progressSeconds, 0), boundedDuration)
        let percentComplete = min(max((boundedProgress / boundedDuration) * 100, 0), 100)

        _ = try await functions.httpsCallable("updateMediaProgress").call([
            "postId": progress.postId,
            "mediaId": progress.mediaId,
            "progressSeconds": boundedProgress,
            "durationSeconds": boundedDuration,
            "percentComplete": percentComplete,
            "completed": percentComplete >= 95 || progress.completed,
            "sourceSurface": progress.sourceSurface.rawValue
        ])
    }
}

@MainActor
final class AmenMediaQueueService: ObservableObject {
    static let shared = AmenMediaQueueService()
    private let functions = Functions.functions()

    private init() {}

    func save(postId: String, mediaId: String, queueType: AmenMediaQueueType, sourceSurface: AmenMediaSourceSurface, note: String? = nil) async throws {
        _ = try await functions.httpsCallable("saveToMediaQueue").call([
            "postId": postId,
            "mediaId": mediaId,
            "queueType": queueType.rawValue,
            "sourceSurface": sourceSurface.rawValue,
            "note": note ?? ""
        ])
    }
}

@MainActor
final class AmenMediaSessionService: ObservableObject {
    static let shared = AmenMediaSessionService()
    private let functions = Functions.functions()

    private init() {}

    func createSession(type: AmenMediaSessionType, sourceSurface: AmenMediaSourceSurface, safetyMode: AmenMediaSafetyMode? = nil, maxItems: Int? = nil, maxDurationSeconds: Int = 8 * 60) async throws -> String {
        let result = try await functions.httpsCallable("createMediaSession").call([
            "sessionType": type.rawValue,
            "sourceSurface": sourceSurface.rawValue,
            "safetyMode": safetyMode?.rawValue ?? "",
            "maxItems": AmenMediaFiniteSessionPolicy.clampedItemCount(maxItems),
            "maxDurationSeconds": maxDurationSeconds
        ])
        let data = result.data as? [String: Any]
        return data?["sessionId"] as? String ?? ""
    }

    func completeSession(sessionId: String, finalAction: AmenMediaCompletionAction) async throws {
        _ = try await functions.httpsCallable("completeMediaSession").call([
            "sessionId": sessionId,
            "finalAction": finalAction.rawValue
        ])
    }

    func createCompletionEvent(postId: String, mediaId: String, sessionId: String?, action: AmenMediaCompletionAction) async throws {
        _ = try await functions.httpsCallable("createMediaCompletionEvent").call([
            "postId": postId,
            "mediaId": mediaId,
            "sessionId": sessionId ?? "",
            "action": action.rawValue
        ])
    }
}

@MainActor
final class AmenMediaSafetyService: ObservableObject {
    static let shared = AmenMediaSafetyService()
    private let functions = Functions.functions()

    private init() {}

    func report(postId: String, mediaId: String, reason: String, details: String?) async throws {
        _ = try await functions.httpsCallable("reportMedia").call([
            "postId": postId,
            "mediaId": mediaId,
            "reason": reason,
            "details": details ?? ""
        ])
    }

    func notInterested(postId: String, mediaId: String, reason: String?) async throws {
        _ = try await functions.httpsCallable("notInterestedMedia").call([
            "postId": postId,
            "mediaId": mediaId,
            "reason": reason ?? ""
        ])
    }
}

@MainActor
final class AmenMediaSearchService: ObservableObject {
    static let shared = AmenMediaSearchService()
    private let functions = Functions.functions()

    private init() {}

    func search(query: String, limit: Int = 20) async throws -> [[String: Any]] {
        let result = try await functions.httpsCallable("searchMedia").call([
            "query": query,
            "filters": [:],
            "limit": min(max(limit, 1), 50)
        ])
        let data = result.data as? [String: Any]
        return data?["items"] as? [[String: Any]] ?? []
    }
}

@MainActor
private final class AmenLegacyOfflineMediaManager: ObservableObject {
    @Published private(set) var mode: LowBandwidthMediaMode = .automatic
    @Published private(set) var errorMessage: String?

    func apply(_ nextMode: LowBandwidthMediaMode) {
        mode = nextMode
    }

    func canCacheMedia(downloadable: Bool, hiddenOrRemoved: Bool) -> Bool {
        downloadable && !hiddenOrRemoved && mode != .transcriptOnly
    }
}

@MainActor
final class AmenMediaPlayerViewModel: ObservableObject {
    @Published var captionsEnabled = true
    @Published var playbackSpeed: Double = 1.0
    @Published var showCompletionReflection = false
    @Published var showControls = true
    @Published var lowBandwidthMode: LowBandwidthMediaMode = .automatic
    @Published var accessibilitySettings = AmenMediaAccessibilitySettings()

    let postId: String
    let mediaId: String
    let sourceSurface: AmenMediaSourceSurface
    private var lastProgressWrite: Date = .distantPast

    init(postId: String, mediaId: String, sourceSurface: AmenMediaSourceSurface) {
        self.postId = postId
        self.mediaId = mediaId
        self.sourceSurface = sourceSurface
    }

    func recordProgress(position: TimeInterval, duration: TimeInterval) async {
        guard Date().timeIntervalSince(lastProgressWrite) >= 10 || position >= duration * 0.95 else { return }
        lastProgressWrite = Date()
        let progress = AmenMediaProgress(
            mediaId: mediaId,
            postId: postId,
            progressSeconds: position,
            durationSeconds: max(duration, 1),
            percentComplete: min(max(position / max(duration, 1) * 100, 0), 100),
            completed: position >= duration * 0.95,
            sourceSurface: sourceSurface
        )
        try? await AmenMediaProgressService.shared.updateProgress(progress)
    }

    func markCompleted() {
        showCompletionReflection = true
    }
}

enum AmenMediaAnalytics {
    static func record(_ eventName: String, postId: String? = nil, mediaId: String? = nil, sessionId: String? = nil, metadata: [String: Any] = [:]) async {
        guard AMENFeatureFlags.shared.analyticsEnabled else { return }
        var payload: [String: Any] = ["eventName": eventName, "metadata": metadata]
        if let postId { payload["postId"] = postId }
        if let mediaId { payload["mediaId"] = mediaId }
        if let sessionId { payload["sessionId"] = sessionId }
        _ = try? await Functions.functions().httpsCallable("recordMediaEvent").call(payload)
    }
}


private struct AmenLegacyTimestampedCommentComposer: View {
    let timestampSeconds: TimeInterval?
    let imageIndex: Int?
    let onSubmit: (String) -> Void
    @State private var bodyText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let timestampSeconds {
                Text("Comment at \(formatTime(timestampSeconds))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else if let imageIndex {
                Text("Comment on image \(imageIndex + 1)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                TextField("Add a thoughtful comment", text: $bodyText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .accessibilityLabel("Timestamped comment")

                Button {
                    let trimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onSubmit(trimmed)
                    bodyText = ""
                } label: {
                    Image(systemName: "paperplane.fill")
                        .frame(width: 44, height: 44)
                }
                .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Post comment")
            }
        }
        .padding()
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded()), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct AmenLegacyTimestampedCommentRow: View {
    let authorName: String
    let text: String
    let timestampSeconds: TimeInterval?
    let imageIndex: Int?
    let onTapContext: () -> Void

    var body: some View {
        Button(action: onTapContext) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(authorName).font(.subheadline.weight(.semibold))
                    Spacer()
                    if let timestampSeconds {
                        Text(formatTime(timestampSeconds)).font(.caption.monospacedDigit())
                    } else if let imageIndex {
                        Text("Image \(imageIndex + 1)").font(.caption)
                    }
                }
                Text(text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Open the referenced media moment")
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded()), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Lightweight card variant used only within AmenHealthyImmersiveMediaSystem.
/// The full canonical completion screen lives in AmenMediaCompletionReflectionView.swift.
private struct _AmenMediaCompletionReflectionCard: View {
    let title: String
    let sessionLabel: String?
    let onAction: (AmenMediaCompletionAction) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                if let sessionLabel {
                    Text(sessionLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)

            AmenLiquidGlassControlDock(placement: .bottom) {
                ForEach(AmenMediaCompletionAction.allCases) { action in
                    AmenLiquidGlassPillButton(title: action.title, systemImage: action.systemImage, isLoading: false, isDisabled: false) {
                        onAction(action)
                    }
                }
            }
        }
        .padding(24)
        .background(reduceTransparency ? AnyShapeStyle(Color.white) : AnyShapeStyle(.regularMaterial), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.65), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 10)
        .accessibilityElement(children: .contain)
    }
}

struct SaveToReflectionQueueSheet: View {
    let postId: String
    let mediaId: String
    let sourceSurface: AmenMediaSourceSurface
    let onSaved: (AmenMediaQueueType) -> Void

    @State private var savingQueue: AmenMediaQueueType?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List(AmenMediaQueueType.allCases) { queue in
                Button {
                    Task { await save(queue) }
                } label: {
                    Label(queue.title, systemImage: queue.systemImage)
                }
                .disabled(savingQueue != nil)
            }
            .navigationTitle("Save Media")
            .overlay(alignment: .bottom) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding()
                }
            }
        }
    }

    private func save(_ queue: AmenMediaQueueType) async {
        savingQueue = queue
        defer { savingQueue = nil }
        do {
            try await AmenMediaQueueService.shared.save(postId: postId, mediaId: mediaId, queueType: queue, sourceSurface: sourceSurface)
            onSaved(queue)
        } catch {
            errorMessage = "Could not save this media right now."
        }
    }
}

struct MediaSafetyGateView: View {
    let title: String
    let message: String
    let continueTitle: String
    let onContinue: () -> Void
    let onTakeBreak: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.blue)
            Text(title).font(.title3.weight(.bold))
            Text(message).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Take Break", action: onTakeBreak)
                    .buttonStyle(.bordered)
                Button(continueTitle, action: onContinue)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

private struct AmenLegacySensitiveContentInterruptionView: View {
    let topicLabel: String
    let onContinue: () -> Void
    let onExit: () -> Void

    var body: some View {
        MediaSafetyGateView(
            title: "Sensitive moment ahead",
            message: "This media includes \(topicLabel). You can continue intentionally or pause here.",
            continueTitle: "Continue"
        ) {
            onContinue()
        } onTakeBreak: {
            onExit()
        }
    }
}

struct ReportMediaSheet: View {
    let postId: String
    let mediaId: String
    let onComplete: () -> Void

    @State private var selectedReason = "harmful_or_dangerous"
    @State private var details = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let reasons = [
        ("harmful_or_dangerous", "Harmful or dangerous"),
        ("harassment", "Harassment"),
        ("graphic_content", "Graphic content"),
        ("misinformation", "Misinformation"),
        ("spiritual_abuse", "Spiritual abuse or manipulation"),
        ("child_safety", "Child safety"),
        ("self_harm", "Self-harm concern"),
        ("spam", "Spam"),
        ("other", "Other")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Picker("Reason", selection: $selectedReason) {
                    ForEach(reasons, id: \.0) { reason in
                        Text(reason.1).tag(reason.0)
                    }
                }
                TextField("Details", text: $details, axis: .vertical)
                    .lineLimit(3...6)
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Report Media")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Submitting" : "Submit") {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting)
                }
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await AmenMediaSafetyService.shared.report(postId: postId, mediaId: mediaId, reason: selectedReason, details: details)
            onComplete()
        } catch {
            errorMessage = "Report could not be submitted."
        }
    }
}

// NotInterestedSheet is defined in NotInterestedSheet.swift

private struct AmenLegacyTakeBreakPromptView: View {
    let onContinue: () -> Void
    let onEndSession: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Pause here?")
                .font(.title3.weight(.bold))
            Text("You can reflect, come back later, or keep going intentionally.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("End Session", action: onEndSession)
                    .buttonStyle(.bordered)
                Button("Continue", action: onContinue)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct SelahMediaPlayerView: View {
    let title: String
    let transcriptHighlights: [String]
    let onReflect: () -> Void
    let onEnd: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.blue)
            Text(title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(transcriptHighlights, id: \.self) { highlight in
                    Text(highlight)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            AmenLiquidGlassControlDock(placement: .bottom) {
                AmenLiquidGlassPillButton(title: "Reflect", systemImage: "text.bubble", isLoading: false, isDisabled: false, action: onReflect)
                AmenLiquidGlassPillButton(title: "End", systemImage: "checkmark.circle", isLoading: false, isDisabled: false, action: onEnd)
            }
        }
        .padding()
        .background(AmenTheme.Colors.backgroundPrimary)
    }
}

struct AmenMediaErrorStateView: View {
    let message: String
    let retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label("Media unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            if let retry {
                Button("Try Again", action: retry)
            }
        }
    }
}

struct AmenMediaEmptyStateView: View {
    let message: String

    var body: some View {
        ContentUnavailableView("No media", systemImage: "photo.on.rectangle", description: Text(message))
    }
}

struct AmenMediaLoadingStateView: View {
    var body: some View {
        ProgressView("Loading media")
            .controlSize(.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Human-First Immersive Media Shells

struct AmenLiquidGlassMediaDock<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 10, content: content)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(reduceTransparency ? AnyShapeStyle(Color.white) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.7), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 8)
            .accessibilityElement(children: .contain)
    }
}

struct AmenLiquidGlassSessionCapsule: View {
    let title: String
    let progressLabel: String
    let communityLabel: String?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.rectangle.on.rectangle")
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text([progressLabel, communityLabel].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(reduceTransparency ? AnyShapeStyle(Color.white) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.7), lineWidth: 1))
        .accessibilityLabel("\(title), \(progressLabel)")
    }
}

struct AmenLiquidGlassCommunityLayer: View {
    let title: String
    let comments: [String]
    let onDiscuss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: "person.3")
                    .font(.headline)
                Spacer()
                Button("Discuss", action: onDiscuss)
                    .buttonStyle(.bordered)
            }

            ForEach(comments.prefix(3), id: \.self) { comment in
                Text(comment)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.6), lineWidth: 1))
    }
}

struct AmenLiquidGlassSelahOverlay: View {
    let title: String
    let message: String
    let onReflect: () -> Void
    let onEnd: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.title3.weight(.bold))
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button("End", action: onEnd)
                    .buttonStyle(.bordered)
                Button("Reflect", action: onReflect)
                    .buttonStyle(.bordered)
                Button("Continue", action: onContinue)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.white.opacity(0.65), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.1), radius: 22, x: 0, y: 12)
    }
}

struct AmenMediaSessionCompletionView: View {
    let sessionTitle: String
    let onAction: (AmenMediaCompletionAction) -> Void

    var body: some View {
        _AmenMediaCompletionReflectionCard(
            title: "Session Complete",
            sessionLabel: sessionTitle,
            onAction: onAction
        )
    }
}

struct AmenImmersiveMediaHomeView: View {
    let onStartSession: (AmenMediaSessionType) -> Void
    var continueSessionTitle: String? = nil
    var onContinueSession: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    continueSessionSection
                    morningSection
                    intentionalSection
                    friendsFamilySection
                    communityMomentsSection
                    localNearbySection
                    selahSection
                    churchCreatorSection
                    learningSection
                    discoverSection
                    savedSection
                }
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Media")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: 1 — Continue Session

    @ViewBuilder
    private var continueSessionSection: some View {
        if let title = continueSessionTitle, let onContinue = onContinueSession {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("Continue where you left off")
                    .padding(.horizontal, 16)
                Button(action: onContinue) { continueCard(title: title) }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
            }
            .padding(.bottom, 28)
        }
    }

    // MARK: 2 — Good Morning

    private var morningSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Good morning")
                .padding(.horizontal, 16)
            Button { onStartSession(.morningInspiration) } label: {
                heroCard(
                    session: .morningInspiration,
                    subtitle: "Begin with something that matters"
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 28)
    }

    // MARK: 3 — Intentional Sessions

    private var intentionalSection: some View {
        horizontalScrollSection(
            label: "Start an intentional session",
            sessions: [.fiveMinuteSelah, .prayerSafeTestimonies, .familySafeWatch, .morningInspiration]
        )
    }

    // MARK: 4 — Friends & Family

    private var friendsFamilySection: some View {
        horizontalScrollSection(
            label: "Friends & family",
            sessions: [.familySafeWatch, .prayerSafeTestimonies]
        )
    }

    // MARK: 5 — Community Moments

    @ViewBuilder
    private var communityMomentsSection: some View {
        if AMENFeatureFlags.shared.communityMediaLayersEnabled {
            horizontalScrollSection(
                label: "Community moments",
                sessions: [.communityMoments]
            )
        }
    }

    // MARK: 6 — Local & Nearby

    private var localNearbySection: some View {
        horizontalScrollSection(
            label: "Local & nearby",
            sessions: [.localChurchUpdates]
        )
    }

    // MARK: 7 — Selah & Reflection

    private var selahSection: some View {
        horizontalScrollSection(
            label: "Selah & reflection",
            sessions: [.fiveMinuteSelah, .prayerSafeTestimonies]
        )
    }

    // MARK: 8 — Church & Creator

    private var churchCreatorSection: some View {
        horizontalScrollSection(
            label: "Church & creator",
            sessions: [.sermonClipReflection, .churchNotesStudyPath, .localChurchUpdates]
        )
    }

    // MARK: 9 — Learning & Teaching

    private var learningSection: some View {
        horizontalScrollSection(
            label: "Learning & teaching",
            sessions: [.sermonClipReflection, .churchNotesStudyPath]
        )
    }

    // MARK: 10 — Discover

    private var discoverSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Discover")
                .padding(.horizontal, 16)
            Button { onStartSession(.discoverFeed) } label: {
                discoverCard
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 28)
    }

    // MARK: 11 — Saved for Later

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Saved for later")
                .padding(.horizontal, 16)
            Button { onStartSession(.savedVideos) } label: { savedCard }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
        }
        .padding(.bottom, 28)
    }

    // MARK: Reusable Section Builder

    private func horizontalScrollSection(label: String, sessions: [AmenMediaSessionType]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(label)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(sessions) { session in
                        sessionCard(session)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }
        }
        .padding(.bottom, 28)
    }

    // MARK: Card Builders

    private func continueCard(title: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("Continue session")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Resume")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.black, in: Capsule())
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5))
    }

    private func heroCard(session: AmenMediaSessionType, subtitle: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: sessionIcon(for: session))
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.primary)
                .frame(width: 52, height: 52)
                .background(Color(.tertiarySystemFill), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(sessionMetaLabel(for: session))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            startPill
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5))
    }

    private func sessionCard(_ session: AmenMediaSessionType) -> some View {
        Button { onStartSession(session) } label: {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: sessionIcon(for: session))
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color(.tertiarySystemFill), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(sessionMetaLabel(for: session))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                startPill.frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(width: 200, height: 190)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(session.title). \(sessionMetaLabel(for: session)). Double-tap to start.")
    }

    private var discoverCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(Color(.tertiarySystemFill), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Discover")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("New voices · Curated for your walk")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            startPill
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5))
    }

    private var savedCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "bookmark.fill")
                .font(.title2)
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(Color(.tertiarySystemFill), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Saved Media")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Your personal queue · Continue anytime")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            startPill
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5))
    }

    private var startPill: some View {
        Text("Start")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black, in: Capsule())
            .accessibilityHidden(true)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
    }

    // MARK: Session Metadata Helpers

    private func sessionIcon(for session: AmenMediaSessionType) -> String {
        switch session {
        case .morningInspiration:    return "sunrise"
        case .fiveMinuteSelah:       return "moon.stars"
        case .prayerSafeTestimonies: return "hands.sparkles"
        case .churchNotesStudyPath:  return "note.text"
        case .sermonClipReflection:  return "quote.bubble"
        case .familySafeWatch:       return "person.3"
        case .localChurchUpdates:    return "building.columns"
        case .savedVideos:           return "bookmark"
        case .communityMoments:      return "person.2.wave.2"
        case .discoverFeed:          return "sparkles"
        @unknown default:            return "play.rectangle"
        }
    }

    private func sessionMetaLabel(for session: AmenMediaSessionType) -> String {
        switch session {
        case .morningInspiration:    return "6 clips · ~8 min · People you trust"
        case .fiveMinuteSelah:       return "3 clips · ~5 min · Quiet reflection"
        case .prayerSafeTestimonies: return "5 clips · ~10 min · Trusted voices"
        case .churchNotesStudyPath:  return "4 clips · ~12 min · Linked to your notes"
        case .sermonClipReflection:  return "3 clips · ~15 min · Sermon highlights"
        case .familySafeWatch:       return "6 clips · ~8 min · Safe for all ages"
        case .localChurchUpdates:    return "5 clips · ~6 min · Your local community"
        case .savedVideos:           return "Your saved media · Continue anytime"
        case .communityMoments:      return "Moments from your community · No metrics"
        case .discoverFeed:          return "Curated voices · Finite session"
        @unknown default:            return "Finite session · Intentional media"
        }
    }
}

struct AmenImmersiveMediaSessionView: View {
    let session: AmenMediaSession
    var onReflect: (() -> Void)?
    var onJournal: (() -> Void)?
    var onDiscuss: (() -> Void)?

    var body: some View {
        if AMENFeatureFlags.shared.mediaFiniteSessionsEnabled {
            AmenMediaSessionView(
                session: session,
                onReflect: onReflect,
                onJournal: onJournal,
                onDiscuss: onDiscuss
            )
        } else {
            AmenMediaEmptyStateView(message: "Finite media sessions are not enabled.")
        }
    }
}
