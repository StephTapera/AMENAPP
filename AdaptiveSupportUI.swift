// AdaptiveSupportUI.swift
// AMENAPP
//
// Adaptive support surfaces shown by SafetyOrchestrator when
// behavioral or content signals indicate a user may need support.
//
// Surfaces (in order of urgency):
//   1. GentleCheckInCard    — soft opt-in check-in prompt
//   2. PauseAndBreatheCard  — grounding/breathing pause surface
//   3. PrayerSupportCard    — prayer + community support resources
//   4. CrisisHelpCard       — 988 + Crisis Text Line + trusted circle
//   5. FinancialHelpCard    — financial support resources
//   6. FullCrisisUrgentView — highest urgency; 988 front-and-center
//
// Design:
//   - Warm, non-clinical, faith-forward
//   - Never accusatory ("we noticed a pattern" vs. "you seem depressed")
//   - Always dismissible — user is never trapped
//   - Uses existing OpenSans font family consistent with app

import SwiftUI

// MARK: - Adaptive Support Overlay

/// Drop this over any view to present the appropriate support surface
/// whenever `SafetyOrchestrator.pendingSupportSurface` is set.
struct AdaptiveSupportOverlay: ViewModifier {
    @ObservedObject private var orchestrator = SafetyOrchestrator.shared
    @State private var isPresented = false
    @State private var currentSurface: SupportSurface?

    func body(content: Content) -> some View {
        content
            .onChange(of: orchestrator.pendingSupportSurface) { _, surface in
                if let surface {
                    currentSurface = surface
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        isPresented = true
                    }
                }
            }
            .sheet(isPresented: $isPresented, onDismiss: {
                orchestrator.dismissPendingSurface()
            }) {
                if let surface = currentSurface {
                    surfaceView(for: surface)
                        .presentationDetents(detentsFor(surface))
                        .presentationDragIndicator(.visible)
                        .presentationCornerRadius(28)
                }
            }
    }

    @ViewBuilder
    private func surfaceView(for surface: SupportSurface) -> some View {
        switch surface {
        case .gentleCheckIn:
            GentleCheckInCard(onDismiss: { isPresented = false })
        case .pauseAndBreathe:
            PauseAndBreatheCard(onDismiss: { isPresented = false })
        case .prayerAndSupport:
            PrayerSupportCard(onDismiss: { isPresented = false })
        case .crisisHelpCard:
            CrisisHelpCard(onDismiss: { isPresented = false })
        case .financialHelpCard:
            FinancialHelpCard(onDismiss: { isPresented = false })
        case .fullCrisisUrgent:
            FullCrisisUrgentView(onDismiss: { isPresented = false })
        }
    }

    private func detentsFor(_ surface: SupportSurface) -> Set<PresentationDetent> {
        switch surface {
        case .gentleCheckIn:   return [.height(320)]
        case .pauseAndBreathe: return [.height(440)]
        case .prayerAndSupport: return [.medium]
        case .crisisHelpCard:  return [.medium, .large]
        case .financialHelpCard: return [.medium]
        case .fullCrisisUrgent: return [.large]
        }
    }
}

extension View {
    /// Attaches the adaptive support overlay to any root view.
    func adaptiveSafetySupport() -> some View {
        modifier(AdaptiveSupportOverlay())
    }
}

// MARK: - Shared Style Helpers

private struct SupportHeaderView: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(iconColor)

            Text(title)
                .font(.custom("OpenSans-Bold", size: 22))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
    }
}

private struct SupportActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 32)
                    .accessibilityHidden(true)

                Text(label)
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }
}

private struct DismissButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 1. Gentle Check-In Card

