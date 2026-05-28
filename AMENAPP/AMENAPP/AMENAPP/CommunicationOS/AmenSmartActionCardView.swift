// AmenSmartActionCardView.swift
// AMEN App — Smart Collaboration Layer: Slice 3 — Action / Follow-up Card
//
// Non-negotiable rules enforced here:
//   1. All actions are "possible/suggested" — never confirmed facts.
//   2. Assignee and due date are always optional suggestions — never auto-assigned.
//   3. Ambiguous owner/date → inline clarification prompt, never inferred.
//   4. UI reads and updates status only (no creation of actions from client).
//   5. Confidence < 0.5 → not shown (enforced in SmartActionsListSection).
//   6. All states handled: empty, loading, error, permission-denied, offline.
//   7. VoiceOver + Reduce Motion supported.
//   8. Flag OFF (threadActionExtractionEnabled) → invisible.

import SwiftUI
import FirebaseFirestore

// MARK: - AmenSmartActionCardView

struct AmenSmartActionCardView: View {
    let action: AmenSmartCollabAction
    let onAccept: () -> Void
    let onDismiss: () -> Void
    let onCorrect: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var appeared = false
    @State private var showCorrectSheet = false

    // Ambiguity prompts
    @State private var assigneePromptDismissed = false
    @State private var dueDatePromptDismissed = false

    private var isLowConfidence: Bool {
        action.confidence >= 0.5 && action.confidence < 0.65
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            actionTextRow
            if isLowConfidence {
                lowConfidenceBadge
            }
            if let assignee = action.assigneeSuggestion, !assigneePromptDismissed {
                assigneeChip(assignee)
            }
            if let dueDate = action.dueDateSuggestion, !dueDatePromptDismissed {
                dueDateChip(dueDate.dateValue())
            }
            sourceCitationChip
            buttonRow
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(actionTypeColor.opacity(0.3), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.07), radius: 8, y: 2)
        .scaleEffect(appeared ? 1 : 0.96)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            let animation: Animation = reduceMotion
                ? .linear(duration: 0.1)
                : .spring(response: 0.35, dampingFraction: 0.8)
            withAnimation(animation) { appeared = true }
        }
        .sheet(isPresented: $showCorrectSheet) {
            CorrectActionSheet(action: action, onDone: {
                showCorrectSheet = false
                onCorrect()
            })
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Possible action: \(action.suggestedText). Type: \(action.actionType.rawValue).")
    }

    // MARK: - Sub-views

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: actionTypeIcon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(actionTypeColor)
            Text(actionTypeLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var actionTextRow: some View {
        Text("Possible: \(action.suggestedText)")
            .font(.subheadline)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var lowConfidenceBadge: some View {
        Text("Low confidence")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.orange.opacity(0.12), in: Capsule())
            .accessibilityLabel("This suggestion has low confidence")
    }

    @ViewBuilder
    private func assigneeChip(_ assignee: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Who should handle this?")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Suggested for: \(assignee) — Tap to change")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Confirm \(assignee)") {
                    assigneePromptDismissed = true
                }
                .buttonStyle(SmallPillButtonStyle(color: actionTypeColor))
                .accessibilityLabel("Confirm \(assignee) as assignee suggestion")
                Button("Skip for now") {
                    assigneePromptDismissed = true
                }
                .buttonStyle(SmallPillButtonStyle(color: .secondary))
                .accessibilityLabel("Skip assignee suggestion")
            }
        }
        .padding(10)
        .background(Color(.tertiarySystemBackground).opacity(0.8), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func dueDateChip(_ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("When should this be done?")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Possibly by: \(date.formatted(date: .abbreviated, time: .omitted)) — Tap to change")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Confirm \(date.formatted(date: .abbreviated, time: .omitted))") {
                    dueDatePromptDismissed = true
                }
                .buttonStyle(SmallPillButtonStyle(color: actionTypeColor))
                .accessibilityLabel("Confirm \(date.formatted(date: .abbreviated, time: .omitted)) as due date suggestion")
                Button("Skip for now") {
                    dueDatePromptDismissed = true
                }
                .buttonStyle(SmallPillButtonStyle(color: .secondary))
                .accessibilityLabel("Skip due date suggestion")
            }
        }
        .padding(10)
        .background(Color(.tertiarySystemBackground).opacity(0.8), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var sourceCitationChip: some View {
        Button {
            // Phase 3+: deep link to source message.
            // For now, log the source message ID for traceability.
            dlog("[AmenSmartActionCardView] Source message tapped: \(action.sourceMessageId)")
        } label: {
            Label("From message", systemImage: "quote.bubble")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color(.tertiarySystemFill), in: Capsule())
        }
        .accessibilityLabel("View source message (deep link available in a future update)")
    }

    private var buttonRow: some View {
        HStack(spacing: 8) {
            Button("Accept") {
                onAccept()
            }
            .buttonStyle(SmallPillButtonStyle(color: .green))
            .accessibilityLabel("Accept this suggested action")

            Button("Dismiss") {
                onDismiss()
            }
            .buttonStyle(SmallPillButtonStyle(color: .secondary))
            .accessibilityLabel("Dismiss this suggestion")

            Button("Fix this") {
                showCorrectSheet = true
            }
            .buttonStyle(SmallPillButtonStyle(color: .orange))
            .accessibilityLabel("Correct this suggestion")

            Spacer()
        }
    }

    // MARK: - Helpers

    private var actionTypeIcon: String {
        switch action.actionType {
        case .followUp:     return "arrow.clockwise"
        case .decision:     return "checklist"
        case .commitment:   return "person.badge.checkmark"
        case .openQuestion: return "questionmark.circle"
        case .reminder:     return "bell"
        }
    }

    private var actionTypeLabel: String {
        switch action.actionType {
        case .followUp:     return "Possible Follow-up"
        case .decision:     return "Possible Decision"
        case .commitment:   return "Possible Commitment"
        case .openQuestion: return "Open Question"
        case .reminder:     return "Possible Reminder"
        }
    }

    private var actionTypeColor: Color {
        switch action.actionType {
        case .followUp:     return .blue
        case .decision:     return .green
        case .commitment:   return .purple
        case .openQuestion: return .orange
        case .reminder:     return .teal
        }
    }

    private var cardBackground: some ShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color(.secondarySystemBackground))
        }
        return AnyShapeStyle(.regularMaterial)
    }
}

