//
//  AmenReportAbuseService.swift
//  AMENAPP
//
//  Client-side abuse reporting service.
//  Submits reports to the Trust + Safety OS backend.
//  Handles emergency escalation categories.
//  Preserves evidence server-side for critical reports.
//

import Foundation
import SwiftUI
import FirebaseFunctions

@MainActor
final class AmenReportAbuseService: ObservableObject {

    static let shared = AmenReportAbuseService()

    private let functions = Functions.functions()
    private let flags = AmenSafetyFeatureFlags.shared

    @Published var isSubmitting: Bool = false
    @Published var submittedReport: TSAbuseReportResult?
    @Published var submissionError: String?

    private init() {}

    // MARK: - Submit report

    func submitReport(
        targetUid: String? = nil,
        contentId: String? = nil,
        contentType: ContentSurface? = nil,
        category: TSReportCategory,
        details: String? = nil
    ) async -> TSAbuseReportResult? {
        guard flags.reportingEnabled else { return nil }

        isSubmitting = true
        submissionError = nil

        var params: [String: Any] = [
            "category": category.rawValue,
        ]
        if let uid = targetUid { params["targetUid"] = uid }
        if let cid = contentId { params["contentId"] = cid }
        if let ct = contentType { params["contentType"] = ct.rawValue }
        if let d = details { params["details"] = d }

        do {
            let result = try await functions.httpsCallable("submitAbuseReport").call(params)
            guard let data = result.data as? [String: Any] else {
                submissionError = "Something went wrong. Please try again."
                isSubmitting = false
                return nil
            }
            let report = TSAbuseReportResult(
                reportId: data["reportId"] as? String ?? UUID().uuidString,
                status: TSReportStatus(rawValue: data["status"] as? String ?? "submitted") ?? .submitted,
                contentQuarantined: data["contentQuarantined"] as? Bool ?? false,
                escalated: data["escalated"] as? Bool ?? false,
                policyVersion: data["policyVersion"] as? String ?? AmenTrustSafetyOSVersion
            )
            submittedReport = report
            isSubmitting = false
            return report
        } catch {
            submissionError = "Unable to submit report. Please try again."
            isSubmitting = false
            return nil
        }
    }

    // MARK: - Fetch my reports

    func fetchMyReports() async -> [TSAbuseReportResult] {
        do {
            let result = try await functions.httpsCallable("getMyAbuseReports").call([:])
            guard let array = result.data as? [[String: Any]] else { return [] }
            return array.compactMap { data in
                TSAbuseReportResult(
                    reportId: data["reportId"] as? String ?? "",
                    status: TSReportStatus(rawValue: data["status"] as? String ?? "submitted") ?? .submitted,
                    contentQuarantined: data["contentQuarantined"] as? Bool ?? false,
                    escalated: data["escalated"] as? Bool ?? false,
                    policyVersion: data["policyVersion"] as? String ?? AmenTrustSafetyOSVersion
                )
            }
        } catch { return [] }
    }

    // MARK: - Submit appeal

    func submitAppeal(strikeId: String, reason: String) async -> String? {
        do {
            let result = try await functions.httpsCallable("submitAppeal").call([
                "strikeId": strikeId,
                "reason": reason,
            ])
            guard let data = result.data as? [String: Any] else { return nil }
            return data["appealId"] as? String
        } catch { return nil }
    }

    func reset() {
        submittedReport = nil
        submissionError = nil
        isSubmitting = false
    }
}
