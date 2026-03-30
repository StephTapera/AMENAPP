//
//  StudioHubView.swift
//  AMENAPP
//
//  AMEN Studio — Dark Liquid Glass redesign.
//  Modes: Write, Canvas, Journal, Legacy, Faith Reel Studio, Synaptic, Blueprint, Collab.
//

import SwiftData
import SwiftUI
import FirebaseAuth

// MARK: - Main Hub

struct StudioHubView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var subscriptionService = StudioSubscriptionService.shared
    @State private var activeMode: StudioMode?
    @State private var showPaywall = false
    @State private var showSynaptic = false
    @State private var showFaithReel = false

    // Entrance animation state
    @State private var cardsVisible = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Dark background
                Color.black.opacity(0.95)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        headerSection
                            .padding(.top, 16)
                            .padding(.bottom, 24)

                        entitlementBanner
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                            .opacity(cardsVisible ? 1 : 0)
                            .offset(y: cardsVisible ? 0 : 20)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.05), value: cardsVisible)

                        // Primary creation modes — 2x2 grid
                        VStack(spacing: 14) {
                            HStack(spacing: 14) {
                                DarkGlassModeCard(mode: .write, subscription: subscriptionService) {
                                    activateMode(.write)
                                }
                                .opacity(cardsVisible ? 1 : 0)
                                .offset(y: cardsVisible ? 0 : 20)
                                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.10), value: cardsVisible)

                                DarkGlassModeCard(mode: .canvas, subscription: subscriptionService) {
                                    activateMode(.canvas)
                                }
                                .opacity(cardsVisible ? 1 : 0)
                                .offset(y: cardsVisible ? 0 : 20)
                                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.15), value: cardsVisible)
                            }
                            HStack(spacing: 14) {
                                DarkGlassModeCard(mode: .journal, subscription: subscriptionService) {
                                    activateMode(.journal)
                                }
                                .opacity(cardsVisible ? 1 : 0)
                                .offset(y: cardsVisible ? 0 : 20)
                                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.20), value: cardsVisible)

                                DarkGlassModeCard(mode: .legacy, subscription: subscriptionService) {
                                    activateMode(.legacy)
                                }
                                .opacity(cardsVisible ? 1 : 0)
                                .offset(y: cardsVisible ? 0 : 20)
                                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.25), value: cardsVisible)
                            }
                        }
                        .padding(.horizontal, 20)

                        // Faith Reel Studio — now live
                        FaithReelLiveCard {
                            showFaithReel = true
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                        .opacity(cardsVisible ? 1 : 0)
                        .offset(y: cardsVisible ? 0 : 20)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.30), value: cardsVisible)

                        // Synaptic Studio
                        DarkGlassSynapticCard {
                            if subscriptionService.requiresUpgrade(for: .create) {
                                showPaywall = true
                            } else {
                                showSynaptic = true
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                        .opacity(cardsVisible ? 1 : 0)
                        .offset(y: cardsVisible ? 0 : 20)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.35), value: cardsVisible)

                        // Blueprint
                        DarkGlassBlueprintCard()
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                            .opacity(cardsVisible ? 1 : 0)
                            .offset(y: cardsVisible ? 0 : 20)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.40), value: cardsVisible)

                        // Collab
                        DarkGlassCollabCard()
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                            .opacity(cardsVisible ? 1 : 0)
                            .offset(y: cardsVisible ? 0 : 20)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.45), value: cardsVisible)

                        // Weekly Challenge
                        DarkGlassChallengeCard()
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                            .opacity(cardsVisible ? 1 : 0)
                            .offset(y: cardsVisible ? 0 : 20)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.50), value: cardsVisible)

                        Color.clear.frame(height: 40)
                    }
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    cardsVisible = true
                }
            }
            .sheet(item: $activeMode) { mode in
                switch mode {
                case .write:   StudioWriteView()
                case .canvas:  StudioAICreationView(initialTool: .scriptureCanvas)
                case .journal: StudioJournalView()
                case .legacy:  LegacyStudioView()
                }
            }
            .sheet(isPresented: $showPaywall) {
                StudioPaywallView()
            }
            .sheet(isPresented: $showSynaptic) {
                SynapticStudioView()
            }
            .fullScreenCover(isPresented: $showFaithReel) {
                FaithReelStudioView()
            }
        }
        .modelContainer(for: StudioDraft.self)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AMEN Studio")
                    .font(.custom("OpenSans-Bold", size: 28))
                    .foregroundStyle(.white)
                Text("Create. Remember. Reflect.")
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
            Spacer()
            Button { dismiss() } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 34, height: 34)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Entitlement Banner

    @ViewBuilder
    private var entitlementBanner: some View {
        let tier = subscriptionService.entitlement
        if tier == .free {
            Button { showPaywall = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Unlock Studio Creator")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("\(3 - subscriptionService.freeCreatesUsed) free creates remaining • Try 7 days free")
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func activateMode(_ mode: StudioMode) {
        if mode == .canvas && subscriptionService.requiresUpgrade(for: .aiMuse) {
            showPaywall = true
        } else if subscriptionService.requiresUpgrade(for: .create) {
            showPaywall = true
        } else {
            activeMode = mode
        }
    }
}

// MARK: - Dark Glass Mode Card (2×2 grid)

private struct DarkGlassModeCard: View {
    let mode: StudioMode
    let subscription: StudioSubscriptionService
    let action: () -> Void

    @State private var isPressed = false
    @State private var rippleScale: CGFloat = 0
    @State private var rippleOpacity: Double = 0

    var body: some View {
        Button(action: {
            triggerRipple()
            action()
        }) {
            ZStack(alignment: .topLeading) {
                // Card background
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                    )

                // Top sheen
                VStack {
                    LinearGradient(
                        colors: [Color.white.opacity(0.05), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    Spacer()
                }

                // Ripple
                GeometryReader { geo in
                    Circle()
                        .fill(Color.white.opacity(0.08 * rippleOpacity))
                        .frame(
                            width: max(geo.size.width, geo.size.height) * 1.5 * rippleScale,
                            height: max(geo.size.width, geo.size.height) * 1.5 * rippleScale
                        )
                        .position(
                            x: geo.size.width / 2,
                            y: geo.size.height / 2
                        )
                        .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                // Content
                VStack(alignment: .leading, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(mode.accentColor.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: mode.icon)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(mode.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(mode.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(mode.subtitle)
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.35))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    if mode.requiresPaid && subscription.entitlement == .free {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                            Text("Creator+")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(Color.white.opacity(0.5))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.07))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
                        )
                    }
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }

    private func triggerRipple() {
        rippleScale = 0
        rippleOpacity = 1
        withAnimation(.easeOut(duration: 0.55)) {
            rippleScale = 1
            rippleOpacity = 0
        }
    }
}

// MARK: - Faith Reel Live Card

private struct FaithReelLiveCard: View {
    let action: () -> Void

    @State private var isPressed = false
    @State private var rippleScale: CGFloat = 0
    @State private var rippleOpacity: Double = 0

    var body: some View {
        Button(action: {
            triggerRipple()
            action()
        }) {
            ZStack(alignment: .topLeading) {
                // Card background
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                    )

                // Top-left sheen
                LinearGradient(
                    colors: [Color.white.opacity(0.05), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                // Ripple
                GeometryReader { geo in
                    Circle()
                        .fill(Color.white.opacity(0.08 * rippleOpacity))
                        .frame(
                            width: max(geo.size.width, geo.size.height) * 1.5 * rippleScale,
                            height: max(geo.size.width, geo.size.height) * 1.5 * rippleScale
                        )
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red.opacity(0.12))
                            .frame(width: 48, height: 48)
                        Image(systemName: "film.stack")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.red.opacity(0.85))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Faith Reel Studio")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Create short-form video testimonies and worship reels")
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.35))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.35))
                }
                .padding(14)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }

    private func triggerRipple() {
        rippleScale = 0
        rippleOpacity = 1
        withAnimation(.easeOut(duration: 0.55)) {
            rippleScale = 1
            rippleOpacity = 0
        }
    }
}

