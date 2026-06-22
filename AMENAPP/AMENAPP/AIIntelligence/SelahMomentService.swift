// SelahMomentService.swift
// AMEN — Selah Moment invocation service
//
// SelahMomentService manages the canonical brief Selah pause triggered at
// intentional formation moments. It dispatches a haptic pulse and sets
// `isActive` for 1.2 seconds before returning to false.
//
// Canonical invocation sites (document here so callsites can be audited):
//   1. Commitment completion — when a user marks a witnessed commitment done.
//   2. Vulnerable content publish — when a user publishes a prayer request,
//      personal testimony, or sensitive reflection.
//
// Flag-gated: AMENFeatureFlags.shared.selahMoments.
// When the flag is OFF, trigger() is a no-op and isActive never becomes true.
//
// Usage:
//   @StateObject private var selahService = SelahMomentService()
//   Button("Complete") {
//       selahService.trigger()
//   }
//   .selahMoment(trigger: selahService.isActive)

import SwiftUI
import UIKit
import AVFoundation
import CoreHaptics

@MainActor
final class SelahMomentService: ObservableObject {

    // MARK: - Published State

    /// True for exactly SelahMomentConfig.duration seconds after trigger() fires.
    /// Consumers can bind `.selahMoment(trigger:)` or any overlay directly to this.
    @Published private(set) var isActive: Bool = false

    // MARK: - Private

    private var deactivationTask: Task<Void, Never>?

    // MARK: - Trigger

    /// Fires a haptic pulse and sets `isActive = true` for `SelahMomentConfig.duration`
    /// seconds, then resets to false.
    ///
    /// Calling trigger() while already active re-arms the timer — the active window
    /// extends from the most-recent call.
    ///
    /// No-op when `AMENFeatureFlags.shared.selahMoments` is false.
    func trigger() {
        guard AMENFeatureFlags.shared.selahMoments else { return }

        if AMENFeatureFlags.shared.selahSensoryLayerEnabled {
            let sensoryState = SelahModifierState(
                timeOfDay: .neutral,
                sabbathMode: false,
                reflectionIdleDuration: 0,
                audioSensitivityReduced: false,
                reduceMotion: UIAccessibility.isReduceMotionEnabled
            )
            SelahSensoryLayer.shared.startAmbientBed(.selahRoomTone, state: sensoryState)
            SelahSensoryLayer.shared.play(.selahStart, state: sensoryState)
        } else {
            // Haptic is a separate accessibility axis from visual motion — always fires.
            let generator = UIImpactFeedbackGenerator(style: SelahMomentConfig.haptic)
            generator.prepare()
            generator.impactOccurred()
        }

        isActive = true

        // Cancel any in-flight deactivation before starting a new one.
        deactivationTask?.cancel()
        deactivationTask = Task { [weak self] in
            do {
                // Wait exactly the configured duration.
                try await Task.sleep(
                    nanoseconds: UInt64(SelahMomentConfig.duration * 1_000_000_000)
                )
                self?.isActive = false
            } catch {
                // Task was cancelled (re-arm scenario) — leave isActive as-is.
            }
        }
    }
}

// MARK: - Selah Sensory Layer Wave 0 Contract

enum SelahSensoryEvent: String, CaseIterable, Identifiable {
    case openBible = "open_bible"
    case pageTurnPsalms = "page_turn_psalms"
    case pageTurnOldTestament = "page_turn_old_testament"
    case pageTurnNewTestament = "page_turn_new_testament"
    case chapterJump = "chapter_jump_10_plus"
    case verseHighlight = "verse_highlight"
    case bookmarkVerse = "bookmark_verse"
    case prayerStart = "prayer_start"
    case prayerEnd = "prayer_end"
    case prayerJournalSave = "prayer_journal_save"
    case selahStart = "selah_start"
    case selahComplete = "selah_complete"

    var id: String { rawValue }
}

enum SelahAmbientBed: String, CaseIterable, Identifiable {
    case selahRoomTone = "selah_room_tone"
    case ancientJerusalemCourtyard = "ancient_jerusalem_courtyard"
    case desertWilderness = "desert_wilderness"
    case upperRoom = "upper_room"
    case galileeShoreline = "galilee_shoreline"
    case monasteryLibrary = "monastery_library"
    case quietChapel = "quiet_chapel"
    case forestPrayerWalk = "forest_prayer_walk"
    case psalmsQuietRoom = "psalms_quiet_room"
    case revelationCinematicSpace = "revelation_cinematic_space"
    case sermonMountOutdoor = "sermon_mount_outdoor"

