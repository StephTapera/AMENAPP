import SwiftUI

struct WellnessStreakCard: View {
    let streak: WellnessStreak
    let service: WellnessStreakService
    @State private var showDetail = false

    var nextBadge: StreakBadge? { service.nextBadge(for: streak) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: streak.type.icon)
                    .foregroundStyle(Color(red: 0.10, green: 0.60, blue: 0.56))
                Text(streak.type.displayName)
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Spacer()
                if streak.shared {
                    Image(systemName: "person.2.fill")
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }
            }
            HStack(alignment: .bottom, spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(Color(red: 0.95, green: 0.45, blue: 0.10))
                Text("\(streak.currentStreak)")
                    .font(.custom("OpenSans-Bold", size: 32))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Text("days")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .padding(.bottom, 5)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Best")
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                    Text("\(streak.longestStreak) days")
                        .font(.custom("OpenSans-Bold", size: 13))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
            }
            if let badge = nextBadge {
                let progress = Double(streak.currentStreak) / Double(badge.daysRequired)
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: min(progress, 1.0))
                        .tint(Color(red: 0.10, green: 0.60, blue: 0.56))
                    Text("\(badge.daysRequired - streak.currentStreak) days until \(badge.displayName)")
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }
            }
            if !streak.badges.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(streak.badges, id: \.self) { badgeId in
                            if let badge = StreakBadge.all.first(where: { $0.id == badgeId }) {
                                Image(systemName: badge.icon)
                                    .foregroundStyle(Color(red: 0.83, green: 0.69, blue: 0.22))
                                    .font(.title3)
                                    .accessibilityLabel(badge.displayName)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(AmenTheme.Colors.surfaceCard)
        .cornerRadius(14)
        .onTapGesture { showDetail = true }
        .accessibilityLabel("\(streak.type.displayName), \(streak.currentStreak) day streak")
        .sheet(isPresented: $showDetail) { WellnessStreakDetailView(streak: streak, service: service) }
    }
}
