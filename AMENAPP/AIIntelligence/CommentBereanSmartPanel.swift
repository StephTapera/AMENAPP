// CommentBereanSmartPanel.swift
// AMENAPP — Smart Comments Wave 3
//
// Berean-powered smart features panel for a comment thread.
// Shows as a collapsed glass capsule pill; expands on tap to reveal async-loaded insights.
//
// Liquid Glass rules:
//   - Collapsed pill: .ultraThinMaterial (floating control)
//   - Expanded card: opaque white background (text content — no-glass-on-glass)
//   - Reduce-transparency fallback: solid systemGray6 pill / systemBackground card

import SwiftUI
import Foundation

struct CommentBereanSmartPanel: View {

    let postId: String
    let commentCount: Int

    // MARK: - State

    @State private var isExpanded = false
    @State private var insights: ThreadInsights?
    @State private var isLoading = false

    // MARK: - Guard

    var body: some View {
        guard AMENFeatureFlags.shared.commentBereanSmartEnabled else {
            return AnyView(EmptyView())
        }
        return AnyView(panelContent)
    }

    // MARK: - Panel Content

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsed pill — always visible
            collapsedPill

            // Expanded card — shown below the pill when expanded
            if isExpanded {
                expandedCard
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
    }

    // MARK: - Collapsed Pill

    private var collapsedPill: some View {
        Button(action: handlePillTap) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.blue)
                Text("Berean insights")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.blue)
                Spacer(minLength: 0)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(pillBackground)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded Card

    private var expandedCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isLoading || insights == nil {
                loadingSkeletons
            } else if let insights = insights {
                insightsContent(insights)
            }
        }
        .padding(16)
        .background(expandedCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
        .padding(.top, 8)
    }

    // MARK: - Loading Skeletons

    private var loadingSkeletons: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(uiColor: .systemGray5))
                    .frame(height: 12)
            }
        }
        .redacted(reason: .placeholder)
    }

    // MARK: - Insights Content

    private func insightsContent(_ insights: ThreadInsights) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // "Summarized by Berean" header
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.blue.opacity(0.7))
                Text("Summarized by Berean · \(insights.analyzedCount) comment\(insights.analyzedCount == 1 ? "" : "s") analyzed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Thread summary
            if let summary = insights.threadSummary {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Thread Summary")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(summary)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("No summary available.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            // Prayer requests count
            if insights.prayerRequestCount > 0 {
                countRow(
                    icon: "hands.and.sparkles.fill",
                    color: .purple,
                    label: "\(insights.prayerRequestCount) prayer request\(insights.prayerRequestCount == 1 ? "" : "s")"
                )
            }

            // Testimonies count
            if insights.testimonyCount > 0 {
                countRow(
                    icon: "quote.bubble.fill",
                    color: .blue,
                    label: "\(insights.testimonyCount) testimon\(insights.testimonyCount == 1 ? "y" : "ies")"
                )
            }

            // Top questions (up to 3)
            if !insights.topQuestions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Questions in this thread")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    ForEach(insights.topQuestions.prefix(3), id: \.self) { question in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                            Text(question)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    private func countRow(icon: String, color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Backgrounds

    @ViewBuilder
    private var pillBackground: some View {
        if UIAccessibility.isReduceTransparencyEnabled {
            Capsule().fill(Color(uiColor: .systemGray6))
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.blue.opacity(0.15), lineWidth: 0.5)
                )
        }
    }

    @ViewBuilder
    private var expandedCardBackground: some View {
        if UIAccessibility.isReduceTransparencyEnabled {
            Color(uiColor: .systemBackground)
        } else {
            Color(uiColor: .systemBackground)
        }
    }

    // MARK: - Actions

    private func handlePillTap() {
        isExpanded.toggle()
        if isExpanded && insights == nil {
            Task { await loadInsights() }
        }
    }

    // MARK: - Load Insights (stub — Wave 4 wires real callable)

    private func loadInsights() async {
        isLoading = true
        defer { isLoading = false }

        // TODO: Wave 4 — call `getBereanThreadInsights` callable with postId.
        // For now, return graceful empty state so UI is verifiable.
        // Simulated async delay
        try? await Task.sleep(nanoseconds: 300_000_000)

        insights = ThreadInsights(
            analyzedCount: commentCount,
            threadSummary: nil,
            prayerRequestCount: 0,
            testimonyCount: 0,
            topQuestions: []
        )
    }
}

// MARK: - Thread Insights Model

private struct ThreadInsights {
    let analyzedCount: Int
    let threadSummary: String?
    let prayerRequestCount: Int
    let testimonyCount: Int
    let topQuestions: [String]
}
