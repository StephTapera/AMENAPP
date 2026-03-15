//
//  GivingNonprofitsDetailView.swift
//  AMENAPP
//
//  Redesigned: Support Hub — Giving & Nonprofits
//  Reference: warm editorial card UI — parchment base, large serif type, dark pill actions,
//             full-bleed hero, Local/Global tab switcher, immersive overlay mode.
//

import SwiftUI

// MARK: - Giving Nonprofits Detail View

struct GivingNonprofitsDetailView: View {
    @State private var selectedTab: GivingTab = .vetted
    @State private var appeared = false
    @State private var showingDonationInfo = false
    @State private var showingHelpRequest = false
    @Environment(\.dismiss) private var dismiss

    enum GivingTab: String, CaseIterable {
        case vetted   = "Vetted"
        case causes   = "Causes"
        case local    = "Local"
        case ways     = "Ways to Give"
        case requests = "Requests"
    }

    @State private var selectedCause: GivingCategory = .all

    enum GivingCategory: String, CaseIterable, Identifiable {
        var id: String { rawValue }
        case all            = "All"
        case disasterRelief = "Disaster Relief"
        case poverty        = "Poverty & Development"
        case cleanWater     = "Clean Water"
        case hunger         = "Hunger"
        case homelessness   = "Housing & Shelter"
        case fosterCare     = "Foster & Orphan Care"
        case antiTrafficking = "Anti-Trafficking"
        case pregnancy      = "Pregnancy & Family"
        case recovery       = "Recovery"
        case refugees       = "Refugees"
        case persecutedChurch = "Persecuted Church"
        case medicalMissions = "Medical Missions"
        case veterans       = "Veterans"
        case education      = "Education & Youth"
        case missions       = "Missions"

        var icon: String {
            switch self {
            case .all:             return "square.grid.2x2.fill"
            case .disasterRelief:  return "bolt.heart.fill"
            case .poverty:         return "globe.americas.fill"
            case .cleanWater:      return "drop.fill"
            case .hunger:          return "fork.knife"
            case .homelessness:    return "house.fill"
            case .fosterCare:      return "figure.2.and.child.holdinghands"
            case .antiTrafficking: return "shield.fill"
            case .pregnancy:       return "heart.fill"
            case .recovery:        return "arrow.clockwise.heart.fill"
            case .refugees:        return "person.2.fill"
            case .persecutedChurch: return "cross.fill"
            case .medicalMissions: return "cross.case.fill"
            case .veterans:        return "medal.fill"
            case .education:       return "graduationcap.fill"
            case .missions:        return "globe.europe.africa.fill"
            }
        }

        var color: Color {
            switch self {
            case .all:             return Color(red: 0.40, green: 0.40, blue: 0.40)
            case .disasterRelief:  return Color(red: 0.82, green: 0.22, blue: 0.18)
            case .poverty:         return Color(red: 0.18, green: 0.42, blue: 0.72)
            case .cleanWater:      return Color(red: 0.12, green: 0.52, blue: 0.72)
            case .hunger:          return Color(red: 0.62, green: 0.32, blue: 0.12)
            case .homelessness:    return Color(red: 0.38, green: 0.28, blue: 0.62)
            case .fosterCare:      return Color(red: 0.72, green: 0.32, blue: 0.42)
            case .antiTrafficking: return Color(red: 0.55, green: 0.18, blue: 0.40)
            case .pregnancy:       return Color(red: 0.82, green: 0.32, blue: 0.42)
            case .recovery:        return Color(red: 0.22, green: 0.52, blue: 0.38)
            case .refugees:        return Color(red: 0.62, green: 0.46, blue: 0.18)
            case .persecutedChurch: return Color(red: 0.48, green: 0.22, blue: 0.72)
            case .medicalMissions: return Color(red: 0.18, green: 0.46, blue: 0.62)
            case .veterans:        return Color(red: 0.14, green: 0.30, blue: 0.55)
            case .education:       return Color(red: 0.28, green: 0.48, blue: 0.22)
            case .missions:        return Color(red: 0.42, green: 0.22, blue: 0.62)
            }
        }
    }

    // Parchment design tokens
    private let parchment     = Color(red: 0.97, green: 0.95, blue: 0.91)
    private let ink           = Color(red: 0.14, green: 0.12, blue: 0.10)
    private let inkSecondary  = Color(red: 0.42, green: 0.38, blue: 0.34)
    private let goldAccent    = Color(red: 0.68, green: 0.52, blue: 0.22)
    private let greenAccent   = Color(red: 0.22, green: 0.52, blue: 0.38)

    var body: some View {
        ZStack(alignment: .top) {
            parchment.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    heroSection
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 14)

                    tabSwitcher
                        .padding(.top, 28)
                        .opacity(appeared ? 1 : 0)

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
        .sheet(isPresented: $showingDonationInfo) {
            DonationInfoSheet()
        }
        .sheet(isPresented: $showingHelpRequest) {
            HelpRequestFlow()
        }
    }

