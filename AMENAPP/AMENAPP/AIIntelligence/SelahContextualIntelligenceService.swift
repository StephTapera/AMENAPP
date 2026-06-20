import Foundation

// MARK: - Selah Contextual Intelligence
// Local, deterministic evaluator for mic-free Selah signals. This file owns the
// restraint contract: every suggestion must pass permission, Sabbath/rest, cooldown,
// and confidence gates before a caller may render it.

enum SelahContextualFeature: String, CaseIterable, Codable, Identifiable {
    case bulletinSlideCapture
    case smallGroupLiveSync
    case worshipSetBuilder
    case sermonMemory
    case liturgicalLayer
    case commuteFormation
    case travelPlaceAwareness
    case seriesAutoAssembly
    case copiedVerseCatch
    case photoMemoryAnchoring
    case prayerRequestRadar
    case groupReadingPresence
    case sabbathRestMode
    case doomscrollInterceptor
    case confidenceGatedSilence
    case reflectionActionLoop
    case bereanVerificationGate
    case crossReferenceWeb
    case translationTraditionTuning
    case stressAwareSurfacing

    var displayName: String {
        switch self {
        case .bulletinSlideCapture: return "Bulletin & Slide Capture"
        case .smallGroupLiveSync: return "Small Group Live Sync"
        case .worshipSetBuilder: return "Worship Set Builder"
        case .sermonMemory: return "Sermon Memory"
        case .liturgicalLayer: return "Liturgical Layer"
        case .commuteFormation: return "Commute Formation"
        case .travelPlaceAwareness: return "Travel & Place Awareness"
        case .seriesAutoAssembly: return "Series Auto-Assembly"
        case .copiedVerseCatch: return "Copied-Verse Catch"
        case .photoMemoryAnchoring: return "Photo-Memory Anchoring"
        case .prayerRequestRadar: return "Prayer Request Radar"
        case .groupReadingPresence: return "Group Reading Presence"
        case .sabbathRestMode: return "Sabbath / Rest Mode"
        case .doomscrollInterceptor: return "Doomscroll Interceptor"
        case .confidenceGatedSilence: return "Confidence-Gated Silence"
        case .reflectionActionLoop: return "Reflection-to-Action Loop"
        case .bereanVerificationGate: return "Berean Verification Gate"
        case .crossReferenceWeb: return "Cross-Reference Web"
        case .translationTraditionTuning: return "Translation & Tradition Tuning"
        case .stressAwareSurfacing: return "Stress-Aware Surfacing"
        }
    }

    var cluster: SelahContextualCluster {
        switch self {
        case .bulletinSlideCapture, .smallGroupLiveSync, .worshipSetBuilder, .sermonMemory:
            return .inTheRoom
        case .liturgicalLayer, .commuteFormation, .travelPlaceAwareness, .seriesAutoAssembly:
            return .acrossTheWeek
        case .copiedVerseCatch, .photoMemoryAnchoring, .prayerRequestRadar, .groupReadingPresence:
            return .flowOfLife
        case .sabbathRestMode, .doomscrollInterceptor, .confidenceGatedSilence, .reflectionActionLoop:
            return .restraintSpine
        case .bereanVerificationGate, .crossReferenceWeb, .translationTraditionTuning, .stressAwareSurfacing:
            return .trustAndDepth
        }
    }

    var requiredPermissions: Set<SelahContextualPermission> {
        switch self {
        case .bulletinSlideCapture:
            return [.camera]
        case .smallGroupLiveSync:
            return [.calendar, .groupMembership]
        case .worshipSetBuilder, .sermonMemory:
            return [.foregroundAudio]
        case .liturgicalLayer, .sabbathRestMode, .confidenceGatedSilence, .reflectionActionLoop, .bereanVerificationGate, .crossReferenceWeb, .translationTraditionTuning:
            return []
        case .commuteFormation:
            return [.motionOrCarPlay]
        case .travelPlaceAwareness:
            return [.locationCategory]
        case .seriesAutoAssembly:
            return [.sermonHistory]
        case .copiedVerseCatch:
            return [.clipboardOrShareSheet]
        case .photoMemoryAnchoring:
            return [.photos]
        case .prayerRequestRadar:
            return [.socialGraph]
        case .groupReadingPresence:
            return [.socialPresence]
        case .doomscrollInterceptor:
            return [.screenTime]
        case .stressAwareSurfacing:
            return [.health]
        }
    }

