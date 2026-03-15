// AMENConnectView.swift
// AMENAPP
//
// AMEN Connect — faith-based professional network, kingdom marketplace,
// volunteer/serve discovery, events, prayer network, mentorship, forum,
// and creator ecosystem. Accessible from Resources → Connect section.

import SwiftUI
import FirebaseAuth

// MARK: - Tab enum

enum AMENConnectTab: String, CaseIterable, Codable, Hashable {
    case all          = "All"
    case jobs         = "Jobs"
    case network      = "Network"
    case marketplace  = "Marketplace"
    case serve        = "Serve"
    case events       = "Events"
    case ministries   = "Ministries"
    case prayer       = "Prayer"
    case mentorship   = "Mentorship"
    case forum        = "Forum"
    case converse     = "Conversations"
}

// MARK: - Data models

struct ConnectListing: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let org: String
    let detail: String
    let tag: String
    let tagColor: Color
    let tab: AMENConnectTab
    let url: String?
    // AI match metadata
    var aiMatchScore: Double = 0      // 0–1, filled by AI intent engine
    var aiMatchReason: String = ""
}

// MARK: - AI Intent Banner model

struct AIIntentSuggestion: Identifiable {
    let id = UUID()
    let headline: String
    let body: String
    let icon: String
    let accentColor: Color
    let targetTab: AMENConnectTab
}

// MARK: - Curated listing data

