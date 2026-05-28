// SpacesCreationViewModel.swift
// AMENAPP — Spaces v2 Creation Wizard (Agent D)
//
// @MainActor ViewModel that drives all four creation-wizard steps.
// Berean scaffold is fetched via the existing `bereanChatProxyStream` SSE endpoint.
// Firestore writes use the schema from CONTRACT_A.md (00_MASTER_CONTRACT.md).

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - CreationStep

extension SpacesCreationViewModel {
    enum CreationStep: Int, CaseIterable {
        case intent   = 0
        case scaffold = 1
        case pricing  = 2
        case confirm  = 3
    }
}

// MARK: - SpacesCreationViewModel

@MainActor
final class SpacesCreationViewModel: ObservableObject {

    // MARK: - Published state

    @Published var draft: SpaceCreationDraft = SpaceCreationDraft()
    @Published var currentStep: CreationStep = .intent
    @Published var isLoadingScaffold: Bool = false
    /// Live SSE delta accumulation shown in the scaffold step typewriter view.
    @Published var scaffoldStreamBuffer: String = ""
    @Published var scaffoldError: String? = nil
    @Published var isCreating: Bool = false
    @Published var creationError: String? = nil
    @Published var isComplete: Bool = false

    // MARK: - Private

    private let db = Firestore.firestore()
    /// SSE endpoint — reuses existing `bereanChatProxyStream` HTTP function.
    private let sseURL = URL(string: "https://us-central1-amen-5e359.cloudfunctions.net/bereanChatProxyStream")!

    // MARK: - Step 1: Intent

    /// Sets the chosen intent on the draft and advances to the scaffold step
    /// if the title is already non-empty.
    func selectIntent(_ intent: SpaceCreationIntent) {
        draft.intent = intent
        if draft.canAdvanceFromIntent {
            advance()
        }
    }

    // MARK: - Step 2: Scaffold

    /// Requests Berean to generate a scaffold via SSE streaming.
    /// Streams deltas into `scaffoldStreamBuffer`; on completion parses `BereanScaffoldResponse`.
    /// Never crashes on parse failure — falls back to `BereanScaffoldResponse.empty`.
    func requestScaffold() async {
        guard let intent = draft.intent else { return }
        guard !isLoadingScaffold else { return }

        isLoadingScaffold = true
        scaffoldStreamBuffer = ""
        scaffoldError = nil

        guard let token = try? await Auth.auth().currentUser?.getIDToken() else {
            scaffoldError = "Sign-in required to generate a scaffold."
            isLoadingScaffold = false
            return
        }

        var request = URLRequest(url: sseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "intent": intent.rawValue,
            "title": draft.title,
            "scaffoldMode": true
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            scaffoldError = "Failed to build request."
            isLoadingScaffold = false
            return
        }

        do {
            let (bytes, _) = try await URLSession.shared.bytes(for: request)
            var accumulator = ""

            for try await line in bytes.lines {
                // SSE lines are prefixed with "data: "
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)

                guard let lineData = payload.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
                else { continue }

                // Terminal frame
                if json["done"] as? Bool == true {
                    break
                }

                // Error frame
                if let errorMsg = json["error"] as? String {
                    scaffoldError = errorMsg
                    isLoadingScaffold = false
                    return
                }

                // Delta frame
                if let delta = json["delta"] as? String {
                    accumulator += delta
                    scaffoldStreamBuffer = accumulator
                }
            }

            // Parse the accumulated buffer as BereanScaffoldResponse
            draft.scaffold = parseScaffold(from: accumulator)

        } catch {
            scaffoldError = "Berean is unavailable. You can continue without a scaffold."
        }

