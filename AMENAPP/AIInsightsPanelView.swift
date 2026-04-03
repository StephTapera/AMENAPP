//
//  AIInsightsPanelView.swift
//  AMENAPP
//
//  AI Insights panel for Church Notes — dark liquid glass style.
//

import SwiftUI
import Combine

// MARK: - Shimmer Helper

private struct ShimmerView: View {
    @State private var shimmerOffset: CGFloat = -200

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.07))
                    .frame(height: i == 1 ? 12 : 16)
                    .overlay(
                        GeometryReader { geo in
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.12), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: 80)
                            .offset(x: shimmerOffset)
                        }
                        .clipped()
                    )
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                shimmerOffset = 300
            }
        }
    }
}

// MARK: - Emotional Depth Bar

private struct DepthBar: View {
    let score: Double
    @State private var animatedWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EMOTIONAL DEPTH")
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(2)
                .foregroundColor(.white.opacity(0.4))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.amenPurple)
                        .frame(width: animatedWidth * geo.size.width, height: 6)
                }
            }
            .frame(height: 6)
            .onAppear {
                withAnimation(Motion.adaptive(.spring(response: 0.8, dampingFraction: 0.7)).delay(0.1)) {
                    animatedWidth = CGFloat(score)
                }
            }

            Text(String(format: "%.0f%%", score * 100))
                .font(.caption2)
                .foregroundColor(.amenPurple)
        }
    }
}

// MARK: - AIInsightsPanelView

struct AIInsightsPanelView: View {
    @ObservedObject var viewModel: AIInsightsViewModel
    @Binding var bodyText: String

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: 20).fill(Color.amenPurple.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack {
                Text("AI INSIGHTS")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.4))

                Spacer()

                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.5, dampingFraction: 0.7))) {
                        viewModel.isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.isExpanded ? "Hide" : "Show")
                            .font(.caption)
                            .fontWeight(.medium)
                        Image(systemName: viewModel.isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(GlassPillButtonStyle())
            }
            .padding(.bottom, 12)

            // Body
            Group {
                if !viewModel.hasEnoughText {
                    Text("Keep writing — insights appear after a few sentences.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.35))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if viewModel.isLoading {
                    ShimmerView()
                } else if let insights = viewModel.insights, viewModel.isExpanded {
                    insightsContent(insights)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .padding(16)
        .background(cardBackground)
        .onChange(of: bodyText) { _, newValue in
            Task { await viewModel.analyzeText(newValue) }
        }
    }

    @ViewBuilder
    private func insightsContent(_ insights: AIInsights) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Theme pill
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundColor(.cnGold)
                Text(insights.detectedTheme)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.cnGold)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .strokeBorder(Color.cnGold.opacity(0.4), lineWidth: 1)
                    .background(Capsule().fill(Color.cnGold.opacity(0.08)))
            )

            // Emotional depth bar
            DepthBar(score: insights.emotionalDepthScore)

            // Action items
            VStack(alignment: .leading, spacing: 8) {
                Text("ACTION STEPS")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.4))

                ForEach(Array(insights.actionItems.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .top, spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.cnGold.opacity(0.2))
                                .frame(width: 20, height: 20)
                            Text("\(idx + 1)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.cnGold)
                        }
                        Text(item)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