    var phase: SelahContextualPhase {
        switch self {
        case .liturgicalLayer, .sabbathRestMode, .confidenceGatedSilence, .reflectionActionLoop, .crossReferenceWeb, .translationTraditionTuning:
            return .phaseOneMicFree
        case .bulletinSlideCapture, .smallGroupLiveSync, .commuteFormation, .travelPlaceAwareness, .copiedVerseCatch, .groupReadingPresence, .bereanVerificationGate, .seriesAutoAssembly:
            return .phaseTwoSystemSignals
        case .worshipSetBuilder, .sermonMemory, .photoMemoryAnchoring, .prayerRequestRadar:
            return .phaseThreeConsentedMedia
        case .doomscrollInterceptor, .stressAwareSurfacing:
            return .phaseFourSensitiveSignals
        }
    }
}

enum SelahContextualCluster: String, Codable, CaseIterable {
    case inTheRoom
    case acrossTheWeek
    case flowOfLife
    case restraintSpine
    case trustAndDepth
}

enum SelahContextualPhase: String, Codable, CaseIterable {
    case phaseOneMicFree
    case phaseTwoSystemSignals
    case phaseThreeConsentedMedia
    case phaseFourSensitiveSignals
}

enum SelahContextualPermission: String, Codable, CaseIterable, Hashable {
    case camera
    case calendar
    case groupMembership
    case foregroundAudio
    case motionOrCarPlay
    case locationCategory
    case sermonHistory
    case clipboardOrShareSheet
    case photos
    case socialGraph
    case socialPresence
    case screenTime
    case health
}

enum SelahContextualSurface: String, Codable, CaseIterable {
    case silent
    case queueForLater
    case inline
    case notification
    case restScreen
}

enum SelahLiturgicalSeason: String, Codable, CaseIterable {
    case ordinaryTime
    case advent
    case christmas
    case epiphany
    case lent
    case holyWeek
    case easter
    case pentecost

    var defaultScriptureRefs: [String] {
        switch self {
        case .ordinaryTime: return ["Psalm 1", "Colossians 3:12-17"]
        case .advent: return ["Isaiah 9:2-7", "Luke 1:26-38"]
        case .christmas: return ["Luke 2:1-20", "John 1:1-14"]
        case .epiphany: return ["Matthew 2:1-12", "Isaiah 60:1-6"]
        case .lent: return ["Psalm 51", "Matthew 4:1-11"]
        case .holyWeek: return ["John 13:1-17", "Isaiah 53"]
        case .easter: return ["John 20:1-18", "1 Corinthians 15:3-8"]
        case .pentecost: return ["Acts 2:1-21", "John 14:15-27"]
        }
    }
}

struct SelahContextualSettings: Equatable {
    var enabledFeatures: Set<SelahContextualFeature> = Set(SelahContextualFeature.allCases)
    var grantedPermissions: Set<SelahContextualPermission> = []
    var interruptTolerance: Double = 0.5
    var chosenSabbathWeekday: Int? = nil
    var quietHours: ClosedRange<Int> = 22...23
    var lastSurfaceAtByFeature: [SelahContextualFeature: Date] = [:]
    var minimumMinutesBetweenSurfaces: Int = 240

    func isFeatureEnabled(_ feature: SelahContextualFeature) -> Bool {
        enabledFeatures.contains(feature)
    }

    func hasPermissions(for feature: SelahContextualFeature) -> Bool {
        feature.requiredPermissions.isSubset(of: grantedPermissions)
    }
}

struct SelahContextualInput: Equatable {
    var now: Date = Date()
    var calendar: Calendar = .current
    var signalConfidenceByFeature: [SelahContextualFeature: Double] = [:]
    var recentReflectionText: String? = nil
    var recentScriptureRefs: [String] = []
    var sessionDurationSeconds: TimeInterval = 0
    var mediaViewedCount: Int = 0
    var highLoadContentFraction: Double = 0

    func confidence(for feature: SelahContextualFeature) -> Double {
        signalConfidenceByFeature[feature] ?? 0
    }
}

struct SelahContextualSuggestion: Identifiable, Equatable {
    let id: UUID
    let feature: SelahContextualFeature
    let surface: SelahContextualSurface
    let title: String
    let message: String
    let scriptureRefs: [String]
    let confidence: Double
    let createdAt: Date