/// Soft, optional check-in prompt. Low urgency — distress signal only.
/// The user is never told "we detected you're distressed."
struct GentleCheckInCard: View {
    let onDismiss: () -> Void
    @State private var selectedMood: CheckInMood?
    @State private var showFollowUp = false

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 5)
                .padding(.top, 12)

            SupportHeaderView(
                icon: "heart.text.square.fill",
                iconColor: Color(red: 0.85, green: 0.45, blue: 0.45),
                title: "Hey — how are you holding up?",
                subtitle: "Take a moment for yourself. No pressure."
            )

            // Mood row
            HStack(spacing: 10) {
                ForEach(CheckInMood.allCases, id: \.self) { mood in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            selectedMood = mood
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            withAnimation { showFollowUp = true }
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(mood.emoji)
                                .font(.system(size: 28))
                            Text(mood.label)
                                .font(.custom("OpenSans-Regular", size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                        .background(
                            selectedMood == mood
                                ? Color(.systemGray5)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .scaleEffect(selectedMood == mood ? 1.08 : 1.0)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)

            if showFollowUp, let mood = selectedMood {
                Text(mood.followUpMessage)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Spacer(minLength: 0)

            DismissButton(label: "I'm good, thanks") { onDismiss() }
                .padding(.bottom, 20)
        }
    }
}

enum CheckInMood: CaseIterable {
    case great, okay, meh, rough, struggling

    var emoji: String {
        switch self {
        case .great:      return "😊"
        case .okay:       return "🙂"
        case .meh:        return "😐"
        case .rough:      return "😔"
        case .struggling: return "😞"
        }
    }

    var label: String {
        switch self {
        case .great:      return "Great"
        case .okay:       return "Okay"
        case .meh:        return "Meh"
        case .rough:      return "Rough"
        case .struggling: return "Struggling"
        }
    }

    var followUpMessage: String {
        switch self {
        case .great:      return "Glad to hear it. Keep shining."
        case .okay:       return "That's okay. One step at a time."
        case .meh:        return "Even ordinary days count. You're here — that matters."
        case .rough:      return "Rough days are real. You're not alone in them."
        case .struggling: return "It's okay to not be okay. Would you like someone to pray with you?"
        }
    }
}

// MARK: - 2. Pause and Breathe Card

/// Gentle grounding prompt shown after frantic scrolling or heavy content.
struct PauseAndBreatheCard: View {
    let onDismiss: () -> Void
    @State private var breathPhase: BreathPhase = .inhale
    @State private var circleScale: CGFloat = 0.6
    @State private var isRunning = false

    var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 5)
                .padding(.top, 12)

            SupportHeaderView(
                icon: "wind",
                iconColor: Color(red: 0.36, green: 0.58, blue: 0.82),
                title: "Take a breath",
                subtitle: "You've been scrolling for a while.\nA moment of stillness can help."
            )

            // Breathing circle
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.44, green: 0.68, blue: 0.90).opacity(0.35),
                                Color(red: 0.36, green: 0.58, blue: 0.82).opacity(0.12)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                    .scaleEffect(circleScale)

                Text(breathPhase.instruction)
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(Color(red: 0.36, green: 0.58, blue: 0.82))
            }
            .frame(height: 180)

            Button {
                isRunning ? stopBreathing() : startBreathing()
            } label: {
                Text(isRunning ? "Pause" : "Start")
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 12)
                    .background(
                        Color(red: 0.36, green: 0.58, blue: 0.82),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            DismissButton(label: "I feel better, continue") { onDismiss() }
                .padding(.bottom, 20)
        }
    }

    private func startBreathing() {
        isRunning = true
        breathPhase = .inhale
        animateBreath()
    }

    private func stopBreathing() {
        isRunning = false
        withAnimation(.easeInOut(duration: 0.4)) { circleScale = 0.6 }
    }

    private func animateBreath() {
        guard isRunning else { return }
        breathPhase = .inhale
        withAnimation(.easeInOut(duration: 4.0)) { circleScale = 1.0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            guard self.isRunning else { return }
            self.breathPhase = .hold
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                guard self.isRunning else { return }
                self.breathPhase = .exhale
                withAnimation(.easeInOut(duration: 4.0)) { self.circleScale = 0.6 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    guard self.isRunning else { return }
                    self.animateBreath()
                }
            }
        }
    }

    enum BreathPhase {
        case inhale, hold, exhale
        var instruction: String {
            switch self {
            case .inhale: return "Breathe in..."
            case .hold:   return "Hold..."
            case .exhale: return "Breathe out..."
            }
        }
    }
}

// MARK: - 3. Prayer Support Card

/// Faith-forward support surface. Shown for emotional distress signals.
struct PrayerSupportCard: View {
    let onDismiss: () -> Void
    @State private var prayerText = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Capsule()
                    .fill(Color(.systemGray4))
                    .frame(width: 36, height: 5)
                    .padding(.top, 12)

                SupportHeaderView(
                    icon: "hands.sparkles.fill",
                    iconColor: Color(red: 0.70, green: 0.50, blue: 0.85),
                    title: "We're here with you",
                    subtitle: "Sometimes words are heavy. Would you like to share what's on your heart?"
                )

