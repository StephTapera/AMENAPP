//
//  AMENConnectView.swift
//  AMENAPP
//
//  AMEN Connect hub — jobs, networking, serve, mentorship, events.
//  Visual layer: warm liquid glass aesthetic inspired by Apple Music Now Playing.
//

import SwiftUI

enum AMENConnectTab: String, CaseIterable, Codable {
    case forYou = "For You"
    case jobs = "Jobs"
    case network = "Network"
    case serve = "Serve"
    case events = "Events"
    case ministries = "Ministries"
    case converse = "Conversations"
    case mentorship = "Mentorship"
    case marketplace = "Marketplace"
    case forum = "Forum"
    case prayer = "Prayer"
}

// MARK: - Main View

struct AMENConnectView: View {
    var initialTab: AMENConnectTab = .forYou

    @State private var selectedTab: AMENConnectTab = .forYou

    // Orb pulse scales (staggered)
    @State private var orb1Scale: CGFloat = 1.0
    @State private var orb2Scale: CGFloat = 1.0
    @State private var orb3Scale: CGFloat = 1.0
    @State private var orb4Scale: CGFloat = 1.0

    var body: some View {
        TabView(selection: $selectedTab) {
            // For You tab
            ConnectForYouView()
                .tag(AMENConnectTab.forYou)
                .tabItem {
                    Label("For You", systemImage: "star.fill")
                }
            
            // Marketplace tab
            ConnectMarketplaceView()
                .tag(AMENConnectTab.marketplace)
                .tabItem {
                    Label("Marketplace", systemImage: "cart.fill")
                }
            
            // Conversations tab
            ConnectConverseView()
                .tag(AMENConnectTab.converse)
                .tabItem {
                    Label("Conversations", systemImage: "bubble.left.and.bubble.right.fill")
                }
            
            // Serve tab
            ConnectServeView()
                .tag(AMENConnectTab.serve)
                .tabItem {
                    Label("Serve", systemImage: "hands.sparkles.fill")
                }
            
            // Ministries tab
            ConnectMinistriesView()
                .tag(AMENConnectTab.ministries)
                .tabItem {
                    Label("Ministries", systemImage: "building.2.fill")
                }
            
            // Network tab (existing)
            ConnectNetworkView()
                .tag(AMENConnectTab.network)
                .tabItem {
                    Label("Network", systemImage: "person.2.fill")
                }
        }
        .navigationTitle("AMEN Connect")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedTab = initialTab
        }
    }

    // MARK: - Orb Background

    private var orbBackground: some View {
        GeometryReader { geo in
            ZStack {
                // Orb 1: coral-red — top-left
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(red: 1.0, green: 0.235, blue: 0.314, opacity: 0.60), .clear],
                        center: .center, startRadius: 0, endRadius: 160
                    ))
                    .frame(width: 320, height: 320)
                    .offset(x: -80, y: -100)
                    .scaleEffect(orb1Scale)
                    .blur(radius: 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // Orb 2: orange — top-right
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(red: 1.0, green: 0.549, blue: 0.0, opacity: 0.45), .clear],
                        center: .center, startRadius: 0, endRadius: 130
                    ))
                    .frame(width: 260, height: 260)
                    .offset(x: 100, y: -20)
                    .scaleEffect(orb2Scale)
                    .blur(radius: 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                // Orb 3: magenta — mid-left
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(red: 0.784, green: 0.196, blue: 0.706, opacity: 0.40), .clear],
                        center: .center, startRadius: 0, endRadius: 120
                    ))
                    .frame(width: 240, height: 240)
                    .offset(x: -40, y: 200)
                    .scaleEffect(orb3Scale)
                    .blur(radius: 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                // Orb 4: gold — bottom-right
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(red: 1.0, green: 0.784, blue: 0.235, opacity: 0.30), .clear],
                        center: .center, startRadius: 0, endRadius: 100
                    ))
                    .frame(width: 200, height: 200)
                    .offset(x: 80, y: 360)
                    .scaleEffect(orb4Scale)
                    .blur(radius: 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func startOrbAnimations() {
        withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
            orb1Scale = 1.08
        }
        withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true).delay(1.5)) {
            orb2Scale = 0.92
        }
        withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true).delay(3.0)) {
            orb3Scale = 1.06
        }
        withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true).delay(4.5)) {
            orb4Scale = 0.94
        }
    }

    // MARK: - Hero Banner

    private var heroBanner: some View {
        ZStack(alignment: .topLeading) {
            // Specular shine
            Circle()
                .fill(RadialGradient(
                    colors: [Color.white.opacity(0.18), .clear],
                    center: .center, startRadius: 0, endRadius: 100
                ))
                .frame(width: 200, height: 200)
                .offset(x: -20, y: -40)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 6) {
                Text("FOR YOU")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.1)
                    .foregroundStyle(.white.opacity(0.55))
                    .textCase(.uppercase)

                Text("Your Connect Hub")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineSpacing(-1)

                Text("Jobs, mentorship, events and community — all within the AMEN network.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.60))
                    .lineLimit(2)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.regularMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.20), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 16)
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AMENConnectTab.allCases, id: \.self) { tab in
                    ConnectFilterChip(
                        label: tab.rawValue,
                        isSelected: selectedTab == tab
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                            selectedTab = tab
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - 2×2 Category Grid

    private var categoryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ConnectCategoryCard(
                icon: "briefcase.fill",
                label: "Browse Jobs",
                tintColor: Color(red: 1.0, green: 0.392, blue: 0.314)
            ) {
                // Navigation handled by NavigationLink below
            }
            .overlay(
                NavigationLink(destination: JobSearchView()) { Color.clear }
            )

            ConnectCategoryCard(
                icon: "calendar.badge.plus",
                label: "Events",
                tintColor: Color(red: 1.0, green: 0.627, blue: 0.157)
            ) {}
            .overlay(
                NavigationLink(destination: EventsView()) { Color.clear }
            )

            ConnectCategoryCard(
                icon: "person.2.fill",
                label: "Mentorship",
                tintColor: Color(red: 0.706, green: 0.314, blue: 0.941)
            ) {}
            .overlay(
                NavigationLink(destination: MentorshipView()) { Color.clear }
            )

            ConnectCategoryCard(
                icon: "hands.sparkles.fill",
                label: "Prayer",
                tintColor: Color(red: 1.0, green: 0.784, blue: 0.235)
            ) {}
            .overlay(
                NavigationLink(destination: PrayerView()) { Color.clear }
            )
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Upcoming Events

    private var upcomingEventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Upcoming Events")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)

            Text("No upcoming events yet")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.35))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
        }
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 16)
    }

    // MARK: - Mentor Banner

    private var mentorBanner: some View {
        ZStack(alignment: .leading) {
            // Gradient wash inside the card
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.471, blue: 0.235, opacity: 0.15),
                    Color(red: 0.706, green: 0.235, blue: 0.941, opacity: 0.10)
                ],
                startPoint: .leading, endPoint: .trailing
            )
            .allowsHitTesting(false)

            HStack(spacing: 14) {
                // CTA icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(red: 1.0, green: 0.471, blue: 0.235, opacity: 0.25))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(red: 1.0, green: 0.471, blue: 0.235, opacity: 0.35), lineWidth: 1)
                        )
                        .frame(width: 44, height: 44)
                    Image(systemName: "person.badge.shield.checkmark.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(hex: "FFB060"))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Find a Mentor")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(hex: "FFB060"))
                    Text("Connect with experienced faith leaders")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer()

                Text("See All")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "FFB060"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 16)
    }
}