    var id: String { rawValue }
}

enum SelahSensoryLayerKind: String {
    case sensoryEvent
    case ambientBed
    case modifier
}

enum SelahAudioSessionContext: Equatable {
    case incidental
    case immersive

    var category: AVAudioSession.Category {
        switch self {
        case .incidental:
            return .ambient
        case .immersive:
            return .playback
        }
    }

    var options: AVAudioSession.CategoryOptions {
        switch self {
        case .incidental:
            return [.mixWithOthers]
        case .immersive:
            return [.mixWithOthers, .duckOthers]
        }
    }
}

enum SelahHapticPatternID: String {
    case softTap = "soft_tap"
    case lightImpact = "light_impact"
    case layeredLightImpacts = "layered_light_impacts"
    case microPulse = "micro_pulse"
    case gentlePulse = "gentle_pulse"
    case releasePulse = "release_pulse"
    case longSoftVibration = "long_soft_vibration"
}

struct SelahSoundAssetDescriptor: Equatable, Identifiable {
    enum PlaybackMode: Equatable {
        case oneShot
        case seamlessLoop(loopStart: TimeInterval, loopEnd: TimeInterval)
    }

    let id: String
    let purpose: String
    let layer: SelahSensoryLayerKind
    let fileName: String
    let fileExtension: String
    let playbackMode: PlaybackMode
    let targetLUFS: Double
    let truePeakCeilingDBTP: Double
    let duckingGainDB: Double
    let crossfadeDuration: TimeInterval
    let sourceLicense: String
}

struct SelahSensoryEventDescriptor: Equatable, Identifiable {
    let id: SelahSensoryEvent
    let purpose: String
    let sound: SelahSoundAssetDescriptor
    let haptic: SelahHapticPatternID
    let sessionContext: SelahAudioSessionContext
    let formationGuardrail: String
}

struct SelahAmbientBedDescriptor: Equatable, Identifiable {
    let id: SelahAmbientBed
    let purpose: String
    let sound: SelahSoundAssetDescriptor
    let defaultGainDB: Double
    let allowsSpatialization: Bool
    let formationGuardrail: String
}

struct SelahModifierState: Equatable {
    enum TimeOfDayProfile: Equatable {
        case morning
        case evening
        case lateNight
        case neutral
    }

    var timeOfDay: TimeOfDayProfile = .neutral
    var sabbathMode: Bool = false
    var reflectionIdleDuration: TimeInterval = 0
    var audioSensitivityReduced: Bool = false
    var reduceMotion: Bool = false
}

struct SelahModifierTransform: Equatable {
    var gainDB: Double = 0
    var lowPassHz: Double?
    var density: Double = 1
    var timingScale: Double = 1

    static let neutral = SelahModifierTransform()

    func combined(with other: SelahModifierTransform) -> SelahModifierTransform {
        SelahModifierTransform(
            gainDB: gainDB + other.gainDB,
            lowPassHz: [lowPassHz, other.lowPassHz].compactMap { $0 }.min(),
            density: density * other.density,
            timingScale: timingScale * other.timingScale
        )
    }
}

protocol SelahModifierChain {
    func transform(for state: SelahModifierState) -> SelahModifierTransform
}

protocol SelahAudioRendering {
    func playOneShot(_ asset: SelahSoundAssetDescriptor, transform: SelahModifierTransform, context: SelahAudioSessionContext)
    func startLoop(_ bed: SelahAmbientBedDescriptor, transform: SelahModifierTransform)
    func stopLoop(id: SelahAmbientBed, fadeOut: TimeInterval)
    func suspend()
}

protocol SelahHapticRendering {
    var supportsHaptics: Bool { get }
    func play(_ pattern: SelahHapticPatternID, transform: SelahModifierTransform)
}

@MainActor
protocol SelahSensoryLayering {
    func play(_ event: SelahSensoryEvent, state: SelahModifierState)
    func startAmbientBed(_ bed: SelahAmbientBed, state: SelahModifierState)
    func stopAmbientBed(_ bed: SelahAmbientBed)
    func suspend()
}

