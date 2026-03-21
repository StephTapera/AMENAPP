import SwiftUI

// MARK: - Subscription Tier

enum AMENSubscriptionTier: Int, Comparable, CaseIterable {
    case free = 0
    case grow = 1
    case lead = 2
    case enterprise = 3

    static func < (lhs: AMENSubscriptionTier, rhs: AMENSubscriptionTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .free:       return "Free"
        case .grow:       return "Grow"
        case .lead:       return "Lead"
        case .enterprise: return "Enterprise"
        }
    }

    var price: String {
        switch self {
        case .free:       return "Always free"
        case .grow:       return "$4.99 / month"
        case .lead:       return "$12.99 / month"
        case .enterprise: return "Contact sales"
        }
    }

    var badgeColor: Color {
        switch self {
        case .free:       return Color(.secondaryLabel)
        case .grow:       return Color(red: 0.20, green: 0.72, blue: 0.44)
        case .lead:       return Color(red: 0.46, green: 0.28, blue: 0.95)
        case .enterprise: return Color(red: 0.90, green: 0.60, blue: 0.20)
        }
    }

    var isContactSales: Bool { self == .enterprise }
}

// MARK: - Pillar

enum TwoFourTwoPillar: String, CaseIterable {
    case teaching   = "teaching"
    case fellowship = "fellowship"
    case table      = "table"
    case prayer     = "prayer"

    var icon: String {
        switch self {
        case .teaching:   return "book.closed.fill"
        case .fellowship: return "person.2.fill"
        case .table:      return "fork.knife"
        case .prayer:     return "hands.sparkles.fill"
        }
    }

    var color: Color {
        switch self {
        case .teaching:   return Color(red: 0.35, green: 0.55, blue: 0.98)
        case .fellowship: return Color(red: 0.20, green: 0.72, blue: 0.54)
        case .table:      return Color(red: 0.95, green: 0.55, blue: 0.18)
        case .prayer:     return Color(red: 0.55, green: 0.28, blue: 0.95)
        }
    }
}

// MARK: - Feature

struct TwoFourTwoFeature: Identifiable {
    let id: String
    let name: String
    let tagline: String
    let description: String
    let iconName: String
    let iconColor: Color
    let pillar: TwoFourTwoPillar
    let requiredTier: AMENSubscriptionTier
    var isComingSoon: Bool = false

    // MARK: All features