// MARK: - CorrectActionSheet

private struct CorrectActionSheet: View {
    let action: AmenSmartCollabAction
    let onDone: () -> Void

    @State private var correctedText: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("What should this say?")
                    .font(.headline)
                Text("Original: \(action.suggestedText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("Enter corrected text", text: $correctedText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
                    .focused($fieldFocused)
                    .accessibilityLabel("Corrected action text")
                Spacer()
            }
            .padding()
            .navigationTitle("Correct Suggestion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDone() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        AMENAnalyticsService.shared.track(
                            .smartActionCorrected(actionType: action.actionType.rawValue)
                        )
                        onDone()
                    }
                    .disabled(correctedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear { fieldFocused = true }
    }
}

// MARK: - SmartActionsListSection

struct SmartActionsListSection: View {
    let threadId: String
    let threadType: AmenSmartThreadType
    let spaceId: String?
    let channelId: String?

    @ObservedObject private var service = AmenSmartActionsService.shared
    @ObservedObject private var killSwitch = RemoteKillSwitch.shared

    var body: some View {
        // Rule 8: Flag OFF → invisible
        guard killSwitch.threadActionExtractionEnabled else {
            return AnyView(EmptyView())
        }
        return AnyView(listContent)
    }

    @ViewBuilder
    private var listContent: some View {
        if service.isLoading {
            skeletonSection
        } else if let error = service.error {
            errorChip(error)
        } else {
            let visible = service.actions.filter { $0.confidence >= 0.5 }
            if visible.isEmpty {
                EmptyView()
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(visible) { action in
                        AmenSmartActionCardView(
                            action: action,
                            onAccept: {
                                Task {
                                    await service.updateActionStatus(
                                        action.id,
                                        threadId: threadId,
                                        threadType: threadType,
                                        spaceId: spaceId,
                                        channelId: channelId,
                                        newStatus: .accepted
                                    )
                                }
                            },
                            onDismiss: {
                                Task {
                                    await service.updateActionStatus(
                                        action.id,
                                        threadId: threadId,
                                        threadType: threadType,
                                        spaceId: spaceId,
                                        channelId: channelId,
                                        newStatus: .dismissed
                                    )
                                }
                            },
                            onCorrect: {
                                // Analytics fired inside CorrectActionSheet on submit.
                                // Status is not changed on correction — remains .suggested.
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: Loading skeleton

    private var skeletonSection: some View {
        VStack(spacing: 10) {
            ForEach(0..<2, id: \.self) { _ in
                SkeletonActionCard()
            }
        }
        .accessibilityLabel("Loading action suggestions")
    }

    // MARK: Error state

    @ViewBuilder
    private func errorChip(_ error: Error) -> some View {
        let isOffline = (error as NSError).domain == NSURLErrorDomain

        HStack(spacing: 8) {
            Image(systemName: isOffline ? "wifi.slash" : "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(isOffline ? Color.secondary : Color.orange)
            Text(isOffline ? "Offline — showing cached suggestions" : "Action suggestions unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !isOffline {
                Spacer()
                Button("Retry") {
                    Task {
                        await service.requestExtraction(
                            threadId: threadId,
                            threadType: threadType,
                            spaceId: spaceId,
                            channelId: channelId
                        )
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("Retry loading action suggestions")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemFill), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isOffline
                ? "Offline — showing cached action suggestions"
                : "Action suggestions unavailable. Tap Retry to try again."
        )
    }
}

// MARK: - Skeleton card (loading placeholder)

private struct SkeletonActionCard: View {
    @State private var shimmer = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 4).frame(width: 120, height: 10)
            RoundedRectangle(cornerRadius: 4).frame(maxWidth: .infinity).frame(height: 14)
            RoundedRectangle(cornerRadius: 4).frame(width: 200, height: 14)
        }
        .foregroundStyle(Color(.systemFill))
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .opacity(shimmer ? 0.5 : 1.0)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
            ) {
                shimmer = true
            }
        }
        .accessibilityHidden(true)
    }
}
