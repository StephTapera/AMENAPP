//
//  SelahScripturePageTurnSoundPlayer.swift
//  AMENAPP
//
//  A subtle, non-intrusive page-turn cue for the Selah Scripture Reader.
//  The cue is OFF by default. When enabled by the user's reader preference,
//  it plays a soft system audio tick on a successful page commit.
//
//  Design contract:
//   * Never auto-plays at view load — only after a confirmed page commit.
//   * Respects the user preference (`pageTurnSoundEnabled`).
//   * Respects `accessibilityReduceMotion` — caller passes the env value.
//   * On iOS, AudioServicesPlaySystemSound naturally yields to the silent
//     switch for the system tick we use (1306, a quiet tock), so no extra
//     ambient/audio-session work is needed.
//

import Foundation
import AudioToolbox

@MainActor
final class SelahScripturePageTurnSoundPlayer {

    static let shared = SelahScripturePageTurnSoundPlayer()

    /// Soft system tock; quieter than the keyboard click. The exact id is an
    /// implementation detail — callers should not depend on it.
    private let systemSoundID: SystemSoundID = 1306

    private init() {}

    /// Play a page-turn cue if the user has it enabled. Safe to call from
    /// the main thread on every page commit; bails out cheaply if disabled.
    func playIfEnabled(
        preferences: SelahScriptureReaderPreferences,
        reduceMotion: Bool = false
    ) {
        guard preferences.pageTurnSoundEnabled, !reduceMotion else { return }
        AudioServicesPlaySystemSound(systemSoundID)
    }
}
