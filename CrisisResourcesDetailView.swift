//
//  CrisisResourcesDetailView.swift
//  AMENAPP
//
//  Redesigned: Support Hub — Crisis Help
//  Design language: Liquid Light (lensing, materialization, fluidity, morphing, adaptivity)
//

import SwiftUI

// MARK: - Crisis Resources Detail View

struct CrisisResourcesDetailView: View {
    @State private var selectedHotline: CrisisHotline?
    @State private var showCallConfirmation = false
    @State private var showTextConfirmation = false
    @State private var expandedSection: CrisisSection? = .immediate
    @State private var safetyPlanExpanded = false
    @State private var breathingActive = false
    @State private var breathPhase: BreathPhase = .inhale
    @State private var breathScale: CGFloat = 1.0
    @State private var appeared = false   // materialization gate

    enum CrisisSection: String, CaseIterable {
        case immediate = "Immediate Help"
        case safetyPlan = "Safety Plan"
        case faithBased = "Faith & Prayer"
        case youth = "Youth Resources"
        case abuse = "Abuse & Safety"
        case addiction = "Recovery"
    }

    enum BreathPhase {
        case inhale, hold, exhale
        var label: String {
            switch self {
            case .inhale: return "Breathe in…"
            case .hold:   return "Hold…"
            case .exhale: return "Breathe out…"
            }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // ── Full-bleed immersive hero — extends into safe area ────────
                heroHeader

                // ── Emergency CTA — always visible ───────────────────────────
                emergencyCTA
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)

                // ── Breathing tool ───────────────────────────────────────────
                breathingTool
                    .padding(.top, 16)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 8)