private let amenConnectListings: [ConnectListing] = [

    // ── Jobs ──────────────────────────────────────────────────────────
    ConnectListing(
        icon: "building.columns.fill",
        title: "Worship Pastor",
        org: "Church hiring board",
        detail: "Full-time · Sunday services + mid-week",
        tag: "Church Staff",
        tagColor: Color(red: 0.42, green: 0.24, blue: 0.82),
        tab: .jobs, url: nil
    ),
    ConnectListing(
        icon: "person.badge.key.fill",
        title: "Youth Director",
        org: "Ministry roles board",
        detail: "Part-time / Full-time · Local churches",
        tag: "Ministry",
        tagColor: Color(red: 0.15, green: 0.45, blue: 0.82),
        tab: .jobs, url: nil
    ),
    ConnectListing(
        icon: "heart.circle.fill",
        title: "Nonprofit Program Manager",
        org: "Faith-based nonprofits",
        detail: "Remote & on-site · Mission-driven orgs",
        tag: "Nonprofit",
        tagColor: Color(red: 0.18, green: 0.62, blue: 0.36),
        tab: .jobs, url: nil
    ),
    ConnectListing(
        icon: "megaphone.fill",
        title: "Community Manager",
        org: "Christian media orgs",
        detail: "Creator / Social / Editor · Remote",
        tag: "Creator",
        tagColor: Color(red: 0.90, green: 0.47, blue: 0.10),
        tab: .jobs, url: nil
    ),
    ConnectListing(
        icon: "graduationcap.fill",
        title: "Christian School Teacher",
        org: "Faith-based schools board",
        detail: "K–12 · All subjects · Across the US",
        tag: "Education",
        tagColor: Color(red: 0.62, green: 0.28, blue: 0.82),
        tab: .jobs, url: nil
    ),
    ConnectListing(
        icon: "stethoscope",
        title: "Healthcare Chaplain",
        org: "Hospital ministry network",
        detail: "Full-time · Hospitals & care facilities",
        tag: "Chaplaincy",
        tagColor: Color(red: 0.18, green: 0.55, blue: 0.55),
        tab: .jobs, url: nil
    ),
    ConnectListing(
        icon: "laptopcomputer",
        title: "Faith-Based App Developer",
        org: "Christian tech startups",
        detail: "Remote · iOS / Android / Web",
        tag: "Tech",
        tagColor: Color(red: 0.15, green: 0.35, blue: 0.80),
        tab: .jobs, url: nil
    ),

    // ── Professional Network ──────────────────────────────────────────
    ConnectListing(
        icon: "person.text.rectangle.fill",
        title: "Ministry Leader Network",
        org: "AMEN Pro",
        detail: "Connect with pastors, directors & leaders",
        tag: "Leadership",
        tagColor: Color(red: 0.42, green: 0.24, blue: 0.82),
        tab: .network, url: nil
    ),
    ConnectListing(
        icon: "hand.raised.fingers.spread.fill",
        title: "Faith + Business Professionals",
        org: "Kingdom entrepreneurs",
        detail: "Mission-aligned companies · Referrals",
        tag: "Business",
        tagColor: Color(red: 0.15, green: 0.45, blue: 0.82),
        tab: .network, url: nil
    ),
    ConnectListing(
        icon: "star.circle.fill",
        title: "Character Endorsements",
        org: "Integrity · Service · Leadership",
        detail: "Endorse believers in your network",
        tag: "Endorsement",
        tagColor: Color(red: 0.90, green: 0.47, blue: 0.10),
        tab: .network, url: nil
    ),
    ConnectListing(
        icon: "briefcase.fill",
        title: "Ministry Portfolio",
        org: "Showcase your calling",
        detail: "Skills · Projects · Volunteer history",
        tag: "Portfolio",
        tagColor: Color(red: 0.18, green: 0.62, blue: 0.36),
        tab: .network, url: nil
    ),
    ConnectListing(
        icon: "person.3.sequence.fill",
        title: "Referral Network",
        org: "Trust through shared values",
        detail: "Hire · partner · collaborate in faith",
        tag: "Referrals",
        tagColor: Color(red: 0.62, green: 0.28, blue: 0.82),
        tab: .network, url: nil
    ),

    // ── Kingdom Marketplace ───────────────────────────────────────────
    ConnectListing(
        icon: "cart.fill",
        title: "Christian Clothing Brands",
        org: "Kingdom marketplace",
        detail: "Apparel · accessories · faith-inspired",
        tag: "Retail",
        tagColor: Color(red: 0.90, green: 0.47, blue: 0.10),
        tab: .marketplace, url: nil
    ),
    ConnectListing(
        icon: "music.mic",
        title: "Worship Artists & Producers",
        org: "Christian music marketplace",
        detail: "Commission · collaborate · release",
        tag: "Music",
        tagColor: Color(red: 0.62, green: 0.28, blue: 0.82),
        tab: .marketplace, url: nil
    ),
    ConnectListing(
        icon: "camera.fill",
        title: "Christian Photographers",
        org: "Wedding & ministry media",
        detail: "Portraits · events · ministry coverage",
        tag: "Photography",
        tagColor: Color(red: 0.15, green: 0.45, blue: 0.82),
        tab: .marketplace, url: nil
    ),
    ConnectListing(
        icon: "heart.text.square.fill",
        title: "Faith-Based Therapists",
        org: "Christian counseling network",
        detail: "Licensed · faith-integrated · online",
        tag: "Counseling",
        tagColor: Color(red: 0.85, green: 0.18, blue: 0.20),
        tab: .marketplace, url: nil
    ),
    ConnectListing(
        icon: "building.2.fill",
        title: "Ministry Consultants",
        org: "Church growth advisors",
        detail: "Strategy · operations · fundraising",
        tag: "Consulting",
        tagColor: Color(red: 0.18, green: 0.55, blue: 0.45),
        tab: .marketplace, url: nil
    ),
    ConnectListing(
        icon: "sparkles",
        title: "Christian App Developers",
        org: "Faith-tech builders",
        detail: "Mobile · web · AI tools for ministry",
        tag: "Tech",
        tagColor: Color(red: 0.15, green: 0.35, blue: 0.80),
        tab: .marketplace, url: nil
    ),
    ConnectListing(
        icon: "bag.fill",
        title: "Nonprofit Fundraising Services",
        org: "Donor development experts",
        detail: "Campaign design · donor relations",
        tag: "Fundraising",
        tagColor: Color(red: 0.18, green: 0.62, blue: 0.36),
        tab: .marketplace, url: nil
    ),

    // ── Serve ─────────────────────────────────────────────────────────
    ConnectListing(
        icon: "fork.knife",
        title: "Serve at a Food Pantry",
        org: "Local church outreach",
        detail: "Weekly shifts · All ages welcome",
        tag: "Outreach",
        tagColor: Color(red: 0.18, green: 0.62, blue: 0.36),
        tab: .serve, url: nil
    ),
    ConnectListing(
        icon: "airplane",
        title: "Short-Term Mission Trip",
        org: "Missions network",
        detail: "1–3 weeks · International & domestic",
        tag: "Missions",
        tagColor: Color(red: 0.85, green: 0.32, blue: 0.32),
        tab: .serve, url: nil
    ),
    ConnectListing(
        icon: "house.fill",
        title: "Homeless Ministry",
        org: "City outreach teams",
        detail: "Weekend mornings · No experience needed",
        tag: "Community",
        tagColor: Color(red: 0.15, green: 0.45, blue: 0.82),
        tab: .serve, url: nil
    ),
    ConnectListing(
        icon: "hands.sparkles.fill",
        title: "Children's Ministry Volunteer",
        org: "Local churches",
        detail: "Sunday mornings · Background check req.",
        tag: "Church",
        tagColor: Color(red: 0.42, green: 0.24, blue: 0.82),
        tab: .serve, url: nil
    ),
    ConnectListing(
        icon: "book.fill",
        title: "Prison Ministry Volunteer",
        org: "Correctional chaplaincy network",
        detail: "Weekly Bible study · Mentoring",
        tag: "Prison Ministry",
        tagColor: Color(red: 0.62, green: 0.28, blue: 0.82),
        tab: .serve, url: nil
    ),
    ConnectListing(
        icon: "figure.2.and.child.holdinghands",
        title: "After-School Tutoring",
        org: "Community education ministry",
        detail: "Weekday afternoons · K–12 students",
        tag: "Education",
        tagColor: Color(red: 0.18, green: 0.55, blue: 0.45),
        tab: .serve, url: nil
    ),
    ConnectListing(
        icon: "clock.arrow.circlepath",
        title: "Disaster Relief Team",
        org: "Faith-based relief network",
        detail: "On-call · Deploy when needed",
        tag: "Relief",
        tagColor: Color(red: 0.85, green: 0.32, blue: 0.32),
        tab: .serve, url: nil
    ),

    // ── Events ────────────────────────────────────────────────────────
    ConnectListing(
        icon: "music.note",
        title: "Worship Night",
        org: "Local church events",
        detail: "Monthly · Open to all · Free admission",
        tag: "Worship",
        tagColor: Color(red: 0.62, green: 0.28, blue: 0.82),
        tab: .events, url: nil
    ),
    ConnectListing(
        icon: "person.3.fill",
        title: "Faith & Business Conference",
        org: "Kingdom entrepreneur summit",
        detail: "Annual · Networking + teaching",
        tag: "Conference",
        tagColor: Color(red: 0.15, green: 0.45, blue: 0.82),
        tab: .events, url: nil
    ),
    ConnectListing(
        icon: "leaf.fill",
        title: "Spiritual Retreat",
        org: "Weekend getaway network",
        detail: "2–3 days · Fasting · Prayer · Rest",
        tag: "Retreat",
        tagColor: Color(red: 0.18, green: 0.62, blue: 0.36),
        tab: .events, url: nil
    ),
    ConnectListing(
        icon: "graduationcap.fill",
        title: "Ministry Training",
        org: "Church leadership institute",
        detail: "Workshops · Certifications · Mentored",
        tag: "Training",
        tagColor: Color(red: 0.90, green: 0.47, blue: 0.10),
        tab: .events, url: nil
    ),
    ConnectListing(
        icon: "heart.circle.fill",
        title: "Charity Walk/Run",
        org: "Nonprofit fundraising events",
        detail: "Community · Raise funds · Impact",
        tag: "Charity",
        tagColor: Color(red: 0.85, green: 0.32, blue: 0.32),
        tab: .events, url: nil
    ),
    ConnectListing(
        icon: "book.closed.fill",
        title: "Women's Bible Study Retreat",
        org: "Ladies' ministry network",
        detail: "Weekend · Guest speakers · Fellowship",
        tag: "Women's Ministry",
        tagColor: Color(red: 0.80, green: 0.20, blue: 0.60),
        tab: .events, url: nil
    ),

    // ── Ministries ────────────────────────────────────────────────────
    ConnectListing(
        icon: "book.fill",
        title: "Wednesday Bible Study",
        org: "Community fellowship groups",
        detail: "In-person & online · All denominations",
        tag: "Bible Study",
        tagColor: Color(red: 0.15, green: 0.45, blue: 0.82),
        tab: .ministries, url: nil
    ),
    ConnectListing(
        icon: "person.2.fill",
        title: "Men's Accountability Group",
        org: "Local church groups",
        detail: "Monthly meetups · Confidential",
        tag: "Accountability",
        tagColor: Color(red: 0.42, green: 0.24, blue: 0.82),
        tab: .ministries, url: nil
    ),
    ConnectListing(
        icon: "figure.2.and.child.holdinghands",
        title: "Marriage & Family Ministry",
        org: "Faith-based counseling",
        detail: "Couples + parenting support",
        tag: "Family",
        tagColor: Color(red: 0.90, green: 0.47, blue: 0.10),
        tab: .ministries, url: nil
    ),
    ConnectListing(
        icon: "music.note.list",
        title: "Worship Team",
        org: "Local church music ministry",
        detail: "Singers, musicians · Sunday services",
        tag: "Worship",
        tagColor: Color(red: 0.62, green: 0.28, blue: 0.82),
        tab: .ministries, url: nil
    ),

    // ── Prayer Network ────────────────────────────────────────────────
    ConnectListing(
        icon: "hands.sparkles.fill",
        title: "Submit a Prayer Request",
        org: "AMEN Prayer Network",
        detail: "Community prays with you · Anonymous ok",
        tag: "Prayer",
        tagColor: Color(red: 0.42, green: 0.24, blue: 0.82),
        tab: .prayer, url: nil
    ),
    ConnectListing(
        icon: "checkmark.seal.fill",
        title: "Answered Prayer Wall",
        org: "Testimonies of faith",
        detail: "Mark prayers answered · Encourage others",
        tag: "Testimony",
        tagColor: Color(red: 0.18, green: 0.62, blue: 0.36),
        tab: .prayer, url: nil
    ),
    ConnectListing(
        icon: "globe.americas.fill",
        title: "Global Prayer Map",
        org: "Worldwide intercession",
        detail: "See prayer happening in real-time",
        tag: "Intercession",
        tagColor: Color(red: 0.15, green: 0.45, blue: 0.82),
        tab: .prayer, url: nil
    ),
    ConnectListing(
        icon: "person.3.fill",
        title: "Prayer Groups",
        org: "Focused intercession circles",
        detail: "Healing · Nations · Family · Workplace",
        tag: "Group Prayer",
        tagColor: Color(red: 0.90, green: 0.47, blue: 0.10),
        tab: .prayer, url: nil
    ),

    // ── Mentorship ────────────────────────────────────────────────────
    ConnectListing(
        icon: "person.fill.checkmark",
        title: "Find a Faith Mentor",
        org: "AMEN mentorship network",
        detail: "1-on-1 spiritual guidance",
        tag: "Mentorship",
        tagColor: Color(red: 0.15, green: 0.45, blue: 0.82),
        tab: .mentorship, url: nil
    ),
    ConnectListing(
        icon: "person.2.wave.2.fill",
        title: "Accountability Partner",
        org: "Same-faith pairing",
        detail: "Weekly check-ins · Private",
        tag: "Accountability",
        tagColor: Color(red: 0.42, green: 0.24, blue: 0.82),
        tab: .mentorship, url: nil
    ),
    ConnectListing(
        icon: "text.book.closed.fill",
        title: "New Believer Discipleship",
        org: "Volunteer mentors",
        detail: "6-week guided journey",
        tag: "Discipleship",
        tagColor: Color(red: 0.18, green: 0.62, blue: 0.36),
        tab: .mentorship, url: nil
    ),
    ConnectListing(
        icon: "figure.wave",
        title: "Leadership Mentoring",
        org: "Church leader network",
        detail: "For those called to lead",
        tag: "Leadership",
        tagColor: Color(red: 0.62, green: 0.28, blue: 0.82),
        tab: .mentorship, url: nil
    ),
    ConnectListing(
        icon: "person.fill.viewfinder",
        title: "Purpose & Calling Coaching",
        org: "Life calling discovery",
        detail: "Identify your God-given purpose",
        tag: "Calling",
        tagColor: Color(red: 0.90, green: 0.47, blue: 0.10),
        tab: .mentorship, url: nil
    ),

    // ── Forum ─────────────────────────────────────────────────────────
    ConnectListing(
        icon: "text.bubble.fill",
        title: "Theology & Doctrine",
        org: "Deep faith discussions",
        detail: "Systematic · Apologetics · Scripture",
        tag: "Theology",
        tagColor: Color(red: 0.15, green: 0.45, blue: 0.82),
        tab: .forum, url: nil
    ),
    ConnectListing(
        icon: "heart.fill",
        title: "Marriage & Relationships",
        org: "Faith-centered advice",
        detail: "Dating · Marriage · Parenting · Healing",
        tag: "Relationships",
        tagColor: Color(red: 0.85, green: 0.18, blue: 0.45),
        tab: .forum, url: nil
    ),
    ConnectListing(
        icon: "briefcase.fill",
        title: "Faith & Business",
        org: "Kingdom entrepreneurship",
        detail: "Ethics · Purpose-driven work · Finance",
        tag: "Business",
        tagColor: Color(red: 0.18, green: 0.55, blue: 0.45),
        tab: .forum, url: nil
    ),
    ConnectListing(
        icon: "brain.head.profile",
        title: "Mental Health & Faith",
        org: "Healing conversations",
        detail: "Anxiety · Depression · Identity · Prayer",
        tag: "Wellness",
        tagColor: Color(red: 0.42, green: 0.24, blue: 0.82),
        tab: .forum, url: nil
    ),
    ConnectListing(
        icon: "sparkles",
        title: "Tech, AI & Ethics",
        org: "Faith meets technology",
        detail: "Digital discernment · AI ethics · Media",
        tag: "Technology",
        tagColor: Color(red: 0.15, green: 0.35, blue: 0.80),
        tab: .forum, url: nil
    ),

    // ── Conversations ─────────────────────────────────────────────────
    ConnectListing(
        icon: "quote.bubble.fill",
        title: "What verse has been carrying you this week?",
        org: "Share in OpenTable",
        detail: "Start a faith conversation",
        tag: "Scripture",
        tagColor: Color(red: 0.15, green: 0.45, blue: 0.82),
        tab: .converse, url: nil
    ),
    ConnectListing(
        icon: "hands.sparkles.fill",
        title: "How can we pray for you right now?",
        org: "Prayer request thread",
        detail: "Open your heart to the community",
        tag: "Prayer",
        tagColor: Color(red: 0.42, green: 0.24, blue: 0.82),
        tab: .converse, url: nil
    ),
    ConnectListing(
        icon: "person.fill.questionmark",
        title: "Anyone new to this city looking for a church?",
        org: "Community thread",
        detail: "Connect with locals",
        tag: "Community",
        tagColor: Color(red: 0.18, green: 0.62, blue: 0.36),
        tab: .converse, url: nil
    ),
    ConnectListing(
        icon: "lightbulb.fill",
        title: "What's one thing you're trusting God with this month?",
        org: "Faith share thread",
        detail: "Encourage others with your testimony",
        tag: "Testimony",
        tagColor: Color(red: 0.90, green: 0.47, blue: 0.10),
        tab: .converse, url: nil
    ),
    ConnectListing(
        icon: "heart.fill",
        title: "What has God been teaching you lately?",
        org: "Growth conversation",
        detail: "Reflection + encouragement",
        tag: "Growth",
        tagColor: Color(red: 0.85, green: 0.32, blue: 0.32),
        tab: .converse, url: nil
    ),
]

