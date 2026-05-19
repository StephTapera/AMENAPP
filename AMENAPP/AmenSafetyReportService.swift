// AmenSafetyReportService.swift
// AMENAPP
// Handles user-initiated safety reports and surfaces appeal status.

import Foundation
import Combine

@MainActor
final class AmenSafetyReportService: ObservableObject {
    static let shared = AmenSafetyReportService()

    @Published private(set) var recentReports: [SafetyReportRecord] = []
    @Published var submissionError: String?
    @Published var isSubmitting = false

    private let core = AmenSocialSafetyService.shared

    func submitReport(
        entityId: String,
        entityType: String,
        category: SafetyRiskCategory,
        description: String?,
        evidenceURLs: [String] = []
    ) async throws -> SafetyReportRecord {
        isSubmitting = true
        defer { isSubmitting = false }
        let record = try await core.createSafetyReport(
            entityId: entityId,
            entityType: entityType,
            category: category,
            description: description,
            evidenceURLs: evidenceURLs
        )
        recentReports.insert(record, at: 0)
        return record
    }

    func requestReview(contentId: String, reason: String) async throws {
        try await core.requestHumanReview(contentId: contentId, reason: reason)
    }
}
