//
//  MentalHealthDetailView.swift
//  AMENAPP
//
//  Redesigned: Support Hub — Mental Health & Wellness
//  Reference: warm editorial card UI — parchment base, large type, dark pill actions,
//             full-bleed hero, dot indicators, immersive overlay mode.
//

import SwiftUI

// MARK: - Mental Health Detail View

struct MentalHealthDetailView: View {
    @State private var selectedTab: WellnessTab = .tools
    @State private var appeared = false
    @State private var featuredIndex = 0
    @Environment(\.dismiss) private var dismiss

    enum WellnessTab: String, CaseIterable {
        case tools    = "Tools"
        case counsel  = "Counseling"
        case groups   = "Groups"
        case faith    = "Faith"
    }

    // Parchment design tokens
    private let parchment     = Color(red: 0.97, green: 0.95, blue: 0.91)
    private let ink           = Color(red: 0.14, green: 0.12, blue: 0.10)
    private let inkSecondary  = Color(red: 0.42, green: 0.38, blue: 0.34)
    private let tealAccent    = Color(red: 0.12, green: 0.52, blue: 0.50)

    var body: some View {
        ZStack(alignment: .top) {
            parchment.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    heroSection
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 14)

                    // Tab switcher — Reference B floating tabs
                    tabSwitcher
                        .padding(.top, 28)
                        .opacity(appeared ? 1 : 0)

                    // Tab content
                    tabContent
                        .padding(.top, 20)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 8)

