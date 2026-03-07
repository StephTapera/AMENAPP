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
        case vetted  = "Vetted"
        case local   = "Local"
        case ways    = "Ways to Give"
        case requests = "Requests"
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

    // MARK: Tab Switcher — Local / Global reference

    private var tabSwitcher: some View {
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

                        Rectangle()
                            .fill(selectedTab == tab ? goldAccent : Color.clear)
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
        case .vetted:    vettedNonprofits
        case .local:     localGiving
        case .ways:      waysToGive
        case .requests:  helpRequests
        }
    }

    // MARK: Vetted Nonprofits

    private var vettedNonprofits: some View {
        VStack(spacing: 14) {
            // Verified badge callout — editorial status pill
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(greenAccent)
                Text("All featured organizations are 501(c)(3) verified")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(inkSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(greenAccent.opacity(0.10))
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(ChristianNonprofit.allNonprofits) { nonprofit in
                NonprofitEditorialCard(nonprofit: nonprofit, ink: ink, inkSecondary: inkSecondary)
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
                    Text(nonprofit.category.rawValue)
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(inkSecondary)
                        .textCase(.uppercase)
                        .kerning(0.4)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)

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
    let icon: String
    let color: Color
    let websiteURL: String
    let donateURL: String?
    let isVerified: Bool
    let impactStats: [String]

    static let allNonprofits = [
        ChristianNonprofit(
            name: "Samaritan's Purse",
            description: "International relief providing spiritual and physical aid to hurting people across the world.",
            category: .vetted,
            icon: "globe.americas.fill",
            color: Color(red: 0.18, green: 0.42, blue: 0.72),
            websiteURL: "https://www.samaritanspurse.org",
            donateURL: "https://www.samaritanspurse.org/donate/",
            isVerified: true,
            impactStats: ["Operating in 100+ countries", "Over $1B in aid distributed"]
        ),
        ChristianNonprofit(
            name: "World Vision",
            description: "Christian humanitarian aid, development, and advocacy for children, families, and communities.",
            category: .vetted,
            icon: "heart.circle.fill",
            color: Color(red: 0.72, green: 0.22, blue: 0.22),
            websiteURL: "https://www.worldvision.org",
            donateURL: "https://www.worldvision.org/donate/",
            isVerified: true,
            impactStats: ["100M+ people served", "Child sponsorship in 100 countries"]
        ),
        ChristianNonprofit(
            name: "Compassion International",
            description: "Releasing children from poverty in Jesus' name through child sponsorship and development.",
            category: .vetted,
            icon: "person.fill.checkmark",
            color: Color(red: 0.48, green: 0.22, blue: 0.72),
            websiteURL: "https://www.compassion.com",
            donateURL: "https://www.compassion.com/donate/",
            isVerified: true,
            impactStats: ["2M+ children sponsored", "26 countries served"]
        ),
        ChristianNonprofit(
            name: "IJM — Justice",
            description: "International Justice Mission rescues victims of violence, sexual exploitation, and slavery.",
            category: .vetted,
            icon: "shield.fill",
            color: Color(red: 0.55, green: 0.20, blue: 0.42),
            websiteURL: "https://www.ijm.org",
            donateURL: "https://www.ijm.org/donate/",
            isVerified: true,
            impactStats: ["50,000+ people rescued", "25+ country offices"]
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
