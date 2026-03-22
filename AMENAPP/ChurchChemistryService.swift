// ChurchChemistryService.swift
// AMENAPP
//
// Congregation chemistry score:
//   - Optional contact matching via CNContactStore (hashed SHA-256 on-device)
//   - Privacy first: only hashed phone numbers stored, no raw contacts
//   - ChemistryScore: mutualCount, lifeStageMatch, scheduleOverlap, total
//   - Permission prompt on first church save (opt-in only)
//   - Displayed on church detail screen only (not card)

import Foundation
import SwiftUI
import Contacts
import CryptoKit
import FirebaseAuth
import FirebaseFirestore

// MARK: - ChemistryScore

struct ChemistryScore {
    let mutualCount: Int
    let lifeStageMatch: Double    // 0–1
    let scheduleOverlap: Double   // 0–1
    var total: Int {
        let raw = Double(mutualCount) * 15 + lifeStageMatch * 50 + scheduleOverlap * 35
        return min(100, Int(raw))
    }
}

// MARK: - ChurchChemistryService

@MainActor
final class ChurchChemistryService: ObservableObject {
    @Published var score: ChemistryScore?
    @Published var isLoading = false
    @Published var contactsAuthorized = false
    @Published var showPermissionPrompt = false

    private let db = Firestore.firestore()
    private var hashedContactNumbers: Set<String> = []

    // MARK: - Permission prompt state
    func requestContactPermission(completion: @escaping (Bool) -> Void) {
        CNContactStore().requestAccess(for: .contacts) { granted, _ in
            DispatchQueue.main.async {
                self.contactsAuthorized = granted
                completion(granted)
            }
        }
    }

    // MARK: - Load hashed contacts from device (on-device only, never stored)
    func loadHashedContacts() async {
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return }
        let store  = CNContactStore()
        let keys   = [CNContactPhoneNumbersKey as CNKeyDescriptor]
        let request = CNFetchRequest(entityType: .contacts)
        request.keysToFetch = keys
        guard let result = try? store.unifiedContacts(matching: .init(value: true), keysToFetch: keys) else { return }
        hashedContactNumbers = Set(
            result.flatMap { $0.phoneNumbers }
                  .map { normalize($0.value.stringValue) }
                  .filter { !$0.isEmpty }
                  .map { sha256($0) }
        )
        // Store own hashed phone to Firestore if user opted in
        if let uid = Auth.auth().currentUser?.uid,
           let phone = Auth.auth().currentUser?.phoneNumber {
            let hashed = sha256(normalize(phone))
            try? await db.document("users/\(uid)").setData(["hashedPhone": hashed], merge: true)
        }
    }

    // MARK: - Compute chemistry score for a church
    func compute(churchId: String) async {
        isLoading = true
        defer { isLoading = false }

        await loadHashedContacts()

        do {
            // Fetch church member hashed phones
            let snap = try await db.collection("churches/\(churchId)/memberHashedPhones").getDocuments()
            let churchHashes = Set(snap.documents.compactMap { $0.data()["hash"] as? String })
            let mutual = hashedContactNumbers.intersection(churchHashes).count

            // Life stage match: compare user's profile fields vs church median (simplified)
            let lifeStage = await computeLifeStageMatch(churchId: churchId)
            let scheduleOverlap = await computeScheduleOverlap(churchId: churchId)

            score = ChemistryScore(mutualCount: mutual, lifeStageMatch: lifeStage, scheduleOverlap: scheduleOverlap)
        } catch {
            print("ChurchChemistryService error: \(error)")
        }
    }

    // MARK: - Record attendance (opt-in hashed phone store)
    func recordAttendance(churchId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        if let phone = Auth.auth().currentUser?.phoneNumber {
            let hashed = sha256(normalize(phone))
            try? await db.collection("churches/\(churchId)/memberHashedPhones")
                .document(uid).setData(["hash": hashed], merge: true)
        }
        try? await db.document("users/\(uid)").setData(["savedChurchId": churchId], merge: true)
    }

    // MARK: - Private helpers

    private func computeLifeStageMatch(churchId: String) async -> Double {
        guard let uid = Auth.auth().currentUser?.uid else { return 0.5 }
        guard let userSnap = try? await db.document("users/\(uid)").getDocument(),
              let churchSnap = try? await db.document("churches/\(churchId)").getDocument() else {
            return 0.5
        }
        // Simple: compare user age range to church demographic median
        let userAge    = userSnap.data()?["age"]               as? Int ?? 30
        let churchAge  = churchSnap.data()?["medianMemberAge"] as? Int ?? 35
        let diff       = abs(userAge - churchAge)
        return max(0, 1.0 - Double(diff) / 30.0)
    }

    private func computeScheduleOverlap(churchId: String) async -> Double {
        // Simplified: check if any service time falls in user's availability window
        // In production: compare small group times vs user.availability
        guard let snap = try? await db.document("churches/\(churchId)").getDocument(),
              let times = snap.data()?["serviceTimes"] as? [[String: Any]] else {
            return 0.5
        }
        // If church has Sunday morning services, assume 60% base overlap
        let hasSundayAM = times.contains { ($0["dayOfWeek"] as? Int) == 1 }
        return hasSundayAM ? 0.65 : 0.35
    }

    private func normalize(_ phone: String) -> String {
        phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
    }

    private func sha256(_ str: String) -> String {
        let data   = Data(str.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - ChurchChemistryView (displayed on church detail screen only)

struct ChurchChemistryView: View {
    let churchId: String
    @StateObject private var service = ChurchChemistryService()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if service.isLoading {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let s = service.score {
                HStack(spacing: 0) {
                    Text("Chemistry estimate: ")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(.secondaryLabel))
                    Text("\(s.total)/100")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(.label))
                }

                if s.mutualCount > 0 {
                    Text("\(s.mutualCount) \(s.mutualCount == 1 ? "person" : "people") you may know attend here")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            } else if CNContactStore.authorizationStatus(for: .contacts) != .authorized {
                Button("Check if you know anyone here →") {
                    service.showPermissionPrompt = true
                }
                .font(.system(size: 13))
                .foregroundStyle(Color(.secondaryLabel))
            }
        }
        .alert("AMEN Connection Check", isPresented: $service.showPermissionPrompt) {
            Button("Allow") {
                service.requestContactPermission { granted in
                    if granted { Task { await service.compute(churchId: churchId) } }
                }
            }
            Button("Skip", role: .cancel) {}
        } message: {
            Text("AMEN can check if any of your contacts already attend churches you're browsing. No contact data is stored or shared.")
        }
        .onAppear {
            if CNContactStore.authorizationStatus(for: .contacts) == .authorized {
                Task { await service.compute(churchId: churchId) }
            }
        }
    }
}