                    Spacer(minLength: 60)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.06)) {
                appeared = true
            }
        }
    }

    // MARK: Hero

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            // Full-bleed warm gradient — immersive overlay reference
            LinearGradient(
                colors: [
                    Color(red: 0.22, green: 0.42, blue: 0.46),
                    Color(red: 0.34, green: 0.55, blue: 0.50)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 260)

            // Lens highlight
            Ellipse()
                .fill(Color.white.opacity(0.12))
                .frame(width: 280, height: 100)
                .blur(radius: 40)
                .offset(x: 60, y: -40)

            // Overlaid text — Reference right-panel style
            VStack(alignment: .leading, spacing: 6) {
                Text("Mental Health\n& Wellness")
                    .font(.custom("Georgia", size: 32))
                    .fontWeight(.regular)
                    .foregroundStyle(.white)
                    .lineSpacing(2)

                Text("Faith-based care for mind, body, and spirit.")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(Color.white.opacity(0.80))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)

            // Dismiss ×
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.28))
                                .frame(width: 36, height: 36)
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.leading, 20)
                    .padding(.top, 56)
                    Spacer()
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
        .clipped()
    }

    // MARK: Tab Switcher — floating pill tabs (Reference B)

    private var tabSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(WellnessTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                        selectedTab = tab
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    VStack(spacing: 6) {
                        Text(tab.rawValue)
                            .font(.custom(selectedTab == tab ? "OpenSans-SemiBold" : "OpenSans-Regular", size: 14))
                            .foregroundStyle(selectedTab == tab ? ink : inkSecondary)
                            .padding(.horizontal, 4)

                        // Underline indicator — glides between tabs
                        Rectangle()
                            .fill(selectedTab == tab ? tealAccent : Color.clear)
                            .frame(height: 2)
                            .cornerRadius(1)
                    }
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(SquishButtonStyle())
            }
        }
        .padding(.horizontal, 20)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(inkSecondary.opacity(0.12))
                .frame(height: 1)
        }
    }

    // MARK: Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .tools:    wellnessToolsGrid
        case .counsel:  counselingList
        case .groups:   supportGroupsList
        case .faith:    faithResourcesList
        }
    }

    // MARK: Tools Tab — grounding exercises + scripture

    private var wellnessToolsGrid: some View {
        VStack(spacing: 0) {
            // Scripture card — editorial blockquote
            scriptureBlockquote
                .padding(.horizontal, 20)

            // Quick tools — 2-col grid (Reference A folder cards)
            let tools: [(String, String, String, Color)] = [
                ("wind", "Breathing",      "Box-breath exercise",       tealAccent),
                ("brain.head.profile", "Grounding",    "5-4-3-2-1 technique",       Color(red: 0.52, green: 0.36, blue: 0.72)),
                ("moon.stars.fill",    "Sleep Hygiene", "Rest & restoration tips",   Color(red: 0.28, green: 0.38, blue: 0.62)),
                ("figure.walk",        "Movement",      "Body & mood connection",    Color(red: 0.22, green: 0.52, blue: 0.38)),
                ("book.fill",          "Journaling",    "Reflection prompts",        Color(red: 0.72, green: 0.46, blue: 0.22)),
                ("hands.sparkles.fill","Prayer",        "Centering in Christ",       Color(red: 0.62, green: 0.22, blue: 0.42)),
            ]

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                spacing: 14
            ) {
                ForEach(tools, id: \.0) { tool in
                    WellnessToolCard(
                        icon: tool.0,
                        title: tool.1,
                        subtitle: tool.2,
                        accent: tool.3,
                        parchment: parchment,
                        ink: ink,
                        inkSecondary: inkSecondary
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            // Berean suggestion
            bereanWellnessBridge
                .padding(.horizontal, 20)
                .padding(.top, 20)
        }
    }

    // MARK: Counseling Tab

    private var counselingList: some View {
        VStack(spacing: 14) {
            ForEach(MentalHealthResource.counselingResources) { resource in
                EditorialResourceCard(resource: resource, ink: ink, inkSecondary: inkSecondary, parchment: parchment)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: Groups Tab

    private var supportGroupsList: some View {
        VStack(spacing: 14) {
            ForEach(MentalHealthResource.groupResources) { resource in
                EditorialResourceCard(resource: resource, ink: ink, inkSecondary: inkSecondary, parchment: parchment)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: Faith Tab

    private var faithResourcesList: some View {
        VStack(spacing: 14) {
            ForEach(MentalHealthResource.faithResources) { resource in
                EditorialResourceCard(resource: resource, ink: ink, inkSecondary: inkSecondary, parchment: parchment)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: Scripture Blockquote

    private var scriptureBlockquote: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle()
                .fill(tealAccent)
                .frame(width: 3, height: 44)
                .cornerRadius(2)
                .padding(.bottom, -44)
                .offset(x: 0)

            HStack(alignment: .top, spacing: 14) {
                Rectangle()
                    .fill(tealAccent)
                    .frame(width: 3)
                    .cornerRadius(2)

                VStack(alignment: .leading, spacing: 6) {
                    Text("\"Do not be anxious about anything, but in every situation, by prayer and petition, present your requests to God.\"")
                        .font(.custom("Georgia", size: 15))
                        .fontWeight(.regular)
                        .foregroundStyle(ink)
                        .italic()
                        .lineSpacing(4)

                    Text("— Philippians 4:6")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(inkSecondary)
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: Berean Bridge

    private var bereanWellnessBridge: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(tealAccent.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(tealAccent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Ask Berean")
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundStyle(ink)
                Text("Private wellness support + scripture")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(inkSecondary)
            }
            Spacer()
            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tealAccent)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.93, green: 0.97, blue: 0.96))
        )
    }
}

// MARK: - Wellness Tool Card (Reference A folder card)

private struct WellnessToolCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let accent: Color
    let parchment: Color
    let ink: Color
    let inkSecondary: Color

    @State private var pressed = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(accent.opacity(0.13))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(ink)
                    Text(subtitle)
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(inkSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .frame(height: 120)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.99, green: 0.98, blue: 0.96))
                    .shadow(color: Color(red: 0.14, green: 0.12, blue: 0.10).opacity(0.07), radius: 8, y: 2)
            )
        }
        .buttonStyle(SquishButtonStyle())
    }
}

// MARK: - Editorial Resource Card (Reference left-panel detail card)

private struct EditorialResourceCard: View {
    let resource: MentalHealthResource
    let ink: Color
    let inkSecondary: Color
    let parchment: Color

    var body: some View {
        Button {
            if let url = URL(string: resource.url) {
                UIApplication.shared.open(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Top row
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(resource.color.opacity(0.13))
                            .frame(width: 48, height: 48)
                        Image(systemName: resource.icon)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(resource.color)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(resource.name)
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(ink)
                                .multilineTextAlignment(.leading)
                            if resource.isFree {
                                Text("Free")
                                    .font(.custom("OpenSans-SemiBold", size: 10))
                                    .foregroundStyle(Color(red: 0.12, green: 0.52, blue: 0.38))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(Color(red: 0.12, green: 0.52, blue: 0.38).opacity(0.12))
                                    )
                            }
                        }
                        Text(resource.categoryLabel)
                            .font(.custom("OpenSans-Regular", size: 11))
                            .foregroundStyle(inkSecondary)
                            .textCase(.uppercase)
                            .kerning(0.5)
                    }

                    Spacer()

                    // Dark pill action — Reference A "Call/Website/Save" style
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(ink.opacity(0.88))
                            .frame(width: 34, height: 34)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(16)

                // Description
                Text(resource.description)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(inkSecondary)
                    .lineSpacing(3)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)

                // Feature tags
                if !resource.features.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(resource.features.prefix(3), id: \.self) { feature in
                                Text(feature)
                                    .font(.custom("OpenSans-Regular", size: 11))
                                    .foregroundStyle(inkSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule()
                                            .fill(Color(red: 0.14, green: 0.12, blue: 0.10).opacity(0.07))
                                    )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(red: 0.99, green: 0.98, blue: 0.96))
                    .shadow(color: Color(red: 0.14, green: 0.12, blue: 0.10).opacity(0.07), radius: 10, y: 2)
            )
        }
        .buttonStyle(SquishButtonStyle())
    }
}

