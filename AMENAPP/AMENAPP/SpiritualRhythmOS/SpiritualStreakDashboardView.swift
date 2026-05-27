// SpiritualStreakDashboardView.swift
// AMENAPP — SpiritualRhythmOS
//
// Dashboard showing active streaks. Warm, encouraging, no shame language.
// White background, native controls, grace-first design.
// Cards use a 2-column LazyVGrid with stroked RoundedRectangle cells.

import SwiftUI

// MARK: - SpiritualStreakDashboardView

struct SpiritualStreakDashboardView: View {
    @StateObject private var service = SpiritualRhythmOSService.shared

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                momentumBanner
                inactivityPauseBanner
                streakGrid
                footerNote
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("Your Rhythms")
        .navigationBarTitleDisplayMode(.large)
        .task { service.startListening() }
    }

    // MARK: - Momentum Banner

    private var momentumBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(service.settings.momentumState.displayName)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.primary)

            Text(service.settings.momentumState.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Inactivity Pause Banner

    @ViewBuilder
    private var inactivityPauseBanner: some View {
        if service.settings.isInactivityPauseActive {
            HStack(spacing: 12) {
                Image(systemName: "moon.zzz.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Most reminders are paused.")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text("Welcome back. No catching up required.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Resume") {
                    Task { await service.handleUserReturn() }
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.primary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
        }
    }

    // MARK: - Streak Grid

    private var streakGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(enabledTypes, id: \.rawValue) { type in
                let streak = service.streaks.first(where: { $0.type == type })
                StreakCard(type: type, streak: streak, service: service)
            }
        }
    }

    private var enabledTypes: [SpiritualStreakType] {
        SpiritualStreakType.allCases.filter {
            service.settings.enabledStreakTypes.contains($0)
        }
    }

    // MARK: - Footer

    private var footerNote: some View {
        Text("Streaks encourage consistency, not perfection.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - StreakCard

private struct StreakCard: View {
    let type: SpiritualStreakType
    /// `nil` when no streak document has been created for this type yet.
    let streak: SpiritualStreak?
    @ObservedObject var service: SpiritualRhythmOSService

    private var currentStreak: Int { streak?.currentStreak ?? 0 }
    private var longestStreak: Int { streak?.longestStreak ?? 0 }
    private var isInGracePeriod: Bool { streak?.isInGracePeriod ?? false }

    /// True if the user has already logged this type today.
    private var loggedToday: Bool {
        guard let lastActivity = streak?.lastActivityAt?.dateValue() else { return false }
        return Calendar.current.isDateInToday(lastActivity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Icon
            Image(systemName: type.icon)
                .font(.title)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Activity name
            Text(type.displayName)
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // Current streak count
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(currentStreak)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                Text("days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Grace period indicator
            if isInGracePeriod {
                Text("Grace period")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.orange.opacity(0.12))
                    )
            }

            // Milestone badge
            if longestStreak >= 7 {
                Text("Your best: \(longestStreak) days")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            // Primary action button
            if isInGracePeriod {
                // Grace recovery
                Button {
                    Task { await service.requestGraceRecovery(for: type) }
                } label: {
                    Text("Recover")
                        .font(.caption)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .controlSize(.small)
            } else if loggedToday {
                // Already logged — show gentle confirmation
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Logged")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Not yet logged today
                Button {
                    Task { await service.recordActivity(type) }
                } label: {
                    Text(currentStreak == 0 ? "Start today" : "Log today")
                        .font(.caption)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.primary)
                .controlSize(.small)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .systemBackground))
                )
        )
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        SpiritualStreakDashboardView()
    }
}
#endif
