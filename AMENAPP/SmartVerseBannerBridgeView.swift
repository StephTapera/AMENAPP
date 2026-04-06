// SmartVerseBannerBridgeView.swift
// Smart Header Orchestrator — NON-DESTRUCTIVE wrapper around existing AIDailyVerseCard
//
// This file does NOT modify AIDailyVerseView.swift or any other existing file.
// It simply embeds the existing component with context-driven visibility and styling.

import SwiftUI

struct SmartVerseBannerBridgeView: View {
    let context: HeaderContext
    let style: VersePresentationStyle
    let onShown: () -> Void

    var body: some View {
        switch style {
        case .banner:
            // Embed the existing component exactly as-is — no changes to it
            AIDailyVerseCard()
                .onAppear { onShown() }
                .transition(TopChromeAnimator.expandTransition)

        case .inline:
            // Compact inline row — still uses the same service data underneath
            InlineVersePill()
                .onAppear { onShown() }
                .transition(TopChromeAnimator.fadeSlide)

        case .hidden:
            EmptyView()
        }
    }
}

// MARK: - Inline Pill (no changes to existing components)

private struct InlineVersePill: View {
    @ObservedObject private var verseService = DailyVerseGenkitService.shared

    var body: some View {
        if let verse = verseService.todayVerse {
            HStack(spacing: 8) {
                Image(systemName: "book.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text(verse.reference)
                    .font(.custom("OpenSans-SemiBold", size: 12))
                    .foregroundStyle(.secondary)

                Text("·")
                    .foregroundStyle(.secondary)

                Text(verse.text)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, TopChromeMetrics.containerPadding)
            .padding(.vertical, 8)
        }
    }
}
