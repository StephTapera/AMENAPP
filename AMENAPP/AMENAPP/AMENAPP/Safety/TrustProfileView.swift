import SwiftUI

// MARK: - TrustProfileView
// Shows the user's current trust level, progress toward the next level,
// unlocked capabilities, and how to earn more trust points.

struct TrustProfileView: View {
    @State private var profile: TrustProfileResult? = nil
    @State private var isLoading = true
    @State private var loadError: String? = nil

    private let safety = AmenSafetyOSClientService.shared

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading trust profile…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = loadError {
                    ContentUnavailableView(
                        "Couldn't Load Profile",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else if let profile {
                    profileContent(profile)
                }
            }
            .navigationTitle("Community Trust")
            .navigationBarTitleDisplayMode(.large)
            .task { await loadProfile() }
        }
    }

    @ViewBuilder
    private func profileContent(_ profile: TrustProfileResult) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                trustLevelCard(profile)
                capabilitiesCard(profile)
                if let events = profile.recentEvents, !events.isEmpty {
                    recentEventsCard(events)
                }
                howToEarnCard()
            }
            .padding()
        }
    }

    // MARK: - Trust Level Card

    private func trustLevelCard(_ profile: TrustProfileResult) -> some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Trust Level \(profile.trustLevel)")
                        .font(.title2.bold())
                    Text(levelLabel(for: profile.trustLevel))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TrustBadgeView(level: profile.trustLevel)
            }

            VStack(spacing: 6) {
                HStack {
                    Text("\(profile.trustPoints) pts")
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                    Spacer()
                    if let next = profile.nextLevelRequirement {
                        Text("\(next) pts to Level \(profile.trustLevel + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Maximum level reached")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                TrustProgressBar(
                    current: profile.trustPoints,
                    nextLevel: profile.nextLevelRequirement,
                    level: profile.trustLevel
                )
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Capabilities Card

    private func capabilitiesCard(_ profile: TrustProfileResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Capabilities")
                .font(.headline)
            let caps = profile.trustCapabilities
            CapabilityRow(icon: "message.fill", label: "Direct Messages", enabled: caps.canDM)
            CapabilityRow(icon: "photo.fill", label: "Upload Media", enabled: caps.canUploadMedia)
            CapabilityRow(icon: "person.3.fill", label: "Create Groups", enabled: caps.canCreateGroup)
            CapabilityRow(icon: "globe", label: "Post Publicly", enabled: caps.canPostPublicly)
            CapabilityRow(icon: "figure.wave", label: "Mentor Others", enabled: caps.canMentor)
            HStack {
                Image(systemName: "text.bubble.fill")
                    .frame(width: 24)
                    .foregroundStyle(.secondary)
                Text("Daily Comments")
                    .font(.body)
                Spacer()
                Text("\(caps.maxDailyComments)")
                    .font(.body.bold())
                    .foregroundStyle(.primary)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Recent Events Card

    private func recentEventsCard(_ events: [[String: String]]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How You Earned Trust")
                .font(.headline)
            ForEach(events.prefix(5), id: \.self) { event in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text(formatEventType(event["eventType"] ?? ""))
                        .font(.subheadline)
                    Spacer()
                    if let pts = event["points"] {
                        Text("+\(pts) pts")
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - How To Earn Card

    private func howToEarnCard() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Earn More Trust")
                .font(.headline)
            TrustEarnRow(icon: "phone.fill", label: "Verify your phone number", points: 10)
            TrustEarnRow(icon: "building.2.fill", label: "Connect to a verified church", points: 20)
            TrustEarnRow(icon: "figure.wave", label: "Complete a mentorship", points: 15)
            TrustEarnRow(icon: "hand.thumbsup.fill", label: "Receive positive community feedback", points: 2)
            TrustEarnRow(icon: "calendar", label: "Account active for 30 days", points: 10)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Helpers

    private func loadProfile() async {
        isLoading = true
        loadError = nil
        do {
            profile = try await safety.getMyTrustProfile()
        } catch {
            loadError = "Couldn't load your trust profile. Please try again."
        }
        isLoading = false
    }

    private func levelLabel(for level: Int) -> String {
        switch level {
        case 0: return "New Member"
        case 1: return "Established"
        case 2: return "Trusted"
        case 3: return "Verified"
        case 4: return "Community Builder"
        case 5: return "Ambassador"
        default: return "Member"
        }
    }

    private func formatEventType(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

// MARK: - Supporting Views

private struct TrustBadgeView: View {
    let level: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(badgeColor.gradient)
                .frame(width: 56, height: 56)
            VStack(spacing: 0) {
                Image(systemName: "shield.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                Text("\(level)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
            }
        }
    }

    private var badgeColor: Color {
        switch level {
        case 0: return .gray
        case 1: return .blue
        case 2: return .teal
        case 3: return .green
        case 4: return .orange
        case 5: return .purple
        default: return .gray
        }
    }
}

private struct TrustProgressBar: View {
    let current: Int
    let nextLevel: Int?
    let level: Int

    private var progress: Double {
        guard let next = nextLevel, next > 0 else { return 1.0 }
        let levelStart = levelStartPoints(for: level)
        let range = next - levelStart
        guard range > 0 else { return 1.0 }
        return min(1.0, Double(current - levelStart) / Double(range))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 8)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.gradient)
                    .frame(width: geo.size.width * progress, height: 8)
                    .animation(.spring(response: 0.6), value: progress)
            }
        }
        .frame(height: 8)
    }

    private func levelStartPoints(for level: Int) -> Int {
        switch level {
        case 0: return 0
        case 1: return 5
        case 2: return 20
        case 3: return 45
        case 4: return 80
        case 5: return 120
        default: return 0
        }
    }
}

private struct CapabilityRow: View {
    let icon: String
    let label: String
    let enabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(enabled ? Color.accentColor : Color.secondary)
            Text(label)
                .font(.body)
                .foregroundStyle(enabled ? .primary : .secondary)
            Spacer()
            Image(systemName: enabled ? "checkmark.circle.fill" : "lock.fill")
                .foregroundStyle(enabled ? .green : Color.secondary)
        }
    }
}

private struct TrustEarnRow: View {
    let icon: String
    let label: String
    let points: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(Color.accentColor)
            Text(label)
                .font(.subheadline)
            Spacer()
            Text("+\(points)")
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.green.opacity(0.15), in: Capsule())
                .foregroundStyle(.green)
        }
    }
}
