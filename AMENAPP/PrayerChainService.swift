//
//  PrayerChainService.swift
//  AMENAPP
//
//  Structured cascading group prayer chains.
//  A prayer chain is a sequential prayer relay where participants
//  commit to praying in order, forming a continuous chain of intercession.
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Models

struct PrayerChain: Identifiable, Codable {
    var id: String = UUID().uuidString
    var title: String
    var description: String
    var creatorId: String
    var creatorName: String
    var category: PrayerChainCategory
    var participants: [ChainParticipant]
    var status: ChainStatus
    var createdAt: Date
    var scheduledAt: Date?
    var completedAt: Date?
    var currentIndex: Int  // Which participant is currently praying
    var isPrivate: Bool

    enum PrayerChainCategory: String, Codable, CaseIterable {
        case healing = "Healing"
        case protection = "Protection"
        case guidance = "Guidance"
        case gratitude = "Gratitude"
        case intercession = "Intercession"
        case revival = "Revival"
        case community = "Community"
        case personal = "Personal"

        var icon: String {
            switch self {
            case .healing: return "heart.fill"
            case .protection: return "shield.fill"
            case .guidance: return "compass.drawing"
            case .gratitude: return "hands.clap.fill"
            case .intercession: return "person.2.fill"
            case .revival: return "flame.fill"
            case .community: return "person.3.fill"
            case .personal: return "person.fill"
            }
        }
    }

    enum ChainStatus: String, Codable {
        case gathering    // Collecting participants
        case active       // Chain is in progress
        case completed    // All participants have prayed
        case cancelled
    }
}

struct ChainParticipant: Identifiable, Codable {
    var id: String  // User ID
    var name: String
    var profileImageURL: String?
    var status: ParticipantStatus
    var prayedAt: Date?
    var prayerNote: String?  // Optional note they leave after praying

    enum ParticipantStatus: String, Codable {
        case waiting     // Hasn't been their turn yet
        case active      // Currently their turn to pray
        case completed   // Finished praying
        case skipped     // Didn't respond in time
    }
}

// MARK: - Service

@MainActor
class PrayerChainService: ObservableObject {
    static let shared = PrayerChainService()
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    @Published var activeChains: [PrayerChain] = []
    @Published var myChains: [PrayerChain] = []
    @Published var isLoading = false

    private init() {}

    // MARK: - Create Chain

    func createChain(
        title: String,
        description: String,
        category: PrayerChain.PrayerChainCategory,
        isPrivate: Bool,
        scheduledAt: Date? = nil
    ) async throws -> String {
        guard let user = Auth.auth().currentUser else { throw PrayerChainError.notAuthenticated }

        let chain = PrayerChain(
            title: title,
            description: description,
            creatorId: user.uid,
            creatorName: user.displayName ?? "Someone",
            category: category,
            participants: [
                ChainParticipant(
                    id: user.uid,
                    name: user.displayName ?? "Someone",
                    profileImageURL: user.photoURL?.absoluteString,
                    status: .waiting
                )
            ],
            status: .gathering,
            createdAt: Date(),
            scheduledAt: scheduledAt,
            currentIndex: 0,
            isPrivate: isPrivate
        )

        let data = try JSONEncoder().encode(chain)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        try await db.collection("prayerChains").document(chain.id).setData(dict)
        return chain.id
    }

    // MARK: - Join Chain

    func joinChain(_ chainId: String) async throws {
        guard let user = Auth.auth().currentUser else { throw PrayerChainError.notAuthenticated }

        let participant = ChainParticipant(
            id: user.uid,
            name: user.displayName ?? "Someone",
            profileImageURL: user.photoURL?.absoluteString,
            status: .waiting
        )

        let data = try JSONEncoder().encode(participant)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        try await db.collection("prayerChains").document(chainId).updateData([
            "participants": FieldValue.arrayUnion([dict])
        ])
    }

    // MARK: - Start Chain

    func startChain(_ chainId: String) async throws {
        try await db.collection("prayerChains").document(chainId).updateData([
            "status": PrayerChain.ChainStatus.active.rawValue,
            "currentIndex": 0
        ])
        // Notify first participant via Cloud Function
    }

    // MARK: - Complete My Turn

    func completeTurn(chainId: String, note: String?) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw PrayerChainError.notAuthenticated }

        let ref = db.collection("prayerChains").document(chainId)
        let doc = try await ref.getDocument()
        guard var chain = try? doc.data(as: PrayerChain.self) else { return }

        // Mark current participant as completed
        if let idx = chain.participants.firstIndex(where: { $0.id == uid && $0.status == .active }) {
            chain.participants[idx].status = .completed
            chain.participants[idx].prayedAt = Date()
            chain.participants[idx].prayerNote = note
        }

        // Advance to next participant
        let nextIndex = chain.currentIndex + 1
        if nextIndex < chain.participants.count {
            chain.participants[nextIndex].status = .active
            chain.currentIndex = nextIndex
            chain.status = .active
        } else {
            // Chain complete
            chain.status = .completed
            chain.completedAt = Date()
        }

        let data = try JSONEncoder().encode(chain)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        try await ref.setData(dict, merge: true)
    }

    // MARK: - Listen

    func startListening() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true

        listener = db.collection("prayerChains")
            .whereField("status", in: [
                PrayerChain.ChainStatus.gathering.rawValue,
                PrayerChain.ChainStatus.active.rawValue
            ])
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let docs = snapshot?.documents else { return }
                let chains = docs.compactMap { try? $0.data(as: PrayerChain.self) }
                self.activeChains = chains.filter { !$0.isPrivate || $0.participants.contains(where: { $0.id == uid }) }
                self.myChains = chains.filter { $0.creatorId == uid || $0.participants.contains(where: { $0.id == uid }) }
                self.isLoading = false
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    enum PrayerChainError: Error {
        case notAuthenticated
        case chainNotFound
    }
}
