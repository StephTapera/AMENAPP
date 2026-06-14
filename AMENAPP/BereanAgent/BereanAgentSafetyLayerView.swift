// BereanAgentSafetyLayerView.swift
// AMEN — Berean Agent Surface (BAS) · Wave 2 · Lane E
//
// Pre-share safety audit sheet. Shown before any share/post action.
// §7: "Share anyway" is ALWAYS present. No hard-blocking. All enforcement is advisory.

import SwiftUI

// MARK: - BereanAgentSafetyLayerView

/// Pre-share safety audit sheet displayed before any share or post action.
/// Surfaces `BASSafetyAudit` results with full per-check detail and advisory banners.
/// Per §7: "Share anyway" is always available — no hard-block enforced in UI.
struct BereanAgentSafetyLayerView: View {

    let audit: BASSafetyAudit
    let onShare: () -> Void
    let onRevise: () -> Void
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Overall Status

    private enum OverallStatus {
        case allPassed
        case hasAdvisory
        case hasBlocking

        var bannerColor: Color {
            switch self {
            case .allPassed:   return Color.green.opacity(0.15)
            case .hasAdvisory: return Color.orange.opacity(0.15)
            case .hasBlocking: return Color.red.opacity(0.15)
            }
        }

        var bannerForeground: Color {
            switch self {
            case .allPassed:   return Color(hex: "1A6B2E")   // accessible green
            case .hasAdvisory: return Color(hex: "7A4500")   // accessible amber
            case .hasBlocking: return Color(hex: "6B2137")   // basWineRed
            }
        }

        var icon: String {
            switch self {
            case .allPassed:   return "checkmark.circle.fill"
            case .hasAdvisory: return "exclamationmark.triangle.fill"
            case .hasBlocking: return "xmark.circle.fill"
            }
        }

        var message: String {
            switch self {
            case .allPassed:   return "Ready to share"
            case .hasAdvisory: return "Review before sharing"
            case .hasBlocking: return "Berean recommends revising"
            }
        }

        var accessibilityDescription: String {
            switch self {
            case .allPassed:   return "All checks passed. Ready to share."
            case .hasAdvisory: return "Advisory items found. Review before sharing."
            case .hasBlocking: return "Berean recommends revising before sharing."
            }
        }

        var shareButtonLabel: String {
            switch self {
            case .allPassed: return "Share"
            default:         return "Share anyway"
            }
        }
    }

