import SwiftUI

struct WellnessStreakDetailView: View {
    let streak: WellnessStreak
    let service: WellnessStreakService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    streakHeaderSection
                    badgesSection
                    if streak.type == .journaling {
                        journalSection
                    }
                }
                .padding(16)
                .padding(.bottom, 32)
            }
            .navigationTitle(streak.type.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                        .font(.custom("OpenSans-Regular", size: 16))
                }
            }
        }
    }

    private var streakHeaderSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 24) {
                streakStatView(value: "\(streak.currentStreak)", label: "Current", icon: "flame.fill", color: Color(red: 0.95, green: 0.45, blue: 0.10))
                streakStatView(value: "\(streak.longestStreak)", label: "Best", icon: "star.fill", color: Color(red: 0.83, green: 0.69, blue: 0.22))
                streakStatView(value: "\(streak.totalDays)", label: "Total Days", icon: "calendar.badge.checkmark", color: Color(red: 0.10, green: 0.60, blue: 0.56))
            }
            .padding(16)
            .background(AmenTheme.Colors.surfaceCard)
            .cornerRadius(14)
        }
    }

    private func streakStatView(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(color)
            Text(value)
                .font(.custom("OpenSans-Bold", size: 24))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text(label)
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var badgesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Earned Badges")
                .font(.custom("OpenSans-Bold", size: 17))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            if streak.badges.isEmpty {
                Text("Keep going! Earn your first badge at 7 days.")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            } else {
                HStack(spacing: 16) {
                    ForEach(streak.badges, id: \.self) { badgeId in
                        if let badge = StreakBadge.all.first(where: { $0.id == badgeId }) {
                            VStack(spacing: 4) {
                                Image(systemName: badge.icon)
                                    .font(.title)
                                    .foregroundStyle(Color(red: 0.83, green: 0.69, blue: 0.22))
                                Text(badge.displayName)
                                    .font(.custom("OpenSans-Regular", size: 11))
                                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(width: 70)
                            .accessibilityLabel(badge.displayName)
                        }
                    }
                }
            }
        }
    }

    private var journalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Journal")
                .font(.custom("OpenSans-Bold", size: 17))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            ForEach(service.journalEntries.prefix(5)) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if let mood = entry.mood { Text(mood.emoji) }
                        Text(entry.date.map { $0.dateValue().formatted(date: .abbreviated, time: .omitted) } ?? "")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                    }
                    Text(entry.entry)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .lineLimit(3)
                }
                .padding(10)
                .background(AmenTheme.Colors.surfaceCard)
                .cornerRadius(10)
            }
        }
    }
}