// MARK: - Dark Glass Synaptic Card

private struct DarkGlassSynapticCard: View {
    let action: () -> Void

    @State private var isPressed = false
    @State private var rippleScale: CGFloat = 0
    @State private var rippleOpacity: Double = 0

    var body: some View {
        Button(action: {
            triggerRipple()
            action()
        }) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                    )

                LinearGradient(
                    colors: [Color.white.opacity(0.05), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                GeometryReader { geo in
                    Circle()
                        .fill(Color.white.opacity(0.08 * rippleOpacity))
                        .frame(
                            width: max(geo.size.width, geo.size.height) * 1.5 * rippleScale,
                            height: max(geo.size.width, geo.size.height) * 1.5 * rippleScale
                        )
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [Color.purple.opacity(0.2), Color.blue.opacity(0.12)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 20))
                            .foregroundStyle(.purple)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("Synaptic Studio")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("BETA")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.7))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.white.opacity(0.12)))
                        }
                        Text("Create from your body's state • Biometric-aware AI")
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.35))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.35))
                }
                .padding(14)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }

    private func triggerRipple() {
        rippleScale = 0
        rippleOpacity = 1
        withAnimation(.easeOut(duration: 0.55)) {
            rippleScale = 1
            rippleOpacity = 0
        }
    }
}