protocol SelahVerseAudioAnchorStore {
    func anchorToneID(for verseRef: String, userID: String) async throws -> String?
    func setAnchorToneID(_ toneID: String, for verseRef: String, userID: String) async throws
}

struct SelahVerseAudioAnchor: Codable, Equatable, Identifiable {
    var id: String { "\(userID):\(verseRef)" }
    let userID: String
    let verseRef: String
    let anchorToneID: String
    let updatedAt: Date
}

enum SelahSensoryRegistry {
    static let eventDescriptors: [SelahSensoryEvent: SelahSensoryEventDescriptor] = {
        Dictionary(uniqueKeysWithValues: SelahSensoryEvent.allCases.map { ($0, descriptor(for: $0)) })
    }()

    static let ambientBedDescriptors: [SelahAmbientBed: SelahAmbientBedDescriptor] = {
        Dictionary(uniqueKeysWithValues: SelahAmbientBed.allCases.map { ($0, descriptor(for: $0)) })
    }()

    static func descriptor(for event: SelahSensoryEvent) -> SelahSensoryEventDescriptor {
        switch event {
        case .openBible:
            return makeEvent(
                event,
                purpose: "Subconscious threshold into Scripture reading.",
                assetID: "selah_event_open_bible",
                fileName: "selah_event_open_bible",
                character: "Very subtle real Bible opening.",
                haptic: .softTap
            )
        case .pageTurnPsalms:
            return makeEvent(
                event,
                purpose: "Whisper-soft page movement for poetic reading.",
                assetID: "selah_event_page_turn_psalms",
                fileName: "selah_event_page_turn_psalms",
                character: "Thin page, soft air, low transient.",
                haptic: .lightImpact
            )
        case .pageTurnOldTestament:
            return makeEvent(
                event,
                purpose: "Heavier tactile page movement for Old Testament reading.",
                assetID: "selah_event_page_turn_ot",
                fileName: "selah_event_page_turn_ot",
                character: "Heavier parchment, restrained body.",
                haptic: .lightImpact
            )
        case .pageTurnNewTestament:
            return makeEvent(
                event,
                purpose: "Soft modern paper movement for New Testament reading.",
                assetID: "selah_event_page_turn_nt",
                fileName: "selah_event_page_turn_nt",
                character: "Modern Bible paper, close and quiet.",
                haptic: .lightImpact
            )
        case .chapterJump:
            return makeEvent(
                event,
                purpose: "Long navigation through Scripture without gamified flourish.",
                assetID: "selah_event_chapter_jump",
                fileName: "selah_event_chapter_jump",
                character: "Multi-page riffle scaled by distance.",
                haptic: .layeredLightImpacts
            )
        case .verseHighlight:
            return makeEvent(
                event,
                purpose: "Marking Scripture as memory and attention.",
                assetID: "selah_event_verse_highlight",
                fileName: "selah_event_verse_highlight",
                character: "Soft ink writing on Bible paper.",
                haptic: .microPulse
            )
        case .bookmarkVerse:
            return makeEvent(
                event,
                purpose: "Associating saved Scripture with a physical journal gesture.",
                assetID: "selah_event_bookmark_verse",
                fileName: "selah_event_bookmark_verse",
                character: "Small leather journal close.",
                haptic: .softTap
            )
        case .prayerStart:
            return makeEvent(
                event,
                purpose: "Crossing into prayer without human imitation.",
                assetID: "selah_event_prayer_start",
                fileName: "selah_event_prayer_start",
                character: "Soft non-human inhale, airy and abstract.",
                haptic: .gentlePulse
            )
        case .prayerEnd:
            return makeEvent(
                event,
                purpose: "Emotional release and closure.",
                assetID: "selah_event_prayer_end",
                fileName: "selah_event_prayer_end",
                character: "Gentle non-human exhale.",
                haptic: .releasePulse
            )
        case .prayerJournalSave:
            return makeEvent(
                event,
                purpose: "Completing a sentence in a private journal.",
                assetID: "selah_event_prayer_journal_save",
                fileName: "selah_event_prayer_journal_save",
                character: "Pen finish and tiny notebook close.",
                haptic: .softTap
            )
        case .selahStart:
            return makeEvent(
                event,
                purpose: "The Signature Selah threshold into stillness.",
                assetID: "selah_event_selah_start",
                fileName: "selah_event_selah_start",
                character: "Ambient fade-in and real Bible opening.",
                haptic: .longSoftVibration,
                context: .immersive
            )
        case .selahComplete:
            return makeEvent(
                event,
                purpose: "Completion without alarm or pressure.",
                assetID: "selah_event_selah_complete",
                fileName: "selah_event_selah_complete",
                character: "Soft bell, wooden chime, or single piano note.",
                haptic: .gentlePulse,
                context: .immersive
            )
        }
    }