    static let all: [TwoFourTwoFeature] = [
        // ── Teaching ──
        TwoFourTwoFeature(
            id: "sermon-library",
            name: "Sermon Library",
            tagline: "Search 3 years of messages by theme",
            description: "Every sermon uploaded by your church is processed for deep semantic search. Pray about something on a Tuesday and find the Sunday message that speaks directly to it — even if it was preached two years ago.",
            iconName: "waveform.and.mic",
            iconColor: Color(red: 0.35, green: 0.55, blue: 0.98),
            pillar: .teaching,
            requiredTier: .free
        ),
        TwoFourTwoFeature(
            id: "berean-study",
            name: "Berean Study",
            tagline: "Scripture alongside everything you read",
            description: "Berean searches the Scriptures as you engage with any content on AMEN. It surfaces relevant passages, flags theological claims, and helps you go deeper without writing a word for you.",
            iconName: "text.magnifyingglass",
            iconColor: Color(red: 0.20, green: 0.42, blue: 0.98),
            pillar: .teaching,
            requiredTier: .free
        ),
        TwoFourTwoFeature(
            id: "covenant-academy",
            name: "Covenant Academy",
            tagline: "Structured paths for spiritual formation",
            description: "Faith formation tracks built around the four pillars of Acts 2:42. Each path is Scripture-anchored, community-accountable, and designed to build the kind of depth that sticks.",
            iconName: "graduationcap.fill",
            iconColor: Color(red: 0.35, green: 0.55, blue: 0.98),
            pillar: .teaching,
            requiredTier: .grow
        ),
        TwoFourTwoFeature(
            id: "values-verified",
            name: "Values Verified",
            tagline: "Faith-aligned businesses worth trusting",
            description: "Every business in this directory has submitted a covenant declaration across four pillars: how they treat employees, how they give, how they serve their community, and how they practice ethical business. These aren't claims — they're commitments.",
            iconName: "checkmark.seal.fill",
            iconColor: Color(red: 0.08, green: 0.62, blue: 0.92),
            pillar: .teaching,
            requiredTier: .free
        ),
        // ── Fellowship ──
        TwoFourTwoFeature(
            id: "amen-connect",
            name: "AMEN Connect",
            tagline: "Find your faith community",
            description: "Groups, events, and connections built around what God is doing in your life right now. Not interest-based networking — calling-based community.",
            iconName: "person.2.circle.fill",
            iconColor: Color(red: 0.20, green: 0.72, blue: 0.54),
            pillar: .fellowship,
            requiredTier: .free
        ),
        TwoFourTwoFeature(
            id: "mentorship",
            name: "Mentorship",
            tagline: "Be led. Lead someone.",
            description: "Intentional faith mentoring relationships matched by spiritual gifts, life stage, and what you're praying about. The kind of Paul-Timothy dynamic that changes the trajectory of a life.",
            iconName: "figure.2.and.child.holdinghands",
            iconColor: Color(red: 0.20, green: 0.72, blue: 0.54),
            pillar: .fellowship,
            requiredTier: .grow
        ),
        TwoFourTwoFeature(
            id: "flock-intelligence",
            name: "Flock Intelligence",
            tagline: "Pastoral briefings from your congregation's data",
            description: "Every Sunday night, your leadership receives a briefing: which burdens are rising in your congregation, which Scripture is resonating, who has gone silent. Anonymized, pastoral, actionable. Built to help you preach to the room that's actually there.",
            iconName: "antenna.radiowaves.left.and.right",
            iconColor: Color(red: 0.46, green: 0.28, blue: 0.95),
            pillar: .fellowship,
            requiredTier: .lead
        ),
        TwoFourTwoFeature(
            id: "prayer-wall-admin",
            name: "Prayer Wall",
            tagline: "Elder-reviewed community intercession",
            description: "Every prayer request is reviewed by your AI elder assistant before any human sees it. Crisis flags go directly to the lead pastor. Sensitive requests route to pastoral care. Everything else surfaces for community intercession.",
            iconName: "shield.lefthalf.filled",
            iconColor: Color(red: 0.35, green: 0.55, blue: 0.98),
            pillar: .fellowship,
            requiredTier: .free
        ),
        // ── Table ──
        TwoFourTwoFeature(
            id: "kingdom-commerce",
            name: "Kingdom Commerce",
            tagline: "Work aligned with your calling",
            description: "Jobs, volunteer roles, and service opportunities matched to your prayer themes and spiritual gifts — not your demographics. A church planting in a hard neighborhood offering zero pay can outrank a Fortune 500 for the right person. No advertising. Only calling alignment.",
            iconName: "briefcase.fill",
            iconColor: Color(red: 0.95, green: 0.55, blue: 0.18),
            pillar: .table,
            requiredTier: .free
        ),
        TwoFourTwoFeature(
            id: "community-events",
            name: "Community Events",
            tagline: "Gather around what matters",
            description: "Church events, community service days, and gatherings — organized, RSVP'd, and followed up on. The breaking of bread is meant to happen in person.",
            iconName: "calendar.badge.plus",
            iconColor: Color(red: 0.95, green: 0.55, blue: 0.18),
            pillar: .table,
            requiredTier: .free
        ),
        TwoFourTwoFeature(
            id: "studio-marketplace",
            name: "Studio",
            tagline: "Commission & support faith creators",
            description: "The creative marketplace for the Kingdom economy. Commission artwork, music, and written work from creators whose gifts are consecrated. Support the people making beautiful things for the Church.",
            iconName: "paintbrush.pointed.fill",
            iconColor: Color(red: 0.90, green: 0.40, blue: 0.20),
            pillar: .table,
            requiredTier: .free
        ),
        TwoFourTwoFeature(
            id: "giving-hub",
            name: "Giving & Nonprofits",
            tagline: "Kingdom resources to Kingdom work",
            description: "Vetted faith-aligned nonprofits, verified giving, and the ability to support your church and the causes your congregation cares most about.",
            iconName: "heart.fill",
            iconColor: Color(red: 0.82, green: 0.18, blue: 0.32),
            pillar: .table,
            requiredTier: .free
        ),
        // ── Prayer ──
        TwoFourTwoFeature(
            id: "living-memory",
            name: "Living Memory",
            tagline: "Your prayer, met by someone else's testimony",
            description: "When you pray, AMEN searches every answered prayer and testimony ever shared on the platform for semantic resonance. The person who prayed about their marriage for 8 months meets the testimony of the person whose marriage was restored. That's not an algorithm — that's a lighthouse.",
            iconName: "sparkles",
            iconColor: Color(red: 0.55, green: 0.28, blue: 0.95),
            pillar: .prayer,
            requiredTier: .free
        ),
        TwoFourTwoFeature(
            id: "intercessors",
            name: "Intercessors Network",
            tagline: "Matched prayer partners",
            description: "Be matched with someone who prays specifically into the things you're carrying. Not random assignment — matched by the spiritual gifts of mercy and intercession, and by the themes you've been bringing to God.",
            iconName: "hands.and.sparkles.fill",
            iconColor: Color(red: 0.55, green: 0.28, blue: 0.95),
            pillar: .prayer,
            requiredTier: .grow
        ),
        TwoFourTwoFeature(
            id: "spiritual-health",
            name: "Spiritual Health",
            tagline: "Track your soul's seasons",
            description: "A private dashboard of your spiritual life: prayer streaks, Scripture engagement, testimony milestones, and growth indicators. Built to encourage, never to perform.",
            iconName: "chart.line.uptrend.xyaxis",
            iconColor: Color(red: 0.20, green: 0.72, blue: 0.44),
            pillar: .prayer,
            requiredTier: .free
        ),
        TwoFourTwoFeature(
            id: "covenant-metrics",
            name: "Covenant Metrics",
            tagline: "Weekly insight on your congregation's spiritual health",
            description: "A weekly narrative delivered to church leaders: what themes your congregation is praying about, which sermons resonated, where the testimony rate is rising. Delivered in pastoral prose, not dashboards.",
            iconName: "chart.bar.doc.horizontal.fill",
            iconColor: Color(red: 0.46, green: 0.28, blue: 0.95),
            pillar: .prayer,
            requiredTier: .lead,
            isComingSoon: false
        ),
    ]

    static func features(for pillar: TwoFourTwoPillar) -> [TwoFourTwoFeature] {
        all.filter { $0.pillar == pillar }
    }
}
