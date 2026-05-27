import SwiftUI

struct BadgeDetailSheet: View {
    let badge: ImpactBadge
    let allBadges: [ImpactBadge]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    badgeHeroSection
                    badgeInfoSection
                    allBadgesSection
                }
                .padding(16)
                .padding(.bottom, 32)
            }
            .navigationTitle("Badge Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                        .font(.custom("OpenSans-Regular", size: 16))
                }
            }
        }
    }

    private var badgeHeroSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(badge.badgeColorValue.opacity(0.15))
                    .frame(width: 100, height: 100)
                Image(systemName: badge.icon)
                    .font(.system(size: 48))
                    .foregroundStyle(badge.badgeColorValue)
            }
            .symbolEffect(.pulse)
            Text(badge.name)
                .font(.custom("OpenSans-Bold", size: 22))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            HStack {
                Text(badge.type.displayName)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(badge.badgeColorValue.opacity(0.15))
                    .foregroundStyle(badge.badgeColorValue)
                    .cornerRadius(10)
                Text(badge.tier.displayName)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AmenTheme.Colors.surfaceChip)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .cornerRadius(10)
            }
            if let earned = badge.earnedAt?.dateValue() {
                Text("Earned \(earned.formatted(date: .long, time: .omitted))")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            }
        }
        .padding(20)
        .background(AmenTheme.Colors.surfaceCard)
        .cornerRadius(16)
    }

    private var badgeInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About this badge")
                .font(.custom("OpenSans-Bold", size: 15))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text(badge.description)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .lineSpacing(4)
        }
        .padding(14)
        .background(AmenTheme.Colors.surfaceCard)
        .cornerRadius(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var allBadgesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("All Earned Badges (\(allBadges.count))")
                .font(.custom("OpenSans-Bold", size: 15))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(allBadges) { b in
                    VStack(spacing: 6) {
                        ZStack {
                            Circle().fill(b.badgeColorValue.opacity(0.12)).frame(width: 52, height: 52)
                            Image(systemName: b.icon).font(.title2).foregroundStyle(b.badgeColorValue)
                        }
                        Text(b.name).font(.custom("OpenSans-Regular", size: 10)).foregroundStyle(AmenTheme.Colors.textSecondary).lineLimit(2).multilineTextAlignment(.center)
                    }
                    .accessibilityLabel(b.name)
                }
            }
        }
    }
}
