// BereanAdvisoryBoardService.swift
// AMENAPP — Berean OS
//
// Manages AI Advisory Boards — create, fetch, add advisors, and consult.
// Each board stores preset or custom AI advisors covering product, finance,
// legal, operations, marketing, and spiritual domains.
//
// Calls CF: bereanConsultAdvisoryBoard

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

// MARK: - Errors

enum BereanAdvisoryBoardError: LocalizedError {
    case featureDisabled
    case notAuthenticated
    case boardNotFound
    case consultFailed(String)

    var errorDescription: String? {
        switch self {
        case .featureDisabled:        return "Advisory Boards are not available yet."
        case .notAuthenticated:       return "You must be signed in to use Advisory Boards."
        case .boardNotFound:          return "The advisory board could not be found."
        case .consultFailed(let msg): return "Consultation failed: \(msg)"
        }
    }
}

// MARK: - Service

@MainActor
final class BereanAdvisoryBoardService: ObservableObject {

    static let shared = BereanAdvisoryBoardService()
    private init() {}

    // MARK: - Preset Advisors

    static let presetAdvisors: [(role: String, specialization: String, systemPrompt: String)] = [
        (
            "Product Advisor",
            "Product strategy, UX, market fit",
            "You are an experienced product advisor focused on user value, market fit, and strategic clarity."
        ),
        (
            "Finance Advisor",
            "Budgeting, funding, financial modeling",
            "You are a practical finance advisor focused on sustainability, unit economics, and risk management."
        ),
        (
            "Legal Advisor",
            "Contracts, compliance, liability",
            "You are a cautious legal advisor focused on risk mitigation. Always recommend consulting a real attorney for binding decisions."
        ),
        (
            "Operations Advisor",
            "Systems, processes, scaling",
            "You are an operations advisor focused on building reliable, scalable systems."
        ),
        (
            "Marketing Advisor",
            "Growth, positioning, messaging",
            "You are a marketing advisor focused on authentic positioning and sustainable growth."
        ),
        (
            "Spiritual Advisor",
            "Faith, values, purpose",
            "You are a wise spiritual advisor focused on aligning decisions with core values and long-term flourishing."
        )
    ]

    // MARK: - Published State

    @Published private(set) var boards: [BereanAdvisoryBoard] = []
    @Published private(set) var isLoading = false

    // MARK: - Private

    private let db = Firestore.firestore()
    private lazy var functions = Functions.functions(region: "us-central1")

    private var currentUID: String {
        get throws {
            guard let uid = Auth.auth().currentUser?.uid else {
                throw BereanAdvisoryBoardError.notAuthenticated
            }
            return uid
        }
    }

    private func requireFeature() throws {
        guard AMENFeatureFlags.shared.bereanOSAdvisoryBoardsEnabled else {
            throw BereanAdvisoryBoardError.featureDisabled
        }
    }

    // MARK: - Public API

    /// Fetches all advisory boards for the current user.
    func fetchBoards() async throws {
        try requireFeature()
        let uid = try currentUID
        isLoading = true
        defer { isLoading = false }

        let snapshot = try await db
            .collection(BereanOSFirestore.advisoryBoards(uid: uid))
            .order(by: "createdAt", descending: true)
            .getDocuments()

        boards = try snapshot.documents.compactMap { doc in
            try doc.data(as: BereanAdvisoryBoard.self)
        }
    }

    /// Creates a new advisory board and writes it to Firestore.
    @discardableResult
    func createBoard(name: String, boardType: String, projectId: String?) async throws -> BereanAdvisoryBoard {
        try requireFeature()
        let uid = try currentUID

        let boardId = db
            .collection(BereanOSFirestore.advisoryBoards(uid: uid))
            .document()
            .documentID

        let board = BereanAdvisoryBoard(
            id: boardId,
            ownerUid: uid,
            name: name,
            boardType: boardType,
            advisors: [],
            projectId: projectId,
            createdAt: Date()
        )

        let encoder = Firestore.Encoder()
        let data = try encoder.encode(board)
        try await db
            .collection(BereanOSFirestore.advisoryBoards(uid: uid))
            .document(boardId)
            .setData(data)

        boards.insert(board, at: 0)
        return board
    }

    /// Adds an advisor to an existing board and updates Firestore.
    func addAdvisor(_ advisor: BereanAIAdvisor, boardId: String) async throws {
        try requireFeature()
        let uid = try currentUID

        guard let idx = boards.firstIndex(where: { $0.id == boardId }) else {
            throw BereanAdvisoryBoardError.boardNotFound
        }

        var updated = boards[idx]
        updated.advisors.append(advisor)
        boards[idx] = updated

        let encoder = Firestore.Encoder()
        let data = try encoder.encode(updated)
        try await db
            .collection(BereanOSFirestore.advisoryBoards(uid: uid))
            .document(boardId)
            .setData(data)
    }

    /// Consults the board by calling the `bereanConsultAdvisoryBoard` Cloud Function.
    func consultBoard(boardId: String, question: String) async throws -> [BereanPerspective] {
        try requireFeature()
        _ = try currentUID

        guard let board = boards.first(where: { $0.id == boardId }) else {
            throw BereanAdvisoryBoardError.boardNotFound
        }

        let advisorsPayload: [[String: String]] = board.advisors.map { advisor in
            [
                "id": advisor.id,
                "role": advisor.role,
                "specialization": advisor.specialization,
                "systemPrompt": advisor.systemPrompt
            ]
        }

        let payload: [String: Any] = [
            "question": question,
            "advisors": advisorsPayload
        ]

        let result = try await functions
            .httpsCallable("bereanConsultAdvisoryBoard")
            .call(payload)

        guard let resultData = result.data as? [String: Any],
              let perspectivesRaw = resultData["perspectives"] as? [[String: Any]] else {
            throw BereanAdvisoryBoardError.consultFailed("Invalid response from advisor board.")
        }

        let perspectives: [BereanPerspective] = perspectivesRaw.compactMap { dict in
            guard let id = dict["id"] as? String,
                  let perspectiveType = dict["perspectiveType"] as? String,
                  let summary = dict["summary"] as? String else { return nil }
            return BereanPerspective(
                id: id,
                perspectiveType: perspectiveType,
                summary: summary,
                agreements: dict["agreements"] as? [String] ?? [],
                disagreements: dict["disagreements"] as? [String] ?? [],
                tradeoffs: dict["tradeoffs"] as? [String] ?? [],
                unknowns: dict["unknowns"] as? [String] ?? []
            )
        }

        return perspectives
    }
}