// MARK: - Data Models

struct MentalHealthResource: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let url: String
    let icon: String
    let color: Color
    let categoryLabel: String
    let isFree: Bool
    let features: [String]

    // Legacy category property for existing code compatibility
    var category: MentalHealthDetailView.WellnessTab {
        switch categoryLabel {
        case "Counseling":       return .counsel
        case "Support Groups":   return .groups
        default:                 return .faith
        }
    }

    static let counselingResources = [
        MentalHealthResource(
            name: "BetterHelp",
            description: "Online therapy with licensed counselors. Get matched in 24 hours. Christian counselor filters available.",
            url: "https://www.betterhelp.com",
            icon: "person.fill.questionmark",
            color: Color(red: 0.22, green: 0.42, blue: 0.72),
            categoryLabel: "Counseling",
            isFree: false,
            features: ["Licensed therapists", "Text, call, or video", "Financial aid"]
        ),
        MentalHealthResource(
            name: "Faithful Counseling",
            description: "Faith-based online therapy connecting you with Christian counselors who integrate scripture.",
            url: "https://www.faithfulcounseling.com",
            icon: "cross.fill",
            color: Color(red: 0.48, green: 0.22, blue: 0.72),
            categoryLabel: "Counseling",
            isFree: false,
            features: ["Christian-based", "Licensed therapists", "Flexible scheduling"]
        ),
        MentalHealthResource(
            name: "Focus on the Family",
            description: "Free phone consultations with licensed counselors. Referrals to Christian therapists nationwide.",
            url: "https://www.focusonthefamily.com/get-help/counseling-services-and-referrals/",
            icon: "phone.circle.fill",
            color: Color(red: 0.12, green: 0.52, blue: 0.38),
            categoryLabel: "Counseling",
            isFree: true,
            features: ["Free consultations", "Therapist referrals", "Faith-based"]
        ),
        MentalHealthResource(
            name: "Psychology Today",
            description: "Find therapists, psychiatrists, and support groups in your area. Filter for faith-informed providers.",
            url: "https://www.psychologytoday.com/us/therapists",
            icon: "magnifyingglass.circle.fill",
            color: Color(red: 0.22, green: 0.48, blue: 0.42),
            categoryLabel: "Counseling",
            isFree: true,
            features: ["Local directory", "Insurance filters", "Faith filter"]
        ),
    ]

    static let groupResources = [
        MentalHealthResource(
            name: "Celebrate Recovery",
            description: "Christ-centered 12-step recovery program for hurts, habits, and hang-ups. Thousands of groups nationwide.",
            url: "https://www.celebraterecovery.com",
            icon: "person.3.fill",
            color: Color(red: 0.12, green: 0.52, blue: 0.38),
            categoryLabel: "Support Groups",
            isFree: true,
            features: ["Nationwide groups", "Biblical foundation", "Free to attend"]
        ),
        MentalHealthResource(
            name: "GriefShare",
            description: "Support groups for people grieving the death of a loved one. Guided by Christian perspectives on loss.",
            url: "https://www.griefshare.org",
            icon: "heart.fill",
            color: Color(red: 0.72, green: 0.32, blue: 0.42),
            categoryLabel: "Support Groups",
            isFree: true,
            features: ["Local grief groups", "Christian perspective", "Workbook included"]
        ),
        MentalHealthResource(
            name: "NAMI Connection",
            description: "Free peer-led support groups for adults living with mental illness. Evidence-based, confidential.",
            url: "https://www.nami.org",
            icon: "person.2.fill",
            color: Color(red: 0.52, green: 0.28, blue: 0.72),
            categoryLabel: "Support Groups",
            isFree: true,
            features: ["Peer-led", "Evidence-based", "Confidential"]
        ),
        MentalHealthResource(
            name: "DivorceCare",
            description: "Support groups and resources for people experiencing separation or divorce. Faith-centered healing.",
            url: "https://www.divorcecare.org",
            icon: "figure.2.arms.open",
            color: Color(red: 0.72, green: 0.46, blue: 0.22),
            categoryLabel: "Support Groups",
            isFree: true,
            features: ["Weekly groups", "Expert teaching", "Workbook"]
        ),
    ]

    static let faithResources = [
        MentalHealthResource(
            name: "Pray.com",
            description: "Christian meditation, prayer, and sleep content designed to reduce anxiety and anchor you in peace.",
            url: "https://www.pray.com",
            icon: "hands.sparkles.fill",
            color: Color(red: 0.48, green: 0.22, blue: 0.72),
            categoryLabel: "Faith",
            isFree: false,
            features: ["Guided prayers", "Bible meditations", "Sleep content"]
        ),
        MentalHealthResource(
            name: "Abide",
            description: "Scripture-based meditation with sleep stories, breathing exercises, and mindfulness grounded in the Word.",
            url: "https://www.abide.co",
            icon: "moon.stars.fill",
            color: Color(red: 0.28, green: 0.32, blue: 0.62),
            categoryLabel: "Faith",
            isFree: false,
            features: ["Scripture-based", "Sleep stories", "Stress relief"]
        ),
        MentalHealthResource(
            name: "YouVersion Bible Plans",
            description: "Free devotional reading plans specifically addressing anxiety, depression, and mental wellness.",
            url: "https://www.bible.com/reading-plans",
            icon: "book.fill",
            color: Color(red: 0.22, green: 0.42, blue: 0.72),
            categoryLabel: "Faith",
            isFree: true,
            features: ["Mental health plans", "Daily devotionals", "100% free"]
        ),
        MentalHealthResource(
            name: "Mental Health America",
            description: "Free screening tools and education. Understanding your mental health is an act of stewardship.",
            url: "https://www.mhanational.org",
            icon: "heart.circle.fill",
            color: Color(red: 0.72, green: 0.22, blue: 0.22),
            categoryLabel: "Faith",
            isFree: true,
            features: ["Free screenings", "Educational articles", "Local resources"]
        ),
    ]

    // All resources combined (used by older search code)
    static let allResources: [MentalHealthResource] = counselingResources + groupResources + faithResources
}

#Preview {
    NavigationStack {
        MentalHealthDetailView()
    }
}