                // ── Collapsible sections ──────────────────────────────────────
                VStack(spacing: 12) {
                    ForEach(CrisisSection.allCases, id: \.self) { section in
                        SupportSectionCard(
                            section: section,
                            isExpanded: expandedSection == section,
                            content: { sectionContent(for: section) }
                        ) {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.75)) {
                                expandedSection = expandedSection == section ? nil : section
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)

                // ── Berean private chat ───────────────────────────────────────
                bereanPrivateCard
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .opacity(appeared ? 1 : 0)

                // ── Bottom safety message ─────────────────────────────────────
                safetyFooter
                    .padding(.top, 24)
                    .padding(.bottom, 48)
                    .opacity(appeared ? 1 : 0)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            withAnimation(.easeOut(duration: 0.55).delay(0.08)) {
                appeared = true
            }
        }
        .alert("Call \(selectedHotline?.name ?? "Hotline")?", isPresented: $showCallConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Call Now") {
                if let n = selectedHotline?.phoneNumber { dial(n) }
            }
        } message: {
            Text(selectedHotline?.description ?? "")
        }
        .alert("Text \(selectedHotline?.name ?? "Hotline")?", isPresented: $showTextConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Open Messages") {
                if let n = selectedHotline?.textNumber { sms(n) }
            }
        } message: {
            Text(selectedHotline?.textInstructions ?? "")
        }
    }

    // MARK: Hero Header

    // Crisis-unique color palette — deep burgundy warmth, not used elsewhere in the app
    private let crisisDark    = Color(red: 0.18, green: 0.07, blue: 0.10)   // deep burgundy-black
    private let crisisMid     = Color(red: 0.42, green: 0.12, blue: 0.22)   // rich crimson
    private let crisisAccent  = Color(red: 0.72, green: 0.28, blue: 0.32)   // warm rose
    private let crisisGold    = Color(red: 0.88, green: 0.72, blue: 0.48)   // harvest gold
    private let crisisInkLight = Color.white.opacity(0.92)
    private let crisisSubLight = Color.white.opacity(0.60)

    private var heroHeader: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                // Base — deep burgundy gradient
                LinearGradient(
                    colors: [crisisDark, crisisMid],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Warm radial bloom from top-right
                RadialGradient(
                    colors: [crisisAccent.opacity(0.35), Color.clear],
                    center: UnitPoint(x: 0.82, y: 0.15),
                    startRadius: 20,
                    endRadius: 280
                )

                // Gold accent — bottom-left warmth
                RadialGradient(
                    colors: [crisisGold.opacity(0.18), Color.clear],
                    center: UnitPoint(x: 0.05, y: 0.95),
                    startRadius: 0,
                    endRadius: 200
                )

                // Subtle grain texture — horizontal editorial lines
                VStack(spacing: 28) {
                    ForEach(0..<6, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.white.opacity(0.03))
                            .frame(height: 1)
                    }
                }
                .frame(maxWidth: .infinity)

                // Content — sits above safe area bottom
                VStack(alignment: .leading, spacing: 0) {
                    Spacer()

                    // Eyebrow label
                    Text("CRISIS HELP & SUPPORT")
                        .font(.system(size: 9, weight: .semibold))
                        .kerning(2.5)
                        .foregroundStyle(crisisSubLight)
                        .padding(.bottom, 10)

                    // Large serif headline
                    Text("You are\nnot alone.")
                        .font(.custom("Georgia", size: 38))
                        .fontWeight(.regular)
                        .foregroundStyle(crisisInkLight)
                        .lineSpacing(4)
                        .padding(.bottom, 10)

                    // Subtitle
                    Text("Confidential help is here, 24/7.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(crisisSubLight)
                        .padding(.bottom, 28)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .ignoresSafeArea(edges: .top)
        .opacity(appeared ? 1 : 0)
    }

    // MARK: Emergency CTA

    private var emergencyCTA: some View {
        VStack(spacing: 10) {
            // Immediate danger
            Button { dial("911") } label: {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 18))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Immediate danger — call 911")
                            .font(.custom("OpenSans-Bold", size: 15))
                        Text("Emergency services in the US")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .opacity(0.8)
                    }
                    Spacer()
                    Image(systemName: "phone.fill")
                        .font(.system(size: 14))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(red: 0.72, green: 0.12, blue: 0.12))
                        .shadow(color: Color(red: 0.72, green: 0.12, blue: 0.12).opacity(0.28), radius: 10, y: 4)
                )
            }
            .buttonStyle(SquishButtonStyle())

            // 988 quick access
            HStack(spacing: 10) {
                QuickContactPill(
                    label: "Call 988",
                    icon: "phone.fill",
                    accent: Color(red: 0.72, green: 0.12, blue: 0.12)
                ) { dial("988") }

                QuickContactPill(
                    label: "Text 988",
                    icon: "message.fill",
                    accent: Color(red: 0.48, green: 0.22, blue: 0.72)
                ) { sms("988") }

                QuickContactPill(
                    label: "Text HOME",
                    icon: "bubble.left.fill",
                    accent: Color(red: 0.18, green: 0.48, blue: 0.72)
                ) {
                    // Crisis Text Line — text HOME to 741741
                    if let url = URL(string: "sms:741741&body=HOME") {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }

    // MARK: Breathing Tool

    private var breathingTool: some View {
        VStack(spacing: 14) {
            HStack {
                Label("Grounding Exercise", systemImage: "wind")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    breathingActive.toggle()
                    if breathingActive { startBreathingCycle() }
                } label: {
                    Text(breathingActive ? "Stop" : "Start")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.blue.opacity(0.10))
                        )
                }
                .buttonStyle(SquishButtonStyle())
            }
            .padding(.horizontal, 20)

            if breathingActive {
                ZStack {
                    // Outer ring — lens glow
                    Circle()
                        .stroke(Color.blue.opacity(0.18), lineWidth: 1.5)
                        .frame(width: 100, height: 100)
                        .scaleEffect(breathScale * 1.2)
                        .blur(radius: 4)

                    // Inner circle — morphs with breath phase
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.blue.opacity(0.25), Color.blue.opacity(0.08)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 50
                            )
                        )
                        .frame(width: 80, height: 80)
                        .scaleEffect(breathScale)

                    Text(breathPhase.label)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
                .animation(.easeInOut(duration: breathPhase == .inhale ? 4.0 : breathPhase == .hold ? 0 : 6.0), value: breathScale)
                .frame(height: 120)
            }
        }
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
    }

    // MARK: Section Content

    @ViewBuilder
    private func sectionContent(for section: CrisisSection) -> some View {
        switch section {
        case .immediate:
            VStack(spacing: 10) {
                ForEach(CrisisHotline.nationalHotlines) { hotline in
                    HotlineRow(hotline: hotline) {
                        selectedHotline = hotline
                        if hotline.textNumber != nil {
                            showTextConfirmation = true
                        } else {
                            showCallConfirmation = true
                        }
                    }
                }
            }
        case .safetyPlan:
            SafetyPlanContent()
        case .faithBased:
            VStack(spacing: 10) {
                ForEach(CrisisHotline.faithBasedResources) { hotline in
                    HotlineRow(hotline: hotline) {
                        selectedHotline = hotline
                        showCallConfirmation = true
                    }
                }
                ResourceLinkRow(
                    icon: "hands.sparkles.fill",
                    title: "Ask Berean for prayer support",
                    subtitle: "Private, scripture-grounded comfort",
                    accent: Color(red: 0.48, green: 0.22, blue: 0.72)
                )
            }
        case .youth:
            VStack(spacing: 10) {
                ForEach(CrisisHotline.youthResources) { hotline in
                    HotlineRow(hotline: hotline) {
                        selectedHotline = hotline
                        showCallConfirmation = true
                    }
                }
                CrisisInfoRow(
                    icon: "lock.shield.fill",
                    text: "If you are under 18, please tell a trusted adult. You can also text a crisis counselor privately.",
                    accent: .orange
                )
            }
        case .abuse:
            VStack(spacing: 10) {
                ForEach(CrisisHotline.abuseResources) { hotline in
                    HotlineRow(hotline: hotline) {
                        selectedHotline = hotline
                        if hotline.textNumber != nil {
                            showTextConfirmation = true
                        } else {
                            showCallConfirmation = true
                        }
                    }
                }
                CrisisInfoRow(
                    icon: "info.circle.fill",
                    text: "If it is not safe to call, text or use the online chat options. Your safety comes first.",
                    accent: Color(red: 0.72, green: 0.12, blue: 0.12)
                )
            }
        case .addiction:
            VStack(spacing: 10) {
                ForEach(CrisisHotline.addictionResources) { hotline in
                    HotlineRow(hotline: hotline) {
                        selectedHotline = hotline
                        showCallConfirmation = true
                    }
                }
                ResourceLinkRow(
                    icon: "person.3.fill",
                    title: "Celebrate Recovery",
                    subtitle: "Christ-centered 12-step groups near you",
                    accent: .green
                )
            }
        }
    }

    // MARK: Berean Private Card

    private var bereanPrivateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.12, green: 0.55, blue: 0.52).opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color(red: 0.12, green: 0.55, blue: 0.52))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Talk to Berean privately")
                        .font(.custom("OpenSans-Bold", size: 15))
                        .foregroundStyle(.primary)
                    Text("No storage option · scripture-grounded support")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }

            Text("Berean won't replace professional care, but can help you process, pray, and find next steps.")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.32), Color.white.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
    }

    // MARK: Footer

    private var safetyFooter: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
            Text("Your privacy is protected. This section is private and is never shown publicly on your profile.")
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: Helpers

    private func dial(_ number: String) {
        let clean = number.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        if let url = URL(string: "tel://\(clean)") { UIApplication.shared.open(url) }
    }

    private func sms(_ number: String) {
        let clean = number.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        if let url = URL(string: "sms:\(clean)") { UIApplication.shared.open(url) }
    }

    private func startBreathingCycle() {
        guard breathingActive else { return }
        breathPhase = .inhale
        breathScale = 1.4
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            guard breathingActive else { return }
            breathPhase = .hold
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard breathingActive else { return }
                breathPhase = .exhale
                withAnimation(.easeInOut(duration: 6.0)) { breathScale = 1.0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) {
                    startBreathingCycle()
                }
            }
        }
    }
}

