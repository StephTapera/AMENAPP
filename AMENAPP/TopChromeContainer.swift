// TopChromeContainer.swift
// Smart Header Orchestrator — Liquid Glass shell that wraps chrome content

import SwiftUI

struct TopChromeContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: TopChromeMetrics.containerRadius)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: TopChromeMetrics.containerRadius)
                        .strokeBorder(Color(.separator).opacity(0.25), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, TopChromeMetrics.containerPadding)
    }
}

// MARK: - Flat container variant (flush to top, no rounded bottom)

struct TopChromeFlushContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(.ultraThinMaterial)
        .overlay(
            Divider(), alignment: .bottom
        )
    }
}
