// ModerationTimelineView.swift
// AMENAPP
//
// Wave 2 — the user-facing moderation timeline. Shows every moderation action
// taken on the person's content, the constitutional principle invoked, the real
// model + rule, and a working Appeal control that routes to the real
// moderation_appeals queue (ModerationTransparencyService).
//
// Two-accent contract: BLUE = affordance (Appeal), GREEN = state (appeal
// resolved in the user's favour). Honest empty/unavailable states — never
// fabricated history.
//
// Gated by AMENFeatureFlags.shared.moderationAuditTrailEnabled (default OFF).

import SwiftUI

struct ModerationTimelineView: View {
    @StateObject private var service = ModerationTransparencyService()
    @State private var appealTarget: ModerationReceipt?

    var body: some View {
        Group {
            if service.isLoading {
                ProgressView("Loading your moderation history…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let reason = service.unavailableReason {
                emptyState(reason, systemImage: "lock.shield")
            } else if service.receipts.isEmpty {
                emptyState("No moderation actions have been taken on your content.",
                           systemImage: "checkmark.shield")
            } else {
                List {
                    Section {
                        ForEach(service.receipts) { receipt in
                            ModerationReceiptRow(receipt: receipt) {
                                appealTarget = receipt
                            }
                        }
                    } header: {
                        Text("Every action, and why")
                    } footer: {
                        Text("These are the real decisions recorded for your content. Confidence and model are reported as logged.")
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Moderation")
        .task { await service.load() }
        .sheet(item: $appealTarget) { receipt in
            AppealSheet(receipt: receipt) { statement in
                await service.submitAppeal(for: receipt, statement: statement)
            }
        }
    }

    private func emptyState(_ message: String, systemImage: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Row

private struct ModerationReceiptRow: View {
    let receipt: ModerationReceipt
    let onAppeal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: receipt.action.symbol)
                    .foregroundStyle(.secondary)
                Text(receipt.action.displayName)
                    .font(.headline)
                Spacer()
                appealBadge
            }

            Label(receipt.principleInvoked.displayName, systemImage: "scalemass")
                .font(.subheadline)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 2) {
                detail("Why", receipt.ruleTriggered)
                detail("Confidence", "\(receipt.confidence.band.rawValue.capitalized) · \(receipt.confidence.basis)")
                detail("Model", receipt.modelUsed)
            }

            if receipt.appealStatus == .available && receipt.humanReviewAvailable {
                Button(action: onAppeal) {
                    Label("Appeal this decision", systemImage: "arrowshape.turn.up.left")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .tint(.blue) // affordance
            }
        }
        .padding(.vertical, 4)
    }

    private func detail(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private var appealBadge: some View {
        switch receipt.appealStatus {
        case .none, .available:
            EmptyView()
        case .overturned:
            Label("Overturned", systemImage: "checkmark.circle.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.green) // state: resolved in user's favour
        default:
            Text(receipt.appealStatus.displayName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
    }
}

// MARK: - Appeal sheet

private struct AppealSheet: View {
    let receipt: ModerationReceipt
    let submit: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var statement = ""
    @State private var isSubmitting = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Tell a human reviewer why this decision should be reconsidered.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section("Your statement") {
                    TextField("What happened, in your words…", text: $statement, axis: .vertical)
                        .lineLimit(4...10)
                }
                if failed {
                    Text("Couldn't submit your appeal. Please try again.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Appeal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        Task {
                            isSubmitting = true
                            failed = false
                            let ok = await submit(statement)
                            isSubmitting = false
                            if ok { dismiss() } else { failed = true }
                        }
                    }
                    .disabled(statement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                }
            }
        }
    }
}

// MARK: - Display helpers (additive extensions on the frozen Wave 0 contracts)

extension TrustModerationAction {
    var displayName: String {
        switch self {
        case .hidden:     return "Held from view"
        case .downranked: return "Shown to fewer people"
        case .warned:     return "Warned"
        case .removed:    return "Removed"
        case .allowed:    return "Reviewed · allowed"
        }
    }
    var symbol: String {
        switch self {
        case .hidden:     return "eye.slash"
        case .downranked: return "arrow.down.right.circle"
        case .warned:     return "exclamationmark.bubble"
        case .removed:    return "trash"
        case .allowed:    return "checkmark.circle"
        }
    }
}

extension ConstitutionalPrinciple {
    var displayName: String {
        switch self {
        case .truthBeforeVirality:        return "Truth before virality"
        case .contextBeforeOutrage:       return "Context before outrage"
        case .dignityBeforeEngagement:    return "Dignity before engagement"
        case .restorationBeforePunishment:return "Restoration before punishment"
        case .humansBeforeAlgorithms:     return "Humans before algorithms"
        case .safetyScalesWithCapability: return "Safety scales with capability"
        }
    }
}

extension TrustAppealStatus {
    var displayName: String {
        switch self {
        case .none:        return ""
        case .available:   return "Appealable"
        case .submitted:   return "Appeal submitted"
        case .underReview: return "Under review"
        case .upheld:      return "Upheld"
        case .overturned:  return "Overturned"
        }
    }
}

#if DEBUG
#Preview("Moderation timeline") {
    NavigationStack { ModerationTimelineView() }
}
#endif
