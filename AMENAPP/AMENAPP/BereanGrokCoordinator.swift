import Foundation
import SwiftUI
import FirebaseAnalytics

// MARK: - BereanGrokCoordinator
//
// Owned by BereanChatViewModel. Drives the Grok pipeline state and
// exposes published state for the view layer to observe.
// BereanChatView includes a BereanGrokOverlay that reads this object.

@MainActor
final class BereanGrokCoordinator: ObservableObject {

    // MARK: - Published State

    @Published var composerPills: [BereanComposerPill] = []
    @Published var grokState: BereanGrokState = .idle
    @Published var thinkingStepIndex: Int = 0
    @Published var pendingProvenance: BereanProvenanceRecord? = nil

    // Sheet triggers
    @Published var showLinkSummarySheet = false
    @Published var showExternalContextSheet = false
    @Published var showStudyOutlineSheet = false
    @Published var showSimplifiedPromptPreview = false
    @Published var showProvenanceSheet = false

    // Sheet data
    @Published var pendingLinkURL: String = ""
    @Published var pendingExternalQuery: String = ""
    @Published var pendingOutlineTopic: String = ""
    @Published var pendingSimplified: BereanSimplifiedPrompt? = nil
    @Published var shownProvenanceRecord: BereanProvenanceRecord? = nil

    // Thinking step cycling
    private var thinkingStepTask: Task<Void, Never>?

    // Callback: called when the view should inject text into composer and send
    var onInjectAndSend: ((String) -> Void)?
    // Callback: called to save to church notes
    var onSaveOutlineToNotes: ((BereanStudyOutline) -> Void)?

    // MARK: - Classify Input

    func classifyInput(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            composerPills = []
            return
        }
        let classification = BereanGrokService.shared.classify(text: text)
        composerPills = classification.suggestedPills
        Analytics.logEvent("berean_flow_started", parameters: [
            "intent": classification.intent.rawValue,
            "risk": classification.risk.rawValue,
            "has_link": classification.containsLink
        ])
        if classification.containsLink && !classification.detectedLinks.isEmpty {
            Analytics.logEvent("berean_link_detected", parameters: nil)
        }
        if classification.isLong {
            Analytics.logEvent("berean_long_prompt_detected", parameters: nil)
        }
    }

    // MARK: - Pill Tapped

    func pillTapped(_ pill: BereanComposerPill, currentText: String) {
        switch pill {
        case .simplifyFirst:
            Task { await handleSimplify(text: currentText) }
        case .summarizeLink, .extractThemes:
            let links = extractLinks(from: currentText)
            guard let first = links.first else { return }
            pendingLinkURL = first
            showLinkSummarySheet = true
            Analytics.logEvent("berean_link_detected", parameters: nil)
        case .externalContext:
            pendingExternalQuery = currentText
            showExternalContextSheet = true
            Analytics.logEvent("berean_external_context_started", parameters: nil)
        case .checkScripture:
            onInjectAndSend?("Check the scriptural basis for: \(currentText)")
            Analytics.logEvent("berean_scripture_check_started", parameters: nil)
        case .createStudyOutline:
            pendingOutlineTopic = currentText
            showStudyOutlineSheet = true
            Analytics.logEvent("berean_study_outline_created", parameters: nil)
        }
    }

    // MARK: - Simplify Flow

    private func handleSimplify(text: String) async {
        grokState = .summarizingPrompt
        if let simplified = await BereanGrokService.shared.simplifyPrompt(text) {
            pendingSimplified = simplified
            grokState = .idle
            showSimplifiedPromptPreview = true
        } else {
            grokState = .idle
            // Fallback: just send the original text
            onInjectAndSend?(text)
        }
    }

    // MARK: - Sheet Callbacks

    func onSimplifiedAskBerean() {
        guard let simplified = pendingSimplified else { return }
        onInjectAndSend?(simplified.simplifiedText)
        pendingSimplified = nil
        composerPills = []
    }

    func onSimplifiedEdit() {
        // The text was already in the composer; user can edit manually
        pendingSimplified = nil
    }

    func onSimplifiedCancel() {
        pendingSimplified = nil
    }

    func onLinkBereanCheck(prompt: String) {
        onInjectAndSend?(prompt)
        Analytics.logEvent("berean_scripture_check_completed", parameters: nil)
    }

    func onExternalContextCompare(prompt: String) {
        onInjectAndSend?(prompt)
        Analytics.logEvent("berean_external_context_completed", parameters: nil)
    }

    func onFollowUp(text: String) {
        onInjectAndSend?(text)
    }

    func onOutlineContinueChat(prompt: String) {
        onInjectAndSend?(prompt)
    }

    // MARK: - Thinking Steps

    func startThinkingCycle() {
        thinkingStepIndex = 0
        thinkingStepTask?.cancel()
        thinkingStepTask = Task {
            let steps = BereanThinkingStep.allCases
            for i in 0..<steps.count {
                guard !Task.isCancelled else { return }
                thinkingStepIndex = i
                try? await Task.sleep(nanoseconds: 1_400_000_000)
            }
        }
    }

    func stopThinkingCycle() {
        thinkingStepTask?.cancel()
        thinkingStepTask = nil
    }

    // MARK: - Provenance

    func showProvenance(_ record: BereanProvenanceRecord) {
        shownProvenanceRecord = record
        showProvenanceSheet = true
        Analytics.logEvent("berean_provenance_sheet_opened", parameters: nil)
    }

    func recordForMessage(helperUsed: Bool, externalUsed: Bool, sensitiveDetected: Bool) -> BereanProvenanceRecord {
        BereanGrokService.shared.buildProvenance(
            helperUsed: helperUsed,
            externalContext: externalUsed,
            sensitiveDetected: sensitiveDetected,
            scripturePassed: true
        )
    }

    // MARK: - Provenance flags

    private var helperUsedFlag = false
    private var externalUsedFlag = false

    func markHelperUsed() { helperUsedFlag = true }
    func markExternalUsed() { externalUsedFlag = true }

    /// Consumes and resets both flags, returning their values.
    func consumePendingFlags() -> (helperUsed: Bool, externalUsed: Bool) {
        let h = helperUsedFlag; let e = externalUsedFlag
        helperUsedFlag = false; externalUsedFlag = false
        return (h, e)
    }

    // MARK: - Clear

    func clearPills() {
        composerPills = []
    }

    // MARK: - Helpers

    private func extractLinks(from text: String) -> [String] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.matches(in: text, range: range)
            .compactMap { $0.url?.absoluteString } ?? []
    }
}

