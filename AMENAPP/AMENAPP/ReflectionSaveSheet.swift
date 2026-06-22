// ReflectionSaveSheet.swift
// AMENAPP — Private, gentle save sheet for the Berean "Save Reflection" action.
//
// Signature (frozen):
//   ReflectionSaveSheet(draft: ReflectionDraft, onSave: () -> Void, onCancel: () -> Void)
//
// Design intent: entirely private, no sharing nudges, no engagement framing,
// no streaks, no comparisons. Solid systemBackground — intentional for private content.

import SwiftUI

// MARK: - View

struct ReflectionSaveSheet: View {

    let draft: ReflectionDraft
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var saved: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Solid background — intentional for private content (no blur material)
                Color(.systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: DesignTokens.spacingL) {
                            reflectionTextBlock
                            if draft.verse != nil || draft.mood != nil {
                                pillRow
                            }
                            privateNotice
                        }
                        .padding(.horizontal, DesignTokens.spacingM)
                        .padding(.top, DesignTokens.spacingM)
                        .padding(.bottom, DesignTokens.spacingM)
                    }

                    actionFooter
                        .padding(.horizontal, DesignTokens.spacingM)
                        .padding(.bottom, DesignTokens.spacingL)
                }
            }
            .navigationTitle("Save Reflection")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemBackground))
    }

    // MARK: - Reflection text block

    private var reflectionTextBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(draft.text)
                .font(.systemScaled(15))
                .foregroundStyle(DesignTokens.textSecondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DesignTokens.spacingM)
        }
        .bereanLiquidGlass(cornerRadius: 18)
        .accessibilityLabel("Your reflection: \(draft.text)")
    }

    // MARK: - Verse + mood pills

    private var pillRow: some View {
        HStack(spacing: DesignTokens.spacingS) {
            if let verse = draft.verse {
                glassInfoPill(icon: "book.closed", text: verse)
            }
            if let mood = draft.mood {
                glassInfoPill(icon: "face.smiling", text: mood)
            }
            Spacer()
        }
    }

    private func glassInfoPill(icon: String, text: String) -> some View {
        HStack(spacing: DesignTokens.spacingXS) {
            Image(systemName: icon)
                .font(.systemScaled(11, weight: .medium))
                .foregroundStyle(DesignTokens.textTertiary)
            Text(text)
                .font(.systemScaled(13))
                .foregroundStyle(DesignTokens.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, DesignTokens.spacingM)
        .padding(.vertical, DesignTokens.spacingS)
        .background(
            Capsule()
                .fill(DesignTokens.glassFill)
                .overlay(
                    Capsule()
                        .strokeBorder(DesignTokens.glassStroke, lineWidth: 0.75)
                )
        )
    }

    // MARK: - Private notice

    private var privateNotice: some View {
        HStack(alignment: .top, spacing: DesignTokens.spacingS) {
            Image(systemName: "lock.fill")
                .font(.systemScaled(11))
                .foregroundStyle(DesignTokens.textTertiary)
                .padding(.top, 1)
            Text("This reflection is saved only to your device and is never shared.")
                .font(.systemScaled(12))
                .foregroundStyle(DesignTokens.textSecondary)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Action footer

    @ViewBuilder
    private var actionFooter: some View {
        if saved {
            // Brief success confirmation before the sheet auto-dismisses
            HStack(spacing: DesignTokens.spacingS) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.systemScaled(18, weight: .medium))
                    .foregroundStyle(.green)
                Text("Reflection saved.")
                    .font(.systemScaled(15, weight: .medium))
                    .foregroundStyle(DesignTokens.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        } else {
            VStack(spacing: DesignTokens.spacingS) {
                Button {
                    handleSave()
                } label: {
                    Text("Save reflection")
                        .font(.systemScaled(16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.radiusCapsule, style: .continuous)
                                .fill(Color.black)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Save this reflection privately")

                Button {
                    onCancel()
                } label: {
                    Text("Not now")
                        .font(.systemScaled(15))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss without saving")
            }
        }
    }

    // MARK: - Save handler

    @MainActor
    private func handleSave() {
        HapticManager.notification(type: .success)
        withAnimation(.amenSpringStandard) {
            saved = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            onSave()
        }
    }
}

// MARK: - Preview

#Preview {
    ReflectionSaveSheet(
        draft: ReflectionDraft(
            text: "Today's sermon on Proverbs 3:5-6 reminded me to lean not on my own understanding. I want to apply this when I feel anxious about the future.",
            verse: "Proverbs 3:5-6",
            mood: "Grateful"
        ),
        onSave: {},
        onCancel: {}
    )
}

#Preview("Text only") {
    ReflectionSaveSheet(
        draft: ReflectionDraft(
            text: "Feeling grounded after prayer this morning."
        ),
        onSave: {},
        onCancel: {}
    )
}
