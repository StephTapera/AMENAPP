import SwiftUI

// MARK: - Discovery Hero Carousel
// Horizontally paging carousel of expandable hero cards at the top of Discovery.
// Each card uses AmenUniversalHeroCard with content-type-specific expanded sections.

struct AmenDiscoveryHeroCarousel: View {

    var onChurchPlanVisit: () -> Void = {}
    var onSpaceJoin: () -> Void = {}
    var onEventRSVP: () -> Void = {}
    var onPrayerPray: () -> Void = {}
    var onSermonWatch: () -> Void = {}

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                AmenChurchHeroCard(
                    church: .sample,
                    onPlanVisit: onChurchPlanVisit,
                    onDirections: {},
                    onSave: {},
                    onShare: {}
                )
                .heroCardFrame()

                AmenSpaceHeroCard(space: .sample, onJoin: onSpaceJoin)
                    .heroCardFrame()

                AmenEventHeroCard(event: .sample, onRSVP: onEventRSVP)
                    .heroCardFrame()

                AmenPrayerHeroCard(prayer: .sample, onPray: onPrayerPray)
                    .heroCardFrame()

                AmenSermonHeroCard(sermon: .sample, onWatch: onSermonWatch)
                    .heroCardFrame()
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, 20, for: .scrollContent)
    }
}

// Sizes each card to fill the screen width minus the peek margin.
private extension View {
    func heroCardFrame() -> some View {
        self.containerRelativeFrame(.horizontal) { length, _ in length - 40 }
    }
}

// MARK: - Space

private struct AmenSpaceData: Identifiable {
    let id: String
    let name: String
    let tagline: String
    let spaceType: String
    let memberCount: Int
    let badges: [String]
    let heroImageURL: URL?
    let upcomingEvent: String?
    let missedDiscussions: Int
    let aiCatchup: String?

    var memberLabel: String { "\(memberCount) Members" }

    static let sample = AmenSpaceData(
        id: "mens-bible",
        name: "Men's Bible Study",
        tagline: "Active · 245 Members",
        spaceType: "Bible Study",
        memberCount: 245,
        badges: ["Men", "Romans", "Weekly"],
        heroImageURL: nil,
        upcomingEvent: "Tue 7 PM",
        missedDiscussions: 14,
        aiCatchup: "This week covered Romans 8:1–17 — no condemnation and life in the Spirit."
    )
}

struct AmenSpaceHeroCard: View {
    let space: AmenSpaceData
    var onJoin: () -> Void = {}
    var onCatchUp: () -> Void = {}