                // Scripture card
                VStack(alignment: .leading, spacing: 8) {
                    Text("\"Cast all your anxiety on him because he cares for you.\"")
                        .font(.custom("OpenSans-Italic", size: 15))
                        .foregroundStyle(.primary)

                    Text("1 Peter 5:7")
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(Color(red: 0.70, green: 0.50, blue: 0.85))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color(red: 0.70, green: 0.50, blue: 0.85).opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .padding(.horizontal, 20)

                // Action buttons
                VStack(spacing: 10) {
                    SupportActionButton(
                        icon: "hands.sparkles",
                        label: "Ask for prayer",
                        color: Color(red: 0.70, green: 0.50, blue: 0.85)
                    ) {
                        // Navigate to create a prayer request
                        NotificationCenter.default.post(name: .navigateToPrayerRequest, object: nil)
                        onDismiss()
                    }

                    SupportActionButton(
                        icon: "person.2.fill",
                        label: "Talk to someone in your community",
                        color: Color(red: 0.36, green: 0.58, blue: 0.82)
                    ) {
                        NotificationCenter.default.post(name: .navigateToMessages, object: nil)
                        onDismiss()
                    }

                    SupportActionButton(
                        icon: "phone.fill",
                        label: "Talk to a counselor (988)",
                        color: Color(red: 0.25, green: 0.68, blue: 0.55)
                    ) {
                        if let url = URL(string: "tel://988") {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                .padding(.horizontal, 20)

                DismissButton(label: "I'm okay, thanks") { onDismiss() }
                    .padding(.bottom, 24)
            }
        }
    }
}

// MARK: - 4. Crisis Help Card

/// Shown when crisis signals are detected. Warm but direct.
struct CrisisHelpCard: View {
    let onDismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Capsule()
                    .fill(Color(.systemGray4))
                    .frame(width: 36, height: 5)
                    .padding(.top, 12)

                SupportHeaderView(
                    icon: "heart.circle.fill",
                    iconColor: Color(red: 0.85, green: 0.35, blue: 0.35),
                    title: "You're not alone",
                    subtitle: "We noticed something that concerned us.\nYou matter, and support is here."
                )

                // Primary: 988
                Button {
                    if let url = URL(string: "tel://988") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Call 988")
                                .font(.custom("OpenSans-Bold", size: 17))
                                .foregroundStyle(.white)
                            Text("Suicide & Crisis Lifeline — 24/7")
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.white.opacity(0.85))
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Color(red: 0.85, green: 0.35, blue: 0.35), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Call 988 — Suicide and Crisis Lifeline, available 24 hours a day, 7 days a week")
                .accessibilityHint("Calls the 988 crisis hotline immediately")
                .accessibilityAddTraits(.isButton)

                VStack(spacing: 10) {
                    // Crisis Text Line
                    SupportActionButton(
                        icon: "message.fill",
                        label: "Text HOME to 741741",
                        color: Color(red: 0.25, green: 0.55, blue: 0.90)
                    ) {
                        if let url = URL(string: "sms:741741&body=HOME") {
                            UIApplication.shared.open(url)
                        }
                    }

                    // Prayer request
                    SupportActionButton(
                        icon: "hands.sparkles",
                        label: "Ask the community to pray",
                        color: Color(red: 0.70, green: 0.50, blue: 0.85)
                    ) {
                        NotificationCenter.default.post(name: .navigateToPrayerRequest, object: nil)
                        onDismiss()
                    }

                    // Christian counseling
                    SupportActionButton(
                        icon: "cross.circle.fill",
                        label: "Find a Christian counselor",
                        color: Color(red: 0.82, green: 0.60, blue: 0.25)
                    ) {
                        if let url = URL(string: "https://www.aacc.net/resources/find-a-counselor/") {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                .padding(.horizontal, 20)

                DismissButton(label: "I'm safe — close") { onDismiss() }
                    .padding(.bottom, 24)
            }
        }
    }
}

// MARK: - 5. Financial Help Card

/// Shown when financial distress signals are detected.
struct FinancialHelpCard: View {
    let onDismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Capsule()
                    .fill(Color(.systemGray4))
                    .frame(width: 36, height: 5)
                    .padding(.top, 12)

                SupportHeaderView(
                    icon: "house.fill",
                    iconColor: Color(red: 0.82, green: 0.60, blue: 0.25),
                    title: "Help is available",
                    subtitle: "Financial hardship is real and difficult.\nYou don't have to face it alone."
                )

