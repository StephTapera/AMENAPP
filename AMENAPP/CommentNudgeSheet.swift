//
//  CommentNudgeSheet.swift
//  AMENAPP
//
//  Liquid Glass bottom sheet shown when checkCommentQuality returns "nudge".
//  Displays contextual suggestion prompts. The user can:
//    • Edit their comment  → sheet dismisses, focus returns to composer
//    • Post anyway         → onPostAnyway() is called, write proceeds
//
//  DESIGN RULES:
//    - Nudges are suggestions, NOT blocks. The post-anyway path is always available.
//    - Safety "warn" nudges are shown with amber accent; neutral nudges with default.
//    - Sheet is non-dismissible by swipe when safetyDecision == .warn
//      (user must explicitly choose an action).
//

import SwiftUI

// MARK: - NudgeSheet

struct CommentNudgeSheet: View {
    let nudges: [String]
    let safetyDecision: CommentQualityResponse.SafetyDecision
    let onEdit: () -> Void
    let onPostAnyway: () -> Void

    // Non-dismissible by swipe when safety warns
    private var allowSwipeDismiss: Bool {
        safetyDecision != .warn
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Handle ──────────────────────────────────────────────────────
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 8)

            // ── Header ──────────────────────────────────────────────────────
            HStack(spacing: 10) {
                Image(systemName: safetyDecision == .warn
                      ? "exclamationmark.triangle.fill"
                      : "lightbulb.fill")
                    .foregroundStyle(safetyDecision == .warn ? .orange : .yellow)
                    .font(.title3)

                Text(safetyDecision == .warn
                     ? "Before You Post"
                     : "A Few Thoughts")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Text("These are suggestions — you can always post anyway.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

            // ── Nudge rows ──────────────────────────────────────────────────
            VStack(spacing: 10) {
                ForEach(nudges, id: \.self) { nudge in
                    NudgeRow(text: nudge, isWarning: safetyDecision == .warn)
                }
            }
            .padding(.horizontal, 16)

            Divider()
                .padding(.vertical, 20)

            // ── Actions ─────────────────────────────────────────────────────
            VStack(spacing: 12) {
                Button(action: onEdit) {
                    Label("Edit my comment", systemImage: "pencil")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.accentColor)
                        )
                        .foregroundStyle(.white)
                }

                Button(action: onPostAnyway) {
                    Text("Post anyway")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(
            // Liquid Glass material
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
        )
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(!allowSwipeDismiss)
    }
}

// MARK: - NudgeRow

private struct NudgeRow: View {
    let text: String
    let isWarning: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(isWarning ? Color.orange.opacity(0.2) : Color.accentColor.opacity(0.15))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: isWarning ? "exclamationmark" : "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isWarning ? .orange : .accentColor)
                )

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            CommentNudgeSheet(
                nudges: [
                    "This may sound harsh — want to rewrite before posting?",
                    "Consider adding a Scripture reference to support your thought.",
                    "Did you read or watch this fully? A more thoughtful reply builds community.",
                ],
                safetyDecision: .warn,
                onEdit: { },
                onPostAnyway: { }
            )
        }
}
#endif