    // MARK: Hero — immersive overlay (Reference right-panel)

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color(red: 0.42, green: 0.36, blue: 0.16),
                    Color(red: 0.62, green: 0.52, blue: 0.26)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 280)

            // Lens highlight
            Ellipse()
                .fill(Color.white.opacity(0.14))
                .frame(width: 300, height: 100)
                .blur(radius: 45)
                .offset(x: 40, y: -50)

            // Impact stat overlay — editorial data point
            VStack(alignment: .trailing, spacing: 2) {
                Text("\"Each one should give\nwhat he has decided\nin his heart to give.\"")
                    .font(.custom("Georgia", size: 13))
                    .fontWeight(.regular)
                    .foregroundStyle(Color.white.opacity(0.72))
                    .italic()
                    .multilineTextAlignment(.trailing)
                Text("— 2 Corinthians 9:7")
                    .font(.custom("OpenSans-Regular", size: 11))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .padding(.trailing, 24)
            .padding(.bottom, 80)
            .frame(maxWidth: .infinity, alignment: .trailing)

            VStack(alignment: .leading, spacing: 6) {
                Text("Giving &\nNonprofits")
                    .font(.custom("Georgia", size: 32))
                    .fontWeight(.regular)
                    .foregroundStyle(.white)
                    .lineSpacing(2)

                Text("Vetted organizations. Transparent impact.")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(Color.white.opacity(0.80))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)

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
                    Button { showingDonationInfo = true } label: {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.28))
                                .frame(width: 36, height: 36)
                            Image(systemName: "info")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.trailing, 20)
                    .padding(.top, 56)
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .clipped()
    }

    // MARK: Tab Switcher — scrollable to fit all tabs

    private var tabSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(GivingTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                            selectedTab = tab
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        VStack(spacing: 6) {
                            Text(tab.rawValue)
                                .font(.custom(selectedTab == tab ? "OpenSans-SemiBold" : "OpenSans-Regular", size: 13))
                                .foregroundStyle(selectedTab == tab ? ink : inkSecondary)
                                .padding(.horizontal, 4)

                            Rectangle()
                                .fill(selectedTab == tab ? goldAccent : Color.clear)
                                .frame(height: 2)
                                .cornerRadius(1)
                        }
                    }
                    .frame(minWidth: 72)
                    .buttonStyle(SquishButtonStyle())
                }
            }
            .padding(.horizontal, 20)
        }
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
        case .vetted:    vettedNonprofits
        case .causes:    causesGrid
        case .local:     localGiving
        case .ways:      waysToGive
        case .requests:  helpRequests
        }
    }

    // MARK: Vetted Nonprofits

    private var filteredNonprofits: [ChristianNonprofit] {
        if selectedCause == .all {
            return ChristianNonprofit.allNonprofits
        }
        return ChristianNonprofit.allNonprofits.filter { $0.givingCategory == selectedCause }
    }

    private var vettedNonprofits: some View {
        VStack(spacing: 14) {
            // Accurate verification sources note
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(greenAccent)
                    Text("How we select featured organizations")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(ink)
                }
                Text("Featured organizations are cross-checked against Charity Navigator, ECFA (Christian ministries), Candid/GuideStar, and BBB Wise Giving Alliance. Badges shown on each card reflect verified status.")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(inkSecondary)
                    .lineSpacing(3)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(greenAccent.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(greenAccent.opacity(0.18), lineWidth: 1)
                    )
            )

            // Category filter — horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GivingCategory.allCases) { cat in
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
                                selectedCause = cat
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: cat.icon)
                                    .font(.system(size: 11, weight: .medium))
                                Text(cat.rawValue)
                                    .font(.custom(selectedCause == cat ? "OpenSans-SemiBold" : "OpenSans-Regular", size: 12))
                            }
                            .foregroundStyle(selectedCause == cat ? .white : ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(selectedCause == cat ? cat.color : Color(red: 0.99, green: 0.98, blue: 0.96))
                                    .shadow(color: ink.opacity(selectedCause == cat ? 0 : 0.06), radius: 4, y: 1)
                            )
                        }
                        .buttonStyle(SquishButtonStyle())
                    }
                }
                .padding(.horizontal, 1)
                .padding(.vertical, 2)
            }

            // Result count
            if selectedCause != .all {
                HStack(spacing: 6) {
                    Image(systemName: selectedCause.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(selectedCause.color)
                    Text("\(filteredNonprofits.count) organization\(filteredNonprofits.count == 1 ? "" : "s") in \(selectedCause.rawValue)")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(inkSecondary)
                    Spacer()
                }
            }

            if filteredNonprofits.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: selectedCause.icon)
                        .font(.system(size: 36))
                        .foregroundStyle(selectedCause.color.opacity(0.4))
                    Text("More \(selectedCause.rawValue) organizations coming soon.")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(inkSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(filteredNonprofits) { nonprofit in
                    NonprofitEditorialCard(nonprofit: nonprofit, ink: ink, inkSecondary: inkSecondary)
                }
            }

            // Guardrail
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(inkSecondary)
                    .padding(.top, 1)
                Text("Nonprofit listings are informational. AMEN does not process donations or guarantee accuracy. Always verify directly with the organization before giving.")
                    .font(.custom("OpenSans-Regular", size: 11))
                    .foregroundStyle(inkSecondary)
                    .lineSpacing(3)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(ink.opacity(0.04))
            )
        }
        .padding(.horizontal, 20)
    }

    // MARK: Causes Grid

    private var causesGrid: some View {
        VStack(spacing: 16) {
            Text("Browse by cause")
                .font(.custom("OpenSans-SemiBold", size: 15))
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(GivingCategory.allCases.filter { $0 != .all }) { cat in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            selectedCause = cat
                            selectedTab = .vetted
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        VStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(cat.color.opacity(0.12))
                                    .frame(width: 48, height: 48)
                                Image(systemName: cat.icon)
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(cat.color)
                            }
                            Text(cat.rawValue)
                                .font(.custom("OpenSans-SemiBold", size: 11))
                                .foregroundStyle(ink)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(red: 0.99, green: 0.98, blue: 0.96))
                                .shadow(color: ink.opacity(0.07), radius: 8, y: 2)
                        )
                    }
                    .buttonStyle(SquishButtonStyle())
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: Local Giving

    private var localGiving: some View {
        VStack(spacing: 16) {
            // Info card
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "location.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(goldAccent)
                    Text("Give locally")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(ink)
                }
                Text("Connect with verified local needs — churches, shelters, and community organizations near you.")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(inkSecondary)
                    .lineSpacing(3)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 13))
                        Text("Find local organizations")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(ink.opacity(0.90))
                    )
                }
                .buttonStyle(SquishButtonStyle())
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(red: 0.99, green: 0.98, blue: 0.96))
                    .shadow(color: ink.opacity(0.07), radius: 10, y: 2)
            )

            // Local categories grid
            let categories: [(String, String, Color)] = [
                ("house.fill", "Housing & Shelter", Color(red: 0.38, green: 0.28, blue: 0.62)),
                ("fork.knife", "Food & Essentials", Color(red: 0.62, green: 0.32, blue: 0.12)),
                ("car.fill", "Transportation", Color(red: 0.18, green: 0.42, blue: 0.62)),
                ("briefcase.fill", "Job Help", Color(red: 0.22, green: 0.52, blue: 0.38)),
            ]

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                spacing: 14
            ) {
                ForEach(categories, id: \.0) { cat in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(cat.2.opacity(0.13))
                                    .frame(width: 40, height: 40)
                                Image(systemName: cat.0)
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(cat.2)
                            }
                            Text(cat.1)
                                .font(.custom("OpenSans-SemiBold", size: 13))
                                .foregroundStyle(ink)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .frame(height: 100)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(red: 0.99, green: 0.98, blue: 0.96))
                                .shadow(color: ink.opacity(0.07), radius: 8, y: 2)
                        )
                    }
                    .buttonStyle(SquishButtonStyle())
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: Ways to Give

    private var waysToGive: some View {
        VStack(spacing: 14) {
            let ways: [(String, String, String, Color)] = [
                ("creditcard.fill",      "One-Time Gift",       "Give once to any cause",            goldAccent),
                ("arrow.clockwise",      "Recurring Giving",    "Monthly or yearly — set and forget", greenAccent),
                ("building.columns.fill","Donor-Advised Fund",  "Strategic, tax-smart giving",        Color(red: 0.38, green: 0.28, blue: 0.62)),
                ("chart.line.uptrend.xyaxis","Assets",          "Donate stocks or real estate",       Color(red: 0.62, green: 0.32, blue: 0.12)),
                ("eye.slash.fill",       "Give Anonymously",    "Protected identity option",          Color(red: 0.28, green: 0.38, blue: 0.58)),
                ("person.badge.clock",   "Volunteer Time",      "Give your skills, not just funds",   Color(red: 0.22, green: 0.52, blue: 0.38)),
            ]

            ForEach(ways, id: \.0) { way in
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(way.3.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: way.0)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(way.3)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(way.1)
                            .font(.custom("OpenSans-SemiBold", size: 15))
                            .foregroundStyle(ink)
                        Text(way.2)
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(inkSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(inkSecondary.opacity(0.5))
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(red: 0.99, green: 0.98, blue: 0.96))
                        .shadow(color: ink.opacity(0.07), radius: 8, y: 2)
                )
            }

            // Tax info nudge
            Button { showingDonationInfo = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                    Text("Understand tax deduction benefits")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                }
                .foregroundStyle(goldAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(goldAccent.opacity(0.09))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(goldAccent.opacity(0.22), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(SquishButtonStyle())
        }
        .padding(.horizontal, 20)
    }

    // MARK: Help Requests

    private var helpRequests: some View {
        VStack(spacing: 16) {
            // Safety callout
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(greenAccent)
                    Text("Safe, verified matching only")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(ink)
                }
                Text("All requests go through a structured review. Approximate location only. No cash apps. Strong anti-scam controls.")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(inkSecondary)
                    .lineSpacing(3)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(greenAccent.opacity(0.08))
            )

            // Request categories
            let requestTypes: [(String, String, String, Color)] = [
                ("dollarsign.circle.fill", "Financial Need",    "Essentials, utilities, bills",      goldAccent),
                ("house.fill",             "Housing & Shelter", "Temporary or transitional housing",  Color(red: 0.38, green: 0.28, blue: 0.62)),
                ("fork.knife",             "Food",              "Groceries or meal support",          Color(red: 0.62, green: 0.32, blue: 0.12)),
                ("car.fill",               "Transportation",    "Rides to work, appointments",        Color(red: 0.18, green: 0.42, blue: 0.62)),
                ("briefcase.fill",         "Job Help",          "Job search or skill support",        greenAccent),
            ]

            ForEach(requestTypes, id: \.0) { req in
                Button {
                    showingHelpRequest = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(req.3.opacity(0.12))
                                .frame(width: 44, height: 44)
                            Image(systemName: req.0)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(req.3)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(req.1)
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(ink)
                            Text(req.2)
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(inkSecondary)
                        }
                        Spacer()
                        // Dark pill — Reference "Call/Website/Save"
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(ink.opacity(0.88))
                                .frame(width: 68, height: 32)
                            Text("Request")
                                .font(.custom("OpenSans-SemiBold", size: 12))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(red: 0.99, green: 0.98, blue: 0.96))
                            .shadow(color: ink.opacity(0.07), radius: 8, y: 2)
                    )
                }
                .buttonStyle(SquishButtonStyle())
            }

            // Church/org sponsor note
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(inkSecondary)
                    Text("Churches and nonprofits can sponsor and verify requests")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(inkSecondary)
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Nonprofit Editorial Card

