// SceneBuilderViewModel.swift
// AMEN Creator — AI Scene Builder
// Observable view model driving the entire creation studio

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore
import PhotosUI

@MainActor
final class SceneBuilderViewModel: ObservableObject {

    // MARK: - Published State

    @Published var selectedAssets: [CreationAsset] = []
    @Published var selectedTemplate: CreationTemplate?
    @Published var scenePlan: ScenePlan?
    @Published var timelineSegments: [CreationTimelineSegment] = []
    @Published var previewState: CreationPreviewState = .idle
    @Published var studioState: CreationStudioState = .idle
    @Published var refinementInput: String = ""
    @Published var safetyStatus: CreationSafetyState = .approved
    @Published var draft: CreationDraft?
    @Published var publishState: CreationPublishState = .idle
    @Published var selectedSegmentId: String?
    @Published var refinementHistory: [String] = []
    @Published var showRefinementSheet = false
    @Published var showTemplateSheet = false
    @Published var showSafetySheet = false
    @Published var showPublishView = false
    @Published var captionEditing: CreationCaptionTrack?
    @Published var overlayEditing: CreationOverlayInstruction?
    @Published var activeTab: CreationStudioTab = .timeline
    @Published var errorMessage: String?

    // MARK: - Private

    private let db = Firestore.firestore()
    private var draftAutoSaveTask: Task<Void, Never>?
    private var generationTask: Task<Void, Never>?
    private var refinementTask: Task<Void, Never>?

    // MARK: - Computed

    var selectedSegment: CreationTimelineSegment? {
        guard let id = selectedSegmentId else { return nil }
        return timelineSegments.first { $0.id == id }
    }

    var canPublish: Bool {
        scenePlan != nil &&
        !timelineSegments.isEmpty &&
        safetyStatus == .approved &&
        publishState == .idle
    }

    var totalDuration: Double {
        timelineSegments.reduce(0) { $0 + $1.duration }
    }

    var isGenerating: Bool {
        if case .generatingPlan = studioState { return true }
        return false
    }

    var isRefining: Bool {
        if case .refining = studioState { return true }
        return false
    }

    // MARK: - Asset Management

    func addAssets(_ newAssets: [CreationAsset]) {
        let uniqueNew = newAssets.filter { new in !selectedAssets.contains { $0.id == new.id } }
        selectedAssets.append(contentsOf: uniqueNew)
        scheduleAutoSave()
    }

    func removeAsset(_ asset: CreationAsset) {
        selectedAssets.removeAll { $0.id == asset.id }
        // Remove segments that reference this asset
        timelineSegments.removeAll { $0.assetId == asset.id }
        scheduleAutoSave()
    }

    func moveAsset(from source: IndexSet, to destination: Int) {
        selectedAssets.move(fromOffsets: source, toOffset: destination)
        scheduleAutoSave()
    }

    // MARK: - Template Selection

    func applyTemplate(_ template: CreationTemplate) {
        selectedTemplate = template
        showTemplateSheet = false
        if !selectedAssets.isEmpty {
            generatePlan()
        }
    }

    // MARK: - Scene Plan Generation

    func generatePlan() {
        guard !selectedAssets.isEmpty || selectedTemplate != nil else { return }
        generationTask?.cancel()
        studioState = .generatingPlan

        generationTask = Task {
            do {
                let plan = try await callGenerateScenePlan()
                if Task.isCancelled { return }
                scenePlan = plan
                timelineSegments = plan.segments
                safetyStatus = plan.safetySummary.status
                studioState = .editingTimeline
                scheduleAutoSave()
            } catch {
                if !Task.isCancelled {
                    studioState = .error(error.localizedDescription)
                    errorMessage = "Couldn't generate your plan. Please try again."
                }
            }
        }
    }

    // MARK: - Refinement

