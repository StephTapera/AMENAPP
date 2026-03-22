// ChurchTeachingStyleService.swift
// AMENAPP
//
// Pastor teaching style compatibility:
//   - inferUserLearningStyle: analyzes user's church notes → analytical/narrative/illustrative/applicational
//   - inferPastorStyle: aggregates church notes → structured/expository/narrative/topical
//   - Compatibility matrix: maps learner style × pastor style → percentage
//   - Displayed on church detail screen

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - Teaching Style Enums

enum LearnerStyle: String {
    case analytical     = "analytical"
    case narrative      = "narrative"
    case illustrative   = "illustrative"
    case applicational  = "applicational"
    case unknown        = ""
}

enum PastorStyle: String {
    case structured  = "structured"
    case expository  = "expository"
    case narrative   = "narrative"
    case topical     = "topical"
    case unknown     = ""
}

// MARK: - Compatibility matrix

extension LearnerStyle {
    func compatibility(with pastor: PastorStyle) -> Int {
        let matrix: [LearnerStyle: [PastorStyle: Int]] = [
            .analytical:    [.expository: 95, .structured: 85, .topical: 60, .narrative: 50],
            .narrative:     [.narrative:   95, .topical: 80, .expository: 65, .structured: 55],
            .illustrative:  [.narrative:   90, .topical: 85, .structured: 65, .expository: 55],
            .applicational: [.topical:     90, .structured: 80, .narrative: 70, .expository: 60],
        ]
        return matrix[self]?[pastor] ?? 70
    }
}

// MARK: - ChurchTeachingStyleService

@MainActor
final class ChurchTeachingStyleService: ObservableObject {
    @Published var learnerStyle: LearnerStyle = .unknown
    @Published var pastorStyle:  PastorStyle  = .unknown
    @Published var compatibilityPct: Int?
    @Published var isLoading = false

    private let db        = Firestore.firestore()
    private let functions = Functions.functions()

    // MARK: - Load

    func load(churchId: String) async {
        isLoading = true
        defer { isLoading = false }

        async let ls = loadLearnerStyle()
        async let ps = loadPastorStyle(churchId: churchId)
        let (l, p) = await (ls, ps)

        learnerStyle     = l
        pastorStyle      = p
        if l != .unknown && p != .unknown {
            compatibilityPct = l.compatibility(with: p)
        }
    }

    // MARK: - Learner style (cached in Firestore, recomputed via Cloud Function)

    private func loadLearnerStyle() async -> LearnerStyle {
        guard let uid = Auth.auth().currentUser?.uid else { return .unknown }
        if let snap = try? await db.document("users/\(uid)").getDocument(),
           let style = snap.data()?["learningStyle"] as? String,
           !style.isEmpty {
            return LearnerStyle(rawValue: style) ?? .unknown
        }
        // Call Cloud Function to infer
        do {
            let result = try await functions.httpsCallable("inferUserLearningStyle").call(["uid": uid])
            if let style = (result.data as? [String: Any])?["style"] as? String {
                return LearnerStyle(rawValue: style) ?? .unknown
            }
        } catch {}
        return .unknown
    }

    private func loadPastorStyle(churchId: String) async -> PastorStyle {
        if let snap = try? await db.document("churches/\(churchId)").getDocument(),
           let style = snap.data()?["pastorStyle"] as? String,
           !style.isEmpty {
            return PastorStyle(rawValue: style) ?? .unknown
        }
        // Call Cloud Function to infer
        do {
            let result = try await functions.httpsCallable("inferPastorStyle").call(["churchId": churchId])
            if let style = (result.data as? [String: Any])?["style"] as? String {
                return PastorStyle(rawValue: style) ?? .unknown
            }
        } catch {}
        return .unknown
    }
}

// MARK: - TeachingCompatibilityView

struct TeachingCompatibilityView: View {
    let churchId: String
    @StateObject private var service = ChurchTeachingStyleService()

    var body: some View {
        Group {
            if service.isLoading {
                EmptyView()
            } else if let pct = service.compatibilityPct {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(.secondaryLabel))
                    Text("Teaching style match: ")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(.secondaryLabel))
                    + Text("\(pct)%")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(.label))
                }
            }
        }
        .task { await service.load(churchId: churchId) }
    }
}