private struct NonprofitEditorialCard: View {
    let nonprofit: ChristianNonprofit
    let ink: Color
    let inkSecondary: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(nonprofit.color.opacity(0.13))
                        .frame(width: 52, height: 52)
                    Image(systemName: nonprofit.icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(nonprofit.color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(nonprofit.name)
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .foregroundStyle(ink)
                        if nonprofit.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Color(red: 0.22, green: 0.52, blue: 0.38))
                        }
                    }
                    // Category + scope row
                    HStack(spacing: 8) {
                        Text(nonprofit.givingCategory.rawValue)
                            .font(.custom("OpenSans-Regular", size: 11))
                            .foregroundStyle(inkSecondary)
                            .textCase(.uppercase)
                            .kerning(0.4)
                        Text("·")
                            .font(.system(size: 10))
                            .foregroundStyle(inkSecondary.opacity(0.5))
                        // Scope pill
                        HStack(spacing: 3) {
                            Image(systemName: nonprofit.scope == "Global" ? "globe" : nonprofit.scope == "National" ? "flag" : "location")
                                .font(.system(size: 9, weight: .medium))
                            Text(nonprofit.scope)
                                .font(.custom("OpenSans-Regular", size: 10))
                        }
                        .foregroundStyle(nonprofit.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(nonprofit.color.opacity(0.10))
                        )
                        if nonprofit.isFaithBased {
                            Image(systemName: "cross.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(inkSecondary.opacity(0.5))
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)

            // Verification badges
            if !nonprofit.verificationBadges.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(nonprofit.verificationBadges, id: \.self) { badge in
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color(red: 0.22, green: 0.52, blue: 0.38))
                                Text(badge)
                                    .font(.custom("OpenSans-SemiBold", size: 10))
                                    .foregroundStyle(Color(red: 0.22, green: 0.52, blue: 0.38))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color(red: 0.22, green: 0.52, blue: 0.38).opacity(0.09))
                                    .overlay(
                                        Capsule()
                                            .stroke(Color(red: 0.22, green: 0.52, blue: 0.38).opacity(0.18), lineWidth: 0.5)
                                    )
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }
            }

            // Description
            Text(nonprofit.description)
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(inkSecondary)
                .lineSpacing(3)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)

            // Impact stats
            if !nonprofit.impactStats.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(nonprofit.impactStats.prefix(2), id: \.self) { stat in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(nonprofit.color.opacity(0.50))
                                .frame(width: 4, height: 4)
                            Text(stat)
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(inkSecondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }

            // Action bar — Reference A "Call / Website / Save" dark pills
            HStack(spacing: 10) {
                Button {
                    let websiteNormalized = nonprofit.websiteURL.hasPrefix("http://") || nonprofit.websiteURL.hasPrefix("https://") ? nonprofit.websiteURL : "https://\(nonprofit.websiteURL)"
                    if let url = URL(string: websiteNormalized) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "safari.fill")
                            .font(.system(size: 12))
                        Text("Website")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(ink.opacity(0.88))
                    )
                }
                .buttonStyle(SquishButtonStyle())

                if let donateURL = nonprofit.donateURL {
                    Button {
                        let donateNormalized = donateURL.hasPrefix("http://") || donateURL.hasPrefix("https://") ? donateURL : "https://\(donateURL)"
                        if let url = URL(string: donateNormalized) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 12))
                            Text("Give")
                                .font(.custom("OpenSans-SemiBold", size: 13))
                        }
                        .foregroundStyle(nonprofit.color)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(nonprofit.color.opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(nonprofit.color.opacity(0.25), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(SquishButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.99, green: 0.98, blue: 0.96))
                .shadow(color: Color(red: 0.14, green: 0.12, blue: 0.10).opacity(0.07), radius: 10, y: 2)
        )
    }
}