// MARK: - AI Intent Engine (lightweight, no server needed)

private func generateAISuggestions(for firstName: String) -> [AIIntentSuggestion] {
    [
        AIIntentSuggestion(
            headline: "Looking for work, \(firstName)?",
            body: "We found faith-aligned jobs that match your interests and community activity.",
            icon: "briefcase.fill",
            accentColor: Color(red: 0.15, green: 0.45, blue: 0.82),
            targetTab: .jobs
        ),
        AIIntentSuggestion(
            headline: "Want to make a difference?",
            body: "Serve opportunities near you — volunteering, missions, and local outreach.",
            icon: "hands.sparkles.fill",
            accentColor: Color(red: 0.18, green: 0.62, blue: 0.36),
            targetTab: .serve
        ),
        AIIntentSuggestion(
            headline: "Grow your faith network",
            body: "Connect with believers who share your values, skills, and calling.",
            icon: "person.3.sequence.fill",
            accentColor: Color(red: 0.42, green: 0.24, blue: 0.82),
            targetTab: .network
        ),
        AIIntentSuggestion(
            headline: "Events in your community",
            body: "Worship nights, retreats, conferences — find what's happening near you.",
            icon: "calendar.badge.plus",
            accentColor: Color(red: 0.90, green: 0.47, blue: 0.10),
            targetTab: .events
        ),
    ]
}

