import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import SwiftUI

enum TheologicalContext: String, Codable {
    case scriptureReference, doctrinalClaim, prayerContent, counseling, general
}

enum TheologicalSeverity: String, Codable {
    case note, caution, warning, blocked
}

struct TheologicalConcern {
    let severity: TheologicalSeverity
    let description: String
    let affectedText: String
}

struct TheologicalValidation {
    let isAcceptable: Bool
    let concerns: [TheologicalConcern]
    let suggestedRevision: String?
}

@MainActor final class TheologicalGuardrailsService: ObservableObject {
    static let shared = TheologicalGuardrailsService()
    private init() {}

    func validateContent(_ text: String, context: TheologicalContext) async throws -> TheologicalValidation {
        guard AMENFeatureFlags.shared.theologicalGuardrailsEnabled else {
            return TheologicalValidation(isAcceptable: true, concerns: [], suggestedRevision: nil)
        }
        dlog("[TheologicalGuardrailsService] validateContent context=\(context.rawValue) length=\(text.count)")
        let payload: [String: Any] = ["text": text, "context": context.rawValue]
        do {
            let result = try await Functions.functions().httpsCallable("validateTheologicalContent").call(payload)
            guard let data = result.data as? [String: Any] else {
                throw NSError(domain: "TheologicalGuardrails", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }
            let isAcceptable = data["isAcceptable"] as? Bool ?? true
            let suggestedRevision = data["suggestedRevision"] as? String
            let concernDicts = data["concerns"] as? [[String: Any]] ?? []
            let concerns: [TheologicalConcern] = concernDicts.compactMap { dict in
                guard let severityRaw = dict["severity"] as? String,
                      let severity = TheologicalSeverity(rawValue: severityRaw),
                      let description = dict["description"] as? String,
                      let affectedText = dict["affectedText"] as? String else { return nil }
                return TheologicalConcern(severity: severity, description: description, affectedText: affectedText)
            }
            return TheologicalValidation(isAcceptable: isAcceptable, concerns: concerns, suggestedRevision: suggestedRevision)
        } catch {
            dlog("[TheologicalGuardrailsService] validateContent error: \(error)")
            throw error
        }
    }
}
