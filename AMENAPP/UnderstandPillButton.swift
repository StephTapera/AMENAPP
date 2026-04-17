// UnderstandPillButton.swift
// AMEN App — Accessibility Intelligence Layer (Phase 2)
//
// Small glass capsule "[lightbulb.min] Understand" shown below post content
// when ContentDifficultyScorer rates the post above the display threshold.
// Taps to open UnderstandSheetView. Liquid Glass design.

import SwiftUI

struct UnderstandPillButton: View {

    let text: String
    let contentId: String
    let difficultyScore: ContentDifficultyScore

    @State private var showSheet = false

    var body: some View {
        Button {
            HapticManager.impact(style: .light)
            showSheet = true
            AccessibilitySignalCollector.shared.recordSignal(.simplified)
            AccessibilitySuggestionEngine.shared.evaluate()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "lightbulb.min")
                    .font(.system(size: 11, weight: .medium))
                Text("Understand")
                    .font(AMENFont.semiBold(12))
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.1))
            .clipShape(Capsule())
        }
        .accessibilityLabel("Understand this content")
        .accessibilityHint("Opens simplified explanations of this post")
        .sheet(isPresented: $showSheet) {
            UnderstandSheetView(
                originalText: text,
                contentId: contentId,
                initialMode: difficultyScore.suggestedMode
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}