// MARK: - AMENConnectView

struct AMENConnectView: View {
    var initialTab: AMENConnectTab = .all

    @StateObject private var membership = AMENConnectMembershipStore.shared
    @State private var selectedTab: AMENConnectTab = .all
    @State private var searchText = ""
    @State private var showAIBanner = true
    @State private var showSignUp = false
    @State private var showUpgradePrompt = false
    @State private var liveAIMatches: [AIConnectMatch] = []
    @State private var isLoadingMatches = false
    @Environment(\.dismiss) private var dismiss

    // Design tokens
    private let ink   = Color(red: 0.10, green: 0.09, blue: 0.09)
    private let slate = Color(red: 0.38, green: 0.38, blue: 0.40)

    private var firstName: String {
        let n = membership.profile.displayName
        let fallback = Auth.auth().currentUser?.displayName ?? ""
        let source = n.isEmpty ? fallback : n
        return source.components(separatedBy: " ").first.map { $0.isEmpty ? "Friend" : $0 } ?? "Friend"
    }

    private var hasProfile: Bool {
        !membership.profile.uid.isEmpty && !membership.profile.displayName.isEmpty
    }

    // Combine static AI suggestions with live post-scan matches
    private var allSuggestions: [AIIntentSuggestion] {
        var suggestions = generateAISuggestions(for: firstName)
        // Inject live matches as custom suggestions (Pro only shows match reason, free shows generic)
        let liveTabsAlreadyCovered = Set(suggestions.map { $0.targetTab })
        for match in liveAIMatches where !liveTabsAlreadyCovered.contains(match.matchedTab) {
            suggestions.insert(AIIntentSuggestion(
                headline: membership.isPro ? match.suggestion : "Matched for you",
                body: membership.isPro
                    ? "Based on your posts: \"\(match.keyword)\""
                    : "Upgrade to Pro to see why this matches you.",
                icon: match.matchedListingIcon,
                accentColor: match.matchedListingColor,
                targetTab: match.matchedTab
            ), at: 0)
        }
        return Array(suggestions.prefix(5))
    }

