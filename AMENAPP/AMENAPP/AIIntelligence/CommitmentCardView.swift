// CommitmentCardView.swift
// AMEN — Commitment Card UI
//
// Shows a Commitment between two people: party avatars, kind label,
// loop state, and action controls. No vanity counters anywhere.
// Flag-gated: AMENFeatureFlags.shared.commitmentConnections

import SwiftUI

struct CommitmentCardView: View {

    // MARK: - Input

    let commitment: CommitmentObject
    /// Display names keyed by uid, used to render gentle copy.
    let displayNames: [String: String]
    let currentUid: String

    // MARK: - Dependencies

    @StateObject private var service = CommitmentConnectionService()
    @StateObject private var selahService = SelahMomentService()

    // MARK: - State

    @State private var isCompleting = false
    @State private var isLapsing = false
    @State private var showCloseTheLoopPrompt = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Computed Helpers

    private var otherUid: String {
        commitment.parties.first(where: { $0 != currentUid }) ?? commitment.parties.first ?? ""
    }

    private var otherName: String {
        displayNames[otherUid] ?? "your friend"
    }

    private var kindLabel: String {
        switch commitment.kind {
        case .prayFor:
            return "Praying for \(otherName) this week"
        case .checkIn:
            return "Checking in with \(otherName)"
        case .readWith:
            return "Reading with \(otherName)"
        case .custom:
            return "A commitment with \(otherName)"
        }
    }

    private var completionLabel: String {
        switch commitment.kind {
        case .prayFor:
            return "I prayed for \(otherName)"
        case .checkIn:
            return "I checked in with \(otherName)"
        case .readWith:
            return "We read together"
        case .custom:
            return "I honored this commitment"
        }
    }

    private var closeTheLoopQuestion: String {
        switch commitment.kind {
        case .prayFor:
            return "Did you get to pray for \(otherName)?"
        case .checkIn:
            return "Were you able to check in with \(otherName)?"
        case .readWith:
            return "Did you and \(otherName) get to read together?"
        case .custom:
            return "How did your commitment with \(otherName) go?"
        }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if AMENFeatureFlags.shared.commitmentConnections {
                cardContent
            }
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Party avatars + kind label
            HStack(spacing: 12) {
                partyAvatarsRow
                VStack(alignment: .leading, spacing: 4) {
                    Text(kindLabel)
                        .font(.callout)
                        .fontWeight(.medium)
                    loopStateIndicator
                }
                Spacer()
            }

            // Close-the-loop prompt (gentle, one-time)
            if showCloseTheLoopPrompt && commitment.loopState == .open {
                closeTheLoopPromptView
            }

            // Action controls
            switch commitment.loopState {
            case .open, .nudged:
                actionButtons
            case .closed:
                closedStateView
            case .lapsedGracefully:
                lapsedStateView
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .breathButton()
        .onAppear {
            // Show close-the-loop prompt if we are past closeTheLoopAt and nudge was sent
            if commitment.loopState == .nudged,
               let closeAt = commitment.closeTheLoopAt,
               Date() >= closeAt {
                showCloseTheLoopPrompt = true
            }
        }
    }

    @ViewBuilder
    private var partyAvatarsRow: some View {
        HStack(spacing: -8) {
            ForEach(commitment.parties.prefix(2), id: \.self) { uid in
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(String(displayNames[uid]?.prefix(1) ?? "?"))
                            .font(.callout)
                            .fontWeight(.semibold)
                    )
                    .accessibilityLabel(displayNames[uid] ?? "person")
            }
        }
    }

    @ViewBuilder
    private var loopStateIndicator: some View {
        switch commitment.loopState {
        case .open:
            Label("Open", systemImage: "circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .nudged:
            Label("Gently reminded", systemImage: "bell.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .closed:
            Label("Complete", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .lapsedGracefully:
            Label("Grace is enough.", systemImage: "heart")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                Task { await complete() }
            } label: {
                Text(completionLabel)
                    .font(.callout)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isCompleting)
            .accessibilityLabel(completionLabel)

            Button {
                Task { await lapseGracefully() }
            } label: {
                Text("Grace is enough.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isLapsing)
            .accessibilityLabel("Mark commitment as lapsed gracefully. No shame.")
        }
    }

    @ViewBuilder
    private var closedStateView: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Completed")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var lapsedStateView: some View {
        Text("Grace is enough.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .italic()
            .accessibilityLabel("This commitment has lapsed. Grace is enough.")
    }

    @ViewBuilder
    private var closeTheLoopPromptView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(closeTheLoopQuestion)
                .font(.callout)
                .foregroundStyle(.primary)
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Actions

    private func complete() async {
        isCompleting = true
        defer { isCompleting = false }
        try? await service.completeCommitment(id: commitment.id)
        selahService.trigger()
    }

    private func lapseGracefully() async {
        isLapsing = true
        defer { isLapsing = false }
        try? await service.lapseCommitmentGracefully(id: commitment.id)
    }
}
