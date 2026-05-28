// BereanCarPlayRouter.swift
// AMEN — Berean Drive CarPlay
//
// Manages the CPInterfaceController template navigation stack.
// Single responsibility: push/pop/present templates in response to mode changes.
// The coordinator owns this router and calls it after every state change.
//
// Navigation rules:
//   - Home is always the root (never popped off)
//   - Mode templates are pushed on top of home
//   - Detail templates (church detail, message detail) are pushed on top of mode
//   - Alerts are presented modally
//   - Max stack depth: 5 (Apple guideline)
//   - Always pop back to home on session end

import CarPlay
import UIKit

@MainActor
final class BereanCarPlayRouter {

    private weak var interfaceController: CPInterfaceController?
    private let templates: BereanCarPlayTemplates

    // Track which template is at the root so we can always reset to it
    private var rootTemplate: CPTemplate?

    init(interfaceController: CPInterfaceController, templates: BereanCarPlayTemplates) {
        self.interfaceController = interfaceController
        self.templates = templates
    }

    // MARK: - Root

    func setHomeRoot() {
        let home = templates.makeHomeTemplate()
        rootTemplate = home
        interfaceController?.setRootTemplate(home, animated: false, completion: nil)
    }

    func popToHome(animated: Bool = true) {
        guard let root = rootTemplate else { return }
        interfaceController?.popToRootTemplate(animated: animated, completion: nil)
        _ = root   // root stays on the stack — popToRoot is sufficient
    }

    // MARK: - Mode Navigation

    func push(_ template: CPTemplate, animated: Bool = true) {
        interfaceController?.pushTemplate(template, animated: animated, completion: nil)
    }

    func pop(animated: Bool = true) {
        interfaceController?.popTemplate(animated: animated, completion: nil)
    }

    // MARK: - Mode-Specific Pushes

    func showPrayerModes() {
        push(templates.makePrayerModeTemplate())
    }

    func showBereanVoice(isListening: Bool = false) {
        push(templates.makeBereanVoiceTemplate(isListening: isListening))
    }

    func refreshBereanVoice(isListening: Bool) {
        // Swap top-of-stack: pop current, push refreshed version so the stack stays clean
        let fresh = templates.makeBereanVoiceTemplate(isListening: isListening)
        interfaceController?.popTemplate(animated: false) { [weak self] _, _ in
            self?.interfaceController?.pushTemplate(fresh, animated: false, completion: nil)
        }
    }

    func showChurchSearchLoading() {
        push(templates.makeChurchSearchLoadingTemplate())
    }

    func showChurchList(_ churches: [BereanDriveChurchResult]) {
        let template = templates.makeChurchListTemplate(churches: churches)
        // Pop the loading screen, then push results so Back goes straight to Home
        interfaceController?.popTemplate(animated: false) { [weak self] _, _ in
            self?.interfaceController?.pushTemplate(template, animated: true, completion: nil)
        }
    }

    func showChurchDetail(_ church: BereanDriveChurchResult) {
        push(templates.makeChurchDetailTemplate(church: church))
    }

    func showMessageList(_ messages: [BereanDriveMessagePreview]) {
        push(templates.makeMessageListTemplate(messages: messages))
    }

    func showMessageReplyOptions(for message: BereanDriveMessagePreview) {
        push(templates.makeMessageReplyTemplate(message: message))
    }

    func refreshMessageReplyOptions(for message: BereanDriveMessagePreview, isListening: Bool) {
        let fresh = templates.makeMessageReplyTemplate(message: message, isListening: isListening)
        interfaceController?.popTemplate(animated: false) { [weak self] _, _ in
            self?.interfaceController?.pushTemplate(fresh, animated: false, completion: nil)
        }
    }

    func showNowPlaying(
        mode: BereanDriveMode,
        onPause: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) {
        templates.configureNowPlayingTemplate(mode: mode, onPause: onPause, onSkip: onSkip)
        push(CPNowPlayingTemplate.shared)
    }

    // MARK: - Modal Alerts

    func presentSafetyAlert(
        message: String = BereanCarPlaySafetyGate.calmDefaultMessage,
        onDismiss: @escaping () -> Void
    ) {
        let alert = templates.makeSafetyAlertTemplate(message: message, onDismiss: onDismiss)
        interfaceController?.presentTemplate(alert, animated: true, completion: nil)
    }

    func presentHandoffAlert(reason: String, onDismiss: @escaping () -> Void) {
        let alert = templates.makeHandoffAlertTemplate(reason: reason, onDismiss: onDismiss)
        interfaceController?.presentTemplate(alert, animated: true, completion: nil)
    }

    func dismissModal(animated: Bool = true) {
        interfaceController?.dismissTemplate(animated: animated, completion: nil)
    }
}
