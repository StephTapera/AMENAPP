// AdaptiveComposerCore.swift
// AMEN — Shared ViewModel for the Adaptive Composer system.
import SwiftUI
import Combine

// MARK: - CreationRailViewModel

@MainActor
final class CreationRailViewModel: ObservableObject {
    @Published private(set) var orderedTools: [CreationTool] = []
    @Published private(set) var railState: RailState = .compact
    @Published private(set) var presentationMode: ComposerPresentationMode
    @Published var context: ComposerContext

    private let intentEngine: any IntentEngine
    private var detectTask: Task<Void, Never>?
    private var lastReorderTime: Date = .distantPast
    private(set) var isUserScrolling: Bool = false

    init(surface: ComposerSurface,
         intentEngine: any IntentEngine,
         churchContext: ChurchComposerContext? = nil,
         spaceContext: SpaceComposerContext? = nil) {
        self.presentationMode = surface.defaultPresentationMode
        self.context = ComposerContext(
            surface: surface,
            churchContext: churchContext,
            spaceContext: spaceContext,
            audience: nil,
            conversationParticipants: [],
            recentBehavior: [],
            pastedContent: nil
        )
        self.intentEngine = intentEngine
        self.orderedTools = Self.filteredTools(for: surface, isChurchMode: churchContext != nil)
    }

    func textDidChange(_ text: String, reduceMotion: Bool = false) {
        detectTask?.cancel()
        if text.isEmpty {
            withAnimation(reduceMotion ? .linear(duration: 0) : .spring(response: 0.35, dampingFraction: 0.8)) {
                railState = .expanded
            }
            return
        }
        railState = .compact
        detectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled, let self else { return }
            let suggestions = await self.intentEngine.detect(in: text, context: self.context)
            guard !Task.isCancelled else { return }
            if suggestions.isEmpty {
                self.railState = .compact
            } else {
                self.applyPredictiveReorder(suggestions: suggestions, reduceMotion: reduceMotion)
            }
        }
    }

    func setScrolling(_ scrolling: Bool) { isUserScrolling = scrolling }

    func setExpanded(_ expanded: Bool, reduceMotion: Bool = false) {
        withAnimation(reduceMotion ? .linear(duration: 0) : .spring(response: 0.35, dampingFraction: 0.8)) {
            railState = expanded ? .expanded : .compact
        }
    }

    func availableTools(for surface: ComposerSurface, isChurchMode: Bool) -> [CreationTool] {
        Self.filteredTools(for: surface, isChurchMode: isChurchMode)
    }

    private func applyPredictiveReorder(suggestions: [IntentSuggestion], reduceMotion: Bool) {
        let now = Date()
        let canReorder = now.timeIntervalSince(lastReorderTime) > 2.0 && !isUserScrolling
        withAnimation(reduceMotion ? .linear(duration: 0) : .easeOut(duration: 0.18)) {
            railState = .predictive(suggestions)
        }
        guard canReorder else { return }
        lastReorderTime = now
        let predictedIDs = suggestions.map { $0.primaryTool }
        var reordered = orderedTools
        var insertIndex = 0
        for toolId in predictedIDs.reversed() {
            if let idx = reordered.firstIndex(where: { $0.id == toolId }), idx != insertIndex {
                let tool = reordered.remove(at: idx)
                reordered.insert(tool, at: insertIndex)
            }
            insertIndex += 1
        }
        orderedTools = reordered
    }

    private static func filteredTools(for surface: ComposerSurface, isChurchMode: Bool) -> [CreationTool] {
        let allowed = surface.defaultToolSet
        return CreationTool.registry.filter { tool in
            guard allowed.contains(tool.id) || tool.id == .more else { return false }
            if tool.tier == .churchOnly && !isChurchMode { return false }
            return true
        }
    }

    static func makeForSurface(_ surface: ComposerSurface,
                                churchContext: ChurchComposerContext? = nil,
                                spaceContext: SpaceComposerContext? = nil) -> CreationRailViewModel {
        CreationRailViewModel(
            surface: surface,
            intentEngine: OnDeviceIntentEngine(),
            churchContext: churchContext,
            spaceContext: spaceContext
        )
    }
}

