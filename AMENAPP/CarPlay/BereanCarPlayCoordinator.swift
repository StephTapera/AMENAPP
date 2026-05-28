// BereanCarPlayCoordinator.swift
// AMEN — Berean Drive CarPlay
//
// Main coordinator for the Berean Drive CarPlay session.
// Owned by AmenCarPlaySceneDelegate — created on connect, destroyed on disconnect.
// Wires together all services and responds to user actions from templates.
//
// Owns:
//   - BereanCarPlayRouter      (template navigation)
//   - BereanCarPlayTemplates   (template factory)
//   - BereanDriveSessionService (backend + session)
//   - BereanDriveAudioService   (TTS + audio session)
//   - BereanDriveVoiceService   (STT + command routing)
//   - BereanCarPlaySafetyGate   (content moderation)
//   - BereanCarPlayAnalytics    (analytics)
//
// All methods run on @MainActor — CarPlay callbacks arrive on main thread.

import CarPlay
import UIKit
import CoreLocation
import Speech
import FirebaseAuth

@MainActor
final class BereanCarPlayCoordinator: NSObject, ObservableObject {

    // MARK: - Services (all retained for session lifetime)

    let templateFactory: BereanCarPlayTemplates
    let router: BereanCarPlayRouter
    let session: BereanDriveSessionService
    let audio: BereanDriveAudioService
    let voice: BereanDriveVoiceService
    let safety: BereanCarPlaySafetyGate
    let analytics: BereanCarPlayAnalytics

    private var preferences: BereanDrivePreferences
    private var locationManager: CLLocationManager?
    private var currentLocation: CLLocation?

    // MARK: - Init

    init(interfaceController: CPInterfaceController) {
        let factory = BereanCarPlayTemplates(coordinator: nil)
        let router = BereanCarPlayRouter(interfaceController: interfaceController, templates: factory)
        self.templateFactory = factory
        self.router = router
        self.session = BereanDriveSessionService.shared
        self.audio = BereanDriveAudioService.shared
        self.voice = BereanDriveVoiceService.shared
        self.safety = BereanCarPlaySafetyGate.shared
        self.analytics = BereanCarPlayAnalytics.shared
        self.preferences = BereanDrivePreferences.load()
        super.init()
        factory.coordinator = self
    }

    // MARK: - Session Lifecycle

    func start() {
        audio.activateAudioSession()
        audio.configureRemoteCommands(
            onPlay: { [weak self] in self?.resumeAudio() },
            onPause: { [weak self] in self?.audio.pauseSpeaking() },
            onSkipForward: { [weak self] in self?.skipCurrentContent() }
        )
        router.setHomeRoot()
        Task {
            await session.startSession(mode: .home)
            analytics.track(.sessionStarted)
        }
        requestLocationIfNeeded()
        dlog("🚗 [BereanDrive] Session started")
    }

    func end() {
        audio.stopSpeaking()
        audio.disableRemoteCommands()
        audio.deactivateAudioSession()
        voice.stopListening()
        session.endSession()
        analytics.track(.sessionEnded)
        dlog("🚗 [BereanDrive] Session ended")
    }

    // MARK: - Mode Selection (from home template taps)

    func didSelectMode(_ mode: BereanDriveMode) {
        analytics.track(.modeSelected(mode: mode.rawValue))
        audio.updateNowPlayingInfo(title: mode.displayTitle, subtitle: "Berean Drive", mode: mode)

        switch mode {
        case .home:
            router.popToHome()
        case .prayerRide:
            router.showPrayerModes()
        case .bereanVoice:
            router.showBereanVoice()
        case .scriptureReflect:
            startScriptureReflection()
        case .sermonAudio:
            startSermonAudio()
        case .churchNoteRecap:
            startChurchNotesRecap()
        case .findChurch:
            startChurchSearch()
        case .messageGroup:
            showGroupMessages()
        }
    }

    // MARK: - Prayer Ride

    func didSelectPrayerMode(_ mode: BereanPrayerMode) {
        analytics.track(.prayerStarted(mode: mode.rawValue))
        Task {
            let response = await session.startPrayerSession(mode: mode, preferences: preferences)
            handleDriveResponse(response, mode: .prayerRide)
        }
    }

    // MARK: - Berean Voice

    func didTapBereanVoiceButton() {
        guard voice.authorizationStatus == .authorized else {
            Task { await voice.requestAuthorization() }
            return
        }
        router.refreshBereanVoice(isListening: true)
        voice.startListening { [weak self] command in
            Task { @MainActor in
                self?.handleVoiceCommand(command)
                self?.router.refreshBereanVoice(isListening: false)
            }
        }
    }

