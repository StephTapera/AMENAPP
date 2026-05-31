// WellbeingDashboardView.swift
// AMENAPP

import SwiftUI
import Charts

@MainActor
struct WellbeingDashboardView: View {
    @ObservedObject private var tracker = AppUsageTracker.shared
    @State private var goalDraft: Double = 0
    @State private var isEditingGoal = false

    private var todayPercent: Double { tracker.usagePercentage }
    private var streak: Int { tracker.currentStreak }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                headerSection
                weekChartSection
                todayRingSection
                goalSection
                streakSection
                verseSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .navigationTitle("Wellbeing")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { goalDraft = Double(tracker.dailyLimitMinutes) }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your usage, your pace.")
                .font(.title3.weight(.medium))
            Text("AMEN tracks your time so you can set your own rhythm — not the app's.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var weekChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Week")
                .font(.headline)

            Chart(tracker.weekHistoryForChart, id: \.date) { item in
                BarMark(
                    x: .value("Day", item.date, unit: .day),
                    y: .value("Minutes", item.minutes)
                )
                .foregroundStyle(barColor(for: item.minutes))
                .cornerRadius(5)

                RuleMark(y: .value("Goal", tracker.dailyLimitMinutes))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel("\(value.as(Int.self) ?? 0)m")
                }
            }
            .frame(height: 160)
            .accessibilityLabel("Weekly usage bar chart. Goal line at \(tracker.dailyLimitMinutes) minutes.")
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var todayRingSection: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: min(todayPercent, 1))
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(Motion.adaptive(.spring(response: 0.6, dampingFraction: 0.8)), value: todayPercent)
                VStack(spacing: 2) {
                    Text("\(tracker.todayUsageMinutes)")
                        .font(.title2.weight(.semibold).monospacedDigit())
                    Text("min")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 88, height: 88)
            .accessibilityLabel("Today: \(tracker.todayUsageMinutes) of \(tracker.dailyLimitMinutes) minutes used.")

            VStack(alignment: .leading, spacing: 6) {
                Text("Today")
                    .font(.headline)
                Text(todayStatusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Daily Goal")
                    .font(.headline)
                Spacer()
                Text("\(Int(goalDraft)) min")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $goalDraft, in: 5...120, step: 5) {
                Text("Daily limit")
            } minimumValueLabel: {
                Text("5m").font(.caption2)
            } maximumValueLabel: {
                Text("2h").font(.caption2)
            }
            .tint(.primary)
            .onChange(of: goalDraft) { _, newValue in
                tracker.updateDailyLimit(Int(newValue))
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var streakSection: some View {
        HStack(spacing: 16) {
            Image(systemName: streak > 0 ? "flame.fill" : "flame")
                .font(.title2)
                .foregroundStyle(streak > 0 ? .orange : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(streak == 1 ? "1 day streak" : "\(streak) day streak")
                    .font(.headline)
                Text(streak > 0
                     ? "Under your goal \(streak) day\(streak == 1 ? "" : "s") in a row."
                     : "Hit your goal today to start a streak.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private var verseSection: some View {
        VStack(spacing: 8) {
            Text("\"Be still, and know that I am God\"")
                .font(.subheadline.italic())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Psalm 46:10")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .tracking(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private var todayStatusText: String {
        let remaining = tracker.remainingMinutes
        if tracker.hasReachedLimit {
            return "You've reached your goal for today. Rest well."
        } else if remaining <= 5 {
            return "\(remaining) min left — almost at your goal."
        } else {
            return "\(remaining) min remaining of your \(tracker.dailyLimitMinutes) min goal."
        }
    }

    private var ringColor: Color {
        todayPercent >= 1 ? .orange : .primary
    }

    private func barColor(for minutes: Int) -> Color {
        guard tracker.dailyLimitMinutes > 0 else { return .secondary }
        return minutes <= tracker.dailyLimitMinutes ? .primary.opacity(0.8) : .orange
    }
}