// MARK: - Support Section Card (folder → detail morphing card)

private struct SupportSectionCard<Content: View>: View {
    let section: CrisisResourcesDetailView.CrisisSection
    let isExpanded: Bool
    @ViewBuilder let content: () -> Content
    let onToggle: () -> Void

    private var accentColor: Color {
        switch section {
        case .immediate:  return Color(red: 0.72, green: 0.12, blue: 0.12)
        case .safetyPlan: return Color(red: 0.18, green: 0.48, blue: 0.72)
        case .faithBased: return Color(red: 0.48, green: 0.22, blue: 0.72)
        case .youth:      return Color(red: 0.82, green: 0.48, blue: 0.10)
        case .abuse:      return Color(red: 0.55, green: 0.20, blue: 0.42)
        case .addiction:  return Color(red: 0.12, green: 0.55, blue: 0.35)
        }
    }

    private var sectionIcon: String {
        switch section {
        case .immediate:  return "phone.fill"
        case .safetyPlan: return "checklist"
        case .faithBased: return "hands.sparkles.fill"
        case .youth:      return "person.badge.shield.checkmark.fill"
        case .abuse:      return "shield.fill"
        case .addiction:  return "heart.circle.fill"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header row — tap to expand (morphing chip → card)
            Button(action: onToggle) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(isExpanded ? 0.18 : 0.11))
                            .frame(width: 40, height: 40)
                        Image(systemName: sectionIcon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(accentColor)
                    }
                    Text(section.rawValue)
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(SquishButtonStyle())

            // Expandable body — materialization
            if isExpanded {
                VStack(spacing: 0) {
                    Divider()
                        .padding(.horizontal, 16)
                    content()
                        .padding(16)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(
                            isExpanded
                                ? accentColor.opacity(0.22)
                                : Color.white.opacity(0.18),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(isExpanded ? 0.07 : 0.04), radius: isExpanded ? 12 : 6, y: 2)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: isExpanded)
    }
}

// MARK: - Hotline Row

private struct HotlineRow: View {
    let hotline: CrisisHotline
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(hotline.color.opacity(0.13))
                        .frame(width: 42, height: 42)
                    Image(systemName: hotline.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(hotline.color)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(hotline.name)
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    if hotline.available247 {
                        HStack(spacing: 4) {
                            Circle().fill(Color.green).frame(width: 5, height: 5)
                            Text("Available 24/7")
                                .font(.custom("OpenSans-Regular", size: 11))
                                .foregroundStyle(.green)
                        }
                    }
                }