    private func handleVoiceCommand(_ command: BereanDriveVoiceCommand) {
        switch command {
        case .askBerean(let question):
            analytics.track(.bereanVoiceQuery(commandType: "ask_berean"))
            Task {
                let response = await session.askBerean(question: question, preferences: preferences)
                handleDriveResponse(response, mode: .bereanVoice)
            }

        case .prayWithMe:
            analytics.track(.bereanVoiceQuery(commandType: "pray_with_me"))
            router.pop()
            router.showPrayerModes()

        case .summarizeChurchNotes:
            analytics.track(.bereanVoiceQuery(commandType: "church_notes"))
            startChurchNotesRecap()

        case .continueSession:
            analytics.track(.bereanVoiceQuery(commandType: "continue_session"))
            didTapContinueSession()

        case .findChurch:
            analytics.track(.bereanVoiceQuery(commandType: "find_church"))
            router.pop()
            startChurchSearch()

        case .dictatedReply(let text):
            // Relay the transcribed text to the active messaging view via notification bridge.
            analytics.track(.bereanVoiceQuery(commandType: "dictated_reply"))
            NotificationCenter.default.post(
                name: .bereanDriveDictatedReplyReady,
                object: nil,
                userInfo: ["replyText": text]
            )

        case .unknown:
            let fallback = BereanDriveResponse(
                spokenText: "I didn't catch that. You can ask me to explain scripture, lead a prayer, or find a nearby church.",
                displayTitle: "Try Again",
                displaySubtitle: "Ask Berean a question by voice",
                safetyState: .safe,
                handoffRequired: false,
                handoffReason: nil,
                sourceRefs: [],
                actionButtons: [],
                audioDurationEstimateSeconds: nil
            )
            handleDriveResponse(fallback, mode: .bereanVoice)
        }
    }

    // MARK: - Continue Session

    func didTapContinueSession() {
        Task {
            let question = "Continue from where we left off. Give me a brief summary and one follow-up insight."
            let response = await session.askBerean(question: question, preferences: preferences)
            handleDriveResponse(response, mode: .bereanVoice)
        }
    }

    // MARK: - Church Notes Recap

    func didTapChurchNotesRecap() { startChurchNotesRecap() }

    private func startChurchNotesRecap() {
        Task {
            let question = "Summarize my most recent church notes. Give me the key scripture, main theme, and one action item."
            let response = await session.askBerean(question: question, preferences: preferences)
            handleDriveResponse(response, mode: .churchNoteRecap)
        }
    }

    // MARK: - Scripture Reflection

    private func startScriptureReflection() {
        Task {
            let question = "Give me a short scripture reflection for my drive today. Use \(preferences.preferredScriptureTranslation). Keep it under 30 seconds."
            let response = await session.askBerean(question: question, preferences: preferences)
            handleDriveResponse(response, mode: .scriptureReflect)
        }
    }

    // MARK: - Sermon Audio

    private func startSermonAudio() {
        // Sermon audio handoff: visual media browsing not appropriate for CarPlay.
        // Direct user to iPhone to pick a sermon; then audio continues over CarPlay.
        router.presentHandoffAlert(reason: "sermon_selection") { [weak self] in
            self?.analytics.track(.handoffToPhone(reason: "sermon_selection"))
            self?.router.dismissModal()
        }
    }

    // MARK: - Church Search

    private func startChurchSearch() {
        router.showChurchSearchLoading()
        guard let location = currentLocation else {
            // No location yet — request it and show empty state
            requestLocationIfNeeded()
            router.showChurchList([])
            return
        }
        Task {
            let results = await session.searchNearbyChurches(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                preferences: preferences
            )
            router.showChurchList(results)
        }
    }

    func didSelectChurch(_ church: BereanDriveChurchResult) {
        router.showChurchDetail(church)
        // Speak service time if available
        if let time = church.nextServiceTime {
            audio.speak("Next service at \(church.name) is \(time).")
        }
    }

    func didTapNavigateToChurch(_ church: BereanDriveChurchResult) {
        guard let lat = church.latitude, let lon = church.longitude else { return }
        analytics.track(.churchNavigationStarted)
        // HandOff navigation to Apple Maps — no navigation entitlement required
        let url = URL(string: "maps://?daddr=\(lat),\(lon)&dirflg=d")!
        UIApplication.shared.open(url)
        dlog("🗺️ [BereanDrive] Navigation handoff to Maps: \(church.name)")
    }