    init(
        id: UUID = UUID(),
        feature: SelahContextualFeature,
        surface: SelahContextualSurface,
        title: String,
        message: String,
        scriptureRefs: [String],
        confidence: Double,
        createdAt: Date
    ) {
        self.id = id
        self.feature = feature
        self.surface = surface
        self.title = title
        self.message = message
        self.scriptureRefs = scriptureRefs
        self.confidence = confidence
        self.createdAt = createdAt
    }
}

struct SelahContextualEvaluation: Equatable {
    var suggestions: [SelahContextualSuggestion]
    var suppressedFeatures: [SelahContextualFeature: SelahSuppressionReason]

    var surfacedSuggestions: [SelahContextualSuggestion] {
        suggestions.filter { $0.surface != .silent }
    }
}

enum SelahSuppressionReason: String, Codable, Equatable {
    case featureDisabled
    case permissionMissing
    case confidenceTooLow
    case cooldownActive
    case sabbathSilence
    case noRelevantSignal
}

struct SelahContextualIntelligenceService {
    static let shared = SelahContextualIntelligenceService()

    func evaluate(
        input: SelahContextualInput,
        settings: SelahContextualSettings = SelahContextualSettings()
    ) -> SelahContextualEvaluation {
        var suggestions: [SelahContextualSuggestion] = []
        var suppressed: [SelahContextualFeature: SelahSuppressionReason] = [:]

        let candidates = buildCandidates(input: input)
        for candidate in candidates {
            let feature = candidate.feature
            if !settings.isFeatureEnabled(feature) {
                suppressed[feature] = .featureDisabled
                continue
            }
            if !settings.hasPermissions(for: feature) {
                suppressed[feature] = .permissionMissing
                continue
            }
            if isSabbathSilenceActive(feature: feature, input: input, settings: settings) {
                suppressed[feature] = .sabbathSilence
                continue
            }
            if isCoolingDown(feature: feature, input: input, settings: settings) {
                suppressed[feature] = .cooldownActive
                continue
            }
            guard candidate.confidence >= threshold(for: feature, tolerance: settings.interruptTolerance) else {
                suppressed[feature] = .confidenceTooLow
                continue
            }
            suggestions.append(candidate)
        }

        for feature in SelahContextualFeature.allCases where suppressed[feature] == nil && !candidates.contains(where: { $0.feature == feature }) {
            suppressed[feature] = .noRelevantSignal
        }

        return SelahContextualEvaluation(suggestions: suggestions, suppressedFeatures: suppressed)
    }

    func liturgicalSeason(for date: Date, calendar: Calendar = .current) -> SelahLiturgicalSeason {
        let components = calendar.dateComponents([.month, .day], from: date)
        guard let month = components.month, let day = components.day else { return .ordinaryTime }

        if month == 12 && day >= 25 { return .christmas }
        if month == 1 && day <= 5 { return .christmas }
        if month == 1 && day >= 6 { return .epiphany }
        if month == 12 && day >= 1 && day <= 24 { return .advent }
        if month == 3 && day >= 1 { return .lent }
        if month == 4 && day <= 7 { return .holyWeek }
        if month == 4 && day <= 30 { return .easter }
        if month == 5 && day <= 31 { return .easter }
        if month == 6 && day <= 15 { return .pentecost }
        return .ordinaryTime
    }

    func isSabbathActive(now: Date, calendar: Calendar = .current, chosenWeekday: Int?) -> Bool {
        guard let chosenWeekday else { return false }
        return calendar.component(.weekday, from: now) == chosenWeekday
    }

