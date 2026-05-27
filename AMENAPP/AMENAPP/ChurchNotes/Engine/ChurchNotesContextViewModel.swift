import Foundation
import SwiftUI

@MainActor
final class ChurchNotesContextViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var contextResult: CNContextResult?
    @Published private(set) var loadState: CNContextLoadState = .idle
    @Published private(set) var recapLoadState: CNContextLoadState = .idle
    @Published private(set) var growthTimelineState: CNContextLoadState = .idle
    @Published private(set) var growthEntries: [CNGrowthEntry] = []
    @Published private(set) var smartRecap: CNSmartRecap?
    @Published private(set) var groupInsight: CNGroupInsight?
    @Published var commandBarResult: CNCommandBarResult?
    @Published var pendingCommandBarText: String = ""
    @Published var isBereanPanelPresented: Bool = false
    @Published var isGrowthTimelinePresented: Bool = false
    @Published var isSmartRecapPresented: Bool = false
    @Published var isCommandBarPresented: Bool = false
    @Published var selectedCommandBarCommand: CNCommandBarCommand?

    private let engine = ChurchNotesContextEngine.shared
    private let service = ChurchNotesContextService()
    private let flags = AMENFeatureFlags.shared

    // MARK: - Context Analysis

    func loadContext(noteId: String, noteText: String, noteHistory: [String] = []) async {
        guard flags.churchNotesContextEngineEnabled else { return }
        loadState = .loading
        let result = engine.analyzeForContext(noteId: noteId, noteText: noteText, noteHistory: noteHistory)
        contextResult = result.isEmpty ? nil : result
        loadState = result.isEmpty ? .empty : .loaded
    }

    func refreshContext(noteId: String, noteText: String, noteHistory: [String] = []) async {
        await loadContext(noteId: noteId, noteText: noteText, noteHistory: noteHistory)
    }

    // MARK: - Smart Recap

    func generateRecap(noteId: String, noteText: String) async {
        guard flags.churchNotesSmartRecapEnabled else { return }
        recapLoadState = .loading
        let themes = engine.detectThemes(in: noteText)
        let scriptures = engine.detectScriptureReferences(in: noteText)
        let recap = engine.generateSmartRecap(for: noteId, from: noteText, themes: themes, scriptures: scriptures)
        smartRecap = recap
        recapLoadState = .loaded

        do {
            try await service.saveRecap(recap)
        } catch {
            // Non-fatal: recap available in-memory; silently skip persist failure
        }
    }

    func loadExistingRecap(noteId: String) async {
        guard flags.churchNotesSmartRecapEnabled else { return }
        recapLoadState = .loading
        do {
            if let recap = try await service.loadRecap(for: noteId) {
                smartRecap = recap
                recapLoadState = .loaded
            } else {
                recapLoadState = .empty
            }
        } catch {
            recapLoadState = .error(error.localizedDescription)
        }
    }

    func editRecap(newText: String) {
        guard let recap = smartRecap else { return }
        smartRecap = CNSmartRecap(
            id: recap.id,
            noteId: recap.noteId,
            whatStoodOut: newText,
            prayerItems: recap.prayerItems,
            nextStep: recap.nextStep,
            relatedScriptures: recap.relatedScriptures,
            relatedNoteIds: recap.relatedNoteIds,
            isEdited: true,
            editedText: newText,
            generatedAt: recap.generatedAt,
            provenance: recap.provenance
        )
    }

    func saveEditedRecap() async {
        guard let recap = smartRecap else { return }
        do {
            try await service.saveRecap(recap)
        } catch {
            // Surface via alert if needed
        }
    }

    // MARK: - Growth Timeline

    func loadGrowthTimeline(userId: String) {
        guard flags.churchNotesGrowthTimelineEnabled else { return }
        growthTimelineState = .loading
        service.listenGrowthTimeline { [weak self] entries in
            guard let self else { return }
            self.growthEntries = entries
            self.growthTimelineState = entries.isEmpty ? .empty : .loaded
        }
    }

    // MARK: - Action Suggestions

    func approveActionSuggestion(_ suggestion: CNActionSuggestion) async {
        guard let noteId = contextResult?.noteId else { return }
        do {
            try await service.approveActionSuggestion(suggestion, noteId: noteId)
            mutateAction(id: suggestion.id) { $0.approvalState = .approved }
        } catch {}
    }

    func rejectActionSuggestion(_ suggestion: CNActionSuggestion) async {
        guard let noteId = contextResult?.noteId else { return }
        do {
            try await service.rejectActionSuggestion(suggestion, noteId: noteId)
            mutateAction(id: suggestion.id) { $0.approvalState = .rejected }
        } catch {}
    }

    func editActionSuggestion(id: String, newText: String) {
        mutateAction(id: id) {
            $0.editedText = newText
            $0.approvalState = .edited
        }
    }

    // MARK: - Group Intelligence

    func loadGroupInsights(churchId: String) async {
        guard flags.churchNotesGroupIntelligenceEnabled else { return }
        do {
            groupInsight = try await service.loadGroupInsights(for: churchId)
        } catch {}
    }

    // MARK: - Command Bar

    func handleCommand(_ command: CNCommandBarCommand, noteText: String) async {
        guard flags.churchNotesCommandBarEnabled else { return }
        selectedCommandBarCommand = command
        pendingCommandBarText = ""

        // Local command handling — server-side commands use callables
        switch command {
        case .prayer:
            let themes = engine.detectThemes(in: noteText)
            let prompts = engine.generatePrayerPrompts(from: noteText, themes: themes)
            let combined = prompts.map { $0.text }.joined(separator: "\n\n")
            commandBarResult = CNCommandBarResult(
                id: UUID().uuidString,
                command: command,
                text: combined.isEmpty ? "No prayer prompts detected in this note yet." : combined,
                editedText: nil,
                isApproved: false,
                provenance: CNProvenanceLabel(
                    source: "your note",
                    confidence: .possible,
                    whySuggested: "Generated from note content — edit before inserting"
                )
            )
        case .actionItems:
            let suggestions = engine.extractActionSuggestions(from: noteText)
            let combined = suggestions.map { "• \($0.text)" }.joined(separator: "\n")
            commandBarResult = CNCommandBarResult(
                id: UUID().uuidString,
                command: command,
                text: combined.isEmpty ? "No action items detected in this note." : combined,
                editedText: nil,
                isApproved: false,
                provenance: CNProvenanceLabel(
                    source: "your note",
                    confidence: .possible,
                    whySuggested: "Extracted from commitment language in your note"
                )
            )
        case .smallGroup:
            let themes = engine.detectThemes(in: noteText)
            let questions = engine.generateSmallGroupQuestions(from: noteText, themes: themes)
            let combined = questions.map { "• \($0.text)" }.joined(separator: "\n")
            commandBarResult = CNCommandBarResult(
                id: UUID().uuidString,
                command: command,
                text: combined.isEmpty ? "No small group questions generated yet." : combined,
                editedText: nil,
                isApproved: false,
                provenance: CNProvenanceLabel(
                    source: "your note",
                    confidence: .possible,
                    whySuggested: "Generated from note themes — review before sharing"
                )
            )
        default:
            // Summarize, study, translate, ask-berean, share-with-group require server callable
            commandBarResult = CNCommandBarResult(
                id: UUID().uuidString,
                command: command,
                text: "This command requires Berean AI — tap to open the full experience.",
                editedText: nil,
                isApproved: false,
                provenance: CNProvenanceLabel(
                    source: "system",
                    confidence: .confirmed,
                    whySuggested: "Requires server-side AI processing"
                )
            )
        }
        isCommandBarPresented = true
    }

    func editCommandBarResult(newText: String) {
        commandBarResult?.editedText = newText
    }

    func approveCommandBarResult() {
        commandBarResult?.isApproved = true
        isCommandBarPresented = false
    }

    func dismissCommandBarResult() {
        commandBarResult = nil
        isCommandBarPresented = false
        selectedCommandBarCommand = nil
    }

    // MARK: - Smart Capture

    func processCapture(extractedText: String, sourceJobId: String) -> CNSmartCaptureResult {
        let result = engine.classifyCapture(extractedText: extractedText, sourceJobId: sourceJobId)
        if var context = contextResult {
            context.smartCaptures.append(result)
            contextResult = context
        }
        return result
    }

    func approveCapture(id: String) {
        guard var context = contextResult else { return }
        context.smartCaptures = context.smartCaptures.map { capture in
            guard capture.id == id else { return capture }
            var updated = capture
            updated.reviewState = .approved
            return updated
        }
        contextResult = context
    }

    func rejectCapture(id: String) {
        guard var context = contextResult else { return }
        context.smartCaptures = context.smartCaptures.map { capture in
            guard capture.id == id else { return capture }
            var updated = capture
            updated.reviewState = .rejected
            return updated
        }
        contextResult = context
    }

    // MARK: - Private Helpers

    private func mutateAction(id: String, _ mutation: (inout CNActionSuggestion) -> Void) {
        guard var result = contextResult else { return }
        result.actionSuggestions = result.actionSuggestions.map { suggestion in
            guard suggestion.id == id else { return suggestion }
            var updated = suggestion
            mutation(&updated)
            return updated
        }
        contextResult = result
    }
}
