// AIMetadata.swift
// AMENAPP
// AI disclosure metadata for universal content nodes.

import Foundation

struct AIMetadata: Codable, Equatable {
    var usedAI: Bool
    var provider: String?
    var model: String?
    var disclosureLabel: String?
    var promptSummary: String?
    var confidence: Double?
    var generatedAt: Date?
    var safetyLabels: [String]?

    static let none = AIMetadata(usedAI: false)
}