    private func buildCandidates(input: SelahContextualInput) -> [SelahContextualSuggestion] {
        var candidates: [SelahContextualSuggestion] = []
        let season = liturgicalSeason(for: input.now, calendar: input.calendar)

        if season != .ordinaryTime {
            candidates.append(SelahContextualSuggestion(
                feature: .liturgicalLayer,
                surface: .inline,
                title: seasonTitle(season),
                message: seasonMessage(season),
                scriptureRefs: season.defaultScriptureRefs,
                confidence: max(0.82, input.confidence(for: .liturgicalLayer)),
                createdAt: input.now
            ))
        }

        if input.confidence(for: .sabbathRestMode) > 0 || input.sessionDurationSeconds > 20 * 60 || input.mediaViewedCount >= 12 {
            candidates.append(SelahContextualSuggestion(
                feature: .sabbathRestMode,
                surface: .restScreen,
                title: "Rest mode",
                message: "Selah can quiet prompts and keep the session simple.",
                scriptureRefs: ["Matthew 11:28-30", "Psalm 23"],
                confidence: max(input.confidence(for: .sabbathRestMode), restConfidence(input: input)),
                createdAt: input.now
            ))
        }

        if let reflection = input.recentReflectionText?.trimmingCharacters(in: .whitespacesAndNewlines), !reflection.isEmpty {
            candidates.append(SelahContextualSuggestion(
                feature: .reflectionActionLoop,
                surface: .queueForLater,
                title: "Follow up on this reflection",
                message: "Schedule one gentle check-in so insight can become practice.",
                scriptureRefs: input.recentScriptureRefs.isEmpty ? ["James 1:22"] : Array(input.recentScriptureRefs.prefix(2)),
                confidence: max(0.76, input.confidence(for: .reflectionActionLoop)),
                createdAt: input.now
            ))
        }

        return candidates
    }

    private func threshold(for feature: SelahContextualFeature, tolerance: Double) -> Double {
        let clampedTolerance = min(max(tolerance, 0), 1)
        let base: Double
        switch feature {
        case .confidenceGatedSilence, .sabbathRestMode, .liturgicalLayer:
            base = 0.65
        case .reflectionActionLoop, .crossReferenceWeb, .translationTraditionTuning:
            base = 0.72
        case .photoMemoryAnchoring, .prayerRequestRadar, .doomscrollInterceptor, .stressAwareSurfacing:
            base = 0.88
        default:
            base = 0.78
        }
        return min(0.95, max(0.45, base + (0.5 - clampedTolerance) * 0.28))
    }

    private func restConfidence(input: SelahContextualInput) -> Double {
        var score = 0.0
        if input.sessionDurationSeconds >= 20 * 60 { score += 0.34 }
        if input.mediaViewedCount >= 12 { score += 0.26 }
        if input.highLoadContentFraction >= 0.5 { score += 0.18 }
        let hour = input.calendar.component(.hour, from: input.now)
        if hour >= 22 || hour < 5 { score += 0.22 }
        return min(score, 0.94)
    }

    private func isCoolingDown(
        feature: SelahContextualFeature,
        input: SelahContextualInput,
        settings: SelahContextualSettings
    ) -> Bool {
        guard let lastSurfaceAt = settings.lastSurfaceAtByFeature[feature] else { return false }
        let cooldown = TimeInterval(settings.minimumMinutesBetweenSurfaces * 60)
        return input.now.timeIntervalSince(lastSurfaceAt) < cooldown
    }

    private func isSabbathSilenceActive(
        feature: SelahContextualFeature,
        input: SelahContextualInput,
        settings: SelahContextualSettings
    ) -> Bool {
        guard isSabbathActive(now: input.now, calendar: input.calendar, chosenWeekday: settings.chosenSabbathWeekday) else {
            return false
        }
        return feature != .sabbathRestMode
    }

    private func seasonTitle(_ season: SelahLiturgicalSeason) -> String {
        switch season {
        case .advent: return "Advent"
        case .christmas: return "Christmas"
        case .epiphany: return "Epiphany"
        case .lent: return "Lent"
        case .holyWeek: return "Holy Week"
        case .easter: return "Easter"
        case .pentecost: return "Pentecost"
        case .ordinaryTime: return "Ordinary Time"
        }
    }

    private func seasonMessage(_ season: SelahLiturgicalSeason) -> String {
        switch season {
        case .advent: return "Shape today around waiting, hope, and the coming of Christ."
        case .christmas: return "Keep the incarnation close to reading, prayer, and reflection."
        case .epiphany: return "Surface light, witness, and the nations without adding noise."
        case .lent: return "Favor repentance, mercy, fasting, and slower reflection."
        case .holyWeek: return "Keep attention on the passion of Christ and quiet prayer."
        case .easter: return "Let resurrection hope guide verses and prompts."
        case .pentecost: return "Make room for the Spirit, mission, and gathered witness."
        case .ordinaryTime: return "Keep steady formation without seasonal emphasis."
        }
    }
}