    var filteredListings: [ConnectListing] {
        let byTab = selectedTab == .all
            ? amenConnectListings
            : amenConnectListings.filter { $0.tab == selectedTab }
        guard !searchText.isEmpty else { return byTab }
        return byTab.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.org.localizedCaseInsensitiveContains(searchText) ||
            $0.tag.localizedCaseInsensitiveContains(searchText) ||
            $0.detail.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Hero header
                    headerView

                    // Membership entry card (shown when user has no profile yet)
                    if !hasProfile {
                        membershipEntryCard
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Search bar
                    searchBar
                        .padding(.horizontal, 20)
                        .padding(.top, hasProfile ? 16 : 12)
                        .padding(.bottom, 4)

                    // Tab pills
                    tabPillsView
                        .padding(.vertical, 8)

                    Divider()
                        .opacity(0.3)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 4)

                    // AI intent banner (only on "All" tab, no search)
                    if selectedTab == .all && searchText.isEmpty && showAIBanner {
                        aiIntentBannerView
                            .padding(.top, 8)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }

                    // Conversation starters (always on All tab)
                    if selectedTab == .all && searchText.isEmpty {
                        conversationStartersSection
                            .padding(.top, 20)
                    }

                    // Section content
                    if selectedTab == .jobs {
                        // Jobs tab: full dynamic search powered by JobService
                        JobSearchView()
                            .padding(.top, 8)
                    } else if selectedTab == .all && searchText.isEmpty {
                        allSectionsView
                    } else if filteredListings.isEmpty {
                        emptyStateView
                    } else {
                        listingsScrollView
                    }

                    // Pro upgrade banner (bottom, free users)
                    if !membership.isPro && hasProfile {
                        proUpgradeBanner
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                    }

                    Color.clear.frame(height: 48)
                }
            }
            .background(Color(.systemBackground))
            .navigationBarHidden(true)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedTab)
            .animation(.easeOut(duration: 0.2), value: showAIBanner)
        }
        .sheet(isPresented: $showSignUp) {
            AMENConnectSignUpView()
        }
        .sheet(isPresented: $showUpgradePrompt) {
            AMENConnectUpgradeSheet()
        }
        .onAppear {
            selectedTab = initialTab
            membership.loadProfile()
            loadAIMatches()
        }
    }

    // MARK: - Load AI matches from post scanning

    private func loadAIMatches() {
        guard !isLoadingMatches else { return }
        isLoadingMatches = true
        Task {
            let matches = await AMENConnectAIMatchEngine.shared.scanRecentPostsForCurrentUser()
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) {
                    liveAIMatches = matches
                }
                isLoadingMatches = false
            }
        }
    }

    // MARK: - Membership Entry Card

    private var membershipEntryCard: some View {
        Button { showSignUp = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.18, green: 0.30, blue: 0.60).opacity(0.12))
                        .frame(width: 46, height: 46)
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color(red: 0.18, green: 0.30, blue: 0.60))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Join AMEN Connect")
                        .font(.custom("OpenSans-Bold", size: 15))
                        .foregroundStyle(.primary)
                    Text("Set up your profile and start connecting — free to join")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color(red: 0.18, green: 0.30, blue: 0.60).opacity(0.25), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(ResourceCardPressStyle())
    }

    // MARK: - Conversation Starters Section

    private var conversationStartersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(red: 0.90, green: 0.47, blue: 0.10).opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: "quote.bubble.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 0.90, green: 0.47, blue: 0.10))
                }
                Text("Start a Conversation")
                    .font(.custom("OpenSans-Bold", size: 17))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        selectedTab = .converse
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("See all")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color(red: 0.90, green: 0.47, blue: 0.10))
                }
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(conversationStarters, id: \.self) { starter in
                        ConversationStarterCard(text: starter)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Pro Upgrade Banner

    private var proUpgradeBanner: some View {
        Button { showUpgradePrompt = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.85, green: 0.58, blue: 0.10).opacity(0.15))
                        .frame(width: 46, height: 46)
                    Image(systemName: "star.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(red: 0.85, green: 0.58, blue: 0.10))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Upgrade to Pro")
                        .font(.custom("OpenSans-Bold", size: 15))
                        .foregroundStyle(.primary)
                    Text("AI matching · Direct connects · Marketplace listings")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer()
                Text("$4.99/mo")
                    .font(.custom("OpenSans-Bold", size: 13))
                    .foregroundStyle(Color(red: 0.85, green: 0.58, blue: 0.10))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.85, green: 0.58, blue: 0.10).opacity(0.12))
                    )
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color(red: 0.85, green: 0.58, blue: 0.10).opacity(0.12), radius: 10, y: 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color(red: 0.85, green: 0.58, blue: 0.10).opacity(0.2), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(ResourceCardPressStyle())
    }

    // MARK: - Hero Header

    private var headerView: some View {
        ZStack(alignment: .bottomLeading) {
            // Off-white background — same as entry card
            Color(red: 0.965, green: 0.963, blue: 0.972)

            // Content — padded below status bar
            VStack(alignment: .leading, spacing: 0) {
                // Safe area spacer so content clears the status bar
                Color.clear.frame(height: 0)
                    .padding(.top, 52)

                // Back button row
                Button { dismiss() } label: {
                    ZStack {
                        Circle()
                            .fill(Color(uiColor: .systemFill))
                            .frame(width: 34, height: 34)
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(uiColor: .label))
                    }
                }
                .padding(.bottom, 14)

                // Eyebrow
                Text("AMEN CONNECT")
                    .font(.system(size: 9, weight: .semibold))
                    .kerning(2.0)
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .padding(.bottom, 8)

                // Typewriter headline
                HStack(alignment: .bottom, spacing: 0) {
                    Text("// ")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Color(red: 0.09, green: 0.09, blue: 0.09))
                    Text("Connect")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Color(red: 0.09, green: 0.09, blue: 0.09))
                    // Static cursor (entry card has animated one; header stays clean)
                    Rectangle()
                        .fill(Color(red: 0.09, green: 0.51, blue: 0.82))
                        .frame(width: 2.5, height: 32)
                        .padding(.leading, 2)
                        .padding(.bottom, 2)
                }

                // Subtitle
                Text("Jobs · Network · Marketplace · Serve · Events · Prayer")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .padding(.top, 8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                // CTA pill
                HStack(spacing: 4) {
                    Text("Explore")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(red: 0.09, green: 0.09, blue: 0.09))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(red: 0.09, green: 0.09, blue: 0.09))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(Color(uiColor: .systemBackground))
                        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
                )
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 22)
        }
        .ignoresSafeArea(edges: .top)
        .frame(minHeight: 240)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 14)

            TextField("Search jobs, serve, events, prayer...", text: $searchText)
                .font(.custom("OpenSans-Regular", size: 15))
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .padding(.trailing, 12)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 3)
        )
        .animation(.easeOut(duration: 0.18), value: searchText.isEmpty)
    }

    // MARK: - Tab Pills

    private var tabPillsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(AMENConnectTab.allCases, id: \.self) { tab in
                    tabPillButton(tab)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func tabPillButton(_ tab: AMENConnectTab) -> some View {
        let isSelected = selectedTab == tab
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                selectedTab = tab
            }
        } label: {
            Text(tab.rawValue)
                .font(.custom(isSelected ? "OpenSans-Bold" : "OpenSans-Regular", size: 13))
                .foregroundStyle(isSelected ? .white : Color(.label).opacity(0.65))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Group {
                        if isSelected {
                            Capsule()
                                .fill(Color(.label))
                                .shadow(color: Color(.label).opacity(0.18), radius: 6, x: 0, y: 3)
                        } else {
                            Capsule()
                                .fill(Color(.secondarySystemBackground))
                                .overlay(
                                    Capsule()
                                        .stroke(Color(.separator).opacity(0.5), lineWidth: 1)
                                )
                        }
                    }
                )
                .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isSelected)
        }
        .buttonStyle(ResourcesSegmentButtonStyle())
    }

    // MARK: - AI Intent Banner

    private var aiIntentBannerView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.55, green: 0.38, blue: 1.0))
                Text("For You — AI Suggestions")
                    .font(.custom("OpenSans-Bold", size: 13))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    withAnimation { showAIBanner = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(Circle().fill(Color(.secondarySystemBackground)))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            // Horizontally scrolling suggestion cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(allSuggestions) { suggestion in
                        AIIntentCard(suggestion: suggestion) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                selectedTab = suggestion.targetTab
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - All Sections View

    private var allSectionsView: some View {
        VStack(spacing: 28) {
            // Jobs
            connectSection(title: "Faith-Based Jobs", icon: "briefcase.fill", color: Color(red: 0.15, green: 0.45, blue: 0.82), tab: .jobs)
            // Professional Network
            connectSection(title: "Professional Network", icon: "person.3.sequence.fill", color: Color(red: 0.42, green: 0.24, blue: 0.82), tab: .network)
            // Kingdom Marketplace
            connectSection(title: "Kingdom Marketplace", icon: "storefront.fill", color: Color(red: 0.90, green: 0.47, blue: 0.10), tab: .marketplace)
            // Serve & Volunteer
            connectSection(title: "Serve & Volunteer", icon: "hands.sparkles.fill", color: Color(red: 0.18, green: 0.62, blue: 0.36), tab: .serve)
            // Events
            connectSection(title: "Events & Gatherings", icon: "calendar.badge.plus", color: Color(red: 0.62, green: 0.28, blue: 0.82), tab: .events)
            // Prayer Network
            prayerNetworkSection
            // Ministries
            connectSection(title: "Ministries & Groups", icon: "book.fill", color: Color(red: 0.15, green: 0.35, blue: 0.80), tab: .ministries)
            // Mentorship
            connectSection(title: "Mentorship & Discipleship", icon: "person.fill.checkmark", color: Color(red: 0.18, green: 0.55, blue: 0.45), tab: .mentorship)
            // Forum
            connectSection(title: "Discussion Forum", icon: "text.bubble.fill", color: Color(red: 0.85, green: 0.32, blue: 0.32), tab: .forum)
            // Conversation Starters
            connectSection(title: "Conversation Starters", icon: "quote.bubble.fill", color: Color(red: 0.85, green: 0.47, blue: 0.10), tab: .converse)
        }
        .padding(.top, 16)
    }

    // Generic section builder for the "All" tab
    @ViewBuilder
    private func connectSection(title: String, icon: String, color: Color, tab: AMENConnectTab) -> some View {
        let listings = amenConnectListings.filter { $0.tab == tab }
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(color.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 17))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("See all")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(color)
                }
            }
            .padding(.horizontal, 20)

            // Horizontal scroll of cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(listings.prefix(4)) { listing in
                        CompactListingCard(listing: listing)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // Special prayer network section with globe + stats aesthetic
    private var prayerNetworkSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(red: 0.42, green: 0.24, blue: 0.82).opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: "globe.americas.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 0.42, green: 0.24, blue: 0.82))
                }
                Text("Prayer Network")
                    .font(.custom("OpenSans-Bold", size: 17))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        selectedTab = .prayer
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("See all")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color(red: 0.42, green: 0.24, blue: 0.82))
                }
            }
            .padding(.horizontal, 20)

            // Prayer globe hero card
            PrayerNetworkHeroCard()
                .padding(.horizontal, 20)

            // Horizontal prayer listing cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(amenConnectListings.filter { $0.tab == .prayer }.dropFirst()) { listing in
                        CompactListingCard(listing: listing)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Listings scroll view (filtered / single tab)

    private var listingsScrollView: some View {
        LazyVStack(spacing: 12) {
            HStack {
                Text("\(filteredListings.count) result\(filteredListings.count == 1 ? "" : "s")")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            ForEach(filteredListings) { listing in
                ConnectListingCard(listing: listing)
                    .padding(.horizontal, 20)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedTab)
        .animation(.easeOut(duration: 0.2), value: filteredListings.count)
    }

    // MARK: - Empty state

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 60)
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.secondary.opacity(0.4))
            Text("No results found")
                .font(.custom("OpenSans-Bold", size: 18))
                .foregroundStyle(.primary)
            Text("Try a different search or category")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 60)
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - AI Intent Card

