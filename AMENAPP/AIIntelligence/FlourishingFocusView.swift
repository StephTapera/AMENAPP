// FlourishingFocusView.swift
// AMENAPP
//
// Wave 5 — the flourishing report + focus-mode surface.
//
//   - Weekly flourishing report: shows ONLY signals with a real source, as plain
//     counts. No leaderboard, no streak, no week-over-week pressure. Uninstrumented
//     signals are named honestly under "Not yet measured" (§2.1).
//   - Focus modes: pick Focus / Reflection / Sabbath / Digital Fast. Sabbath and
//     Digital Fast surface scripture (public-domain KJV) + a journal prompt.
//
// Gated by flourishingMetricsEnabled / focusModesEnabled (default OFF).

import SwiftUI

struct FlourishingFocusView: View {
    @StateObject private var metricsService = FlourishingMetricsService()
    @StateObject private var focus = FocusModeController.shared
    @AppStorage("trust.flourishing.journal") private var journalNote: String = ""

    var body: some View {
        List {
            focusSection

            if focus.mode.surfacesScripture {
                scriptureSection
                journalSection
            }

            flourishingSection
            notMeasuredSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Flourishing")
        .onAppear { metricsService.refresh() }
    }

    // MARK: - Focus modes

    private var focusSection: some View {
        Section {
            ForEach(FocusMode.allCases) { mode in
                Button {
                    focus.mode = mode
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                            Text(mode.blurb).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if focus.mode == mode {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) // state
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Focus")
        } footer: {
            Text("Focus modes hide likes, notifications, and the feed where you've turned them off. Nothing is counted against you.")
        }
    }

    // MARK: - Scripture + journal (Sabbath / Digital Fast)

    private var scriptureSection: some View {
        Section("A verse to sit with") {
            VStack(alignment: .leading, spacing: 6) {
                Text(verse.text).font(.body)
                Text(verse.reference).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var journalSection: some View {
        Section("A line for your journal") {
            TextField("What is God showing you today?", text: $journalNote, axis: .vertical)
                .lineLimit(3...8)
        }
    }

    // MARK: - Flourishing report (real signals only)

    private var flourishingSection: some View {
        Section {
            if let metrics = metricsService.metrics, !metrics.signals.isEmpty {
                ForEach(metrics.signals) { signal in
                    HStack {
                        Text(title(for: signal.key)).font(.subheadline)
                        Spacer()
                        Text(formatted(signal.value))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                }
            } else {
                Text("Nothing measured yet this week.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        } header: {
            Text("This week")
        } footer: {
            if let metrics = metricsService.metrics {
                Text("Week of \(metrics.weekOf). These are counts, not scores — there's no leaderboard.")
            }
        }
    }

    private var notMeasuredSection: some View {
        Group {
            if !metricsService.notYetMeasured.isEmpty {
                Section("Not yet measured") {
                    ForEach(metricsService.notYetMeasured, id: \.self) { name in
                        HStack(spacing: 8) {
                            Image(systemName: "circle.dashed").foregroundStyle(.tertiary)
                            Text(name).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("We show these only when there's a real signal behind them — never a guessed number.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func title(for key: String) -> String {
        switch key {
        case "berean_topics_remembered": return "Topics Berean remembers"
        case "prayer_logged_today":      return "Prayer logged today"
        default:                          return key
        }
    }

    private func formatted(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    // Public-domain (KJV) verses — real content, rotated by weekday (deterministic).
    private var verse: (text: String, reference: String) {
        let verses: [(String, String)] = [
            ("Be still, and know that I am God.", "Psalm 46:10"),
            ("Come unto me, all ye that labour and are heavy laden, and I will give you rest.", "Matthew 11:28"),
            ("The Lord is my shepherd; I shall not want.", "Psalm 23:1"),
            ("In quietness and in confidence shall be your strength.", "Isaiah 30:15"),
            ("This is the day which the Lord hath made; we will rejoice and be glad in it.", "Psalm 118:24")
        ]
        let day = Calendar.current.component(.day, from: Date())
        return verses[day % verses.count]
    }
}

#if DEBUG
#Preview("Flourishing + Focus") {
    NavigationStack { FlourishingFocusView() }
}
#endif