        isLoadingScaffold = false
    }

    /// Skips scaffold — advances to pricing without accepting.
    func skipScaffold() {
        draft.scaffoldAccepted = false
        advance()
    }

    /// Accepts the scaffold — marks it as accepted and advances to pricing.
    func acceptScaffold() {
        draft.scaffoldAccepted = true
        advance()
    }

    // MARK: - Step 3: Pricing

    func setPricing(_ state: SpacesPricingState) {
        draft.pricingState = state
    }

    // MARK: - Step 4: Confirm + Create

    /// Executes the full creation pipeline:
    /// 1. Writes `spaces/{id}` (AmenSpaceExtended fields)
    /// 2. Writes creator `SpaceMember` to `spaces/{id}/members/{creatorUserId}`
    /// 3. If scaffold accepted + study: writes `studies/{id}` + `blocks` subcollection
    /// 4. If scaffold accepted + non-study: writes `threads/{id}` for each starterPrompt
    func createSpace(communityId: String, creatorUserId: String) async {
        guard let intent = draft.intent else {
            creationError = "Please select a Space type."
            return
        }

        isCreating = true
        creationError = nil

        do {
            // --- 1. Write the space document ---
            let spacesRef = db.collection("spaces")
            let spaceDoc  = spacesRef.document()
            let spaceId   = spaceDoc.documentID
            let now       = Date()

            var spaceData: [String: Any] = [
                "communityId":   communityId,
                "type":          intent.mapsToSpaceV2Type.rawValue,
                "title":         draft.title,
                "createdBy":     creatorUserId,
                "createdAt":     Timestamp(date: now),
                "accessPolicy":  draft.pricingState.policy.rawValue,
                "sharedWith":    [String](),
                "isDeleted":     false
            ]

            if !draft.description.isEmpty {
                spaceData["description"] = draft.description
            }

            if let priceConfig = draft.pricingState.priceConfig {
                var pc: [String: Any] = [
                    "amountCents": priceConfig.amountCents,
                    "currency":    priceConfig.currency
                ]
                if let interval = priceConfig.interval {
                    pc["interval"] = interval
                }
                spaceData["priceConfig"] = pc
            }

            try await spaceDoc.setData(spaceData)

            // --- 2. Write creator member ---
            let memberData: [String: Any] = [
                "role":     "owner",
                "access":   "granted",
                "joinedAt": Timestamp(date: now)
                // homeCommunityId intentionally omitted (nil = owning community member)
            ]
            try await spaceDoc.collection("members").document(creatorUserId).setData(memberData)

            // --- 3. Scaffold writes ---
            if let scaffold = draft.scaffold, draft.scaffoldAccepted {
                if intent == .study {
                    try await writeStudyScaffold(
                        scaffold: scaffold,
                        spaceRef: spaceDoc,
                        title: draft.title,
                        creatorUserId: creatorUserId,
                        now: now
                    )
                } else {
                    try await writeThreadSeeds(
                        scaffold: scaffold,
                        spaceRef: spaceDoc,
                        creatorUserId: creatorUserId,
                        now: now
                    )
                }
            }

            draft.createdSpaceId = spaceId
            isComplete = true

        } catch {
            creationError = error.localizedDescription
        }

        isCreating = false
    }

    // MARK: - Navigation helpers

    func goBack() {
        let prev = currentStep.rawValue - 1
        guard prev >= 0, let step = CreationStep(rawValue: prev) else { return }
        currentStep = step
    }

    // MARK: - Private helpers

    private func advance() {
        let next = currentStep.rawValue + 1
        guard next < CreationStep.allCases.count,
              let step = CreationStep(rawValue: next) else { return }
        currentStep = step
    }

    /// Parses the accumulated SSE buffer as `BereanScaffoldResponse`.
    /// Falls back to `BereanScaffoldResponse.empty` on any failure — never crashes.
    private func parseScaffold(from buffer: String) -> BereanScaffoldResponse {
        guard !buffer.isEmpty,
              let bufferData = buffer.data(using: .utf8)
        else { return .empty }

        do {
            let decoded = try JSONDecoder().decode(BereanScaffoldResponse.self, from: bufferData)
            return decoded
        } catch {
            // Graceful fallback: return empty scaffold rather than crashing
            return .empty
        }
    }

    /// Writes a `studies/{id}` doc + `blocks` subcollection from the scaffold.
    private func writeStudyScaffold(
        scaffold: BereanScaffoldResponse,
        spaceRef: DocumentReference,
        title: String,
        creatorUserId: String,
        now: Date
    ) async throws {
        let studyRef = spaceRef.collection("studies").document()

        var studyData: [String: Any] = [
            "title":       title,
            "passageRefs": scaffold.passageRefs,
            "createdBy":   creatorUserId,
            "createdAt":   Timestamp(date: now)
        ]
        if let cadence = scaffold.cadence {
            studyData["cadence"] = cadence
        }
        try await studyRef.setData(studyData)

        // Write each ScaffoldBlock as a ChurchNoteBlock-compatible document
        for block in scaffold.blockDrafts {
            let blockData: [String: Any] = [
                "id":        block.id,
                "type":      block.resolvedBlockType,
                "text":      block.text,
                "textRuns":  [[
                    "text":      block.text,
                    "highlight": NSNull()
                ]],
                "tags":      [String](),
                "createdAt": Timestamp(date: now),
                "updatedAt": Timestamp(date: now)
            ]
            try await studyRef.collection("blocks").document(block.id).setData(blockData)
        }
    }

    /// Writes one `threads/{id}` document per starter prompt.
    private func writeThreadSeeds(
        scaffold: BereanScaffoldResponse,
        spaceRef: DocumentReference,
        creatorUserId: String,
        now: Date
    ) async throws {
        for prompt in scaffold.starterPrompts {
            guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let threadData: [String: Any] = [
                "title":         prompt,
                "createdBy":     creatorUserId,
                "createdAt":     Timestamp(date: now),
                "lastMessageAt": Timestamp(date: now)
            ]
            try await spaceRef.collection("threads").document().setData(threadData)
        }
    }
}