// MARK: - Filter Chip

private struct ConnectFilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.55))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.ultraThinMaterial))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(isSelected ? 0.30 : 0.12), lineWidth: 0.75)
                )
                .clipShape(Capsule())
                .scaleEffect(isSelected ? 1.04 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Category Card

private struct ConnectCategoryCard: View {
    let icon: String
    let label: String
    let tintColor: Color
    let action: () -> Void

    @GestureState private var isPressed = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Tint leak from top-right
            Circle()
                .fill(RadialGradient(
                    colors: [tintColor.opacity(0.35), .clear],
                    center: .center, startRadius: 0, endRadius: 70
                ))
                .frame(width: 140, height: 140)
                .offset(x: 30, y: -30)
                .allowsHitTesting(false)

            // Specular shine dot
            Circle()
                .fill(RadialGradient(
                    colors: [Color.white.opacity(0.30), .clear],
                    center: .center, startRadius: 0, endRadius: 50
                ))
                .frame(width: 100, height: 100)
                .offset(x: 30, y: -30)
                .allowsHitTesting(false)

            // Content
            VStack(alignment: .leading, spacing: 10) {
                Text(icon.isEmpty ? "" : "")   // spacer for top-right orb room
                    .frame(height: 8)

                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(.white)

                Spacer()

                Text(label)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .frame(height: 120)
        .background(.regularMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in state = true }
                .onEnded { _ in action() }
        )
    }
}

// MARK: - Entry card (used elsewhere in the app — preserved)

struct AMENConnectEntryCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.blue)
                Text("AMEN Connect")
                    .font(.system(size: 18, weight: .bold))
            }
            Text("Jobs, serve, mentor, and connect with the faith community")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.systemGray6)))
    }
}