// MARK: - BereanGrokOverlay
//
// A self-contained overlay embeddable in BereanChatView.
// Owns the sheet presentations and pill row.
// BereanChatView embeds this as a VStack row above the composer.

struct BereanGrokOverlay: View {
    @ObservedObject var coordinator: BereanGrokCoordinator
    let currentText: String

    @ObservedObject private var flags = AMENFeatureFlags.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if flags.bereanHelperModelEnabled && !coordinator.composerPills.isEmpty {
                BereanComposerActionPillRow(pills: coordinator.composerPills) { pill in
                    coordinator.pillTapped(pill, currentText: currentText)
                }
            }
        }
        // Simplified prompt preview (Flow 2)
        .sheet(isPresented: $coordinator.showSimplifiedPromptPreview) {
            if let simplified = coordinator.pendingSimplified {
                BereanSimplifiedPromptPreview(
                    simplified: simplified,
                    onAskBerean: { coordinator.onSimplifiedAskBerean() },
                    onEdit: { coordinator.onSimplifiedEdit() },
                    onCancel: { coordinator.onSimplifiedCancel() }
                )
            }
        }
        // Link summary (Flow 3)
        .sheet(isPresented: $coordinator.showLinkSummarySheet) {
            BereanLinkSummarySheet(
                url: coordinator.pendingLinkURL,
                onRunBereanCheck: { prompt in coordinator.onLinkBereanCheck(prompt: prompt) },
                onAskFollowUp: { text in coordinator.onFollowUp(text: text) }
            )
        }
        // External context (Flow 4)
        .sheet(isPresented: $coordinator.showExternalContextSheet) {
            BereanExternalContextSheet(
                query: coordinator.pendingExternalQuery,
                onCompareWithScripture: { prompt in coordinator.onExternalContextCompare(prompt: prompt) },
                onAskFollowUp: { text in coordinator.onFollowUp(text: text) }
            )
        }
        // Study outline
        .sheet(isPresented: $coordinator.showStudyOutlineSheet) {
            BereanStudyOutlineSheet(
                topic: coordinator.pendingOutlineTopic,
                onContinueChat: { prompt in coordinator.onOutlineContinueChat(prompt: prompt) },
                onSaveToNotes: { outline in coordinator.onSaveOutlineToNotes?(outline) }
            )
        }
        // Provenance sheet
        .sheet(isPresented: $coordinator.showProvenanceSheet) {
            if let record = coordinator.shownProvenanceRecord {
                BereanProvenanceSheet(provenance: record)
            }
        }
    }
}
