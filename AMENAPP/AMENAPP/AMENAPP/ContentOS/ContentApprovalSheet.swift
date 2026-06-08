// ContentApprovalSheet.swift
// AMENAPP — ContentOS
//
// Liquid Glass approval + share sheet for ContentOS.
// Shown when a user taps "Discuss", "Forward", or "Share" on any ContentCard.
// Glass lives on the control layer only — reading surface stays clean.

import SwiftUI

// MARK: - Approval Sheet

struct ContentApprovalSheet: View {
    let card: ContentCard
    let requestorIsCreator: Bool
    let requestorIsSpaceAdmin: Bool
    let requestorIsChurchAdmin: Bool
    let requestorIsTrustedMember: Bool

    var onAction: (ContentAction) -> Void
    var onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @StateObject private var router = ContentAIRouter.shared
    @State private var showExternalRiskSheet = false
    @State private var showRedactionPanel = false
    @State private var pendingExternalAction: ContentAction?
    @State private var appeared = false

    private var availableActions: [ContentAction] {
        ContentPermissionEngine.availableActions(
            for: card,
            requestorIsCreator: requestorIsCreator,
            requestorIsTrustedMember: requestorIsTrustedMember
        )
    }

    private var externalRisk: ExternalShareRisk {
        ContentPermissionEngine.externalShareRisk(for: card)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Clean reading background — no glass on content
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        originPill
                        aiSuggestionsSection
                        actionsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Share or Discuss")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onDismiss()
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .scaleEffect(appeared ? 1 : 0.96)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.78)) {
                appeared = true
            }
            Task { await router.route(card: card) }
        }
        .sheet(isPresented: $showExternalRiskSheet) {
            if let action = pendingExternalAction {
                ExternalShareRiskSheet(
                    card: card,
                    risk: externalRisk,
                    onConfirm: {
                        showExternalRiskSheet = false
                        onAction(action)
                        ContentForwardingService.shared.recordForwardDecision(
                            card: card,
                            action: action,
                            destination: .feed,
                            outcome: .allowedInstantly,
                            isExternal: true
                        )
                        dismiss()
                    },
                    onRedact: { showRedactionPanel = true },
                    onCancel: { showExternalRiskSheet = false }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showRedactionPanel) {
            ContentRedactionPanel(card: card) {
                showRedactionPanel = false
                dismiss()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Origin Pill (glass — control layer)

    private var originPill: some View {
        HStack(spacing: 10) {
            Image(systemName: card.sourceType.icon)
                .font(.systemScaled(15, weight: .semibold))
                .foregroundStyle(.purple)

            VStack(alignment: .leading, spacing: 2) {
                Text("Originally shared with")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(card.originalAudience.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Spacer()

            if card.sensitivityScore > 0.5 {
                sensitivityBadge
            }
        }
        .padding(14)
        .background(glassBackground(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Originally shared with \(card.originalAudience.displayName)")
    }

    private var sensitivityBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.caption2)
            Text("Sensitive")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.1), in: Capsule())
    }

    // MARK: - AI Suggestions Section

    @ViewBuilder
    private var aiSuggestionsSection: some View {
        if AMENFeatureFlags.shared.contentAIRouterEnabled
            && !router.suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Suggested", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                VStack(spacing: 0) {
                    ForEach(Array(router.suggestions.prefix(3).enumerated()), id: \.element.id) { index, suggestion in
                        aiSuggestionRow(suggestion)

                        if index < min(router.suggestions.count, 3) - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .background(glassBackground(cornerRadius: 16))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func aiSuggestionRow(_ suggestion: ContentRouteSuggestion) -> some View {
        Button {
            handleAction(suggestion.action)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: suggestion.action.icon)
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(.purple)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.label)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(suggestion.rationale)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(suggestion.label). \(suggestion.rationale)")
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("All Options")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(availableActions.enumerated()), id: \.element) { index, action in
                    let outcome = ContentPermissionEngine.evaluate(
                        action: action,
                        card: card,
                        requestorIsCreator: requestorIsCreator,
                        requestorIsSpaceAdmin: requestorIsSpaceAdmin,
                        requestorIsChurchAdmin: requestorIsChurchAdmin,
                        requestorIsTrustedMember: requestorIsTrustedMember,
                        targetSurface: surfaceFor(action: action)
                    )

                    actionRow(action, outcome: outcome)

                    if index < availableActions.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .background(glassBackground(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func actionRow(_ action: ContentAction, outcome: ContentPermissionOutcome) -> some View {
        Button {
            guard outcome.canProceed else { return }
            handleAction(action)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(iconColor(action, outcome: outcome).opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: action.icon)
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(iconColor(action, outcome: outcome))
                }

                Text(action.displayName)
                    .font(.subheadline)
                    .foregroundStyle(outcome.canProceed ? .primary : .secondary)

                Spacer()

                if outcome.requiresApproval {
                    Text("Requires approval")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if case .denied = outcome {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .disabled(!outcome.canProceed && !outcome.requiresApproval)
        .accessibilityLabel(actionAccessibilityLabel(action, outcome: outcome))
        .accessibilityHint(outcome.displayTitle)
    }

    // MARK: - Helpers

    private func handleAction(_ action: ContentAction) {
        if action == .shareExternal && externalRisk.hasAnyRisk {
            pendingExternalAction = action
            showExternalRiskSheet = true
            return
        }

        if action == .requestPermission {
            Task {
                try? await ContentForwardingService.shared.sendApprovalRequest(
                    card: card,
                    requestedAction: action,
                    targetSurface: .space,
                    note: nil
                )
            }
            dismiss()
            return
        }

        ContentForwardingService.shared.recordForwardDecision(
            card: card,
            action: action,
            destination: surfaceFor(action: action),
            outcome: .allowedInstantly,
            isExternal: action == .shareExternal
        )

        if action == .saveToChurchNotes {
            Task { try? await ContentForwardingService.shared.saveToChurchNotes(card: card) }
        }

        onAction(action)
        dismiss()
    }

    private func surfaceFor(action: ContentAction) -> ContentSurface {
        switch action {
        case .discussInSpace, .sendToSmallGroup, .sendToChurchTeam:  return .space
        case .discussInConnect:   return .amenConnect
        case .sendToMentor:       return .mentorThread
        case .saveToChurchNotes, .createStudy: return .churchNotes
        case .createPrayerRoom:   return .space
        case .forwardDM:          return .directMessage
        case .shareExternal:      return .feed
        default:                  return .objectHub
        }
    }

    private func iconColor(_ action: ContentAction, outcome: ContentPermissionOutcome) -> Color {
        if case .denied = outcome { return .secondary }
        if action.isDestructiveAdjacent { return .orange }
        return .purple
    }

    private func actionAccessibilityLabel(_ action: ContentAction, outcome: ContentPermissionOutcome) -> String {
        if case .denied(let reason) = outcome {
            return "\(action.displayName). Not available: \(reason)"
        }
        if outcome.requiresApproval {
            return "\(action.displayName). Requires approval."
        }
        return action.displayName
    }

    private func glassBackground(cornerRadius: CGFloat) -> some ShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground))
        }
        return AnyShapeStyle(.regularMaterial)
    }
}

// MARK: - External Share Risk Sheet

struct ExternalShareRiskSheet: View {
    let card: ContentCard
    let risk: ExternalShareRisk
    var onConfirm: () -> Void
    var onRedact: () -> Void
    var onCancel: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            dragHandle

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    warningHeader
                    riskList
                    actionButtons
                }
                .padding(20)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }

    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(Color.secondary.opacity(0.4))
            .frame(width: 36, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 6)
    }

    private var warningHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("Before sharing outside Amen")
                    .font(.headline)
                Text("Review the following before proceeding.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(reduceTransparency ? AnyShapeStyle(Color.orange.opacity(0.08)) : AnyShapeStyle(.regularMaterial))
        )
        .accessibilityElement(children: .combine)
    }

    private var riskList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(risk.riskItems, id: \.self) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.top, 2)
                    Text(item)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(item)
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button(action: onConfirm) {
                Text("Share Anyway")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.orange, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share anyway — I understand the risks")

            Button(action: onRedact) {
                Text("Review and Redact")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)

            Button("Cancel", action: onCancel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Content Redaction Panel

struct ContentRedactionPanel: View {
    let card: ContentCard
    var onDone: () -> Void

    private var suggestions: [ContentRedactionSuggestion] {
        ContentPermissionEngine.redactionSuggestions(for: card)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(suggestions) { suggestion in
                        Label(suggestion.description, systemImage: suggestion.type.icon)
                            .font(.subheadline)
                    }
                } header: {
                    Text("AI Redaction Suggestions")
                } footer: {
                    Text("These changes help protect privacy before sharing outside Amen.")
                        .font(.caption)
                }
            }
            .navigationTitle("Redact Before Sharing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDone)
                }
            }
        }
    }
}