struct AIIntentCard: View {
    let suggestion: AIIntentSuggestion
    let onTap: () -> Void
    @State private var pressed = false
    @State private var appeared = false

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onTap()
        }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(suggestion.accentColor.opacity(0.15))
                            .frame(width: 38, height: 38)
                        Image(systemName: suggestion.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(suggestion.accentColor)
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(suggestion.accentColor.opacity(0.7))
                }

                Text(suggestion.headline)
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(suggestion.body)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                // Mini CTA
                HStack(spacing: 4) {
                    Text("Explore")
                        .font(.custom("OpenSans-Bold", size: 11))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(suggestion.accentColor)
                )
            }
            .padding(16)
            .frame(width: 195)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: suggestion.accentColor.opacity(0.12), radius: 12, x: 0, y: 5)
                    .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(suggestion.accentColor.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(ResourceCardPressStyle())
        .scaleEffect(appeared ? 1 : 0.88)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7).delay(Double.random(in: 0...0.2))) {
                appeared = true
            }
        }
    }
}

// MARK: - Compact Listing Card (horizontal scroll)

struct CompactListingCard: View {
    let listing: ConnectListing
    @State private var appeared = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(listing.tagColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: listing.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(listing.tagColor)
                }

                Text(listing.title)
                    .font(.custom("OpenSans-Bold", size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(listing.org)
                    .font(.custom("OpenSans-SemiBold", size: 11))
                    .foregroundStyle(listing.tagColor)
                    .lineLimit(1)

                Text(listing.detail)
                    .font(.custom("OpenSans-Regular", size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                // Tag pill
                Text(listing.tag)
                    .font(.custom("OpenSans-SemiBold", size: 10))
                    .foregroundStyle(listing.tagColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(listing.tagColor.opacity(0.10))
                    )
            }
            .padding(14)
            .frame(width: 165, height: 175)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: listing.tagColor.opacity(0.09), radius: 10, x: 0, y: 4)
                    .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(listing.tagColor.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(ResourceCardPressStyle())
        .scaleEffect(appeared ? 1 : 0.9)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.72).delay(Double.random(in: 0...0.15))) {
                appeared = true
            }
        }
    }
}

