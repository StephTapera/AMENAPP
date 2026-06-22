// CompactTopChromeView.swift
// Smart Header Orchestrator — Compact single-line bar (scroll-collapsed state)

import SwiftUI

struct CompactTopChromeView: View {
    let greeting: String
    let accentColor: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(accentColor.opacity(0.2))
                .frame(width: 6, height: 6)

            Text(greeting)
                .font(.custom("OpenSans-SemiBold", size: 13))
                .foregroundStyle(Color(.label))
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, TopChromeMetrics.containerPadding)
        .padding(.vertical, 8)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
        )
    }
}
