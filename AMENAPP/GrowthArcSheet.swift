//
//  GrowthArcSheet.swift
//  AMENAPP
//
//  Growth Arc — 52-week note history, top themes, and faith vocabulary score.
//

import SwiftUI
#if canImport(Charts)
import Charts
#endif

struct GrowthArcSheet: View {
    @StateObject var viewModel: GrowthArcViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "050508").ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {

                        // Chart
                        VStack(alignment: .leading, spacing: 10) {
                            sectionHeader("52-WEEK GROWTH")

                            #if canImport(Charts)
                            ChartsLineChart(data: viewModel.weeklyData)
                                .frame(height: 180)
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(.ultraThinMaterial)
                                        .overlay(RoundedRectangle(cornerRadius: 20).fill(Color.amenPurple.opacity(0.06)))
                                        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                                )
                            #else
                            FallbackBarChart(data: viewModel.weeklyData)
                                .frame(height: 180)
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(.ultraThinMaterial)
                                        .overlay(RoundedRectangle(cornerRadius: 20).fill(Color.amenPurple.opacity(0.06)))
                                        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                                )
                            #endif
                        }

                        // Top Themes
                        VStack(alignment: .leading, spacing: 10) {
                            sectionHeader("TOP THEMES")

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(viewModel.topThemes.prefix(8), id: \.theme) { entry in
                                        ThemePill(theme: entry.theme, count: entry.count)
                                    }
                                }
                                .padding(.horizontal, 4)
                            }
                        }

                        // Vocabulary score
                        VStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.ultraThinMaterial)
                                .overlay(RoundedRectangle(cornerRadius: 20).fill(Color.cnGold.opacity(0.06)))
                                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                                .overlay(
                                    VStack(spacing: 8) {
                                        Text("\(viewModel.animatedScore)")
                                            .font(.systemScaled(48, weight: .bold, design: .rounded))
                                            .foregroundColor(.cnGold)

                                        Text("FAITH VOCABULARY SCORE")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .tracking(2)
                                            .foregroundColor(.white.opacity(0.4))

                                        Text("words in your spiritual lexicon")
                                            .font(.subheadline)
                                            .foregroundColor(.white.opacity(0.5))
                                    }
                                    .padding(24)
                                )
                                .frame(height: 160)
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle("My Growth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.cnGold)
                }
            }
        }
        .presentationBackground(.ultraThinMaterial)
        .presentationCornerRadius(28)
        .presentationDetents([.large])
        .onAppear {
            viewModel.loadGrowthData()
            viewModel.animateScoreCount()
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .tracking(2)
            .foregroundColor(.white.opacity(0.4))
    }
}

// MARK: - Charts Line Chart (iOS 16+)

#if canImport(Charts)
private struct ChartsLineChart: View {
    let data: [GrowthDataPoint]
    @State private var appeared = false

    var body: some View {
        Chart {
            ForEach(data) { point in
                AreaMark(
                    x: .value("Week", point.weekNumber),
                    y: .value("Notes", appeared ? point.noteCount : 0)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.amenPurple.opacity(0.6), Color.amenPurple.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Week", point.weekNumber),
                    y: .value("Notes", appeared ? point.noteCount : 0)
                )
                .foregroundStyle(Color.amenPurple)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: 13)) { value in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel {
                    if let week = value.as(Int.self) {
                        Text("W\(week)")
                            .font(.caption2)
                            .foregroundStyle(Color.white.opacity(0.35))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel()
                    .foregroundStyle(Color.white.opacity(0.35))
            }
        }
        .onAppear {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.8).delay(0.2)) {
                appeared = true
            }
        }
    }
}
#endif

// MARK: - Fallback Bar Chart (Canvas-based)

private struct FallbackBarChart: View {
    let data: [GrowthDataPoint]
    @State private var appeared = false

    var body: some View {
        Canvas { context, size in
            guard !data.isEmpty else { return }
            let maxCount = max(1, data.map(\.noteCount).max() ?? 1)
            let barWidth = size.width / CGFloat(data.count) * 0.6
            let spacing = size.width / CGFloat(data.count)

            for (i, point) in data.enumerated() {
                let fraction = appeared ? CGFloat(point.noteCount) / CGFloat(maxCount) : 0
                let barH = fraction * (size.height - 20)
                let x = CGFloat(i) * spacing + (spacing - barWidth) / 2
                let y = size.height - barH - 10

                let rect = CGRect(x: x, y: y, width: barWidth, height: barH)
                let path = Path(roundedRect: rect, cornerRadius: 2)
                context.fill(path, with: .color(Color.amenPurple.opacity(0.7)))
            }
        }
        .onAppear {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.8).delay(0.2)) {
                appeared = true
            }
        }
    }
}

// MARK: - Theme Pill

private struct ThemePill: View {
    let theme: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(theme)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.8))
            Text("\(count)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.amenPurple)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.amenPurple.opacity(0.2)))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.white.opacity(0.04)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8))
        )
    }
}