    var body: some View {
        AmenUniversalHeroCard(
            heroURL: space.heroImageURL,
            title: space.name,
            subtitle: space.tagline,
            ctaLabel: "Join Space",
            badges: space.badges,
            onCTA: onJoin
        ) {
            expandedContent
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Stats row
            HStack(spacing: 0) {
                HeroStatCell(value: space.memberLabel, label: "Members")
                Divider().frame(height: 32)
                HeroStatCell(value: space.spaceType, label: "Type")
                if let event = space.upcomingEvent {
                    Divider().frame(height: 32)
                    HeroStatCell(value: event, label: "Next Event")
                }
            }

            Divider()

            // Missed discussions callout
            if space.missedDiscussions > 0 {
                HStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You missed \(space.missedDiscussions) discussions")
                            .font(.subheadline.weight(.semibold))
                        Text("Tap to get caught up")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Catch Up", action: onCatchUp)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
                .padding(12)
                .background(Color.accentColor.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // AI catch-up summary
            if let catchup = space.aiCatchup {
                VStack(alignment: .leading, spacing: 6) {
                    Label("AI Summary", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(catchup)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

// MARK: - Event

private struct AmenEventData: Identifiable {
    let id: String
    let title: String
    let dateTimeLabel: String
    let location: String
    let speaker: String?
    let attendeeCount: Int
    let description: String
    let badges: [String]
    let heroImageURL: URL?

    static let sample = AmenEventData(
        id: "ya-night",
        title: "Young Adult Night",
        dateTimeLabel: "Fri, Jun 6 · 7:00 PM",
        location: "Main Campus, Bldg C",
        speaker: "Pastor Marcus",
        attendeeCount: 87,
        description: "A night of worship, community, and a powerful word for young adults. Casual dress, all are welcome.",
        badges: ["Tonight", "Free", "18–35"],
        heroImageURL: nil
    )
}

struct AmenEventHeroCard: View {
    let event: AmenEventData
    var onRSVP: () -> Void = {}
    var onDirections: () -> Void = {}

    var body: some View {
        AmenUniversalHeroCard(
            heroURL: event.heroImageURL,
            title: event.title,
            subtitle: event.dateTimeLabel,
            ctaLabel: "RSVP",
            badges: event.badges,
            onCTA: onRSVP
        ) {
            expandedContent
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Stats row
            HStack(spacing: 0) {
                HeroStatCell(value: event.dateTimeLabel, label: "When")
                Divider().frame(height: 32)
                HeroStatCell(value: "\(event.attendeeCount) Going", label: "Attendees")
            }

            Divider()

            // Location + Speaker
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text(event.location)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                if let speaker = event.speaker {
                    HStack(spacing: 8) {
                        Image(systemName: "person.circle")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Text(speaker)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                }
            }

            Divider()

            // Description
            Text(event.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Directions button
            Button {
                onDirections()
            } label: {
                Label("Get Directions", systemImage: "arrow.triangle.turn.up.right.circle")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

// MARK: - Prayer

private struct AmenPrayerData: Identifiable {
    let id: String
    let subject: String
    let context: String
    let prayerCount: Int
    let latestUpdate: String
    let suggestedScripture: String
    let suggestedPrayer: String?
    let badges: [String]
    let heroImageURL: URL?

    static let sample = AmenPrayerData(
        id: "prayer-sarah",
        subject: "Pray For Sarah",
        context: "Health Recovery",
        prayerCount: 43,
        latestUpdate: "Surgery went well. Please continue praying for a speedy recovery and renewed strength.",
        suggestedScripture: "Psalm 30:2",
        suggestedPrayer: "Lord, we lift Sarah to you. Bring healing, peace, and strength to her body and spirit.",
        badges: ["Urgent", "Medical"],
        heroImageURL: nil
    )
}

struct AmenPrayerHeroCard: View {
    let prayer: AmenPrayerData
    var onPray: () -> Void = {}

    var body: some View {
        AmenUniversalHeroCard(
            heroURL: prayer.heroImageURL,
            title: prayer.subject,
            subtitle: prayer.context,
            ctaLabel: "Pray",
            badges: prayer.badges,
            onCTA: onPray
        ) {
            expandedContent
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Stats row
            HStack(spacing: 0) {
                HeroStatCell(value: "\(prayer.prayerCount)", label: "Praying")
                Divider().frame(height: 32)
                HeroStatCell(value: prayer.suggestedScripture, label: "Scripture")
            }

            Divider()

            // Latest update
            VStack(alignment: .leading, spacing: 6) {
                Label("Latest Update", systemImage: "bell")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(prayer.latestUpdate)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Suggested prayer
            if let suggested = prayer.suggestedPrayer {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Suggested Prayer", systemImage: "hands.sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\"\(suggested)\"")
                        .font(.subheadline.italic())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

// MARK: - Sermon

private struct AmenSermonData: Identifiable {
    let id: String
    let title: String
    let pastor: String
    let duration: String
    let series: String?
    let scriptures: [String]
    let keyPoints: [String]
    let badges: [String]
    let heroImageURL: URL?

    static let sample = AmenSermonData(
        id: "sermon-faith",
        title: "Faith Over Fear",
        pastor: "Pastor James",
        duration: "42 min",
        series: "Walking In Faith",
        scriptures: ["Matthew 14:22–33", "Isaiah 41:10"],
        keyPoints: [
            "Peter walked on water by fixing his eyes on Jesus",
            "Faith is not the absence of fear — it's acting despite it",
            "In every storm, Christ is present"
        ],
        badges: ["New", "42 min"],
        heroImageURL: nil
    )
}

struct AmenSermonHeroCard: View {
    let sermon: AmenSermonData
    var onWatch: () -> Void = {}
    var onTakeNotes: () -> Void = {}

    var body: some View {
        AmenUniversalHeroCard(
            heroURL: sermon.heroImageURL,
            title: sermon.title,
            subtitle: sermon.pastor,
            ctaLabel: "Watch",
            badges: sermon.badges,
            onCTA: onWatch
        ) {
            expandedContent
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Stats row
            HStack(spacing: 0) {
                HeroStatCell(value: sermon.pastor, label: "Speaker")
                Divider().frame(height: 32)
                HeroStatCell(value: sermon.duration, label: "Duration")
                if let series = sermon.series {
                    Divider().frame(height: 32)
                    HeroStatCell(value: series, label: "Series")
                }
            }

            Divider()

            // Scriptures
            VStack(alignment: .leading, spacing: 8) {
                Label("Scripture", systemImage: "book.closed")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 8) {
                    ForEach(sermon.scriptures, id: \.self) { ref in
                        Text(ref)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(.tertiarySystemBackground), in: Capsule())
                    }
                    Spacer()
                }
            }

            Divider()

            // Key points
            VStack(alignment: .leading, spacing: 8) {
                Label("Key Points", systemImage: "list.bullet")
                    .font(.subheadline.weight(.semibold))
                ForEach(sermon.keyPoints, id: \.self) { point in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Color.accentColor.opacity(0.7))
                            .frame(width: 6, height: 6)
                            .padding(.top, 5)
                        Text(point)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            // Take notes CTA
            Button {
                onTakeNotes()
            } label: {
                Label("Take Notes", systemImage: "note.text")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

// MARK: - Sample church data extension

extension AmenChurchHeroData {
    static let sample = AmenChurchHeroData(
        id: "crosspoint",
        name: "Crosspoint Church",
        city: "Phoenix",
        state: "Arizona",
        denomination: "Non-Denominational",
        rating: 4.8,
        distanceMiles: 3.2,
        memberCount: 850,
        sizeRange: "500–1000",
        serviceLengthMinutes: 75,
        services: [
            ChurchHeroService(time: "9:00 AM"),
            ChurchHeroService(time: "11:00 AM")
        ],
        pastor: "John Smith",
        atmosphere: ["Family", "Worship", "Bible Teaching", "Young Adults"],
        aiSummary: "Contemporary worship, strong kids ministry, active young adult community, casual dress environment.",
        aiMatchReasons: [
            "Matches your interest in Bible study",
            "Active young adults community",
            "Strong community groups",
            "Contemporary worship style"
        ],
        badges: ["Young Adults", "Kids", "Bible Focused"],
        heroImageURL: nil,
        hasKids: true,
        hasYouth: true,
        hasLivestream: true
    )
}

// MARK: - Preview

#Preview("Discovery Hero Carousel") {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            Text("Featured")
                .font(.title2.bold())
                .padding(.horizontal, 20)
            AmenDiscoveryHeroCarousel()
        }
        .padding(.vertical, 20)
    }
    .background(Color(.systemGroupedBackground))
}