// MARK: - Tool Registry
extension CreationTool {
    static let registry: [CreationTool] = [
        CreationTool(id: .photo, icon: "photo", title: "Photo", tier: .primary,
                     surfaces: Set(ComposerSurface.allCases), makeAttachment: nil),
        CreationTool(id: .camera, icon: "camera", title: "Camera", tier: .primary,
                     surfaces: [.post, .message, .groupChat, .space, .churchSpace, .churchNote, .prayerRequest, .event], makeAttachment: nil),
        CreationTool(id: .bible, icon: "book.fill", title: "Scripture", tier: .primary,
                     surfaces: Set(ComposerSurface.allCases), makeAttachment: nil),
        CreationTool(id: .link, icon: "link", title: "Link", tier: .primary,
                     surfaces: [.post, .message, .groupChat, .space, .churchSpace, .comment, .bibleStudy], makeAttachment: nil),
        CreationTool(id: .poll, icon: "chart.bar.fill", title: "Poll", tier: .extended,
                     surfaces: [.post, .space, .groupChat, .churchSpace], makeAttachment: nil),
        CreationTool(id: .event, icon: "calendar", title: "Event", tier: .extended,
                     surfaces: [.post, .groupChat, .space, .churchSpace, .event], makeAttachment: nil),
        CreationTool(id: .music, icon: "music.note", title: "Music", tier: .extended,
                     surfaces: [.post, .message, .groupChat, .space, .churchNote], makeAttachment: nil),
        CreationTool(id: .podcast, icon: "waveform", title: "Podcast", tier: .extended,
                     surfaces: [.post, .message, .groupChat, .bibleStudy], makeAttachment: nil),
        CreationTool(id: .prayerRequest, icon: "hands.sparkles", title: "Prayer", tier: .primary,
                     surfaces: [.post, .comment, .message, .groupChat, .space, .churchSpace, .prayerRequest, .event, .bibleStudy], makeAttachment: nil),
        CreationTool(id: .anonymousPrayer, icon: "person.fill.questionmark", title: "Anonymous Prayer", tier: .extended,
                     surfaces: [.prayerRequest, .churchSpace], makeAttachment: nil),
        CreationTool(id: .prayerCircle, icon: "circle.dashed", title: "Prayer Circle", tier: .extended,
                     surfaces: [.prayerRequest, .churchSpace, .groupChat], makeAttachment: nil),
        CreationTool(id: .voice, icon: "mic.fill", title: "Voice", tier: .primary,
                     surfaces: [.post, .comment, .message, .groupChat, .prayerRequest, .bibleStudy], makeAttachment: nil),
        CreationTool(id: .video, icon: "video", title: "Video", tier: .extended,
                     surfaces: [.post, .space, .churchSpace, .churchNote, .event], makeAttachment: nil),
        CreationTool(id: .location, icon: "mappin.and.ellipse", title: "Location", tier: .extended,
                     surfaces: [.post, .event, .churchSpace], makeAttachment: nil),
        CreationTool(id: .file, icon: "paperclip", title: "File", tier: .extended,
                     surfaces: [.message, .groupChat, .space, .churchSpace, .bibleStudy], makeAttachment: nil),
        CreationTool(id: .checklist, icon: "checklist", title: "Checklist", tier: .extended,
                     surfaces: [.space, .groupChat, .bibleStudy, .churchSpace], makeAttachment: nil),
        CreationTool(id: .task, icon: "checkmark.square", title: "Task", tier: .extended,
                     surfaces: [.space, .groupChat, .churchSpace], makeAttachment: nil),
        CreationTool(id: .donation, icon: "dollarsign.circle", title: "Giving", tier: .extended,
                     surfaces: [.post, .churchSpace, .churchNote, .event], makeAttachment: nil),
        CreationTool(id: .announcement, icon: "megaphone", title: "Announcement", tier: .extended,
                     surfaces: [.churchSpace, .churchNote, .event], makeAttachment: nil),
        CreationTool(id: .churchNote, icon: "building.columns", title: "Church Note", tier: .extended,
                     surfaces: [.post, .churchSpace, .churchNote, .bibleStudy], makeAttachment: nil),
        CreationTool(id: .sermon, icon: "speaker.wave.2", title: "Sermon", tier: .churchOnly,
                     surfaces: [.churchSpace, .churchNote], makeAttachment: nil),
        CreationTool(id: .worshipSong, icon: "music.quarternote.3", title: "Worship Song", tier: .churchOnly,
                     surfaces: [.churchSpace, .churchNote], makeAttachment: nil),
        CreationTool(id: .teachingSeries, icon: "books.vertical", title: "Teaching Series", tier: .churchOnly,
                     surfaces: [.churchSpace, .churchNote], makeAttachment: nil),
        CreationTool(id: .volunteerSignup, icon: "person.badge.plus", title: "Volunteer", tier: .churchOnly,
                     surfaces: [.churchSpace, .event], makeAttachment: nil),
        CreationTool(id: .ministryInterestForm, icon: "doc.badge.plus", title: "Ministry Form", tier: .churchOnly,
                     surfaces: [.churchSpace], makeAttachment: nil),
        CreationTool(id: .rsvpCard, icon: "envelope.badge", title: "RSVP", tier: .extended,
                     surfaces: [.event, .churchSpace, .groupChat], makeAttachment: nil),
        CreationTool(id: .directionsCard, icon: "arrow.triangle.turn.up.right.diamond", title: "Directions", tier: .extended,
                     surfaces: [.event, .churchSpace], makeAttachment: nil),
        CreationTool(id: .reminder, icon: "bell.fill", title: "Reminder", tier: .extended,
                     surfaces: [.event, .groupChat, .churchSpace], makeAttachment: nil),
        CreationTool(id: .bibleStudy, icon: "book.closed", title: "Bible Study", tier: .extended,
                     surfaces: [.post, .space, .churchSpace, .bibleStudy], makeAttachment: nil),
        CreationTool(id: .discussionThread, icon: "bubble.left.and.bubble.right", title: "Discussion", tier: .extended,
                     surfaces: [.post, .space, .churchSpace, .bibleStudy], makeAttachment: nil),
        CreationTool(id: .more, icon: "ellipsis", title: "More", tier: .primary,
                     surfaces: Set(ComposerSurface.allCases), makeAttachment: nil),
    ]
}

// MARK: - OnDeviceIntentEngine stub
// Companion file ComposerIntentEngine.swift provides the real implementation.
// This stub ensures AdaptiveComposerCore.swift compiles standalone.
final class OnDeviceIntentEngine: IntentEngine {
    func detect(in text: String, context: ComposerContext) async -> [IntentSuggestion] { [] }
}