// MARK: - Prayer Network Hero Card

struct PrayerNetworkHeroCard: View {
    @State private var pulse = false
    @State private var appeared = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Deep purple gradient
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.06, blue: 0.22),
                    Color(red: 0.28, green: 0.12, blue: 0.50),
                    Color(red: 0.42, green: 0.24, blue: 0.82),
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )

            // Pulsing globe
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 80, weight: .ultraLight))
                .foregroundStyle(Color.white.opacity(0.08))
                .scaleEffect(pulse ? 1.06 : 1.0)
                .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true), value: pulse)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 10)
                .padding(.trailing, 16)

            // Accent dots
            Circle()
                .fill(Color.white.opacity(0.25))
                .frame(width: 6, height: 6)
                .offset(x: 60, y: -20)
            Circle()
                .fill(Color.white.opacity(0.35))
                .frame(width: 4, height: 4)
                .offset(x: 90, y: -44)

            // Content
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                        .overlay(
                            Circle()
                                .fill(Color.green.opacity(0.4))
                                .frame(width: 14, height: 14)
                                .scaleEffect(pulse ? 1.3 : 1.0)
                                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulse)
                        )
                    Text("Live · Prayer happening now")
                        .font(.custom("OpenSans-SemiBold", size: 11))
                        .foregroundStyle(Color.white.opacity(0.80))
                }

                Text("Global Prayer\nNetwork")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(.white)
                    .lineSpacing(2)

                Text("Join believers worldwide in intercession")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(Color.white.opacity(0.70))

                HStack(spacing: 5) {
                    Text("Pray now")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 0.28, green: 0.12, blue: 0.50))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color(red: 0.28, green: 0.12, blue: 0.50))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.92)))
                .padding(.top, 2)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color(red: 0.42, green: 0.24, blue: 0.82).opacity(0.28), radius: 16, x: 0, y: 6)
        .scaleEffect(appeared ? 1 : 0.94)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            pulse = true
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) {
                appeared = true
            }
        }
        .onDisappear {
            // Reset pulse so the repeatForever animation is not sustained off-screen
            pulse = false
            appeared = false
        }
    }
}

// MARK: - ConnectListingCard (full-width, filtered tab view)

struct ConnectListingCard: View {
    let listing: ConnectListing

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(listing.tagColor)
                    .frame(width: 4)
                    .padding(.vertical, 14)
                    .padding(.leading, 16)

                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(listing.tagColor.opacity(0.10))
                        .frame(width: 50, height: 50)
                    Image(systemName: listing.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(listing.tagColor)
                }
                .padding(.leading, 14)

                VStack(alignment: .leading, spacing: 4) {
                    Text(listing.title)
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(listing.org)
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(listing.tagColor)
                        .lineLimit(1)

                    Text(listing.detail)
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.leading, 14)
                .padding(.vertical, 16)

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(listing.tag)
                        .font(.custom("OpenSans-SemiBold", size: 10))
                        .foregroundStyle(listing.tagColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(listing.tagColor.opacity(0.10))
                        )

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .padding(.trailing, 16)
            }
            .frame(minHeight: 82)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: listing.tagColor.opacity(0.08), radius: 12, x: 0, y: 5)
                    .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(listing.tagColor.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(ResourceCardPressStyle())
    }
}

// MARK: - Conversation Starters Data

private let conversationStarters: [String] = [
    "What verse has been carrying you this week?",
    "How can we pray for you right now?",
    "What is God teaching you in this season?",
    "Is anyone looking for a church in their city?",
    "What's one thing you're trusting God with this month?",
    "Anyone willing to be an accountability partner?",
    "What does your daily time with God look like?",
    "What book of the Bible changed your life?",
]

// MARK: - Conversation Starter Card

struct ConversationStarterCard: View {
    let text: String
    @State private var appeared = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            // TODO: navigate to CreatePost pre-filled with this starter
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(red: 0.90, green: 0.47, blue: 0.10).opacity(0.7))

                Text(text)
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                HStack(spacing: 5) {
                    Text("Start thread")
                        .font(.custom("OpenSans-Bold", size: 11))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(Color(red: 0.90, green: 0.47, blue: 0.10))
            }
            .padding(14)
            .frame(width: 170, height: 150)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color(red: 0.90, green: 0.47, blue: 0.10).opacity(0.09), radius: 10, x: 0, y: 4)
                    .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(red: 0.90, green: 0.47, blue: 0.10).opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(ResourceCardPressStyle())
        .scaleEffect(appeared ? 1 : 0.9)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.72).delay(Double.random(in: 0...0.15))) {
                appeared = true
            }
        }
    }
}

// MARK: - Pro Upgrade Sheet