                // Scripture card
                VStack(alignment: .leading, spacing: 8) {
                    Text("\"My God will meet all your needs according to the riches of his glory in Christ Jesus.\"")
                        .font(.custom("OpenSans-Italic", size: 14))
                        .foregroundStyle(.primary)

                    Text("Philippians 4:19")
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(Color(red: 0.82, green: 0.60, blue: 0.25))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color(red: 0.82, green: 0.60, blue: 0.25).opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .padding(.horizontal, 20)

                VStack(spacing: 10) {
                    SupportActionButton(
                        icon: "building.columns.fill",
                        label: "Find local assistance (211.org)",
                        color: Color(red: 0.82, green: 0.60, blue: 0.25)
                    ) {
                        if let url = URL(string: "https://www.211.org") {
                            UIApplication.shared.open(url)
                        }
                    }

                    SupportActionButton(
                        icon: "cross.circle.fill",
                        label: "Ask your church for support",
                        color: Color(red: 0.70, green: 0.50, blue: 0.85)
                    ) {
                        NotificationCenter.default.post(name: .navigateToFindChurch, object: nil)
                        onDismiss()
                    }

                    SupportActionButton(
                        icon: "hands.sparkles",
                        label: "Ask the community to pray",
                        color: Color(red: 0.36, green: 0.58, blue: 0.82)
                    ) {
                        NotificationCenter.default.post(name: .navigateToPrayerRequest, object: nil)
                        onDismiss()
                    }
                }
                .padding(.horizontal, 20)

                DismissButton(label: "I'm okay — close") { onDismiss() }
                    .padding(.bottom, 24)
            }
        }
    }
}

// MARK: - 6. Full Crisis Urgent View

/// Highest urgency. Shown only for confirmed crisis-level signals.
/// 988 is immediately front-and-center.
struct FullCrisisUrgentView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Warm top banner
            VStack(spacing: 16) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 64, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.90, green: 0.40, blue: 0.40),
                                     Color(red: 0.95, green: 0.62, blue: 0.45)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("Please reach out right now")
                    .font(.custom("OpenSans-Bold", size: 24))
                    .foregroundStyle(.primary)

                Text("You are seen. You are loved.\nHelp is one call or text away.")
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)
            .padding(.horizontal, 28)
            .padding(.bottom, 28)

            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    // 988 — Full-width primary CTA
                    Button {
                        if let url = URL(string: "tel://988") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Call 988 now")
                                    .font(.custom("OpenSans-Bold", size: 18))
                                    .foregroundStyle(.white)
                                Text("Suicide & Crisis Lifeline")
                                    .font(.custom("OpenSans-Regular", size: 14))
                                    .foregroundStyle(.white.opacity(0.85))
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 18)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.88, green: 0.35, blue: 0.35),
                                         Color(red: 0.80, green: 0.28, blue: 0.28)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 18)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)

                    // Text line
                    SupportActionButton(
                        icon: "message.fill",
                        label: "Text HOME to 741741",
                        color: Color(red: 0.25, green: 0.55, blue: 0.90)
                    ) {
                        if let url = URL(string: "sms:741741&body=HOME") {
                            UIApplication.shared.open(url)
                        }
                    }
                    .padding(.horizontal, 20)

                    // Emergency
                    SupportActionButton(
                        icon: "cross.case.fill",
                        label: "Call 911 (immediate danger)",
                        color: Color(red: 0.82, green: 0.25, blue: 0.25)
                    ) {
                        if let url = URL(string: "tel://911") {
                            UIApplication.shared.open(url)
                        }
                    }
                    .padding(.horizontal, 20)

                    // Prayer
                    SupportActionButton(
                        icon: "hands.sparkles",
                        label: "Ask the community to pray for me",
                        color: Color(red: 0.70, green: 0.50, blue: 0.85)
                    ) {
                        NotificationCenter.default.post(name: .navigateToPrayerRequest, object: nil)
                        onDismiss()
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 20)
                .padding(.bottom, 36)
            }

            // Close — requires explicit tap
            Button(action: onDismiss) {
                Text("I am safe — close")
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 16)
        }
    }
}

// MARK: - Navigation Notification Keys

extension Notification.Name {
    static let navigateToPrayerRequest = Notification.Name("navigateToPrayerRequest")
    static let navigateToMessages      = Notification.Name("navigateToMessages")
}
