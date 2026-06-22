// AmenSafetyNudgeCard.swift
// AMENAPP
//
// Phase 7: Pre-send safety nudge card.
// Surfaces when AMENMessageSafetyEngine returns .softWarn or .requireEdit.
// Plain copy, no AI branding. Never blocks send for .softWarn.

import SwiftUI

struct AmenSafetyNudgeContext: Equatable {
    let warningMessage: String
    let messageText: String
    let canSendAnyway: Bool
}

struct AmenSafetyNudgeCard: View {
    let context: AmenSafetyNudgeContext
    let onEdit: () -> Void
    let onSendAnyway: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout.weight(.semibold))
                Text("Before you send")
                    .font(.callout.weight(.semibold))
                Spacer()
            }

            Text(context.warningMessage)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Edit Message", action: onEdit)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())

                if context.canSendAnyway, let sendAnyway = onSendAnyway {
                    Button("Send Anyway") {
                        sendAnyway()
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                }

                Spacer()

                Button("Don't Send", action: onDismiss)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .orange.opacity(0.10), radius: 12, y: 4)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
    }
}
