import SwiftUI

// Privacy-gated "Near Me" discovery — shows AMEN users nearby who have
// opted into location-based discovery. Feature is gated by user consent
// and AMENFeatureFlags.nearbyDiscoveryEnabled (default OFF).
struct NearbyPeopleView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "person.2.wave.2.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(AmenTheme.Colors.amenGold)

                VStack(spacing: 8) {
                    Text("Find People Near You")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                    Text("Discover AMEN community members who have opted into location-based discovery.")
                        .font(.subheadline)
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Text("Coming Soon")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(AmenTheme.Colors.surfaceChip, in: Capsule())

                Spacer()
            }
            .background(AmenTheme.Colors.backgroundGrouped.ignoresSafeArea())
            .navigationTitle("Near Me")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
