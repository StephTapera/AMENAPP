// ONEReachBudgetPill.swift
// ONE — Compact reach budget indicator shown on feed cells.
// P3-E | Displays sharesRemaining + chain depth; relay action in ONEWorldFeedView.

import SwiftUI

struct ONEReachBudgetPill: View {
    let budget: ONEReachBudget

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.systemScaled(9))
            Text(label)
                .font(.systemScaled(10, weight: .medium))
                .monospacedDigit()
        }
        .foregroundStyle(pillColor)
        .padding(.horizontal, ONE.Spacing.sm)
        .padding(.vertical, 3)
        .background(Capsule().fill(pillColor.opacity(0.10)))
        .accessibilityLabel(accessibilityText)
    }

    private var icon: String {
        if !budget.hasReachRemaining { return "arrow.triangle.2.circlepath.slash" }
        if budget.chainDepth >= budget.maxChainDepth - 1 { return "exclamationmark.arrow.triangle.2.circlepath" }
        return "arrow.triangle.2.circlepath"
    }

    private var label: String {
        if !budget.hasReachRemaining { return "No relays" }
        return "\(budget.sharesRemaining) relay\(budget.sharesRemaining == 1 ? "" : "s")"
    }

    private var pillColor: Color {
        if !budget.hasReachRemaining { return .secondary }
        if budget.sharesRemaining <= 2 { return ONE.Colors.ephemeralRed }
        return ONE.Colors.witnessGold
    }

    private var accessibilityText: String {
        if !budget.hasReachRemaining {
            return "No relays remaining for this moment"
        }
        return "\(budget.sharesRemaining) relay\(budget.sharesRemaining == 1 ? "" : "s") remaining. Chain depth \(budget.chainDepth) of \(budget.maxChainDepth)."
    }
}