// MARK: - Help Request Flow Sheet

struct HelpRequestFlow: View {
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var selectedCategory = ""
    @State private var description = ""
    @State private var anonymous = false
    @State private var verificationStep = false

    private let ink = Color(red: 0.14, green: 0.12, blue: 0.10)
    private let inkSecondary = Color(red: 0.42, green: 0.38, blue: 0.34)
    private let parchment = Color(red: 0.97, green: 0.95, blue: 0.91)

    var body: some View {
        NavigationStack {
            ZStack {
                parchment.ignoresSafeArea()

                VStack(spacing: 24) {
                    // Step indicator
                    HStack(spacing: 8) {
                        ForEach(0..<3) { i in
                            Capsule()
                                .fill(i <= step
                                      ? Color(red: 0.22, green: 0.52, blue: 0.38)
                                      : Color(red: 0.14, green: 0.12, blue: 0.10).opacity(0.15))
                                .frame(height: 4)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                    Group {
                        if step == 0 {
                            step0
                        } else if step == 1 {
                            step1
                        } else {
                            step2
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                            if step < 2 { step += 1 } else { dismiss() }
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        Text(step < 2 ? "Continue" : "Submit Request")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(ink.opacity(0.90))
                            )
                    }
                    .buttonStyle(SquishButtonStyle())
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        if step > 0 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { step -= 1 }
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: step > 0 ? "chevron.left" : "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ink)
                    }
                }
            }
        }
    }

    private var step0: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What kind of help\ndo you need?")
                    .font(.custom("Georgia", size: 26))
                    .foregroundStyle(ink)
                    .lineSpacing(2)
                Text("Your request is private until matched.")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(inkSecondary)
            }
            .padding(.horizontal, 24)

            let categories = ["Financial Need", "Housing & Shelter", "Food", "Transportation", "Job Help"]
            VStack(spacing: 10) {
                ForEach(categories, id: \.self) { cat in
                    Button {
                        selectedCategory = cat
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack {
                            Text(cat)
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(ink)
                            Spacer()
                            if selectedCategory == cat {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color(red: 0.22, green: 0.52, blue: 0.38))
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(selectedCategory == cat
                                      ? Color(red: 0.22, green: 0.52, blue: 0.38).opacity(0.09)
                                      : Color(red: 0.99, green: 0.98, blue: 0.96))
                                .shadow(color: ink.opacity(0.06), radius: 6, y: 2)
                        )
                    }
                    .buttonStyle(SquishButtonStyle())
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private var step1: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Describe your\nneeds briefly.")
                    .font(.custom("Georgia", size: 26))
                    .foregroundStyle(ink)
                    .lineSpacing(2)
                Text("No personal info here — just context for matching.")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(inkSecondary)
            }
            .padding(.horizontal, 24)

            TextEditor(text: $description)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(ink)
                .frame(height: 130)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(red: 0.99, green: 0.98, blue: 0.96))
                        .shadow(color: ink.opacity(0.06), radius: 6, y: 2)
                )
                .padding(.horizontal, 24)

            Toggle(isOn: $anonymous) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep my identity private")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(ink)
                    Text("Only a verifier will see your name")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(inkSecondary)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.22, green: 0.52, blue: 0.38)))
            .padding(.horizontal, 24)
        }
    }

    private var step2: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Verify your\nidentity.")
                    .font(.custom("Georgia", size: 26))
                    .foregroundStyle(ink)
                    .lineSpacing(2)
                Text("One-time verification protects everyone in the community.")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(inkSecondary)
            }
            .padding(.horizontal, 24)

            VStack(spacing: 10) {
                let tiers = [
                    ("envelope.fill",          "Email verified",  "Already done", true),
                    ("phone.fill",             "Phone number",    "Quick SMS code", false),
                    ("building.2.fill",        "Church sponsor",  "Ask your church to vouch", false),
                ]
                ForEach(tiers, id: \.0) { tier in
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(tier.3
                                      ? Color(red: 0.22, green: 0.52, blue: 0.38).opacity(0.14)
                                      : Color(red: 0.14, green: 0.12, blue: 0.10).opacity(0.07))
                                .frame(width: 40, height: 40)
                            Image(systemName: tier.0)
                                .font(.system(size: 16))
                                .foregroundStyle(tier.3
                                                 ? Color(red: 0.22, green: 0.52, blue: 0.38)
                                                 : inkSecondary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tier.1)
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(ink)
                            Text(tier.2)
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(inkSecondary)
                        }
                        Spacer()
                        if tier.3 {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color(red: 0.22, green: 0.52, blue: 0.38))
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(red: 0.99, green: 0.98, blue: 0.96))
                            .shadow(color: ink.opacity(0.06), radius: 6, y: 2)
                    )
                }
            }
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Donation Info Sheet

