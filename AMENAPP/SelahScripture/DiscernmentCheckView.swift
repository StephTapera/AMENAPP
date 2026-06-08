//
//  DiscernmentCheckView.swift
//  AMENAPP
//
//  Four-state SwiftUI result card for a Berean discernment check.
//
//  States:
//    1. Loading   — check == nil
//    2. Refused   — check.status == "refused"
//    3. Grounded  — check.status == "grounded", verdict != "contested"
//    4. Contested — check.verdict == "contested"
//
//  Design tokens (selah.contracts.ts §6–§7):
//    Card: white, cornerRadius 28, dual shadow
//    Citation block: Color(.tertiarySystemBackground), cornerRadius 16, padding 12
//    Verdict chip: .regularMaterial + Capsule, black text ONLY — never red/green
//    Privacy footer: always visible in non-refused grounded states
//
//  HARD CONSTRAINTS enforced here:
//    - Verdict chip background is .regularMaterial — NEVER red, green, gold, or purple
//    - Label text is Color(.label) — never "FALSE/UNBIBLICAL"
//    - Sharing is always an explicit user tap — never automatic
//

import SwiftUI

// MARK: - DiscernmentCheckView

struct DiscernmentCheckView: View {

    let check: DiscernmentCheckResult?   // nil → loading state
    let onShare: () -> Void
    let onDismiss: () -> Void
    @Binding var isSharing: Bool