    static func descriptor(for bed: SelahAmbientBed) -> SelahAmbientBedDescriptor {
        let purpose: String
        let gain: Double
        let spatial: Bool

        switch bed {
        case .selahRoomTone:
            purpose = "Distant room tone, subtle air, and near-imperceptible chapel ambience."
            gain = -26
            spatial = false
        case .ancientJerusalemCourtyard:
            purpose = "Historically inspired courtyard bed for Scripture and study."
            gain = -24
            spatial = true
        case .desertWilderness:
            purpose = "Sparse wind and open air for wilderness passages."
            gain = -25
            spatial = true
        case .upperRoom:
            purpose = "Close, warm room tone for prayer and Gospel study."
            gain = -26
            spatial = true
        case .galileeShoreline:
            purpose = "Quiet shoreline movement for Gospel reading."
            gain = -25
            spatial = true
        case .monasteryLibrary:
            purpose = "Still library air for focused study."
            gain = -27
            spatial = true
        case .quietChapel:
            purpose = "Soft chapel ambience for prayer and reflection."
            gain = -27
            spatial = true
        case .forestPrayerWalk:
            purpose = "Subtle outdoor prayer walk environment."
            gain = -25
            spatial = true
        case .psalmsQuietRoom:
            purpose = "Quiet room bed for Psalms."
            gain = -28
            spatial = false
        case .revelationCinematicSpace:
            purpose = "Restrained spacious bed for apocalyptic readings."
            gain = -29
            spatial = true
        case .sermonMountOutdoor:
            purpose = "Open hillside air for Sermon on the Mount passages."
            gain = -26
            spatial = true
        }

        return SelahAmbientBedDescriptor(
            id: bed,
            purpose: purpose,
            sound: SelahSoundAssetDescriptor(
                id: "selah_bed_\(bed.rawValue)",
                purpose: purpose,
                layer: .ambientBed,
                fileName: "selah_bed_\(bed.rawValue)",
                fileExtension: "caf",
                playbackMode: .seamlessLoop(loopStart: 0, loopEnd: 60),
                targetLUFS: -30,
                truePeakCeilingDBTP: -6,
                duckingGainDB: -8,
                crossfadeDuration: 3,
                sourceLicense: "Commissioned, AMEN-owned, no third-party sample library without written clearance."
            ),
            defaultGainDB: gain,
            allowsSpatialization: spatial,
            formationGuardrail: "Ambient beds must make space for stillness; density never increases to retain attention."
        )
    }

    private static func makeEvent(
        _ id: SelahSensoryEvent,
        purpose: String,
        assetID: String,
        fileName: String,
        character: String,
        haptic: SelahHapticPatternID,
        context: SelahAudioSessionContext = .incidental
    ) -> SelahSensoryEventDescriptor {
        SelahSensoryEventDescriptor(
            id: id,
            purpose: purpose,
            sound: SelahSoundAssetDescriptor(
                id: assetID,
                purpose: character,
                layer: .sensoryEvent,
                fileName: fileName,
                fileExtension: "caf",
                playbackMode: .oneShot,
                targetLUFS: -24,
                truePeakCeilingDBTP: -8,
                duckingGainDB: -6,
                crossfadeDuration: 0.12,
                sourceLicense: "Commissioned, AMEN-owned, no third-party sample library without written clearance."
            ),
            haptic: haptic,
            sessionContext: context,
            formationGuardrail: "Sound is paired with haptic, may degrade to haptic-only or silence, and is never used as reward feedback."
        )
    }
}