    func refine(with prompt: String) {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let plan = scenePlan else { return }
        refinementTask?.cancel()
        refinementHistory.append(prompt)
        studioState = .refining(prompt: prompt)
        refinementInput = ""

        refinementTask = Task {
            do {
                let refined = try await callRefineScenePlan(plan: plan, prompt: prompt)
                if Task.isCancelled { return }
                scenePlan = refined
                timelineSegments = refined.segments
                safetyStatus = refined.safetySummary.status
                studioState = .editingTimeline
                scheduleAutoSave()
            } catch {
                if !Task.isCancelled {
                    dlog("⚠️ [SceneBuilderViewModel] refine failed: \(error.localizedDescription)")
                    studioState = .editingTimeline
                    errorMessage = "Couldn't apply refinement. Try a different prompt."
                }
            }
        }
    }

    func applyRefinementChip(_ chip: CreationRefinementChip) {
        refine(with: chip.prompt)
    }

    // MARK: - Timeline Editing

    func moveSegment(from source: IndexSet, to destination: Int) {
        timelineSegments.move(fromOffsets: source, toOffset: destination)
        scheduleAutoSave()
    }

    func deleteSegment(_ segment: CreationTimelineSegment) {
        timelineSegments.removeAll { $0.id == segment.id }
        if selectedSegmentId == segment.id { selectedSegmentId = nil }
        scheduleAutoSave()
    }

    func updateSegmentCaption(_ segmentId: String, caption: String) {
        guard let idx = timelineSegments.firstIndex(where: { $0.id == segmentId }) else { return }
        timelineSegments[idx].captionText = caption
        scheduleAutoSave()
    }

    func updateSegmentOverlayText(_ segmentId: String, text: String) {
        guard let idx = timelineSegments.firstIndex(where: { $0.id == segmentId }) else { return }
        timelineSegments[idx].text = text
        scheduleAutoSave()
    }

    func replaceAssetInSegment(_ segmentId: String, with assetId: String) {
        guard let idx = timelineSegments.firstIndex(where: { $0.id == segmentId }) else { return }
        timelineSegments[idx].assetId = assetId
        scheduleAutoSave()
    }

    func selectSegment(_ id: String?) {
        selectedSegmentId = id
    }

    // MARK: - Safety Check

    func runSafetyCheck() async {
        studioState = .safetyReview
        do {
            let result = try await callSafetyCheck()
            safetyStatus = result.status
            if result.status == .blocked {
                showSafetySheet = true
            }
            studioState = .editingTimeline
        } catch {
            dlog("⚠️ [SceneBuilderViewModel] runSafetyCheck failed: \(error.localizedDescription)")
            safetyStatus = .review
            studioState = .editingTimeline
        }
    }

    // MARK: - Publish

    func publish() {
        guard canPublish else { return }
        showPublishView = true
    }

    func executePublish(destinations: [String]) {
        publishState = .validating

        Task {
            do {
                publishState = .uploading(progress: 0.0)
                // Simulate upload progress
                for i in 1...10 {
                    try await Task.sleep(nanoseconds: 100_000_000)
                    publishState = .uploading(progress: Double(i) / 10.0)
                }
                publishState = .publishing
                try await savePublishedDraft(destinations: destinations)
                publishState = .success
                studioState = .published
            } catch {
                publishState = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Draft

    func loadDraft(_ draftId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let doc = try await db
                .collection("creationDrafts")
                .document(draftId)
                .getDocument()
            if let d = try? doc.data(as: CreationDraft.self), d.userId == uid {
                draft = d
            }
        } catch {
            dlog("⚠️ [SceneBuilderViewModel] loadDraft failed: \(error.localizedDescription)")
        }
    }

    func discardDraft() {
        selectedAssets = []
        selectedTemplate = nil
        scenePlan = nil
        timelineSegments = []
        draft = nil
        studioState = .idle
        publishState = .idle
        safetyStatus = .approved
        refinementHistory = []
    }

    private func scheduleAutoSave() {
        draftAutoSaveTask?.cancel()
        draftAutoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)  // 1.5s debounce
            if Task.isCancelled { return }
            await saveDraftToFirestore()
        }
    }