    var body: some View {
        ZStack {
            switch resolvedState {
            case .loading:
                loadingCard
            case .refused:
                refusedCard
            case .grounded:
                groundedCard
            case .contested:
                contestedCard
            }
        }
        .background(Color(.secondarySystemBackground))
        .cornerRadius(28)
        .shadow(color: .black.opacity(0.10), radius: 20, y: 8)
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    // MARK: - State Resolution

    private enum CardState { case loading, refused, grounded, contested }

    private var resolvedState: CardState {
        guard let check else { return .loading }
        if check.status == "refused" { return .refused }
        if check.verdict == "contested" { return .contested }
        return .grounded
    }

    // MARK: - State 1: Loading

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            bereanHeader

            // Three pulsing placeholder rows
            VStack(alignment: .leading, spacing: 10) {
                PlaceholderRow(width: 200)
                PlaceholderRow(width: 280)
                PlaceholderRow(width: 160)
            }

            Text("Checking Scripture…")
                .font(.footnote)
                .foregroundColor(Color(.secondaryLabel))
        }
        .padding(24)
    }

    // MARK: - State 2: Refused

    private var refusedCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            bereanHeader

            // Citation-block styled inset — calm, non-alarming copy
            VStack(alignment: .leading, spacing: 6) {
                Text(check?.refusalReason
                     ?? "Unable to assess this claim against Scripture at this time.")
                    .font(.body)
                    .foregroundColor(Color(.label))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(16)

            dismissButton
        }
        .padding(24)
    }

    // MARK: - State 3: Grounded (non-contested)

    private var groundedCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            bereanHeader

            if let verdict = check?.verdict {
                verdictChip(for: verdict)
            }

            if let claims = check?.claims, !claims.isEmpty {
                claimsSection(claims)
            }

            if let citations = check?.citations, !citations.isEmpty {
                citationsSection(citations)
            }

            privacyFooter

            HStack(spacing: 16) {
                shareButton
                Spacer()
                dismissButton
            }
        }
        .padding(24)
    }

    // MARK: - State 4: Contested

    private var contestedCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            bereanHeader

            // "Multiple Perspectives" verdict chip — neutral only
            verdictChip(for: "contested")

            if let claims = check?.claims, !claims.isEmpty {
                claimsSection(claims)
            }

            if let citations = check?.citations, !citations.isEmpty {
                citationsSection(citations)
            }

            if let perspectives = check?.perspectives, !perspectives.isEmpty {
                perspectivesSection(perspectives)
            }

            privacyFooter

            HStack(spacing: 16) {
                shareButton
                Spacer()
                dismissButton
            }
        }
        .padding(24)
    }

    // MARK: - Shared Sub-views

    /// Standard "Berean Check / Acts 17:11" header
    private var bereanHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Berean Check")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(Color(.label))
            Text("Acts 17:11 · 1 Thess 5:21")
                .font(.caption)
                .foregroundColor(Color(.secondaryLabel))
        }
    }

    /// Verdict chip — .regularMaterial background, black text ONLY.
    /// HARD CONSTRAINT: never red, never green, never gold, never purple.
    private func verdictChip(for verdict: String) -> some View {
        let label: String = {
            switch verdict {
            case "aligns":       return "Aligns with Scripture"
            case "diverges":     return "Diverges from Scripture"
            case "insufficient": return "Insufficient Evidence"
            case "contested":    return "Multiple Perspectives"
            default:             return verdict.capitalized
            }
        }()

        return Text(label)
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(Color(.label))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial)
            .clipShape(Capsule())
            .accessibilityLabel("Verdict: \(label)")
    }

    /// Claims section with classification badges
    private func claimsSection(_ claims: [DiscernmentClaim]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claims")
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundColor(Color(.secondaryLabel))
                .textCase(.uppercase)

            ForEach(Array(claims.enumerated()), id: \.offset) { _, claim in
                HStack(alignment: .top, spacing: 8) {
                    Text(claim.text)
                        .font(.subheadline)
                        .foregroundColor(Color(.label))
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 4)

                    Text(claim.classification.capitalized)
                        .font(.caption2)
                        .foregroundColor(Color(.secondaryLabel))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }
            }
        }
    }

    /// Citations section with inset citation blocks
    private func citationsSection(_ citations: [DiscernmentCitation]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scripture")
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundColor(Color(.secondaryLabel))
                .textCase(.uppercase)

            ForEach(Array(citations.enumerated()), id: \.offset) { _, citation in
                citationBlock(citation)
            }
        }
    }

    private func citationBlock(_ citation: DiscernmentCitation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(citation.reference)
                    .font(.caption)
                    .foregroundColor(Color(.secondaryLabel))

                Text(citation.translation)
                    .font(.caption2)
                    .foregroundColor(Color(.secondaryLabel))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }

            Text(citation.text)
                .font(.body)
                .foregroundColor(Color(.label))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(16)
    }

    /// Perspectives section for contested verdict — segmented or stacked
    private func perspectivesSection(_ perspectives: [DiscernmentPerspective]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Perspectives")
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundColor(Color(.secondaryLabel))
                .textCase(.uppercase)

            ForEach(Array(perspectives.enumerated()), id: \.offset) { _, perspective in
                VStack(alignment: .leading, spacing: 6) {
                    Text(perspective.tradition)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Color(.label))

                    Text(perspective.summary)
                        .font(.subheadline)
                        .foregroundColor(Color(.label))
                        .fixedSize(horizontal: false, vertical: true)

                    if !perspective.citations.isEmpty {
                        ForEach(Array(perspective.citations.enumerated()), id: \.offset) { _, citation in
                            citationBlock(citation)
                        }
                    }
                }
                .padding(12)
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(16)
            }
        }
    }

    /// Privacy footer — visible in ALL non-refused states
    private var privacyFooter: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.caption2)
                .foregroundColor(Color(.tertiaryLabel))
            Text("Private · Only visible to you")
                .font(.caption2)
                .foregroundColor(Color(.tertiaryLabel))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Private check. Only visible to you.")
    }

    /// "Share to thread" — link style, explicit user action only
    private var shareButton: some View {
        Button(action: onShare) {
            Text("Share to thread")
                .font(.subheadline)
                .foregroundColor(Color(.label))
        }
        .disabled(isSharing)
        .accessibilityLabel("Share this Berean check to the thread")
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Text("Done")
                .font(.subheadline)
                .foregroundColor(Color(.secondaryLabel))
        }
        .accessibilityLabel("Dismiss Berean check")
    }
}

// MARK: - PlaceholderRow (loading animation)

private struct PlaceholderRow: View {
    let width: CGFloat
    @State private var opacity: Double = 0.4

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(.systemGray4))
            .frame(width: width, height: 14)
            .opacity(opacity)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.9)
                    .repeatForever(autoreverses: true)
                ) {
                    opacity = 0.9
                }
            }
    }
}