struct SelahDefaultModifierChain: SelahModifierChain {
    func transform(for state: SelahModifierState) -> SelahModifierTransform {
        var transform = SelahModifierTransform.neutral

        switch state.timeOfDay {
        case .morning:
            transform = transform.combined(with: SelahModifierTransform(gainDB: 0.5, lowPassHz: nil, density: 1, timingScale: 1))
        case .evening:
            transform = transform.combined(with: SelahModifierTransform(gainDB: -1, lowPassHz: 7_500, density: 0.9, timingScale: 1.05))
        case .lateNight:
            transform = transform.combined(with: SelahModifierTransform(gainDB: -4, lowPassHz: 4_800, density: 0.65, timingScale: 1.15))
        case .neutral:
            break
        }

        if state.sabbathMode {
            transform = transform.combined(with: SelahModifierTransform(gainDB: -2, lowPassHz: 6_200, density: 0.75, timingScale: 1.2))
        }

        if state.reflectionIdleDuration >= 300 {
            transform = transform.combined(with: SelahModifierTransform(gainDB: -5, lowPassHz: 5_200, density: 0.45, timingScale: 1.3))
        }

        if state.audioSensitivityReduced {
            transform = transform.combined(with: SelahModifierTransform(gainDB: -6, lowPassHz: 4_500, density: 0.5, timingScale: 1.2))
        }

        if state.reduceMotion {
            transform = transform.combined(with: SelahModifierTransform(gainDB: -1, lowPassHz: nil, density: 0.85, timingScale: 1.1))
        }

        return transform
    }
}

@MainActor
final class SelahSensoryLayer: SelahSensoryLayering {
    static let shared = SelahSensoryLayer(
        isEnabled: { AMENFeatureFlags.shared.selahSensoryLayerEnabled }
    )

    private let audioRenderer: SelahAudioRendering
    private let hapticRenderer: SelahHapticRendering
    private let modifierChain: SelahModifierChain
    private let isEnabled: () -> Bool

    init(
        audioRenderer: SelahAudioRendering? = nil,
        hapticRenderer: SelahHapticRendering? = nil,
        modifierChain: SelahModifierChain? = nil,
        isEnabled: @escaping () -> Bool = { false }
    ) {
        self.audioRenderer = audioRenderer ?? SelahAudioEngineRenderer()
        self.hapticRenderer = hapticRenderer ?? SelahHapticRenderer()
        self.modifierChain = modifierChain ?? SelahDefaultModifierChain()
        self.isEnabled = isEnabled
    }

    func play(_ event: SelahSensoryEvent, state: SelahModifierState) {
        guard isEnabled(), let descriptor = SelahSensoryRegistry.eventDescriptors[event] else { return }

        let transform = modifierChain.transform(for: state)
        hapticRenderer.play(descriptor.haptic, transform: transform)
        audioRenderer.playOneShot(descriptor.sound, transform: transform, context: descriptor.sessionContext)
    }

    func startAmbientBed(_ bed: SelahAmbientBed, state: SelahModifierState) {
        guard isEnabled(), let descriptor = SelahSensoryRegistry.ambientBedDescriptors[bed] else { return }
        audioRenderer.startLoop(descriptor, transform: modifierChain.transform(for: state))
    }

    func stopAmbientBed(_ bed: SelahAmbientBed) {
        audioRenderer.stopLoop(id: bed, fadeOut: 3)
    }

    func suspend() {
        audioRenderer.suspend()
    }
}