struct AMENConnectUpgradeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var membership = AMENConnectMembershipStore.shared
    @State private var billingAnnual = false
    @State private var isUpgrading = false
    @State private var showSuccess = false

    private let gold = Color(red: 0.85, green: 0.58, blue: 0.10)

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Gold hero
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(LinearGradient(
                                colors: [Color(red: 0.12, green: 0.08, blue: 0.02),
                                         Color(red: 0.30, green: 0.20, blue: 0.04),
                                         Color(red: 0.55, green: 0.38, blue: 0.08)],
                                startPoint: .topTrailing, endPoint: .bottomLeading
                            ))
                            .frame(height: 160)

                        Image(systemName: "star.fill")
                            .font(.system(size: 70, weight: .ultraLight))
                            .foregroundStyle(gold.opacity(0.08))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(.top, 10).padding(.trailing, 16)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("AMEN Connect")
                                .font(.system(size: 10, weight: .semibold)).kerning(2)
                                .foregroundStyle(Color.white.opacity(0.5))
                            HStack(spacing: 0) {
                                Text("Pro").font(.system(size: 32, weight: .black)).foregroundStyle(gold)
                                Circle().fill(gold).frame(width: 8, height: 8).offset(x: 3, y: 4)
                            }
                            Text("AI matching · Connects · Marketplace")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(Color.white.opacity(0.70))
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 20)

                    // Billing toggle
                    HStack(spacing: 0) {
                        upgradeToggleButton("Monthly", isSelected: !billingAnnual) { billingAnnual = false }
                        upgradeToggleButton("Annual · Save 33%", isSelected: billingAnnual) { billingAnnual = true }
                    }
                    .padding(3)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                    .padding(.horizontal, 20)

                    // Feature list
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Everything in Pro")
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 20)
                        ForEach(AMENConnectTier.pro.features.filter { $0.included }) { feature in
                            HStack(spacing: 12) {
                                Image(systemName: feature.icon)
                                    .font(.system(size: 15))
                                    .foregroundStyle(gold)
                                    .frame(width: 24)
                                Text(feature.text)
                                    .font(.custom("OpenSans-Regular", size: 14))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(gold)
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    // CTA
                    Button {
                        Task { await upgradePro() }
                    } label: {
                        Group {
                            if isUpgrading {
                                ProgressView().tint(.white)
                            } else if showSuccess {
                                Label("You're Pro!", systemImage: "checkmark")
                                    .font(.custom("OpenSans-Bold", size: 16))
                            } else {
                                Text(billingAnnual
                                     ? "Upgrade to Pro · \(AMENConnectTier.pro.annualPrice)"
                                     : "Upgrade to Pro · \(AMENConnectTier.pro.monthlyPrice)")
                                    .font(.custom("OpenSans-Bold", size: 16))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(showSuccess ? Color.green : gold)
                                .shadow(color: gold.opacity(0.3), radius: 10, y: 4)
                        )
                    }
                    .padding(.horizontal, 20)
                    .disabled(isUpgrading || showSuccess)

                    Text("7-day money-back guarantee. Cancel anytime in Settings.")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color(.secondarySystemBackground)))
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func upgradePro() async {
        isUpgrading = true
        let purchased = await membership.upgradeToPro()
        isUpgrading = false
        guard purchased else { return } // user cancelled or purchase failed — stay on sheet
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { showSuccess = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { dismiss() }
    }

    @ViewBuilder
    private func upgradeToggleButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.custom(isSelected ? "OpenSans-Bold" : "OpenSans-Regular", size: 13))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    Group {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.07), radius: 4, y: 2)
                        } else {
                            RoundedRectangle(cornerRadius: 10).fill(Color.clear)
                        }
                    }
                )
        }
        .animation(.easeOut(duration: 0.18), value: isSelected)
    }
}

// MARK: - AMENConnectEntryCard (Resources entry point)

struct AMENConnectEntryCard: View {
    // Cursor blink state
    @State private var cursorVisible = true
    @State private var appeared = false

    // The headline words that "type out"
    private let headlinePrefix = "// "
    private let headlineSuffix = "Connect"
    @State private var visibleChars = 0
    private let cursorBlue = Color(red: 0.09, green: 0.51, blue: 0.82)

    var body: some View {
        ZStack(alignment: .leading) {
            // Off-white card background
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.965, green: 0.963, blue: 0.972))

            VStack(alignment: .leading, spacing: 0) {
                // Eyebrow
                Text("AMEN CONNECT")
                    .font(.system(size: 9, weight: .semibold))
                    .kerning(2.0)
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .padding(.bottom, 10)

                // Typewriter headline + blinking cursor
                HStack(alignment: .bottom, spacing: 0) {
                    // Static prefix
                    Text(headlinePrefix)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color(red: 0.09, green: 0.09, blue: 0.09))

                    // Animated suffix characters
                    let displayed = String(headlineSuffix.prefix(visibleChars))
                    Text(displayed)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color(red: 0.09, green: 0.09, blue: 0.09))

                    // Blinking cursor — shown while typing OR always after done
                    Rectangle()
                        .fill(cursorBlue)
                        .frame(width: 2.5, height: 30)
                        .opacity(cursorVisible ? 1 : 0)
                        .padding(.leading, 1)
                        .padding(.bottom, 2)
                }

                // Subtitle
                Text("Jobs · Network · Marketplace · Serve")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .padding(.top, 10)

                // CTA pill
                HStack(spacing: 4) {
                    Text("Explore")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(red: 0.09, green: 0.09, blue: 0.09))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(red: 0.09, green: 0.09, blue: 0.09))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(Color(uiColor: .systemBackground))
                        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
                )
                .padding(.top, 16)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 22)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 170)
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
        .onAppear {
            // Typewriter: reveal one char every 60ms
            for i in 0...headlineSuffix.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.07) {
                    visibleChars = i
                }
            }
            // Blink cursor
            withAnimation(
                .easeInOut(duration: 0.5)
                .repeatForever(autoreverses: true)
                .delay(Double(headlineSuffix.count) * 0.07)
            ) {
                cursorVisible = false
            }
        }
    }
}

#Preview {
    AMENConnectView()
}