    private var overallStatus: OverallStatus {
        let failed = audit.results.filter { !$0.passed }
        if failed.contains(where: { $0.severity == .blocking }) { return .hasBlocking }
        if failed.contains(where: { $0.severity == .advisory }) { return .hasAdvisory }
        return .allPassed
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // ── Interpretation Banner ──────────────────────────────
                    if audit.isInterpretation {
                        interpretationBanner
                    }

                    // ── Audit Results ──────────────────────────────────────
                    auditResultsList

                    // ── Overall Status Banner ─────────────────────────────
                    overallStatusBanner

                    // ── Action Buttons ─────────────────────────────────────
                    actionButtons
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Color.basWarmPaper.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    headerRow
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "shield.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.basWineRed)
                .accessibilityHidden(true)

            Text("Safety Check")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.basInk)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Safety Check panel")
    }

    // MARK: - Interpretation Banner

    private var interpretationBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.quote")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(hex: "7A4500"))
                .accessibilityHidden(true)

            Text("This response includes interpretation, not direct Scripture quotation.")
                .font(.subheadline)
                .foregroundStyle(Color(hex: "7A4500"))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "FFF3CC").opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(hex: "D4A017").opacity(0.4), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Interpretation notice: This is interpretation, not direct scripture.")
    }

    // MARK: - Audit Results List

    private var auditResultsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(audit.results.enumerated()), id: \.element.id) { index, result in
                auditResultRow(result: result, isLast: index == audit.results.count - 1)
            }
        }
        .background(Color.basTan.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    private func auditResultRow(result: BASSafetyAuditResult, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Status icon
                Image(systemName: statusIcon(for: result))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(statusIconColor(for: result))
                    .frame(width: 22, alignment: .center)
                    .padding(.top, 1)
                    .accessibilityHidden(true)

                // Check name + note
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(result.check.displayName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.basInk)

                        Spacer()

                        // Severity badge
                        Text(result.severity.badgeText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(severityBadgeForeground(result.severity))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(severityBadgeBackground(result.severity))
                            .clipShape(Capsule())
                    }

                    if let note = result.note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(Color.basInk.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(rowAccessibilityLabel(for: result))

            if !isLast {
                Divider()
                    .padding(.leading, 50)
                    .opacity(0.4)
            }
        }
    }

    // MARK: - Overall Status Banner

    private var overallStatusBanner: some View {
        let status = overallStatus
        return HStack(spacing: 10) {
            Image(systemName: status.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(status.bannerForeground)
                .accessibilityHidden(true)

            Text(status.message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(status.bannerForeground)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(status.bannerColor)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(status.bannerForeground.opacity(0.2), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(status.accessibilityDescription)
        .animation(
            reduceMotion
                ? .none
                : Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8)),
            value: overallStatus.message
        )
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
                // Share / Share anyway — ALWAYS present per §7
                Button {
                    onShare()
                } label: {
                    Text(overallStatus.shareButtonLabel)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .background(Color.basWineRed)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityLabel("Share")
                .accessibilityHint("Shares this content.")

                // Revise button
                Button {
                    onRevise()
                } label: {
                    Text("Revise")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.basInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .background(Color.basTan)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityLabel("Revise")
                .accessibilityHint("Returns to edit the content before sharing.")

                // Cancel link
                Button {
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(.subheadline)
                        .foregroundStyle(Color.basInk.opacity(0.6))
                        .padding(.vertical, 6)
                }
                .accessibilityLabel("Cancel")
                .accessibilityHint("Dismisses the safety check without sharing.")
            }
        }
    }

    // MARK: - Helpers

    private func statusIcon(for result: BASSafetyAuditResult) -> String {
        if result.passed {
            return "checkmark.circle.fill"
        }
        switch result.severity {
        case .info:      return "info.circle.fill"
        case .advisory:  return "exclamationmark.triangle.fill"
        case .blocking:  return "xmark.circle.fill"
        }
    }

    private func statusIconColor(for result: BASSafetyAuditResult) -> Color {
        if result.passed {
            return Color(hex: "2E7D32")  // accessible green
        }
        switch result.severity {
        case .info:      return Color(hex: "1565C0")  // accessible blue
        case .advisory:  return Color(hex: "E65100")  // accessible amber
        case .blocking:  return Color(hex: "B71C1C")  // accessible red
        }
    }

    private func severityBadgeForeground(_ severity: BASSeverityLevel) -> Color {
        switch severity {
        case .info:     return Color(hex: "1565C0")
        case .advisory: return Color(hex: "7A4500")
        case .blocking: return Color(hex: "6B2137")
        }
    }

    private func severityBadgeBackground(_ severity: BASSeverityLevel) -> Color {
        switch severity {
        case .info:     return Color(hex: "E3F2FD")
        case .advisory: return Color(hex: "FFF3CC")
        case .blocking: return Color(hex: "FDECEA")
        }
    }

    private func rowAccessibilityLabel(for result: BASSafetyAuditResult) -> String {
        let status = result.passed ? "passed" : "needs review"
        let noteText = result.note.map { " Note: \($0)" } ?? ""
        return "\(result.check.displayName): \(status).\(noteText)"
    }
}

// MARK: - BASSafetyAuditResult display helpers

private extension BASAuditCheckKind {
    var displayName: String {
        switch self {
        case .scriptureAccuracy:      return "Scripture Accuracy"
        case .verseInContext:         return "Verse In Context"
        case .translationMatch:       return "Translation Match"
        case .theologicalConfidence:  return "Theological Confidence"
        case .harmfulAdvice:          return "Harmful Advice"
        case .manipulativeClaim:      return "Manipulative Claim"
        case .misquote:               return "Misquote Check"
        case .interpretationLabel:    return "Interpretation Label"
        }
    }
}

private extension BASSeverityLevel {
    var badgeText: String {
        switch self {
        case .info:     return "Info"
        case .advisory: return "Advisory"
        case .blocking: return "Blocking"
        }
    }
}

// MARK: - Preview

#Preview("All Passed") {
    BereanAgentSafetyLayerView(
        audit: BASSafetyAudit(
            results: [
                BASSafetyAuditResult(
                    id: UUID(),
                    check: .scriptureAccuracy,
                    passed: true,
                    severity: .info,
                    note: nil
                ),
                BASSafetyAuditResult(
                    id: UUID(),
                    check: .misquote,
                    passed: true,
                    severity: .advisory,
                    note: nil
                ),
                BASSafetyAuditResult(
                    id: UUID(),
                    check: .harmfulAdvice,
                    passed: true,
                    severity: .blocking,
                    note: nil
                )
            ],
            policy: .advisory,
            isInterpretation: false
        ),
        onShare: {},
        onRevise: {},
        onCancel: {}
    )
}

#Preview("Advisory + Interpretation") {
    BereanAgentSafetyLayerView(
        audit: BASSafetyAudit(
            results: [
                BASSafetyAuditResult(
                    id: UUID(),
                    check: .scriptureAccuracy,
                    passed: true,
                    severity: .info,
                    note: nil
                ),
                BASSafetyAuditResult(
                    id: UUID(),
                    check: .misquote,
                    passed: false,
                    severity: .advisory,
                    note: "Possible misquotation detected. Please verify the exact wording."
                ),
                BASSafetyAuditResult(
                    id: UUID(),
                    check: .interpretationLabel,
                    passed: true,
                    severity: .info,
                    note: "Content is marked as interpretation."
                )
            ],
            policy: .advisory,
            isInterpretation: true
        ),
        onShare: {},
        onRevise: {},
        onCancel: {}
    )
}

#Preview("Blocking Severity (still shareable — §7)") {
    BereanAgentSafetyLayerView(
        audit: BASSafetyAudit(
            results: [
                BASSafetyAuditResult(
                    id: UUID(),
                    check: .harmfulAdvice,
                    passed: false,
                    severity: .blocking,
                    note: "Potentially harmful guidance detected. Berean recommends revising."
                ),
                BASSafetyAuditResult(
                    id: UUID(),
                    check: .scriptureAccuracy,
                    passed: false,
                    severity: .advisory,
                    note: "No scripture reference detected in content."
                )
            ],
            policy: .advisory,
            isInterpretation: false
        ),
        onShare: {},
        onRevise: {},
        onCancel: {}
    )
}