struct DonationInfoSheet: View {
    @Environment(\.dismiss) var dismiss

    private let ink = Color(red: 0.14, green: 0.12, blue: 0.10)
    private let inkSecondary = Color(red: 0.42, green: 0.38, blue: 0.34)
    private let parchment = Color(red: 0.97, green: 0.95, blue: 0.91)

    var body: some View {
        NavigationStack {
            ZStack {
                parchment.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tax Benefits of\nCharitable Giving")
                                .font(.custom("Georgia", size: 28))
                                .foregroundStyle(ink)
                                .lineSpacing(2)
                            Text("Understanding how donations can reduce your tax burden")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(inkSecondary)
                        }

                        TaxInfoSection(
                            title: "Standard Deduction vs. Itemizing",
                            content: "To claim charitable deductions, you must itemize on Schedule A. Compare this to the standard deduction to see which benefits you more.",
                            ink: ink, inkSecondary: inkSecondary
                        )
                        TaxInfoSection(
                            title: "Cash Donations",
                            content: "You can generally deduct up to 60% of your adjusted gross income (AGI) for cash donations to qualified organizations.",
                            ink: ink, inkSecondary: inkSecondary
                        )
                        TaxInfoSection(
                            title: "Appreciated Assets",
                            content: "Donating stocks or real estate held over one year lets you deduct fair market value and avoid capital gains taxes.",
                            ink: ink, inkSecondary: inkSecondary
                        )
                        TaxInfoSection(
                            title: "Record Keeping",
                            content: "Keep receipts and acknowledgment letters. Donations of $250+ require written acknowledgment from the organization.",
                            ink: ink, inkSecondary: inkSecondary
                        )

                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(Color(red: 0.68, green: 0.52, blue: 0.22))
                            Text("This is educational only. Consult a qualified tax professional for personalized advice.")
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(inkSecondary)
                                .lineSpacing(3)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(red: 0.68, green: 0.52, blue: 0.22).opacity(0.09))
                        )
                    }
                    .padding(24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(inkSecondary)
                    }
                }
            }
        }
    }
}

private struct TaxInfoSection: View {
    let title: String
    let content: String
    let ink: Color
    let inkSecondary: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.custom("OpenSans-SemiBold", size: 15))
                .foregroundStyle(ink)
            Text(content)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(inkSecondary)
                .lineSpacing(4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.99, green: 0.98, blue: 0.96))
                .shadow(color: ink.opacity(0.06), radius: 6, y: 2)
        )
    }
}

// MARK: - Data Models

