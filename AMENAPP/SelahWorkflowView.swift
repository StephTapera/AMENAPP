//
//  SelahWorkflowView.swift
//  AMENAPP
//
//  Verse-to-testimony workflow engine UI — guides users through
//  Verse → Reflect → Pray → Journal → Testimony → Share.
//

import SwiftUI

// MARK: - Workflow Progress View

struct SelahWorkflowProgressView: View {
    let workflow: SelahWorkflow
    let onAction: (WorkflowAction) -> Void

    @ObservedObject private var selahService = SelahService.shared

    private var currentStage: WorkflowStage {
        workflow.currentWorkflowStage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Progress dots
            HStack(spacing: 4) {
                ForEach(WorkflowStage.allCases) { stage in
                    WorkflowStageDot(
                        stage: stage,
                        isCurrent: stage == currentStage,
                        isComplete: stage.order < currentStage.order
                    )
                }
            }

            // Current stage card
            let suggestion = selahService.suggestNextStep(for: workflow)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: currentStage.icon)
                        .font(.systemScaled(13))
                        .foregroundStyle(Color.accentColor)
                    Text(currentStage.rawValue)
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                if let aiSuggestion = suggestion.aiSuggestion {
                    Text(aiSuggestion)
                        .font(.systemScaled(13))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }

                // Action button
                Button {
                    handleStageAction()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: actionIcon)
                        Text(actionLabel)
                    }
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                    )
            )
        }
    }

    private var actionIcon: String {
        switch currentStage {
        case .verse:     return "book.fill"
        case .reflect:   return "brain.head.profile"
        case .pray:      return "hands.sparkles"
        case .journal:   return "pencil.line"
        case .testimony: return "person.wave.2"
        case .share:     return "square.and.arrow.up"
        }
    }

    private var actionLabel: String {
        switch currentStage {
        case .verse:     return "Open Verse"
        case .reflect:   return "Start Reflecting"
        case .pray:      return "Begin Prayer"
        case .journal:   return "Open Journal"
        case .testimony: return "Write Testimony"
        case .share:     return "Share Now"
        }
    }

    private func handleStageAction() {
        switch currentStage {
        case .verse:     onAction(.openVerse(workflow.verseReference))
        case .reflect:   onAction(.startSelah)
        case .pray:      onAction(.createPrayer)
        case .journal:   onAction(.openJournal)
        case .testimony: onAction(.createTestimony)
        case .share:     onAction(.shareToOpenTable)
        }
    }
}

// MARK: - Workflow Stage Dot

struct WorkflowStageDot: View {
    let stage: WorkflowStage
    let isCurrent: Bool
    let isComplete: Bool

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(fillColor)
                    .frame(width: isCurrent ? 24 : 16, height: isCurrent ? 24 : 16)

                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.systemScaled(8, weight: .bold))
                        .foregroundStyle(.white)
                } else if isCurrent {
                    Image(systemName: stage.icon)
                        .font(.systemScaled(10, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .animation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.8)), value: isCurrent)

            if isCurrent {
                Text(stage.rawValue)
                    .font(.systemScaled(8, weight: .semibold))
                    .foregroundStyle(.primary)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var fillColor: Color {
        if isComplete { return .green }
        if isCurrent { return Color.accentColor }
        return Color.primary.opacity(0.12)
    }
}

// MARK: - Workflow Next Step Card

struct SelahWorkflowNextStepCard: View {
    let suggestion: WorkflowSuggestion

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: suggestion.stage.icon)
                .font(.systemScaled(18))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text("Next: \(suggestion.stage.rawValue)")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(suggestion.prompt)
                    .font(.systemScaled(12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.systemScaled(12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

// MARK: - Active Workflows View

struct SelahActiveWorkflowsView: View {
    var onAction: ((WorkflowAction) -> Void)? = nil

    @ObservedObject private var selahService = SelahService.shared

    var body: some View {
        if !selahService.workflows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("ACTIVE JOURNEYS")
                    .font(.systemScaled(10, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)

                ForEach(selahService.workflows) { workflow in
                    SelahWorkflowProgressView(workflow: workflow) { action in
                        onAction?(action)
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }
}

// MARK: - Start Workflow Button

struct StartWorkflowButton: View {
    let verseReference: String?

    @ObservedObject private var selahService = SelahService.shared
    @State private var isCreating = false

    var body: some View {
        if let ref = verseReference {
            Button {
                guard !isCreating else { return }
                isCreating = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()

                Task {
                    _ = try? await selahService.createWorkflow(verseReference: ref)
                    isCreating = false
                }
            } label: {
                HStack(spacing: 5) {
                    if isCreating {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.systemScaled(12, weight: .medium))
                    }
                    Text("Journey")
                        .font(.systemScaled(12, weight: .medium))
                }
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.accentColor.opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isCreating)
        }
    }
}
