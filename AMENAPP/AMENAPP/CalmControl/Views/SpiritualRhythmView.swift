import SwiftUI

struct SpiritualRhythmView: View {
    @StateObject private var rhythmService = SpiritualRhythmService.shared
    @State private var showRecoverySheet = false
    @State private var recoveryStreakType: AmenStreakType?

    var body: some View {
        NavigationStack {
            List {
                // MARK: Momentum
                momentumSection

                // MARK: Streaks
                Section {
                    ForEach(AmenStreakType.allCases, id: \.self) { type in
                        StreakRowView(streak: rhythmService.streak(for: type)) {
                            recoveryStreakType = type
                            showRecoverySheet = true
                        }
                    }
                } header: {
                    Text("Your Rhythms")
                } footer: {
                    Text("Streaks celebrate consistency, not performance. Taking a break is part of the journey.")
                        .font(.caption)
                }

                // MARK: Sabbath Mode
                Section {
                    Toggle("Sabbath Mode", isOn: Binding(
                        get: { rhythmService.rhythm.sabbathModeEnabled },
                        set: { newVal in
                            Task { await rhythmService.setSabbathMode(enabled: newVal) }
                        }
                    ))
                } header: {
                    Text("Rest")
                } footer: {
                    Text("Sabbath Mode pauses all non-essential notifications and social pressure indicators.")
                        .font(.caption)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Spiritual Rhythm")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await rhythmService.loadAll()
                await rhythmService.checkInactivityPolicy()
            }
            .sheet(isPresented: $showRecoverySheet) {
                if let type = recoveryStreakType {
                    StreakRecoverySheet(streakType: type)
                }
            }
        }
    }

    private var momentumSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(rhythmService.rhythm.momentumLabel.displayName)
                    .font(.title2.weight(.semibold))
                Text(rhythmService.rhythm.momentumLabel.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        } header: {
            Text("Momentum")
        }
    }
}

// MARK: - Streak Row

struct StreakRowView: View {
    let streak: AmenStreak
    let onRecover: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: streak.type.icon)
                .font(.title3)
                .foregroundStyle(streak.state.isAlive ? .primary : .tertiary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(streak.type.displayName)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 4) {
                    Text(streak.displayCount)
                        .font(.caption)
                        .foregroundStyle(streak.state.isAlive ? .primary : .secondary)
                    if !streak.state.isAlive {
                        Text("· Paused")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if streak.state == .paused && !streak.gracePeriodUsed {
                Button("Continue") { onRecover() }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Streak Recovery Sheet

struct StreakRecoverySheet: View {
    let streakType: AmenStreakType
    @StateObject private var rhythmService = SpiritualRhythmService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: streakType.icon)
                    .font(.system(size: 52))
                    .foregroundStyle(.primary)

                VStack(spacing: 8) {
                    Text("Welcome back.")
                        .font(.title2.weight(.semibold))
                    Text("Your \(streakType.displayName) rhythm is here whenever you are. Would you like to continue where you left off?")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button("Continue My Rhythm") {
                    Task {
                        await rhythmService.recoverStreak(type: streakType)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Not right now") { dismiss() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Resume Rhythm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    SpiritualRhythmView()
}
