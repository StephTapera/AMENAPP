// SpiritualStreakView.swift
// AMENAPP — Calm Control + Spiritual Rhythm OS
//
// Shows the user's spiritual rhythm across four activity types.
// Design rules:
//   • Calm, grace-based language. No flame emojis. No "broken streak" copy.
//   • "Your Rhythm" framing — not "Your Streaks".
//   • Momentum indicator is always private and clearly labeled as such.
//   • Full Dynamic Type, VoiceOver, Reduce Motion support.

import SwiftUI

// MARK: - SpiritualStreakView

struct SpiritualStreakView: View {

    @ObservedObject var service: SpiritualRhythmService

    var body: some View {
        NavigationStack {
            List {
                rhythmSection
                momentumSection
                gracePeriodSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Your Rhythm")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await service.loadAll()
            }
        }
    }

    // MARK: - Rhythm Section

    private var rhythmSection: some View {
        Section {
            ForEach(AmenStreakType.allCases, id: \.self) { type in
                StreakCard(streak: service.streak(for: type)) {
                    Task { await service.recoverStreak(type: type) }
                }
            }
        } header: {
            Text("Your Rhythms")
        } footer: {
            Text("Consistency matters. So does rest. Both are part of a healthy rhythm.")
                .font(.caption)
        }
    }

    // MARK: - Momentum Section

    private var momentumSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(service.rhythm.momentumLabel.displayName)
                            .font(.title3.weight(.semibold))
                        Text(service.rhythm.momentumLabel.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }

                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text("This is private and only visible to you.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Your momentum: \(service.rhythm.momentumLabel.displayName). \(service.rhythm.momentumLabel.subtitle). This information is private and only visible to you."
            )
        } header: {
            Text("Momentum")
        }
    }

    // MARK: - Grace Period Section

    private var gracePeriodSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "heart")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Grace days available")
                        .font(.subheadline.weight(.medium))
                    Text(graceDaysMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        } footer: {
            Text("Life happens — we understand. Grace days let your rhythm breathe without resetting.")
                .font(.caption)
        }
    }

    private var graceDaysMessage: String {
        let totalGrace = service.streaks.values.map(\.gracePeriodUsed ? 0 : 1).reduce(0, +)
        let noun = totalGrace == 1 ? "grace day" : "grace days"
        return "You have \(totalGrace) \(noun) available across your rhythms. Life happens — we understand."
    }
}

// MARK: - StreakCard

private struct StreakCard: View {

    let streak: AmenStreak
    let onResume: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var stateLabel: String {
        switch streak.state {
        case .alive:  return "Active"
        case .paused: return "Resting"
        case .broken: return "Recovering"
        }
    }

    private var encouragementText: String {
        switch streak.state {
        case .alive  where streak.currentCount == 0:
            return "Start when you're ready. There's no pressure."
        case .alive  where streak.currentCount < 7:
            return "Small steps build lasting roots. You're on your way."
        case .alive  where streak.currentCount < 30:
            return "Consistency is forming something meaningful. Keep going."
        case .alive:
            return "You are building a deep and steady rhythm. Beautiful."
        case .paused:
            return "Resting is part of the journey. Come back whenever you're ready."
        case .broken:
            return "You can pick this back up — grace is always available."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: streak.type.icon)
                    .font(.title3)
                    .foregroundStyle(streak.state.isAlive ? .primary : .secondary)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(streak.type.displayName)
                        .font(.headline)
                    Text(stateLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(stateLabel == "Active" ? .primary : .secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(streak.displayCount)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(streak.state.isAlive ? .primary : .secondary)
                    Text("Best: \(streak.longestCount) days")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Text(encouragementText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if streak.state == .paused && !streak.gracePeriodUsed {
                Button(action: onResume) {
                    Text("Resume")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(.systemGray6))
                        )
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Resume \(streak.type.displayName) rhythm")
                .accessibilityHint("Marks today as a grace day and continues your rhythm from where you left off")
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(streak.type.displayName). \(stateLabel). \(streak.displayCount). Best: \(streak.longestCount) days. \(encouragementText)"
        )
    }
}

// MARK: - AmenStreakLifeState helper

private extension AmenStreakLifeState {
    var isAlive: Bool { self == .alive }
}

// MARK: - Preview

#if DEBUG
#Preview {
    SpiritualStreakView(service: SpiritualRhythmService.shared)
}
#endif
