//
//  SharePlayService.swift
//  AMENAPP
//
//  SharePlay integration for group Bible study over FaceTime.
//  Uses GroupActivities framework for synchronized scripture reading.
//

import Foundation
import GroupActivities
import Combine

// MARK: - Bible Study Activity

struct BibleStudyActivity: GroupActivity {
    static let activityIdentifier = "com.amenapp.biblestudy"

    var metadata: GroupActivityMetadata {
        var meta = GroupActivityMetadata()
        meta.title = "Bible Study"
        meta.subtitle = passage.isEmpty ? "Study together" : "Studying \(passage)"
        meta.type = .generic
        return meta
    }

    let passage: String
    let hostName: String
}

// MARK: - Shared State

struct BibleStudyState: Codable {
    var currentBook: String
    var currentChapter: Int
    var currentVerse: Int
    var highlightedVerses: [Int]
    var notes: [SharedNote]
    var hostId: String

    struct SharedNote: Codable, Identifiable {
        let id: String
        let authorName: String
        let text: String
        let verse: Int
        let timestamp: Date
    }
}

// MARK: - Service

@MainActor
class SharePlayService: ObservableObject {
    static let shared = SharePlayService()

    @Published var isSessionActive = false
    @Published var currentState: BibleStudyState?
    @Published var participantCount = 0

    private var session: GroupSession<BibleStudyActivity>?
    private var messenger: GroupSessionMessenger?
    private var tasks: Set<Task<Void, Never>> = []
    private var cancellables = Set<AnyCancellable>()

    private init() {
        listenForSessions()
    }

    // MARK: - Start Activity

    func startBibleStudy(passage: String, hostName: String) async throws {
        let activity = BibleStudyActivity(passage: passage, hostName: hostName)

        switch await activity.prepareForActivation() {
        case .activationPreferred:
            _ = try await activity.activate()
        case .activationDisabled:
            throw SharePlayError.activationDisabled
        case .cancelled:
            throw SharePlayError.cancelled
        @unknown default:
            break
        }
    }

    // MARK: - Listen for Sessions

    private func listenForSessions() {
        let task = Task {
            for await session in BibleStudyActivity.sessions() {
                await configureSession(session)
            }
        }
        tasks.insert(task)
    }

    private func configureSession(_ session: GroupSession<BibleStudyActivity>) async {
        self.session = session
        let messenger = GroupSessionMessenger(session: session)
        self.messenger = messenger

        session.$state.sink { [weak self] state in
            Task { @MainActor in
                self?.isSessionActive = (state == .joined)
            }
        }.store(in: &cancellables)

        session.$activeParticipants.sink { [weak self] participants in
            Task { @MainActor in
                self?.participantCount = participants.count
            }
        }.store(in: &cancellables)

        // Listen for state updates
        let receiveTask = Task {
            for await (state, _) in messenger.messages(of: BibleStudyState.self) {
                await MainActor.run {
                    self.currentState = state
                }
            }
        }
        tasks.insert(receiveTask)

        session.join()
    }

    // MARK: - Send State Update

    func sendStateUpdate(_ state: BibleStudyState) async {
        currentState = state
        try? await messenger?.send(state)
    }

    // MARK: - Navigate Passage

    func navigateToVerse(book: String, chapter: Int, verse: Int) async {
        guard var state = currentState else { return }
        state.currentBook = book
        state.currentChapter = chapter
        state.currentVerse = verse
        await sendStateUpdate(state)
    }

    // MARK: - Add Shared Note

    func addNote(text: String, verse: Int, authorName: String) async {
        guard var state = currentState else { return }
        let note = BibleStudyState.SharedNote(
            id: UUID().uuidString,
            authorName: authorName,
            text: text,
            verse: verse,
            timestamp: Date()
        )
        state.notes.append(note)
        await sendStateUpdate(state)
    }

    // MARK: - End Session

    func endSession() {
        session?.end()
        session = nil
        messenger = nil
        isSessionActive = false
        currentState = nil
        participantCount = 0
    }

    enum SharePlayError: Error {
        case activationDisabled
        case cancelled
    }
}
