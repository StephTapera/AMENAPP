// ForwardingSheetView.swift
// AMENAPP — ContentFlowOS
// Forwarding destination picker with pre-forward risk review.

import SwiftUI

struct ForwardingSheetView: View {
    let card: ContentCard
    let requestorIsCreator: Bool
    let requestorIsTrustedMember: Bool
    let onForward: (ContentAction) -> Void
    let onDismiss: () -> Void

    @State private var showApproval = false
    @State private var selectedAction: ContentAction = .forwardDM
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var risk: ExternalShareRisk {
        ContentPermissionEngine.externalShareRisk(for: card)
    }

    private var availableActions: [ContentAction] {
        ContentPermissionEngine.availableActions(
            for: card,
            requestorIsCreator: requestorIsCreator,
            requestorIsTrustedMember: requestorIsTrustedMember
        )
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                // Risk warning
                if risk.hasAnyRisk {
                    riskBanner
                }

                List {
                    Section("Share Inside Amen") {
                        ForEach(internalActions, id: \.self) { action in
                            ForwardActionRow(action: action) {
                                selectedAction = action
                                showApproval = true
                            }
                        }
                    }
                    if availableActions.contains(.shareExternal) {
                        Section("Share Outside Amen") {
                            ForwardActionRow(action: .shareExternal) {
                                selectedAction = .shareExternal
                                showApproval = true
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Share This")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
            }
            .sheet(isPresented: $showApproval) {
                ApprovalSheetView(
                    card: card,
                    proposedAction: selectedAction,
                    requestorIsCreator: requestorIsCreator,
                    requestorIsSpaceAdmin: false,
                    requestorIsChurchAdmin: false,
                    requestorIsTrustedMember: requestorIsTrustedMember,
                    targetSurface: surfaceFor(selectedAction),
                    onApproved: { action, _ in
                        onForward(action)
                        showApproval = false
                        onDismiss()
                    },
                    onDenied: { _ in showApproval = false },
                    onDismiss: { showApproval = false }
                )
                .presentationDetents([.large])
            }
        }
    }

    private var internalActions: [ContentAction] {
        availableActions.filter { $0 != .shareExternal }
    }

    @ViewBuilder
    private var riskBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Privacy Check", systemImage: "exclamationmark.shield.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            ForEach(risk.riskItems, id: \.self) { item in
                Label(item, systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.orange.opacity(0.1))
    }

    private func surfaceFor(_ action: ContentAction) -> ContentSurface {
        switch action {
        case .forwardDM:         return .directMessage
        case .forwardGroup:      return .space
        case .discussInSpace:    return .space
        case .discussInConnect:  return .amenConnect
        case .shareExternal:     return .feed
        default:                 return .space
        }
    }
}

// MARK: - Action Row

private struct ForwardActionRow: View {
    let action: ContentAction
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: action.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(action.isDestructiveAdjacent ? Color.orange : Color.amenGold)
                    .frame(width: 28)
                Text(action.displayName)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(action.displayName)
    }
}
