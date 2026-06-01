// AmenMessageSaveActionsSheet.swift
// AMENAPP
//
// Phase 6: Bottom sheet for saving a message to cross-surface destinations.
// addToChurchNotes and saveToSelah are wired to real services (AmenMessageSaveService).
// saveToNotes and remindMe remain honestly unavailable — no service exists.
// Success state is only shown after a confirmed service write.

import SwiftUI

enum AmenSaveActionType: String, CaseIterable, Identifiable {
    case saveToSelah
    case addToChurchNotes
    case saveToNotes
    case remindMe

    var id: String { rawValue }

    var label: String {
        switch self {
        case .saveToSelah:      return "Save to Selah"
        case .addToChurchNotes: return "Add to Church Notes"
        case .saveToNotes:      return "Save to Notes"
        case .remindMe:         return "Remind Me"
        }
    }

    var systemImage: String {
        switch self {
        case .saveToSelah:      return "bookmark.fill"
        case .addToChurchNotes: return "note.text"
        case .saveToNotes:      return "square.and.pencil"
        case .remindMe:         return "bell.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .saveToSelah:      return .purple
        case .addToChurchNotes: return .blue
        case .saveToNotes:      return .orange
        case .remindMe:         return .red
        }
    }

    func isUnavailable(
        selahEnabled: Bool,
        crossSurfaceEnabled: Bool = true,
        hasConversationId: Bool = true
    ) -> Bool {
        switch self {
        case .saveToSelah:
            return !selahEnabled
        case .addToChurchNotes:
            return false
        case .saveToNotes:
            return !crossSurfaceEnabled || !hasConversationId
        case .remindMe:
            return true
        }
    }
}

struct AmenMessageSaveContext: Identifiable {
    let id = UUID()
    let message: AppMessage
    let conversationName: String        // used as note title when senderName is unavailable
    let presentedActions: [AmenSaveActionType]
}

struct AmenMessageSaveActionsSheet: View {
    let context: AmenMessageSaveContext
    let flags: AMENFeatureFlags
    let onDismiss: () -> Void

    @State private var activeAction: AmenSaveActionType? = nil
    @State private var confirmationMessage: String? = nil
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(.tertiaryLabel))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 8) {
                Text("Save message")
                    .font(.headline)
                    .padding(.horizontal, 20)

                if !context.message.text.isEmpty {
                    Text(context.message.text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .padding(10)
                        .background(Color(.secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 16)

            if let confirmation = confirmationMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(confirmation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 12)
                .transition(.opacity)
            }

            if let err = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(err)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 12)
                .transition(.opacity)
            }

            VStack(spacing: 10) {
                ForEach(context.presentedActions) { action in
                    actionRow(action)
                }
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 32)
        }
        .background(Color(.systemBackground))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .animation(.easeInOut(duration: 0.2), value: confirmationMessage)
        .animation(.easeInOut(duration: 0.2), value: errorMessage)
    }

    @ViewBuilder
    private func actionRow(_ action: AmenSaveActionType) -> some View {
        Button {
            Task { await performAction(action) }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: action.systemImage)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(action.tintColor)
                    .frame(width: 28, alignment: .center)

                Text(action.label)
                    .font(.callout)
                    .foregroundStyle(.primary)

                Spacer()

                if activeAction == action {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if isUnavailable(action) {
                    Text("Coming soon")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 12))
        }
        .disabled(activeAction != nil || isUnavailable(action))
        .buttonStyle(.plain)
        .accessibilityLabel(action.label)
        .accessibilityHint(isUnavailable(action) ? "Coming soon" : "Double-tap to save")
    }

    private func isUnavailable(_ action: AmenSaveActionType) -> Bool {
        switch action {
        case .saveToSelah:      return !flags.selahMediaOSEnabled
        case .addToChurchNotes: return false   // wired to AmenMessageSaveService
        case .saveToNotes:      return true    // no notes save service — honest unavailable
        case .remindMe:         return true    // no reminder service — honest unavailable
        }
    }

    private func performAction(_ action: AmenSaveActionType) async {
        guard !isUnavailable(action) else { return }
        activeAction = action
        errorMessage = nil
        AmenMessagingAnalytics.track(.saveSheetShown, parameters: ["action": action.rawValue])

        do {
            switch action {
            case .addToChurchNotes:
                try await AmenMessageSaveService.saveToChurchNotes(
                    message: context.message,
                    conversationName: context.conversationName
                )
                AmenMessagingAnalytics.track(.addToChurchNotesTapped)
                await finish(confirmation: "Added to church notes")

            case .saveToSelah:
                try await AmenMessageSaveService.saveToSelah(
                    message: context.message,
                    conversationName: context.conversationName
                )
                AmenMessagingAnalytics.track(.saveToSelahTapped)
                await finish(confirmation: "Saved to Selah")

            case .saveToNotes, .remindMe:
                // Unreachable — buttons are disabled via isUnavailable
                break
            }
        } catch {
            activeAction = nil
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func finish(confirmation: String) async {
        activeAction = nil
        confirmationMessage = confirmation
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        onDismiss()
    }
}
