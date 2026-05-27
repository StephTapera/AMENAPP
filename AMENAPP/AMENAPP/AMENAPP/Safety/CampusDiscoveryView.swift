import SwiftUI

// MARK: - CampusDiscoveryView
// Campus mode discovery: local groups, events, and study hubs for campus users.
// Only shown when the user's interaction mode is .campus.

struct CampusDiscoveryView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    CampusModeHeroBanner()
                    CampusSectionCard(
                        title: "Study Groups",
                        subtitle: "Find groups studying the same material",
                        icon: "books.vertical.fill",
                        color: .blue
                    )
                    CampusSectionCard(
                        title: "Local Events",
                        subtitle: "Worship nights, bible studies near you",
                        icon: "calendar.badge.plus",
                        color: .orange
                    )
                    CampusSectionCard(
                        title: "Campus Hubs",
                        subtitle: "Your university's faith community",
                        icon: "building.columns.fill",
                        color: .purple
                    )
                    CampusSectionCard(
                        title: "Prayer Partners",
                        subtitle: "Paired prayer accountability",
                        icon: "hands.sparkles.fill",
                        color: .teal
                    )
                }
                .padding()
            }
            .navigationTitle("Campus")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

private struct CampusModeHeroBanner: View {
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "building.columns.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text("Campus Mode Active")
                    .font(.headline)
                Text("Discover local study groups, events, and faith communities on your campus.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct CampusSectionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.bold())
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