                Spacer()

                // Contact badges
                HStack(spacing: 6) {
                    if hotline.phoneNumber != nil {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(hotline.color)
                    }
                    if hotline.textNumber != nil {
                        Image(systemName: "message.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(hotline.color)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(hotline.color.opacity(0.06))
            )
        }
        .buttonStyle(SquishButtonStyle())
    }
}

// MARK: - Safety Plan Content

private struct SafetyPlanContent: View {
    @State private var expandedStep: Int? = nil

    private let steps: [(title: String, prompt: String)] = [
        ("Warning signs I notice",         "What thoughts, feelings, or situations tell me I'm in crisis?"),
        ("My internal coping strategies",  "Things I can do on my own to take my mind off distress."),
        ("People and places that help",    "Who can I contact for support? Where can I go?"),
        ("People I can ask for help",      "Name and contact for 2–3 trusted people."),
        ("Professional support contacts",  "Therapist, counselor, or crisis line."),
        ("Making my environment safe",     "What can I do to reduce access to means of harm?"),
    ]

    var body: some View {
        VStack(spacing: 8) {
            Text("A safety plan helps you prepare before a crisis. Tap each step to reflect on it.")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .padding(.bottom, 4)

            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                        expandedStep = expandedStep == index ? nil : index
                    }
                } label: {
                    VStack(alignment: .leading, spacing: expandedStep == index ? 8 : 0) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Color(red: 0.18, green: 0.48, blue: 0.72).opacity(0.14))
                                    .frame(width: 28, height: 28)
                                Text("\(index + 1)")
                                    .font(.custom("OpenSans-Bold", size: 13))
                                    .foregroundStyle(Color(red: 0.18, green: 0.48, blue: 0.72))
                            }
                            Text(step.title)
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: expandedStep == index ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        if expandedStep == index {
                            Text(step.prompt)
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.secondary)
                                .lineSpacing(3)
                                .padding(.leading, 38)
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(expandedStep == index
                                  ? Color(red: 0.18, green: 0.48, blue: 0.72).opacity(0.07)
                                  : Color(.systemGray6).opacity(0.6))
                    )
                }
                .buttonStyle(SquishButtonStyle())
            }
        }
    }
}

