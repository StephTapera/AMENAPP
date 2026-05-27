import SwiftUI

struct SmartCommunityLocationPrompt: View {
    let onAllow: () -> Void
    let onSkip: () -> Void
    let onManualEntry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "location.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
                .accessibilityHidden(true)

            Text("Find nearby communities")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)

            Text("Location helps Amen find nearby churches, groups, and events. Your location is only used for this search.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 10) {
                Button(action: onAllow) {
                    Text("Use My Location")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .accessibilityLabel("Allow location access for nearby search")

                Button(action: onManualEntry) {
                    Text("Enter ZIP or City")
                        .font(.subheadline)
                        .foregroundStyle(.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.accentColor, lineWidth: 1))
                }
                .accessibilityLabel("Enter ZIP code or city name instead")

                Button(action: onSkip) {
                    Text("Search Without Location")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Skip location and search anyway")
            }
            .padding(.horizontal)
        }
        .padding(24)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
