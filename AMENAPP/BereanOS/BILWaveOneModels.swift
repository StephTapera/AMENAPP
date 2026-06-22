// BILWaveOneModels.swift
// AMENAPP — Berean Intelligence Layer Wave 1
//
// Compiled SwiftUI scaffolding for BI-01...BI-05. All user-visible entry
// points remain hidden unless bil_enabled and the feature flag are true.

import Foundation
import FirebaseRemoteConfig

struct BILWaveOneFeatureGate {
    static var isWaveOneEnabled: Bool {
        isEnabled("bil_compactor") ||
        isEnabled("bil_ledger") ||
        isEnabled("bil_branching") ||
        isEnabled("bil_source_cards") ||
        isEnabled("bil_context_packages")
    }

    static var compactorEnabled: Bool { isEnabled("bil_compactor") }
    static var ledgerEnabled: Bool { isEnabled("bil_ledger") }
    static var branchingEnabled: Bool { isEnabled("bil_branching") }
    static var sourceCardsEnabled: Bool { isEnabled("bil_source_cards") }
    static var contextPackagesEnabled: Bool { isEnabled("bil_context_packages") }

    private static func isEnabled(_ key: String) -> Bool {
        let config = RemoteConfig.remoteConfig()
        return config.configValue(forKey: "bil_enabled").boolValue &&
            config.configValue(forKey: key).boolValue
    }
}

enum BILTier: String, CaseIterable, Identifiable {
    case tierS = "Tier S"
    case tierC = "Tier C"
    case tierP = "Tier P"

    var id: String { rawValue }

    var detail: String {
        switch self {
        case .tierS:
            return "Sealed data stays on device."
        case .tierC:
            return "Confidential data can produce consented signals."
        case .tierP:
            return "Private plaintext remains local unless an approved local engine handles it."
        }
    }
}

enum BILApprovalState: String {
    case autoApproved = "Auto-approved"
    case pendingUserApproval = "Needs review"
    case approved = "Approved"
    case rejected = "Rejected"
    case undone = "Undone"
}

struct BILSummaryFact: Identifiable {
    let id: String
    let title: String
    let detail: String
    let confidence: Double
}

struct BILLedgerPreviewEntry: Identifiable {
    let id: String
    let belief: String
    let provenance: String
    let state: String
}

struct BILConversationBranchPreview: Identifiable {
    let id: String
    let name: String
    let forkTurn: String
    let divergenceSummary: String
}

struct BILSourceCardPreview: Identifiable {
    let id: String
    let title: String
    let oneLine: String
    let citationCount: Int
    let tier: BILTier
}

struct BILContextPackagePreview: Identifiable {
    let id: String
    let name: String
    let mode: String
    let version: Int
    let sourceCount: Int
    let ledgerCount: Int
}

struct BILWaveOneSamples {
    static let facts = [
        BILSummaryFact(id: "decision", title: "Decision", detail: "Use the Romans study outline for Wednesday group prep.", confidence: 0.91),
        BILSummaryFact(id: "open-question", title: "Open question", detail: "Clarify whether the group wants a pastoral or exegetical mode next.", confidence: 0.77),
        BILSummaryFact(id: "risk", title: "Risk", detail: "Do not summarize Tier P counseling details to a server model.", confidence: 0.98)
    ]

    static let ledger = [
        BILLedgerPreviewEntry(id: "locked", belief: "The user prefers Scripture-first answers with visible citations.", provenance: "Pinned from turn 18", state: "Locked"),
        BILLedgerPreviewEntry(id: "active", belief: "Romans 8 is an active study theme this week.", provenance: "Compaction episode", state: "Active"),
        BILLedgerPreviewEntry(id: "conflict", belief: "Leadership tone should stay gentle, not directive.", provenance: "Source card", state: "Conflict review")
    ]

    static let branches = [
        BILConversationBranchPreview(id: "main", name: "Main study", forkTurn: "Turn 14", divergenceSummary: "Keeps the original pastoral answer path."),
        BILConversationBranchPreview(id: "research", name: "Historical context", forkTurn: "Turn 17", divergenceSummary: "Explores authorship and first-century background."),
        BILConversationBranchPreview(id: "group", name: "Small group plan", forkTurn: "Turn 19", divergenceSummary: "Converts insights into a discussion guide.")
    ]

    static let sourceCards = [
        BILSourceCardPreview(id: "sermon", title: "Sermon notes — Romans 8", oneLine: "A source card with outline, entities, and normalized Scripture refs.", citationCount: 6, tier: .tierC),
        BILSourceCardPreview(id: "pdf", title: "Imported PDF commentary", oneLine: "Paragraph summary plus citation locators, without raw text leakage.", citationCount: 12, tier: .tierP),
        BILSourceCardPreview(id: "thread", title: "Thread timeline", oneLine: "Conversation-derived source card for grounded follow-up answers.", citationCount: 4, tier: .tierS)
    ]

    static let packages = [
        BILContextPackagePreview(id: "prayer", name: "Prayer companion", mode: "Prayer", version: 1, sourceCount: 3, ledgerCount: 2),
        BILContextPackagePreview(id: "study", name: "Romans study pack", mode: "Study", version: 2, sourceCount: 5, ledgerCount: 4),
        BILContextPackagePreview(id: "leadership", name: "Leader prep", mode: "Leadership", version: 1, sourceCount: 2, ledgerCount: 3)
    ]
}