// MARK: - Dark Glass Blueprint Card

private struct DarkGlassBlueprintCard: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                )

            LinearGradient(
                colors: [Color.white.opacity(0.05), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.25), Color.yellow.opacity(0.15)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                    Image(systemName: "lightbulb.max.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Blueprint")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                        Text("COMING SOON")
                            .font(.system(size: 9, weight: .semibold))
                            .kerning(0.5)
                            .foregroundStyle(Color.white.opacity(0.35))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.07)))
                    }
                    Text("Turn your ideas into reality")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.35))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(["Idea Intake", "Stress Test", "Collaborators", "Launch Pad"], id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.orange.opacity(0.85))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.orange.opacity(0.09)))
                            }
                        }
                    }
                    .padding(.top, 2)
                }

                Spacer()
            }
            .padding(18)
        }
    }
}

// MARK: - Dark Glass Collab Card

private struct DarkGlassCollabCard: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                )

            LinearGradient(
                colors: [Color.white.opacity(0.05), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [Color.teal.opacity(0.25), Color.blue.opacity(0.15)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.teal)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Collab")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                        Text("COMING SOON")
                            .font(.system(size: 9, weight: .semibold))
                            .kerning(0.5)
                            .foregroundStyle(Color.white.opacity(0.35))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.07)))
                    }
                    Text("Co-create with your community")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.35))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(["Active Collabs", "Invite Followers", "Live Presence"], id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.teal.opacity(0.85))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.teal.opacity(0.09)))
                            }
                        }
                    }
                    .padding(.top, 2)
                }

                Spacer()

                // Live cursor presence dots — keep exact original colors
                HStack(spacing: -6) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill([Color.teal, Color.blue, Color.purple][i])
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle().stroke(Color.black.opacity(0.8), lineWidth: 2)
                            )
                    }
                }
            }
            .padding(18)
        }
    }
}

// MARK: - Dark Glass Challenge Card

private struct DarkGlassChallengeCard: View {
    let challengeTitle = "This Week: Write your testimony in 100 words"
    let challengeDeadline = "Ends Sunday"
    let participantCount = 247

    @State private var showChallenge = false
    @State private var isPressed = false
    @State private var rippleScale: CGFloat = 0
    @State private var rippleOpacity: Double = 0

    var body: some View {
        Button {
            triggerRipple()
            showChallenge = true
        } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                    )

                LinearGradient(
                    colors: [Color.white.opacity(0.05), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                GeometryReader { geo in
                    Circle()
                        .fill(Color.white.opacity(0.08 * rippleOpacity))
                        .frame(
                            width: max(geo.size.width, geo.size.height) * 1.5 * rippleScale,
                            height: max(geo.size.width, geo.size.height) * 1.5 * rippleScale
                        )
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.orange.opacity(0.12))
                            .frame(width: 48, height: 48)
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.orange)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Weekly Challenge")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)
                        Text(challengeTitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text("\(participantCount) creators participating • \(challengeDeadline)")
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.35))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.35))
                }
                .padding(16)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .sheet(isPresented: $showChallenge) {
            StudioAICreationView(initialTool: .challenge)
        }
    }

    private func triggerRipple() {
        rippleScale = 0
        rippleOpacity = 1
        withAnimation(.easeOut(duration: 0.55)) {
            rippleScale = 1
            rippleOpacity = 0
        }
    }
}

// MARK: - Studio Mode Enum

enum StudioMode: String, Identifiable {
    case write, canvas, journal, legacy
    var id: String { rawValue }

    var title: String {
        switch self {
        case .write:   return "Write"
        case .canvas:  return "Canvas"
        case .journal: return "Journal"
        case .legacy:  return "Legacy"
        }
    }
    var subtitle: String {
        switch self {
        case .write:   return "Testimonies, prayers, devotionals & sermon prep"
        case .canvas:  return "Scripture art & faith vision boards"
        case .journal: return "Private AI-assisted spiritual reflection"
        case .legacy:  return "Preserve life stories for generations"
        }
    }
    var icon: String {
        switch self {
        case .write:   return "pencil.and.scribble"
        case .canvas:  return "paintbrush.pointed.fill"
        case .journal: return "brain.head.profile"
        case .legacy:  return "heart.text.square.fill"
        }
    }
    var accentColor: Color {
        switch self {
        case .write:   return .blue
        case .canvas:  return .purple
        case .journal: return .green
        case .legacy:  return .orange
        }
    }
    var requiresPaid: Bool {
        switch self {
        case .canvas: return true
        default: return false
        }
    }
}