struct ChristianNonprofit: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let category: GivingNonprofitsDetailView.GivingTab
    let givingCategory: GivingNonprofitsDetailView.GivingCategory
    let icon: String
    let color: Color
    let websiteURL: String
    let donateURL: String?
    let isVerified: Bool
    let verificationBadges: [String]   // e.g. ["ECFA", "Charity Navigator 4★", "501(c)(3)"]
    let isFaithBased: Bool
    let scope: String                  // "Global", "National", "Local"
    let impactStats: [String]

    static let allNonprofits: [ChristianNonprofit] = disasterReliefOrgs
        + povertyOrgs + cleanWaterOrgs + hungerOrgs + antiTraffickingOrgs
        + persecutedChurchOrgs + medicalOrgs + fosterCareOrgs + recoveryOrgs
        + refugeeOrgs + veteransOrgs

    // MARK: Disaster Relief
    static let disasterReliefOrgs = [
        ChristianNonprofit(
            name: "Samaritan's Purse",
            description: "International relief providing emergency aid, Operation Christmas Child, and disaster response in Jesus' name.",
            category: .vetted, givingCategory: .disasterRelief,
            icon: "bolt.heart.fill",
            color: Color(red: 0.18, green: 0.42, blue: 0.72),
            websiteURL: "https://www.samaritanspurse.org",
            donateURL: "https://www.samaritanspurse.org/donate/",
            isVerified: true,
            verificationBadges: ["ECFA", "Charity Navigator 4★", "501(c)(3)"],
            isFaithBased: true, scope: "Global",
            impactStats: ["Operating in 100+ countries", "Over $1B in aid distributed"]
        ),
        ChristianNonprofit(
            name: "Convoy of Hope",
            description: "Feeding the hungry and responding to disasters worldwide through a network of community outreaches.",
            category: .vetted, givingCategory: .disasterRelief,
            icon: "shippingbox.fill",
            color: Color(red: 0.72, green: 0.36, blue: 0.14),
            websiteURL: "https://www.convoyofhope.org",
            donateURL: "https://www.convoyofhope.org/donate/",
            isVerified: true,
            verificationBadges: ["ECFA", "Charity Navigator 4★", "501(c)(3)"],
            isFaithBased: true, scope: "Global",
            impactStats: ["200M+ people served since 1994", "Disaster response in 100+ nations"]
        ),
        ChristianNonprofit(
            name: "World Vision",
            description: "Christian humanitarian aid, development, and advocacy for children, families, and communities in crisis.",
            category: .vetted, givingCategory: .disasterRelief,
            icon: "heart.circle.fill",
            color: Color(red: 0.72, green: 0.22, blue: 0.22),
            websiteURL: "https://www.worldvision.org",
            donateURL: "https://www.worldvision.org/donate/",
            isVerified: true,
            verificationBadges: ["ECFA", "Charity Navigator 3★", "BBB Accredited", "501(c)(3)"],
            isFaithBased: true, scope: "Global",
            impactStats: ["100M+ people served", "Child sponsorship in 100 countries"]
        ),
        ChristianNonprofit(
            name: "Operation Blessing",
            description: "Disaster relief, hunger fighting, and medical care bringing hope and healing around the world.",
            category: .vetted, givingCategory: .disasterRelief,
            icon: "cross.case.fill",
            color: Color(red: 0.22, green: 0.48, blue: 0.32),
            websiteURL: "https://www.ob.org",
            donateURL: "https://www.ob.org/donate/",
            isVerified: true,
            verificationBadges: ["ECFA", "501(c)(3)"],
            isFaithBased: true, scope: "Global",
            impactStats: ["2B+ pounds of food distributed", "Active in 40+ countries"]
        ),
    ]

    // MARK: Poverty & Development
    static let povertyOrgs = [
        ChristianNonprofit(
            name: "Compassion International",
            description: "Releasing children from poverty in Jesus' name through holistic child development and sponsorship.",
            category: .vetted, givingCategory: .poverty,
            icon: "person.fill.checkmark",
            color: Color(red: 0.48, green: 0.22, blue: 0.72),
            websiteURL: "https://www.compassion.com",
            donateURL: "https://www.compassion.com/sponsor_a_child/",
            isVerified: true,
            verificationBadges: ["ECFA", "Charity Navigator 4★", "Candid Platinum Seal", "501(c)(3)"],
            isFaithBased: true, scope: "Global",
            impactStats: ["2M+ children sponsored", "26 countries served"]
        ),
        ChristianNonprofit(
            name: "Food for the Hungry",
            description: "Ending poverty through sustainable community development, disaster response, and discipleship.",
            category: .vetted, givingCategory: .poverty,
            icon: "globe.americas.fill",
            color: Color(red: 0.62, green: 0.32, blue: 0.12),
            websiteURL: "https://www.fh.org",
            donateURL: "https://www.fh.org/give/",
            isVerified: true,
            verificationBadges: ["ECFA", "Charity Navigator 4★", "501(c)(3)"],
            isFaithBased: true, scope: "Global",
            impactStats: ["Active in 20+ countries", "Christian integrated development"]
        ),
        ChristianNonprofit(
            name: "World Relief",
            description: "The humanitarian arm of the National Association of Evangelicals, serving the vulnerable globally and locally.",
            category: .vetted, givingCategory: .poverty,
            icon: "hands.and.sparkles.fill",
            color: Color(red: 0.18, green: 0.42, blue: 0.62),
            websiteURL: "https://www.worldrelief.org",
            donateURL: "https://www.worldrelief.org/donate/",
            isVerified: true,
            verificationBadges: ["ECFA", "Charity Navigator 4★", "BBB Accredited", "501(c)(3)"],
            isFaithBased: true, scope: "Global",
            impactStats: ["Active in 20 countries", "Refugee resettlement in the US"]
        ),
    ]

    // MARK: Clean Water
    static let cleanWaterOrgs = [
        ChristianNonprofit(
            name: "charity: water",
            description: "100% of public donations fund clean water projects in developing nations. Every project GPS-tracked and reported back.",
            category: .vetted, givingCategory: .cleanWater,
            icon: "drop.fill",
            color: Color(red: 0.12, green: 0.52, blue: 0.72),
            websiteURL: "https://www.charitywater.org",
            donateURL: "https://www.charitywater.org/donate/",
            isVerified: true,
            verificationBadges: ["Charity Navigator 4★", "Candid Platinum Seal", "BBB Accredited", "501(c)(3)"],
            isFaithBased: false, scope: "Global",
            impactStats: ["17M+ people served", "100% of donations to projects"]
        ),
        ChristianNonprofit(
            name: "Living Water International",
            description: "Providing safe water access to communities in need — and sharing the living water of Christ.",
            category: .vetted, givingCategory: .cleanWater,
            icon: "water.waves",
            color: Color(red: 0.08, green: 0.44, blue: 0.68),
            websiteURL: "https://www.water.cc",
            donateURL: "https://www.water.cc/donate/",
            isVerified: true,
            verificationBadges: ["ECFA", "Charity Navigator 4★", "501(c)(3)"],
            isFaithBased: true, scope: "Global",
            impactStats: ["5M+ people with clean water access", "Active in 26 countries"]
        ),
        ChristianNonprofit(
            name: "Water Mission",
            description: "Faith-based nonprofit engineering safe water, sanitation, and hygiene solutions in developing nations and disaster areas.",
            category: .vetted, givingCategory: .cleanWater,
            icon: "drop.triangle.fill",
            color: Color(red: 0.12, green: 0.38, blue: 0.62),
            websiteURL: "https://www.watermission.org",
            donateURL: "https://www.watermission.org/give/",
            isVerified: true,
            verificationBadges: ["ECFA", "Charity Navigator 4★", "501(c)(3)"],
            isFaithBased: true, scope: "Global",
            impactStats: ["8M+ people served", "60+ countries reached"]
        ),
    ]

    // MARK: Hunger
    static let hungerOrgs = [
        ChristianNonprofit(
            name: "Feeding America",
            description: "The largest domestic hunger-relief organization, supporting 200+ food banks and 60,000 food pantries nationwide.",
            category: .vetted, givingCategory: .hunger,
            icon: "fork.knife",
            color: Color(red: 0.82, green: 0.42, blue: 0.10),
            websiteURL: "https://www.feedingamerica.org",
            donateURL: "https://www.feedingamerica.org/donate/",
            isVerified: true,
            verificationBadges: ["Charity Navigator 4★", "Candid Platinum Seal", "BBB Accredited", "501(c)(3)"],
            isFaithBased: false, scope: "National",
            impactStats: ["53M Americans face hunger", "200+ food bank network"]
        ),
        ChristianNonprofit(
            name: "Children's Hunger Fund",
            description: "Delivering food and resources to vulnerable children in poverty through local church partnerships.",
            category: .vetted, givingCategory: .hunger,
            icon: "figure.and.child.holdinghands",
            color: Color(red: 0.62, green: 0.32, blue: 0.12),
            websiteURL: "https://www.childrenshungerfund.org",
            donateURL: "https://www.childrenshungerfund.org/donate/",
            isVerified: true,
            verificationBadges: ["ECFA", "Charity Navigator 4★", "501(c)(3)"],
            isFaithBased: true, scope: "Global",
            impactStats: ["500K+ children served annually", "Church-to-family delivery model"]
        ),
    ]

    // MARK: Anti-Trafficking
    static let antiTraffickingOrgs = [
        ChristianNonprofit(
            name: "International Justice Mission",
            description: "Rescuing victims of violence, sexual exploitation, slavery, and oppression — bringing rescue, restoration, and justice.",
            category: .vetted, givingCategory: .antiTrafficking,
            icon: "shield.fill",
            color: Color(red: 0.55, green: 0.18, blue: 0.40),
            websiteURL: "https://www.ijm.org",
            donateURL: "https://www.ijm.org/donate/",
            isVerified: true,
            verificationBadges: ["ECFA", "Charity Navigator 4★", "Candid Platinum Seal", "501(c)(3)"],
            isFaithBased: true, scope: "Global",
            impactStats: ["50,000+ people rescued", "25+ country offices"]
        ),
        ChristianNonprofit(
            name: "A21",
            description: "Abolishing injustice in the 21st century — fighting human trafficking through awareness, intervention, and aftercare.",
            category: .vetted, givingCategory: .antiTrafficking,
            icon: "figure.stand",
            color: Color(red: 0.14, green: 0.14, blue: 0.14),
            websiteURL: "https://www.a21.org",
            donateURL: "https://www.a21.org/donate/",
            isVerified: true,
            verificationBadges: ["ECFA", "501(c)(3)"],
            isFaithBased: true, scope: "Global",
            impactStats: ["Active in 13 countries", "Hotlines, shelters & legal support"]
        ),
        ChristianNonprofit(
            name: "Destiny Rescue",
            description: "Rescuing children from sexual exploitation and slavery, and helping them stay free.",
            category: .vetted, givingCategory: .antiTrafficking,
            icon: "lock.open.fill",
            color: Color(red: 0.72, green: 0.22, blue: 0.28),
            websiteURL: "https://www.destinyrescue.org",
            donateURL: "https://www.destinyrescue.org/us/donate/",
            isVerified: true,
            verificationBadges: ["ECFA", "Charity Navigator 4★", "501(c)(3)"],
            isFaithBased: true, scope: "Global",
            impactStats: ["12,000+ rescued", "Undercover rescue operations"]
        ),
    ]

    // MARK: Persecuted Church
    static let persecutedChurchOrgs = [
        ChristianNonprofit(
            name: "Open Doors",
            description: "Serving persecuted Christians in the world's most hostile places with Bibles, training, and practical support.",
            category: .vetted, givingCategory: .persecutedChurch,
            icon: "cross.fill",
            color: Color(red: 0.72, green: 0.18, blue: 0.18),
            websiteURL: "https://www.opendoorsusa.org",
            donateURL: "https://www.opendoorsusa.org/give/",
            isVerified: true,
            verificationBadges: ["ECFA", "Charity Navigator 4★", "501(c)(3)"],
            isFaithBased: true, scope: "Global",
            impactStats: ["360M+ persecuted Christians served", "Active in 70+ countries"]
        ),
        ChristianNonprofit(
            name: "Voice of the Martyrs",
            description: "Serving persecuted Christians worldwide through practical and spiritual assistance and raising awareness.",
            category: .vetted, givingCategory: .persecutedChurch,
            icon: "megaphone.fill",
            color: Color(red: 0.48, green: 0.22, blue: 0.72),
            websiteURL: "https://www.persecution.com",
            donateURL: "https://www.persecution.com/give/",
            isVerified: true,
            verificationBadges: ["ECFA", "501(c)(3)"],
            isFaithBased: true, scope: "Global",
            impactStats: ["Active in 70+ countries", "Founded 1967"]
        ),
        ChristianNonprofit(
            name: "Wycliffe Bible Translators",
            description: "Translating scripture into every language so all people can encounter God's Word in their heart language.",
            category: .vetted, givingCategory: .persecutedChurch,
            icon: "book.fill",
            color: Color(red: 0.22, green: 0.42, blue: 0.72),
            websiteURL: "https://www.wycliffe.org",
            donateURL: "https://www.wycliffe.org/donate/",
            isVerified: true,
            verificationBadges: ["ECFA", "Charity Navigator 4★", "501(c)(3)"],
            isFaithBased: true, scope: "Global",
            impactStats: ["3,000+ languages with active translation", "Active since 1942"]
        ),
    ]

    // MARK: Medical Missions
    static let medicalOrgs = [
        ChristianNonprofit(
            name: "Mercy Ships",
            description: "Operating hospital ships that bring world-class surgery and medical training to the world's poorest nations.",
            category: .vetted, givingCategory: .medicalMissions,
            icon: "cross.case.fill",
            color: Color(red: 0.12, green: 0.38, blue: 0.62),
            websiteURL: "https://www.mercyships.org",
            donateURL: "https://www.mercyships.org/give/",
            isVerified: true,
            verificationBadges: ["ECFA", "Charity Navigator 4★", "501(c)(3)"],
            isFaithBased: true, scope: "Global",
            impactStats: ["2.5M+ direct services since 1978", "Largest non-governmental hospital ship"]
        ),
        ChristianNonprofit(
            name: "Joni and Friends",
            description: "Advancing disability ministry and providing wheelchairs, respite, and support for families with disabilities worldwide.",
            category: .vetted, givingCategory: .medicalMissions,
            icon: "figure.roll",
            color: Color(red: 0.28, green: 0.48, blue: 0.62),
            websiteURL: "https://www.joniandfriends.org",
            donateURL: "https://www.joniandfriends.org/donate/",
            isVerified: true,
            verificationBadges: ["ECFA", "Charity Navigator 4★", "501(c)(3)"],
            isFaithBased: true, scope: "Global",
            impactStats: ["250,000+ wheelchairs donated", "Family retreats in 50+ locations"]
        ),
    ]

    // MARK: Foster Care & Orphan Care
    static let fosterCareOrgs = [
        ChristianNonprofit(
            name: "Show Hope",
            description: "Founded by Steven Curtis Chapman — providing care for orphans and funding adoptions for families.",
            category: .vetted, givingCategory: .fosterCare,
            icon: "heart.fill",
            color: Color(red: 0.72, green: 0.22, blue: 0.36),
            websiteURL: "https://www.showhope.org",
            donateURL: "https://www.showhope.org/donate/",
            isVerified: true,
            verificationBadges: ["ECFA", "Charity Navigator 4★", "501(c)(3)"],
            isFaithBased: true, scope: "Global",
            impactStats: ["8,500+ grant families helped", "Cares for 200+ children in China"]
        ),
        ChristianNonprofit(
            name: "The Forgotten Initiative",
            description: "Equipping the church to engage the foster care crisis and care for vulnerable children and families.",
            category: .vetted, givingCategory: .fosterCare,
            icon: "figure.2.and.child.holdinghands",
            color: Color(red: 0.42, green: 0.22, blue: 0.62),
            websiteURL: "https://www.theforgotteninitiative.org",
            donateURL: "https://www.theforgotteninitiative.org/donate/",
            isVerified: true,
            verificationBadges: ["ECFA", "501(c)(3)"],
            isFaithBased: true, scope: "National",
            impactStats: ["400K+ foster children in the US", "Church mobilization network"]
        ),
    ]

    // MARK: Recovery
    static let recoveryOrgs = [
        ChristianNonprofit(
            name: "Celebrate Recovery",
            description: "Christ-centered 12-step recovery program for hurts, habits, and hang-ups in thousands of churches.",
            category: .vetted, givingCategory: .recovery,
            icon: "arrow.clockwise.heart.fill",
            color: Color(red: 0.22, green: 0.52, blue: 0.38),
            websiteURL: "https://www.celebraterecovery.com",
            donateURL: "https://www.celebraterecovery.com",
            isVerified: true,
            verificationBadges: ["ECFA", "501(c)(3)"],
            isFaithBased: true, scope: "National",
            impactStats: ["35,000+ groups worldwide", "7M+ participants since 1991"]
        ),
        ChristianNonprofit(
            name: "Teen Challenge",
            description: "Faith-based addiction recovery and discipleship programs with one of the highest success rates in the nation.",
            category: .vetted, givingCategory: .recovery,
            icon: "person.fill.checkmark",
            color: Color(red: 0.28, green: 0.44, blue: 0.22),
            websiteURL: "https://www.teenchallenge.com",
            donateURL: "https://www.teenchallenge.com/donate/",
            isVerified: true,
            verificationBadges: ["ECFA", "501(c)(3)"],
            isFaithBased: true, scope: "National",
            impactStats: ["1,400+ programs worldwide", "86% long-term sobriety rate"]
        ),
    ]

    // MARK: Refugees
    static let refugeeOrgs = [
        ChristianNonprofit(
            name: "World Relief (Refugees)",
            description: "Resettling refugees in the US and providing care for displaced people globally through church partnerships.",
            category: .vetted, givingCategory: .refugees,
            icon: "person.2.fill",
            color: Color(red: 0.62, green: 0.46, blue: 0.18),
            websiteURL: "https://www.worldrelief.org/refugees/",
            donateURL: "https://www.worldrelief.org/donate/",
            isVerified: true,
            verificationBadges: ["ECFA", "Charity Navigator 4★", "BBB Accredited", "501(c)(3)"],
            isFaithBased: true, scope: "Global",
            impactStats: ["300,000+ refugees resettled in the US", "Active in 20 countries"]
        ),
    ]

    // MARK: Veterans
    static let veteransOrgs = [
        ChristianNonprofit(
            name: "Tunnel to Towers Foundation",
            description: "Honoring fallen heroes by building specially adapted smart homes for catastrophically injured veterans and first responders.",
            category: .vetted, givingCategory: .veterans,
            icon: "shield.lefthalf.filled",
            color: Color(red: 0.14, green: 0.28, blue: 0.52),
            websiteURL: "https://www.t2t.org",
            donateURL: "https://www.t2t.org/donate/",
            isVerified: true,
            verificationBadges: ["BBB Accredited", "Charity Navigator 3★", "501(c)(3)"],
            isFaithBased: false, scope: "National",
            impactStats: ["Mortgage-free homes for Gold Star families", "200+ homes donated"]
        ),
    ]
}

// ImpactRow / WaysToGiveCard kept for backward-compat if referenced elsewhere
struct ImpactRow: View {
    let icon: String; let title: String; let description: String; let color: Color
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(color).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.custom("OpenSans-Bold", size: 14)).foregroundStyle(.primary)
                Text(description).font(.custom("OpenSans-Regular", size: 13)).foregroundStyle(.secondary)
            }
        }
    }
}

struct WaysToGiveCard: View {
    let icon: String; let title: String; let description: String; let color: Color
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(color.opacity(0.15)).frame(width: 44, height: 44)
                Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.custom("OpenSans-Bold", size: 15)).foregroundStyle(.primary)
                Text(description).font(.custom("OpenSans-Regular", size: 13)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
    }
}

#Preview {
    NavigationStack {
        GivingNonprofitsDetailView()
    }
}
