//
//  DevotionalGeneratorViewModel.swift
//  AMENAPP
//
//  @Observable view model that drives the Devotional Generator UI.
//  Owns the DevotionalContext (user inputs), generation phase, and the
//  generated DevotionalResponse. Coordinates between the generation
//  service, safety service, and rhythm service.
//

import SwiftUI
import Observation
import FirebaseAuth

@Observable
final class DevotionalGeneratorViewModel {

    // MARK: - User Input State

    var topic: String = ""
    var selectedTone: DevotionalTone = .contemplative
    var communityMode: CommunityMode = .personal
    var specificQuestion: String = ""
    var selectedVerses: [String] = []
    var safetyMode: DevotionalSafetyMode = .standard
    var useChurchNotesContext: Bool = true
    var usePrayerContext: Bool = true

    // MARK: - Generation State

    var phase: DevotionalGenerationPhase = .idle
    var generatedDevotional: DevotionalResponse? = nil
    var errorMessage: String? = nil
    var showGenerated: Bool = false

    // MARK: - History

    var history: [DevotionalResponse] = []
    var isLoadingHistory: Bool = false

    // MARK: - UI Convenience

    var isGenerating: Bool { phase.isLoading }

    var topicIsValid: Bool {
        !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !selectedVerses.isEmpty
    }

    var suggestedTopicChips: [String] {
        if topic.count >= 2 {
            let matched = DevotionalTopicMap.suggestedTopics(for: topic)
            return matched.isEmpty ? Array(DevotionalTopicMap.allTopics.prefix(12)) : matched
        }
        return Array(DevotionalTopicMap.allTopics.prefix(12))
    }

    var recommendedVerses: [String] {
        DevotionalTopicMap.passages(for: topic)
    }

    // MARK: - Services

    private let generationService = DevotionalGenerationService.shared
    private let rhythmService = SpiritualRhythmService.shared

    // MARK: - Init

    init() {
        Task { await loadHistory() }
    }

    // MARK: - Actions

    @MainActor
    func generate() async {
        guard topicIsValid else {
            errorMessage = "Please enter a topic or select a scripture verse."
            return
        }

        let userId = Auth.auth().currentUser?.uid ?? ""
        errorMessage = nil
        generatedDevotional = nil
        showGenerated = false

        var churchNotesSnippet: String? = nil
        var prayerSnippet: String? = nil

        // Optionally pull context snippets
        if useChurchNotesContext || usePrayerContext {
            let bundle = await SelahService.shared.buildSourceBundle(
                forVerses: selectedVerses,
                query: topic,
                limit: 3
            )
            if useChurchNotesContext, let firstNote = bundle.notes.first {
                churchNotesSnippet = firstNote.contentPreview
            }
            if usePrayerContext, let firstPrayer = bundle.prayers.first {
                prayerSnippet = firstPrayer.contentPreview
            }
        }

        let context = DevotionalContext(
            topic: topic,
            tone: selectedTone,
            communityMode: communityMode,
            selectedVerses: selectedVerses,
            churchNotesSnippet: churchNotesSnippet,
            prayerSnippet: prayerSnippet,
            specificQuestion: specificQuestion.isEmpty ? nil : specificQuestion,
            safetyMode: safetyMode
        )

        do {
            let result = try await generationService.generate(context: context) { [weak self] newPhase in
                Task { @MainActor [weak self] in
                    self?.phase = newPhase
                }
            }
            generatedDevotional = result
            showGenerated = true
            phase = .complete

            // Record in rhythm service
            await rhythmService.recordCompletion(devotional: result)

            // Refresh history in background
            Task { await loadHistory() }

        } catch {
            phase = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    /// Save the current devotional to Church Notes.
    @MainActor
    func saveToNotes() async {
        guard let devotional = generatedDevotional else { return }
        do {
            let noteId = try await generationService.saveToChurchNotes(devotional: devotional)
            // Update local copy to show saved state
            generatedDevotional = DevotionalResponse(
                requestId: devotional.requestId,
                userId: devotional.userId,
                title: devotional.title,
                openingVerse: devotional.openingVerse,
                additionalScriptures: devotional.additionalScriptures,
                reflection: devotional.reflection,
                prayer: devotional.prayer,
                practice: devotional.practice,
                community: devotional.community,
                guardrailNotice: devotional.guardrailNotice,
                tone: devotional.tone,
                topicTags: devotional.topicTags
            )
        } catch {
            errorMessage = "Could not save to notes: \(error.localizedDescription)"
        }
    }

    /// Reset the generator to start fresh.
    @MainActor
    func reset() {
        phase = .idle
        generatedDevotional = nil
        showGenerated = false
        errorMessage = nil
        topic = ""
        selectedVerses = []
        specificQuestion = ""
    }

    /// Load the devotional history from Firestore.
    @MainActor
    func loadHistory() async {
        isLoadingHistory = true
        do {
            history = try await generationService.loadHistory(limit: 20)
        } catch {
            // History is non-critical; fail silently
        }
        isLoadingHistory = false
    }

    /// Toggle a verse in/out of the selected list.
    func toggleVerse(_ ref: String) {
        if selectedVerses.contains(ref) {
            selectedVerses.removeAll { $0 == ref }
        } else {
            selectedVerses.append(ref)
        }
    }

    /// Apply a topic chip directly.
    func applyTopic(_ chip: String) {
        topic = chip.capitalized
    }
}
