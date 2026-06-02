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
        case .discoverFeed: return "Discover Feed"
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

struct AmenHealthyMediaSession: Identifiable, Codable, Equatable {
    let id: String
    let sessionType: AmenMediaSessionType
    let itemIds: [String]
    var currentIndex: Int
    var completed: Bool
    let sourceSurface: AmenMediaSourceSurface
    let safetyMode: AmenMediaSafetyMode?
    let maxItems: Int
    let maxDurationSeconds: Int

    var isFinite: Bool { maxItems > 0 && itemIds.count <= maxItems }
    var progressLabel: String { "\(min(currentIndex + 1, max(itemIds.count, 1))) of \(itemIds.count)" }
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
final class OfflineMediaManager: ObservableObject {
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

// MARK: - Reusable Frontend Surfaces

struct MediaCaptionOverlay: View {
    let text: String
    var settings: AmenMediaAccessibilitySettings = AmenMediaAccessibilitySettings()

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Text(text)
            .font(.system(size: settings.highContrastCaptions ? 19 : 17, weight: .semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(settings.highContrastCaptions ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(settings.highContrastCaptions ? 0.8 : 0.45), lineWidth: 1)
            )
            .accessibilityLabel("Captions")
            .accessibilityValue(text)
    }

    private var backgroundStyle: some ShapeStyle {
        if reduceTransparency || settings.reduceTransparency || settings.highContrastCaptions {
            return AnyShapeStyle(Color.black.opacity(0.82))
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }
}

struct MediaKeyMomentsRail: View {
    let moments: [MediaKeyMoment]
    let onSelect: (MediaKeyMoment) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(moments.filter { $0.isPubliclyApproved }) { moment in
                    AmenLiquidGlassPillButton(
                        title: "\(moment.timestampLabel) \(moment.label)",
                        systemImage: "sparkle.magnifyingglass",
                        isLoading: false,
                        isDisabled: false
                    ) {
                        onSelect(moment)
                    }
                    .accessibilityHint("Seek to this approved key moment")
                }
            }
            .padding(.horizontal)
        }
    }
}

struct TimestampedCommentComposer: View {
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

struct TimestampedCommentRow: View {
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

struct AmenMediaCompletionReflectionView: View {
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
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

struct SensitiveContentInterruptionView: View {
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

struct NotInterestedSheet: View {
    let postId: String
    let mediaId: String
    let onComplete: () -> Void
    @State private var reason = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Not Interested")
                .font(.title3.weight(.bold))
            Text("This helps keep sessions intentional and safe.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("Optional reason", text: $reason, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            Button("Hide Similar Media") {
                Task {
                    try? await AmenMediaSafetyService.shared.notInterested(postId: postId, mediaId: mediaId, reason: reason)
                    onComplete()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

struct TakeBreakPromptView: View {
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
        .background(Color.white)
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
