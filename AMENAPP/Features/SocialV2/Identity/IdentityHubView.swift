import SwiftUI

struct IdentityHubView: View {
    private let profile = IdentitySampleData.profile

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                header
                trustSignals
                interestBadges
                sectionGrid
            }
            .padding(20)
        }
        .background(Color.white)
        .navigationTitle("Identity Hub")
    }

    private var header: some View {
        SocialV2GlassCard(tintContext: .interactive, isActive: true) {
            VStack(alignment: .leading, spacing: 8) {
                Text(profile.displayName)
                    .font(.title2.weight(.semibold))
                Text(profile.about)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Visibility: \(profile.privacyScope.rawValue.capitalized)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var trustSignals: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Trust Signals")
                .font(.headline)
            HStack(spacing: 8) {
                ForEach(profile.trustSignals) { signal in
                    SocialV2GlassPill(tintContext: .state, isSelected: true) {
                        Label(signal.rawValue.capitalized, systemImage: "checkmark.seal")
                    }
                }
            }
        }
    }

    private var interestBadges: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Interest Badges")
                .font(.headline)
            HStack(spacing: 8) {
                ForEach(profile.badges) { badge in
                    SocialV2GlassPill(tintContext: .interactive, isSelected: false) {
                        Label(badge.title, systemImage: badge.systemImage)
                    }
                }
            }
        }
    }

    private var sectionGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 148), spacing: 10)], spacing: 10) {
            ForEach(profile.sections) { section in
                SocialV2GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: section.systemImage)
                            .foregroundStyle(.blue)
                        Text(section.title)
                            .font(.headline)
                        Text(section.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct IdentityProfile {
    let displayName: String
    let about: String
    let privacyScope: SocialV2PrivacyScope
    let trustSignals: [SocialV2TrustSignal]
    let badges: [IdentityBadge]
    let sections: [IdentitySection]
}

private struct IdentityBadge: Identifiable {
    let id: String
    let title: String
    let systemImage: String
}

private struct IdentitySection: Identifiable {
    let id: String
    let title: String
    let summary: String
    let systemImage: String
}

private enum IdentitySampleData {
    static let profile = IdentityProfile(
        displayName: "Jordan Lee",
        about: "Builder, mentor, and volunteer serving local ministry teams.",
        privacyScope: .followers,
        trustSignals: [.verified, .volunteer, .contributor],
        badges: [
            IdentityBadge(id: "builder", title: "Builder", systemImage: "hammer"),
            IdentityBadge(id: "mentor", title: "Mentor", systemImage: "person.2"),
            IdentityBadge(id: "teacher", title: "Teacher", systemImage: "book")
        ],
        sections: [
            IdentitySection(id: "about", title: "About", summary: "Bio, testimony, and intro.", systemImage: "text.alignleft"),
            IdentitySection(id: "skills", title: "Skills", summary: "Ways this person can serve.", systemImage: "sparkles"),
            IdentitySection(id: "ministries", title: "Ministries", summary: "Current areas of service.", systemImage: "building.2"),
            IdentitySection(id: "projects", title: "Projects", summary: "Active work and collaborations.", systemImage: "folder"),
            IdentitySection(id: "resources", title: "Resources", summary: "Teaching, courses, and links.", systemImage: "books.vertical"),
            IdentitySection(id: "communities", title: "Communities", summary: "Spaces this profile chooses to show.", systemImage: "person.3")
        ]
    )
}