    func didTapCallChurch(_ phone: String) {
        let cleaned = phone.filter { $0.isNumber }
        guard !cleaned.isEmpty, let url = URL(string: "tel://\(cleaned)") else { return }
        UIApplication.shared.open(url)
    }

    func didTapSaveChurch(_ church: BereanDriveChurchResult) {
        audio.speak("\(church.name) has been saved. You can find it in your Amen app.")
        // Persist via Firestore — fire-and-forget
        Task {
            // Bridge to the existing church save flow in the main app
            NotificationCenter.default.post(
                name: .bereanDriveSaveChurch,
                object: nil,
                userInfo: ["amenSpaceId": church.amenSpaceId ?? "", "churchName": church.name]
            )
        }
    }

    // MARK: - Group Messages

    private func showGroupMessages() {
        guard preferences.messageReadAloudEnabled else {
            let blocked = BereanDriveResponse(
                spokenText: "Message read-aloud is turned off. Enable it in Berean Drive settings.",
                displayTitle: "Messages Off",
                displaySubtitle: "Enable in Settings",
                safetyState: .safe,
                handoffRequired: false, handoffReason: nil,
                sourceRefs: [], actionButtons: [],
                audioDurationEstimateSeconds: nil
            )
            handleDriveResponse(blocked, mode: .messageGroup)
            return
        }
        // In a full implementation, messages would be fetched from Firestore and
        // screened through BereanDriveSessionService.reviewMessageSafety before
        // being passed here. For now, route to iPhone for message reading.
        router.presentHandoffAlert(reason: "message_reading") { [weak self] in
            self?.analytics.track(.handoffToPhone(reason: "message_reading"))
            self?.router.dismissModal()
        }
    }

    func didSelectMessage(_ message: BereanDriveMessagePreview) {
        guard message.safetyState != .blocked else {
            analytics.track(.safetyBlockTriggered(category: "message_blocked"))
            router.presentSafetyAlert { [weak self] in self?.router.dismissModal() }
            return
        }
        let text = "Message from \(message.senderName): \(message.previewText)"
        audio.speak(text)
    }

    func didTapDictateReply(for message: BereanDriveMessagePreview) {
        router.refreshMessageReplyOptions(for: message, isListening: true)
        voice.startListening { [weak self] command in
            Task { @MainActor in
                guard let self else { return }
                self.router.refreshMessageReplyOptions(for: message, isListening: false)
                // Post dictated reply to main app messaging layer via notification bridge
                NotificationCenter.default.post(
                    name: .bereanDriveDictatedReplyReady,
                    object: nil,
                    userInfo: [
                        "conversationId": message.conversationId,
                        "command": "\(command)"
                    ]
                )
            }
        }
    }

    // MARK: - Drive Response Handler

    /// Central handler — speaks the response, updates now-playing, handles handoffs.
    func handleDriveResponse(_ response: BereanDriveResponse, mode: BereanDriveMode) {
        if response.safetyState == .blocked {
            analytics.track(.safetyBlockTriggered(category: "response_blocked"))
            audio.speak(response.spokenText)
            return
        }

        if response.handoffRequired {
            router.presentHandoffAlert(reason: response.handoffReason ?? "detail") { [weak self] in
                self?.analytics.track(.handoffToPhone(reason: response.handoffReason ?? "detail"))
                self?.router.dismissModal()
            }
            return
        }

        audio.updateNowPlayingInfo(title: response.displayTitle, subtitle: response.displaySubtitle ?? "", mode: mode)
        audio.speak(response.spokenText)
    }

    // MARK: - Audio Controls

    private func resumeAudio() {
        audio.resumeSpeaking()
    }

    private func skipCurrentContent() {
        audio.stopSpeaking()
    }

    // MARK: - Location

    private func requestLocationIfNeeded() {
        guard preferences.drivingContextEnabled && preferences.locationPersonalizationEnabled else { return }
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager?.requestWhenInUseAuthorization()
        locationManager?.startUpdatingLocation()
    }
}

// MARK: - CLLocationManagerDelegate

extension BereanCarPlayCoordinator: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = location
            self.locationManager?.stopUpdatingLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        dlog("⚠️ [BereanDrive] Location error: \(error.localizedDescription)")
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let bereanDriveSaveChurch = Notification.Name("bereanDriveSaveChurch")
    static let bereanDriveHandoffToPhone = Notification.Name("bereanDriveHandoffToPhone")
    static let bereanDriveResumeInCarPlay = Notification.Name("bereanDriveResumeInCarPlay")
    static let bereanDriveDictatedReplyReady = Notification.Name("bereanDriveDictatedReplyReady")
}
