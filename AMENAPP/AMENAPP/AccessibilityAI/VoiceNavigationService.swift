// VoiceNavigationService.swift
// AMENAPP — Accessibility Intelligence Layer

import UIKit
import FirebaseFunctions

@MainActor
final class VoiceNavigationService: ObservableObject {

    static let shared = VoiceNavigationService()

    @Published private(set) var isActive: Bool = false
    @Published private(set) var currentNarration: String = ""
    @Published private(set) var suggestions: [String] = []
    @Published private(set) var isProcessing: Bool = false

    private var currentContext: String = ""

    private let functions = Functions.functions()

    private init() {}

    func activate() {
        isActive = true
        UIAccessibility.post(notification: .announcement, argument: "Voice navigation active")
    }

    func deactivate() {
        isActive = false
        currentNarration = ""
        suggestions = []
        isProcessing = false
        currentContext = ""
    }

    func updateContext(_ context: String) {
        currentContext = context
        if isActive {
            fetchContextualHelp()
        }
    }

    func askQuestion(_ query: String) async {
        guard AMENFeatureFlags.shared.voiceIntelligenceEnabled else { return }
        isProcessing = true
        defer { isProcessing = false }

        let payload: [String: Any] = [
            "screenContext": currentContext,
            "userQuery": query
        ]

        do {
            let result = try await functions.httpsCallable("a11yContextProxy").safeCall(payload)
            guard let data = result.data as? [String: Any] else { return }
            let answer = data["answer"] as? String ?? ""
            let rawSuggestions = data["suggestions"] as? [String] ?? []
            currentNarration = answer
            suggestions = rawSuggestions
        } catch {
            dlog("[VoiceNavigation] askQuestion error: \(error)")
        }
    }

    private func fetchContextualHelp() {
        Task {
            guard AMENFeatureFlags.shared.voiceIntelligenceEnabled else { return }
            isProcessing = true
            defer { isProcessing = false }

            let payload: [String: Any] = [
                "screenContext": currentContext,
                "userQuery": ""
            ]

            do {
                let result = try await functions.httpsCallable("a11yContextProxy").safeCall(payload)
                guard let data = result.data as? [String: Any] else { return }
                let rawSuggestions = data["suggestions"] as? [String] ?? []
                suggestions = rawSuggestions
            } catch {
                dlog("[VoiceNavigation] fetchContextualHelp error: \(error)")
            }
        }
    }
}
