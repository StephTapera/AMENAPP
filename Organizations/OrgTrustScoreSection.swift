import SwiftUI

struct OrgTrustScoreSection: View {
    let verification: OrgVerification
    let lastVerified: Date?
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Trust & Verification")
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                Spacer()
                trustScoreBadge
            }
            verificationBadges
            if let date = lastVerified {
                HStack {
                    Image(systemName: "clock").font(.caption).foregroundStyle(AmenTheme.Colors.textTertiary)
                    Text("Last verified \(date.formatted(.relative(presentation: .named)))")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }
            }
            if showDetails { expandedDetails }
            Button { withAnimation(.spring(response: 0.32, dampingFraction: 0.80)) { showDetails.toggle() } } label: {
                Text(showDetails ? "Hide Details" : "Show Details")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(Color(red: 0.10, green: 0.60, blue: 0.56))
            }
            .accessibilityLabel(showDetails ? "Hide verification details" : "Show verification details")
        }
        .padding(14)
        .background(AmenTheme.Colors.surfaceCard)
        .cornerRadius(14)
    }

    private var trustScoreBadge: some View {
        ZStack {
            Circle()
                .stroke(verification.trustColor.opacity(0.3), lineWidth: 4)
                .frame(width: 52, height: 52)
            Circle()
                .trim(from: 0, to: CGFloat(verification.trustScore) / 100.0)
                .stroke(verification.trustColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 52, height: 52)
            Text("\(verification.trustScore)")
                .font(.custom("OpenSans-Bold", size: 15))
                .foregroundStyle(verification.trustColor)
        }
        .accessibilityLabel("Trust score: \(verification.trustScore) out of 100")
    }

    private var verificationBadges: some View {
        HStack(spacing: 8) {
            ForEach(verification.badges, id: \.name) { badge in
                VStack(spacing: 4) {
                    Image(systemName: badge.verified ? badge.icon : "xmark.circle.fill")
                        .foregroundStyle(badge.verified ? .green : AmenTheme.Colors.textTertiary)
                        .font(.title3)
                    Text(badge.name)
                        .font(.custom("OpenSans-Regular", size: 10))
                        .foregroundStyle(badge.verified ? AmenTheme.Colors.textPrimary : AmenTheme.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(badge.verified ? Color.green.opacity(0.08) : AmenTheme.Colors.surfaceChip)
                .cornerRadius(8)
                .accessibilityLabel("\(badge.name): \(badge.verified ? "verified" : "not verified")")
            }
        }
    }

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let nav = verification.charityNavigator, nav.status, let rating = nav.rating {
                HStack {
                    Text("Charity Navigator Rating")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                    Spacer()
                    HStack(spacing: 2) {
                        ForEach(0..<4) { i in
                            Image(systemName: i < rating ? "star.fill" : "star")
                                .font(.caption)
                                .foregroundStyle(i < rating ? Color(red: 0.83, green: 0.69, blue: 0.22) : AmenTheme.Colors.textTertiary)
                        }
                    }
                }
            }
            if let cert = verification.ecfa?.certNumber {
                HStack {
                    Text("ECFA Cert #").font(.custom("OpenSans-Regular", size: 13)).foregroundStyle(AmenTheme.Colors.textSecondary)
                    Spacer()
                    Text(cert).font(.custom("OpenSans-Bold", size: 13)).foregroundStyle(AmenTheme.Colors.textPrimary)
                }
            }
        }
        .padding(10)
        .background(AmenTheme.Colors.backgroundPrimary)
        .cornerRadius(8)
    }
}
