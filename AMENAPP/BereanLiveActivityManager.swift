//
//  BereanLiveActivityManager.swift
//  AMENAPP
//
//  Manages the Berean AI Live Activity / Dynamic Island lifecycle.
//  Wraps ActivityKit behind #if canImport so it degrades safely.
//

import Foundation
import Combine

// MARK: - Manager

// MARK: - ActivityKit support disabled
// ActivityKit Live Activities are only available on physical devices running iOS 16.1+
// This file provides stub implementations for simulator and development builds

#if false  // Disabled until ActivityKit is properly configured in project

#if canImport(ActivityKit)
import ActivityKit
#endif

@available(iOS 16.1, *)
@MainActor
final class BereanLiveActivityManager: ObservableObject {
    static let shared = BereanLiveActivityManager()
    private init() {}

    @Published private(set) var activeActivityID: String?
    private var activity: Activity<BereanDynamicIslandAttributes>?

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // MARK: - Start

    func start(sessionID: String = UUID().uuidString) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Reuse existing activity if one is running
        if activity != nil {
            await update(.listening())
            return
        }

        let attributes = BereanDynamicIslandAttributes(
            sessionID: sessionID,
            sessionName: "Berean Assistant"
        )
        do {
            let newActivity = try Activity<BereanDynamicIslandAttributes>.request(
                attributes: attributes,
                content: .init(state: .listening(), staleDate: nil),
                pushType: nil
            )
            activity = newActivity
            activeActivityID = newActivity.id
            dlog("[BereanLiveActivity] Started: \(newActivity.id)")
        } catch {
            dlog("[BereanLiveActivity] Failed to start: \(error)")
        }
    }

    // MARK: - Update

    func update(_ state: BereanDynamicIslandAttributes.ContentState) async {
        guard let activity else { return }
        await activity.update(.init(state: state, staleDate: nil))
    }

    func setListening() async {
        await update(.listening())
    }

    func setThinking(progress: Double = 0.45) async {
        await update(.thinking(progress: progress))
    }

    func setSpeaking(reference: String? = nil) async {
        await update(.speaking(reference: reference))
    }

    func setVerse(reference: String) async {
        await update(.verse(reference))
    }

    // MARK: - End

    func end(immediately: Bool = false) async {
        guard let activity else { return }
        await activity.end(
            .init(state: .idle(), staleDate: nil),
            dismissalPolicy: immediately ? .immediate : .default
        )
        self.activity = nil
        activeActivityID = nil
        dlog("[BereanLiveActivity] Ended")
    }
}

// MARK: - Bridge (call sites in BereanIslandViewModel and feature code)

@MainActor
final class BereanLiveActivityBridge {
    static let shared = BereanLiveActivityBridge()
    private init() {}

    private let manager = BereanLiveActivityManager.shared

    func handleVoiceSessionStarted() {
        Task {
            await manager.start()
            await manager.setListening()
        }
    }

    func handleTranscriptionFinished() {
        Task { await manager.setThinking(progress: 0.42) }
    }

    func handleModelBeganResponding(scripture: String?) {
        Task { await manager.setSpeaking(reference: scripture) }
    }

    func handleScriptureSurfaced(_ reference: String) {
        Task { await manager.setVerse(reference: reference) }
    }

    func handleSessionEnded() {
        Task { await manager.end() }
    }
}

#else

// MARK: - Fallback stubs (macOS / simulator without ActivityKit)

@MainActor
final class BereanLiveActivityManager: ObservableObject {
    static let shared = BereanLiveActivityManager()
    private init() {}
    var activeActivityID: String? { nil }
    var isSupported: Bool { false }
    func start(sessionID: String = UUID().uuidString) async {}
    func setListening() async {}
    func setThinking(progress: Double = 0.45) async {}
    func setSpeaking(reference: String? = nil) async {}
    func setVerse(reference: String) async {}
    func end(immediately: Bool = false) async {}
}

@MainActor
final class BereanLiveActivityBridge {
    static let shared = BereanLiveActivityBridge()
    private init() {}
    func handleVoiceSessionStarted() {}
    func handleTranscriptionFinished() {}
    func handleModelBeganResponding(scripture: String?) {}
    func handleScriptureSurfaced(_ reference: String) {}
    func handleSessionEnded() {}
}

#endif