    private func saveDraftToFirestore() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let draftId = draft?.id ?? UUID().uuidString
        let data: [String: Any] = [
            "userId":            uid,
            "title":             selectedTemplate?.name ?? "Untitled Draft",
            "templateId":        selectedTemplate?.id as Any,
            "assetIds":          selectedAssets.map { $0.id },
            "updatedAt":         FieldValue.serverTimestamp(),
            "status":            "active",
            "refinementHistory": refinementHistory,
        ]
        do {
            try await db
                .collection("creationDrafts")
                .document(draftId)
                .setData(data, merge: true)
        } catch {
            dlog("⚠️ [SceneBuilderViewModel] auto-save draft failed: \(error.localizedDescription)")
        }
    }

    private func savePublishedDraft(destinations: [String]) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let draftId = draft?.id ?? UUID().uuidString
        try await db
            .collection("creationDrafts")
            .document(draftId)
            .setData([
                "userId":      uid,
                "status":      "published",
                "publishedAt": FieldValue.serverTimestamp(),
                "destinations": destinations,
            ], merge: true)
    }

    // MARK: - Cloud Function Calls

    private func callGenerateScenePlan() async throws -> ScenePlan {
        // Build AI prompt from assets + template + intent
        let assetSummary = selectedAssets.map { a in
            "\(a.type.rawValue): \(a.duration.map { "\(Int($0))s" } ?? "unknown duration")"
        }.joined(separator: ", ")

        let templateDesc = selectedTemplate.map { "Template: \($0.name) (\($0.description))" } ?? ""
        let prompt = """
        Generate a structured scene plan for a short-form faith content piece.
        Assets: \(assetSummary.isEmpty ? "text only" : assetSummary)
        \(templateDesc)

        Return a JSON plan with segments, tone, titleSuggestion, coverTextSuggestion.
        Keep transitions minimal (softFade or cut only).
        Optimize for clarity and emotional honesty.
        Duration: \(selectedTemplate?.defaultDuration ?? 30) seconds.

        Respond in JSON: {"tone":"hopeful","titleSuggestion":"...","coverTextSuggestion":"...","segments":[{"id":"s1","kind":"intro","duration":3,"text":"...","captionText":"...","emphasis":"medium","lockedByAI":false}]}
        """

        let raw = try await ClaudeService.shared.sendMessageSync(prompt, mode: .scholar)
        return parseScenePlan(from: raw ?? "")
    }

    private func callRefineScenePlan(plan: ScenePlan, prompt: String) async throws -> ScenePlan {
        let currentStructure = timelineSegments.map { "\($0.kind.displayName) (\(Int($0.duration))s)" }.joined(separator: " → ")

        let refinePrompt = """
        You are refining a short-form faith content timeline.
        Current structure: \(currentStructure)
        User refinement request: "\(prompt)"

        Apply the refinement thoughtfully. Keep it reverent and calm.
        Return updated JSON segments only: {"segments":[{"id":"...","kind":"...","duration":...,"text":"...","captionText":"...","emphasis":"medium","lockedByAI":false}]}
        """

        let raw = try await ClaudeService.shared.sendMessageSync(refinePrompt, mode: .scholar)
        return parseScenePlan(from: raw ?? "", preserving: plan)
    }

    private func callSafetyCheck() async throws -> CreationSafetySummary {
        let overlayTexts = timelineSegments.compactMap { $0.text }.joined(separator: " | ")
        let captions = timelineSegments.compactMap { $0.captionText }.joined(separator: " | ")

        guard !overlayTexts.isEmpty && !captions.isEmpty else {
            return CreationSafetySummary.approved
        }

        let safetyPrompt = """
        Review this faith-based content for safety. Be permissive with genuine religious expression.
        Only flag: explicit content, harassment, dangerous health claims, exploitative manipulation.

        Text overlays: \(overlayTexts)
        Captions: \(captions)

        Respond JSON: {"status":"approved","flags":[],"notes":[],"canPublish":true}
        """

        let raw = try await ClaudeService.shared.sendMessageSync(safetyPrompt, mode: .scholar)
        return parseSafetySummary(from: raw ?? "")
    }

    // MARK: - JSON Parsing

    private func parseScenePlan(from raw: String, preserving existing: ScenePlan? = nil) -> ScenePlan {
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        struct RawPlan: Decodable {
            let tone: String?
            let titleSuggestion: String?
            let coverTextSuggestion: String?
            let segments: [RawSegment]?
        }
        struct RawSegment: Decodable {
            let id: String?
            let kind: String?
            let duration: Double?
            let text: String?
            let captionText: String?
            let emphasis: String?
            let lockedByAI: Bool?
        }

        if let data = cleaned.data(using: .utf8),
           let parsed = try? JSONDecoder().decode(RawPlan.self, from: data) {

            let tone = CreationSceneTone(rawValue: parsed.tone ?? "hopeful") ?? .hopeful
            let segments: [CreationTimelineSegment] = (parsed.segments ?? []).map { s in
                CreationTimelineSegment(
                    id:            s.id ?? UUID().uuidString,
                    kind:          CreationSegmentKind(rawValue: s.kind ?? "mainClip") ?? .mainClip,
                    assetId:       nil,
                    startTime:     nil,
                    endTime:       nil,
                    duration:      s.duration ?? 5,
                    text:          s.text,
                    captionText:   s.captionText,
                    overlayStyle:  nil,
                    transitionIn:  .softFade,
                    transitionOut: .softFade,
                    emphasis:      CreationSegmentEmphasis(rawValue: s.emphasis ?? "medium") ?? .medium,
                    lockedByAI:    s.lockedByAI ?? false
                )
            }

            return ScenePlan(
                id:                  existing?.id ?? UUID().uuidString,
                templateId:          selectedTemplate?.id,
                titleSuggestion:     parsed.titleSuggestion ?? existing?.titleSuggestion,
                coverTextSuggestion: parsed.coverTextSuggestion ?? existing?.coverTextSuggestion,
                targetDuration:      segments.reduce(0) { $0 + $1.duration },
                tone:                tone,
                segments:            segments,
                captionTracks:       existing?.captionTracks ?? [],
                overlays:            existing?.overlays ?? [],
                musicSuggestion:     existing?.musicSuggestion,
                safetySummary:       CreationSafetySummary.approved,
                createdAt:           existing?.createdAt ?? Date()
            )
        }

        // Fallback — return default plan from template
        return makeFallbackPlan(preserving: existing)
    }

    private func parseSafetySummary(from raw: String) -> CreationSafetySummary {
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        struct RawSafety: Decodable {
            let status: String?
            let canPublish: Bool?
            let notes: [String]?
        }
        if let data = cleaned.data(using: .utf8),
           let parsed = try? JSONDecoder().decode(RawSafety.self, from: data) {
            return CreationSafetySummary(
                status: CreationSafetyState(rawValue: parsed.status ?? "approved") ?? .approved,
                flags: [],
                notes: parsed.notes ?? [],
                canPublish: parsed.canPublish ?? true
            )
        }
        return CreationSafetySummary.approved
    }

    private func makeFallbackPlan(preserving existing: ScenePlan?) -> ScenePlan {
        let template = selectedTemplate ?? CreationTemplate.systemTemplates[0]
        let segments: [CreationTimelineSegment] = template.structure.map { rule in
            CreationTimelineSegment(
                id:            UUID().uuidString,
                kind:          rule.kind,
                assetId:       nil,
                startTime:     nil,
                endTime:       nil,
                duration:      rule.maxDuration,
                text:          nil,
                captionText:   nil,
                overlayStyle:  nil,
                transitionIn:  .softFade,
                transitionOut: .softFade,
                emphasis:      .medium,
                lockedByAI:    false
            )
        }
        return ScenePlan(
            id:                  existing?.id ?? UUID().uuidString,
            templateId:          template.id,
            titleSuggestion:     "My \(template.name)",
            coverTextSuggestion: nil,
            targetDuration:      template.defaultDuration,
            tone:                .hopeful,
            segments:            segments,
            captionTracks:       [],
            overlays:            [],
            musicSuggestion:     nil,
            safetySummary:       CreationSafetySummary.approved,
            createdAt:           Date()
        )
    }
}

// MARK: - Studio Tab

enum CreationStudioTab: String, CaseIterable {
    case timeline  = "Timeline"
    case captions  = "Captions"
    case overlays  = "Overlays"
    case music     = "Music"

    var icon: String {
        switch self {
        case .timeline: return "slider.horizontal.3"
        case .captions: return "text.bubble.fill"
        case .overlays: return "rectangle.on.rectangle.fill"
        case .music:    return "waveform"
        }
    }
}