final class SelahAudioEngineRenderer: SelahAudioRendering {
    private let engine = AVAudioEngine()
    private var playerNodes: [String: AVAudioPlayerNode] = [:]

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionChange),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func playOneShot(_ asset: SelahSoundAssetDescriptor, transform: SelahModifierTransform, context: SelahAudioSessionContext) {
        guard let file = audioFile(for: asset) else { return }
        configureSession(context)
        startEngineIfNeeded()

        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
        node.volume = volume(for: asset, transform: transform)
        node.scheduleFile(file, at: nil) { [weak self, weak node] in
            guard let self, let node else { return }
            self.engine.detach(node)
        }
        node.play()
    }

    func startLoop(_ bed: SelahAmbientBedDescriptor, transform: SelahModifierTransform) {
        guard let file = audioFile(for: bed.sound) else { return }
        configureSession(.immersive)
        startEngineIfNeeded()

        let node = playerNodes[bed.sound.id] ?? AVAudioPlayerNode()
        if playerNodes[bed.sound.id] == nil {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
            playerNodes[bed.sound.id] = node
        }
        node.volume = volume(for: bed.sound, transform: transform)
        node.scheduleFile(file, at: nil, completionHandler: nil)
        if !node.isPlaying {
            node.play()
        }
    }

    func stopLoop(id: SelahAmbientBed, fadeOut: TimeInterval) {
        guard let descriptor = SelahSensoryRegistry.ambientBedDescriptors[id],
              let node = playerNodes[descriptor.sound.id] else { return }
        node.stop()
        engine.detach(node)
        playerNodes[descriptor.sound.id] = nil
    }

    func suspend() {
        playerNodes.values.forEach { $0.stop() }
        playerNodes.removeAll()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func configureSession(_ context: SelahAudioSessionContext) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(context.category, mode: .default, options: context.options)
            try session.setActive(true, options: [])
        } catch {
            return
        }
    }

    private func startEngineIfNeeded() {
        guard !engine.isRunning else { return }
        engine.prepare()
        try? engine.start()
    }

    private func audioFile(for asset: SelahSoundAssetDescriptor) -> AVAudioFile? {
        guard let url = Bundle.main.url(forResource: asset.fileName, withExtension: asset.fileExtension) else {
            return nil
        }
        return try? AVAudioFile(forReading: url)
    }

    private func volume(for asset: SelahSoundAssetDescriptor, transform: SelahModifierTransform) -> Float {
        let adjustedLUFS = asset.targetLUFS + transform.gainDB
        let scalar = pow(10, adjustedLUFS / 20)
        return Float(min(max(scalar, 0), 1))
    }

    @objc private func handleAudioSessionChange() {
        suspend()
    }
}

final class SelahHapticRenderer: SelahHapticRendering {
    private let userDefaults: UserDefaults
    private var engine: CHHapticEngine?

    var supportsHaptics: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func play(_ pattern: SelahHapticPatternID, transform: SelahModifierTransform) {
        guard supportsHaptics, userDefaults.object(forKey: "hapticsEnabled") as? Bool ?? true else { return }

        switch pattern {
        case .softTap:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.55)
        case .lightImpact:
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.45)
        case .microPulse:
            UISelectionFeedbackGenerator().selectionChanged()
        case .layeredLightImpacts, .gentlePulse, .releasePulse, .longSoftVibration:
            playCoreHaptic(pattern, transform: transform)
        }
    }

    private func playCoreHaptic(_ pattern: SelahHapticPatternID, transform: SelahModifierTransform) {
        do {
            if engine == nil {
                engine = try CHHapticEngine()
            }
            try engine?.start()
            let hapticPattern = try CHHapticPattern(events: events(for: pattern, transform: transform), parameters: [])
            let player = try engine?.makePlayer(with: hapticPattern)
            try player?.start(atTime: 0)
        } catch {
            return
        }
    }

    private func events(for pattern: SelahHapticPatternID, transform: SelahModifierTransform) -> [CHHapticEvent] {
        let timing = max(transform.timingScale, 0.6)

        switch pattern {
        case .layeredLightImpacts:
            return [0, 0.06, 0.13, 0.21].map {
                transient(intensity: 0.28, sharpness: 0.2, time: $0 * timing)
            }
        case .gentlePulse:
            return [
                continuous(intensity: 0.22, sharpness: 0.08, time: 0, duration: 0.45 * timing)
            ]
        case .releasePulse:
            return [
                continuous(intensity: 0.18, sharpness: 0.05, time: 0, duration: 0.6 * timing),
                transient(intensity: 0.1, sharpness: 0.04, time: 0.62 * timing)
            ]
        case .longSoftVibration:
            return [
                continuous(intensity: 0.16, sharpness: 0.02, time: 0, duration: 1.4 * timing)
            ]
        case .softTap, .lightImpact, .microPulse:
            return []
        }
    }

    private func transient(intensity: Float, sharpness: Float, time: TimeInterval) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: time
        )
    }

    private func continuous(intensity: Float, sharpness: Float, time: TimeInterval, duration: TimeInterval) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: time,
            duration: duration
        )
    }
}
