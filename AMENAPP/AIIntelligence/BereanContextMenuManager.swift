import Foundation
import SwiftUI

@MainActor
final class BereanContextMenuManager: ObservableObject {
    static let shared = BereanContextMenuManager()

    @Published var activePayload: BereanContextPayload?
    @Published var selectedAction: BereanContextAction?
    @Published var showingResult = false

    private let engine = BereanContextActionEngine.shared
    private var activeTask: Task<Void, Never>?

    var compactActions: [BereanContextAction] {
        [.askBerean, .explain, .prayAboutThis, .reflect, .saveToChurchNotes, .summarize, .compareScripture, .translate]
    }

    func actions(for payload: BereanContextPayload) -> [BereanContextAction] {
        var actions: [BereanContextAction] = [.askBerean, .explain, .simplify, .summarize, .reflect]

        switch payload.contentType {
        case .scripture:
            actions += [.prayAboutThis, .compareScripture, .historicalContext, .crossReference, .createStudy, .turnIntoDevotional, .turnIntoSermonOutline, .searchRelatedVerses]
        case .note, .transcript, .article:
            actions += [.saveToChurchNotes, .createStudy, .turnIntoPrayer, .turnIntoDevotional, .leadershipInsight]
        case .message, .comment, .post, .caption:
            actions += [.emotionalInsight, .youthExplanation, .beginnerExplanation, .discussWithGroup, .shareReflection]
        case .media:
            actions += [.voiceExplain, .factCheck, .createCarousel, .createPost]
        case .unknown:
            actions += [.define, .translate, .factCheck]
        }

        if payload.selectedText.split(separator: " ").count <= 8 {
            actions.append(.define)
        }

        actions += [.translate, .askFollowUp, .continueReading]
        return Array(NSOrderedSet(array: actions).compactMap { $0 as? BereanContextAction })
    }

    func activate(payload: BereanContextPayload, action: BereanContextAction) {
        activeTask?.cancel()
        activePayload = payload
        selectedAction = action
        showingResult = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        activeTask = Task { [weak self] in
            _ = await self?.engine.perform(action, payload: payload)
        }
    }

    func retryActiveAction() {
        guard let activePayload, let selectedAction else { return }
        activate(payload: activePayload, action: selectedAction)
    }

    func cancelActiveAction() {
        activeTask?.cancel()
        activeTask = nil
        engine.clearResult()
        showingResult = false
    }
}