// MARK: - Resource Link Row

private struct ResourceLinkRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(accent.opacity(0.06))
        )
    }
}

// MARK: - Info Row

private struct CrisisInfoRow: View {
    let icon: String
    let text: String
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(accent)
                .padding(.top, 1)
            Text(text)
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(accent.opacity(0.07))
        )
    }
}

// MARK: - Quick Contact Pill

private struct QuickContactPill: View {
    let label: String
    let icon: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.custom("OpenSans-SemiBold", size: 13))
            }
            .foregroundStyle(accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(accent.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(accent.opacity(0.20), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(SquishButtonStyle())
    }
}

// MARK: - Squish Button Style (fluidity)

struct SquishButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Data Models

struct CrisisHotline: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let phoneNumber: String?
    let textNumber: String?
    let textInstructions: String?
    let icon: String
    let color: Color
    let available247: Bool

    static let nationalHotlines = [
        CrisisHotline(
            name: "988 Suicide & Crisis Lifeline",
            description: "Free, confidential support for people in distress, prevention and crisis resources.",
            phoneNumber: "988",
            textNumber: "988",
            textInstructions: "Text 988 to connect with a crisis counselor.",
            icon: "phone.fill",
            color: Color(red: 0.72, green: 0.12, blue: 0.12),
            available247: true
        ),
        CrisisHotline(
            name: "Crisis Text Line",
            description: "Text HOME to 741741 to reach a crisis counselor. Free, 24/7, confidential.",
            phoneNumber: nil,
            textNumber: "741741",
            textInstructions: "Text HOME to 741741 from anywhere in the US.",
            icon: "message.fill",
            color: .orange,
            available247: true
        ),
        CrisisHotline(
            name: "SAMHSA National Helpline",
            description: "Treatment referral for mental health and substance use disorders. Free & confidential.",
            phoneNumber: "1-800-662-4357",
            textNumber: nil,
            textInstructions: nil,
            icon: "heart.circle.fill",
            color: .purple,
            available247: true
        ),
        CrisisHotline(
            name: "Veterans Crisis Line",
            description: "Confidential support for veterans, service members, and their families.",
            phoneNumber: "988",
            textNumber: "838255",
            textInstructions: "Text 838255, or press 1 after calling 988.",
            icon: "star.fill",
            color: Color(red: 0.18, green: 0.38, blue: 0.72),
            available247: true
        ),
    ]

    static let faithBasedResources = [
        CrisisHotline(
            name: "Christian Crisis Hotline",
            description: "Faith-based crisis counseling and prayer support from trained volunteers.",
            phoneNumber: "1-855-382-5433",
            textNumber: nil,
            textInstructions: nil,
            icon: "cross.fill",
            color: Color(red: 0.18, green: 0.38, blue: 0.72),
            available247: true
        ),
        CrisisHotline(
            name: "Focus on the Family Counseling",
            description: "Licensed Christian counselors available by phone for free consultation.",
            phoneNumber: "1-855-771-4357",
            textNumber: nil,
            textInstructions: nil,
            icon: "person.3.fill",
            color: .green,
            available247: false
        ),
    ]

    static let youthResources = [
        CrisisHotline(
            name: "Teen Line",
            description: "Teens helping teens. Talk to a trained teen counselor about any problem.",
            phoneNumber: "1-800-852-8336",
            textNumber: "839863",
            textInstructions: "Text TEEN to 839863.",
            icon: "person.fill",
            color: .orange,
            available247: false
        ),
        CrisisHotline(
            name: "The Trevor Project",
            description: "Crisis intervention and suicide prevention for LGBTQ young people.",
            phoneNumber: "1-866-488-7386",
            textNumber: "678-678",
            textInstructions: "Text START to 678-678.",
            icon: "heart.fill",
            color: .pink,
            available247: true
        ),
    ]

    static let abuseResources = [
        CrisisHotline(
            name: "National DV Hotline",
            description: "Support for victims of domestic violence and abuse. Confidential, 24/7.",
            phoneNumber: "1-800-799-7233",
            textNumber: "88788",
            textInstructions: "Text START to 88788.",
            icon: "shield.fill",
            color: Color(red: 0.55, green: 0.20, blue: 0.42),
            available247: true
        ),
        CrisisHotline(
            name: "RAINN Sexual Assault Hotline",
            description: "Free, confidential support from trained staff about sexual assault.",
            phoneNumber: "1-800-656-4673",
            textNumber: nil,
            textInstructions: nil,
            icon: "shield.lefthalf.filled",
            color: Color(red: 0.72, green: 0.12, blue: 0.12),
            available247: true
        ),
        CrisisHotline(
            name: "National Human Trafficking Hotline",
            description: "Report trafficking, connect with services, or get help. Multilingual.",
            phoneNumber: "1-888-373-7888",
            textNumber: "233733",
            textInstructions: "Text 233733 (BEFREE).",
            icon: "lock.open.fill",
            color: .purple,
            available247: true
        ),
    ]

    static let addictionResources = [
        CrisisHotline(
            name: "SAMHSA Helpline",
            description: "Free, confidential treatment referrals for substance use and mental health.",
            phoneNumber: "1-800-662-4357",
            textNumber: nil,
            textInstructions: nil,
            icon: "heart.circle.fill",
            color: .purple,
            available247: true
        ),
        CrisisHotline(
            name: "AA Hotline",
            description: "Alcoholics Anonymous — find local meetings and get peer support.",
            phoneNumber: "1-800-839-1686",
            textNumber: nil,
            textInstructions: nil,
            icon: "person.2.fill",
            color: .green,
            available247: true
        ),
    ]
}

struct OnlineResource: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let url: String
    let icon: String
    let color: Color

    static let crisisResources = [
        OnlineResource(
            name: "MentalHealth.gov",
            description: "Comprehensive mental health information and resources",
            url: "https://www.mentalhealth.gov",
            icon: "brain.head.profile",
            color: .blue
        ),
        OnlineResource(
            name: "NAMI Support",
            description: "National Alliance on Mental Illness resources and support groups",
            url: "https://www.nami.org",
            icon: "person.2.fill",
            color: .purple
        ),
        OnlineResource(
            name: "Psychology Today",
            description: "Find therapists and counselors in your area",
            url: "https://www.psychologytoday.com/us/therapists",
            icon: "magnifyingglass",
            color: .green
        ),
        OnlineResource(
            name: "IMAlive Crisis Chat",
            description: "Free online crisis chat service",
            url: "https://www.imalive.org",
            icon: "bubble.left.and.bubble.right.fill",
            color: .orange
        ),
    ]
}

#Preview {
    NavigationStack {
        CrisisResourcesDetailView()
    }
}
