//
//  AppUsageTracker.swift
//  AMENAPP
//
//  Created by Steph on 1/31/26.
//
//  Tracks daily app usage time and shows reminders when limit is reached
//

import SwiftUI
import Combine

/// Tracks app usage time and manages daily time limits
@MainActor
class AppUsageTracker: ObservableObject {
    static let shared = AppUsageTracker()
    
    @Published var todayUsageMinutes: Int = 0
    @Published var dailyLimitMinutes: Int = 45
    @Published var showLimitReachedDialog: Bool = false
    @Published var hasShownLimitDialog: Bool = false
    @Published var snoozeUntil: Date? = nil
    /// Frozen snapshot of todayUsageMinutes captured the moment the limit dialog fires.
    /// Used by DailyLimitReachedDialog so the displayed count doesn't tick live.
    @Published var snapshotUsageMinutes: Int = 0
    
    private var sessionStartTime: Date?
    private var currentSessionStartTime: Date?  // Track current continuous session
    private var timer: Timer?
    private var lastSaveDate: Date?
    /// Stored handle for the per-tick smart-break analysis task so it can be
    /// cancelled in deinit rather than leaking into the next timer cycle.
    private var smartBreakTask: Task<Void, Never>?
    
    private let usageKey = "app_usage_today"
    private let limitKey = "daily_time_limit"
    private let lastSaveDateKey = "last_save_date"
    
    // Smart break reminder integration
    private let smartBreakReminder = SmartBreakReminderService.shared
    
    private init() {
        loadUsageData()
        setupTimer()
    }
    
    // MARK: - Public Methods
    
    /// Start tracking session when app becomes active
    func startSession() {
        // Guard against duplicate calls (e.g. scenePhase .active + ContentView .task)
        guard sessionStartTime == nil else { return }
        sessionStartTime = Date()
        currentSessionStartTime = Date()  // Start continuous session tracking
        dlog("📊 AppUsageTracker: Session started")
    }
    
    /// End tracking session when app becomes inactive
    func endSession() {
        guard let startTime = sessionStartTime else { return }
        
        let sessionDuration = Date().timeIntervalSince(startTime)
        let sessionMinutes = Int(sessionDuration / 60)
        
        todayUsageMinutes += sessionMinutes
        saveUsageData()
        sessionStartTime = nil
        currentSessionStartTime = nil  // End continuous session tracking
        
        dlog("📊 AppUsageTracker: Session ended. Duration: \(sessionMinutes) minutes. Total today: \(todayUsageMinutes) minutes")
    }
    
    /// Update daily time limit
    func updateDailyLimit(_ minutes: Int) {
        dailyLimitMinutes = minutes
        UserDefaults.standard.set(minutes, forKey: limitKey)
        dlog("⏱️ AppUsageTracker: Daily limit updated to \(minutes) minutes")
    }
    
    /// Reset usage for a new day
    func resetDailyUsage() {
        todayUsageMinutes = 0
        hasShownLimitDialog = false
        saveUsageData()
        
        // Also reset smart break reminder counters
        smartBreakReminder.resetDailyCounters()
        
        dlog("🔄 AppUsageTracker: Daily usage reset")
    }
    
    /// Check if limit has been reached
    var hasReachedLimit: Bool {
        todayUsageMinutes >= dailyLimitMinutes
    }
    
    /// Get remaining time in minutes
    var remainingMinutes: Int {
        max(0, dailyLimitMinutes - todayUsageMinutes)
    }
    
    /// Get progress percentage
    var usagePercentage: Double {
        guard dailyLimitMinutes > 0 else { return 0 }
        return min(1.0, Double(todayUsageMinutes) / Double(dailyLimitMinutes))
    }

    /// Read-only continuous (foreground) session length in seconds; 0 when no session
    /// is active. Consumed by Selah Contextual to drive rest / doomscroll cues.
    var continuousSessionSeconds: TimeInterval {
        guard let start = currentSessionStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    // MARK: - Private Methods
    
    private func setupTimer() {
        // Update every minute
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkAndUpdateUsage()
            }
        }
    }
    
    private func checkAndUpdateUsage() {
        guard sessionStartTime != nil else { return }
        
        // Increment usage by 1 minute
        todayUsageMinutes += 1
        saveUsageData()
        
        // Calculate continuous session duration
        let continuousMinutes: Int
        if let sessionStart = currentSessionStartTime {
            continuousMinutes = Int(Date().timeIntervalSince(sessionStart) / 60)
        } else {
            continuousMinutes = 0
        }
        
        // Check smart break reminder only when below the daily reminder cap.
        // Skipping the Task entirely when the limit is already exhausted avoids
        // spawning an async task + printing "limit reached" on every 1-minute tick
        // for users who have been using the app beyond their daily threshold.
        if smartBreakReminder.usageRemindersToday < 2 {
            // Cancel any in-flight task from the previous tick before starting a new one.
            smartBreakTask?.cancel()
            smartBreakTask = Task { [weak self] in
                guard let self else { return }
                await self.smartBreakReminder.analyzeUsageAndRemind(
                    continuousMinutes: continuousMinutes,
                    totalMinutesToday: self.todayUsageMinutes,
                    dailyLimit: self.dailyLimitMinutes
                )
            }
        }
        
        // Show dialog when limit is reached (or re-reached after a snooze)
        if todayUsageMinutes >= dailyLimitMinutes && !hasShownLimitDialog {
            if let snoozeEnd = snoozeUntil, Date() < snoozeEnd { return }
            snapshotUsageMinutes = todayUsageMinutes
            showLimitReachedDialog = true
            hasShownLimitDialog = true
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.warning)
            dlog("⏰ AppUsageTracker: Daily limit of \(dailyLimitMinutes) minutes reached! Showing dialog.")
        }
    }

    /// Hide the dialog and re-arm it after the given number of minutes.
    func snooze(minutes: Int) {
        snoozeUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        hasShownLimitDialog = false
        showLimitReachedDialog = false
        dlog("⏰ AppUsageTracker: Snoozed for \(minutes) min")
    }
    
    private func loadUsageData() {
        // Load daily limit
        if UserDefaults.standard.object(forKey: limitKey) != nil {
            dailyLimitMinutes = UserDefaults.standard.integer(forKey: limitKey)
        }
        
        // Load last save date
        if let lastDate = UserDefaults.standard.object(forKey: lastSaveDateKey) as? Date {
            lastSaveDate = lastDate
            
            // Check if it's a new day
            if !Calendar.current.isDateInToday(lastDate) {
                resetDailyUsage()
                return
            }
        }
        
        // Load today's usage
        todayUsageMinutes = UserDefaults.standard.integer(forKey: usageKey)
        
        dlog("📊 AppUsageTracker: Loaded usage data - \(todayUsageMinutes) minutes used, \(dailyLimitMinutes) limit")
    }
    
    private func saveUsageData() {
        // Capture values before leaving MainActor
        let minutesSnapshot = todayUsageMinutes
        let now = Date()
        lastSaveDate = now
        // Write to UserDefaults on a background queue — synchronous I/O must not block the main thread
        Task.detached(priority: .utility) {
            UserDefaults.standard.set(minutesSnapshot, forKey: self.usageKey)
            UserDefaults.standard.set(now, forKey: self.lastSaveDateKey)
        }
    }
    
    deinit {
        timer?.invalidate()
        smartBreakTask?.cancel()
    }
}

// MARK: - Daily Limit Dialog View
//
//  Redesign (2026-06-22): clean WHITE Liquid Glass on a near-white ambient
//  background. Replaces the dark native `.prominent` glass with a bright
//  frosted-white surface (`selahWhiteGlass`) and layers in the ambient-motion
//  set that fits a modal break screen:
//    • Adaptive blur header  — top frost condenses + title collapses on scroll
//    • Living background     — very slow drifting warm/cool glows (20s+)
//    • Card light sweep      — periodic gloss reflection across each glass card
//    • Breathing CTA         — "Take a Break" pulses 1.00→1.02 every ~4.5s
//    • AI-orb motion         — the "+" fab traces a sub-pixel orbit
//    • Dynamic-Island toast  — limit changes drop a small glass toast from top
//    • Smart haptics         — distinct feedback per action class
//  Smarter + personal: time-aware greeting, context-chosen verse, and copy
//  that adapts to how far past the goal the moment is.
//  Every ambient loop is gated on Reduce Motion; every glass surface has a
//  solid Reduce Transparency fallback.

struct DailyLimitReachedDialog: View {
    @EnvironmentObject var tracker: AppUsageTracker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appear = false
    @State private var ringProgress = 0.0
    @State private var isBreakStarting = false
    @State private var showContinueConfirmation = false

    // Scroll-driven adaptive header (Adaptive Blur Header + Hero Collapse).
    @State private var scrollY: CGFloat = 0
    // Scroll velocity (pts/update) for tab tuck + velocity blur. Decays to 0 on stop.
    @State private var lastScrollY: CGFloat = 0
    @State private var scrollVelocity: CGFloat = 0
    @State private var velocityToken = 0
    // Living-background drift phase + slow ambient hero zoom (1.00 → 1.03).
    @State private var ambientPhase: CGFloat = 0
    @State private var heroZoom: CGFloat = 1.0
    // Dynamic-Island-style in-screen toast.
    @State private var toast: SelahToast?
    @State private var toastToken = 0

    private struct SelahToast: Equatable {
        let icon: String
        let text: String
    }

    private struct VerseMoment {
        let text: String
        let reference: String
    }

    private var displayedUsageMinutes: Int {
        max(tracker.snapshotUsageMinutes, tracker.todayUsageMinutes)
    }

    private var overGoalMinutes: Int {
        max(0, displayedUsageMinutes - tracker.dailyLimitMinutes)
    }

    private var usageFraction: Double {
        guard tracker.dailyLimitMinutes > 0 else { return 0 }
        return min(1.0, Double(displayedUsageMinutes) / Double(tracker.dailyLimitMinutes))
    }

    // MARK: Personalization

    /// 0 = at/under goal, climbs as the moment runs further past it. Used to pick
    /// copy + verse so the screen feels responsive to the actual moment.
    private var overageSeverity: Double {
        guard tracker.dailyLimitMinutes > 0 else { return 0 }
        return Double(overGoalMinutes) / Double(tracker.dailyLimitMinutes)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "A quiet night"
        }
    }

    /// Verse chosen for the moment: rest-themed when well over goal, otherwise
    /// time-of-day appropriate. Calm, never guilt-laden.
    private var verse: VerseMoment {
        if overageSeverity >= 1.0 {
            return VerseMoment(text: "Come to me, all who are weary, and I will give you rest.",
                               reference: "MATTHEW 11:28")
        }
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:
            return VerseMoment(text: "This is the day the Lord has made; rejoice in it.",
                               reference: "PSALM 118:24")
        case 12..<17:
            return VerseMoment(text: "Be still, and know that I am God.",
                               reference: "PSALM 46:10")
        case 17..<22:
            return VerseMoment(text: "In peace I will lie down and sleep, for you alone keep me safe.",
                               reference: "PSALM 4:8")
        default:
            return VerseMoment(text: "It is in vain that you rise early and stay up late — he gives rest to those he loves.",
                               reference: "PSALM 127:2")
        }
    }

    var body: some View {
        ZStack {
            background

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    // Scroll probe — reports content offset in the named space.
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: SelahScrollOffsetKey.self,
                            value: geo.frame(in: .named("selahScroll")).minY
                        )
                    }
                    .frame(height: 0)

                    heroCard
                        .padding(.top, 56)
                        .offset(y: appear ? 0 : 24)
                        .scaleEffect(appear ? 1 : 0.97, anchor: .top)
                        .blur(radius: appear ? 0 : 8)
                        .opacity(appear ? 1 : 0)

                    milestoneCard
                        .offset(y: appear ? 0 : 22)
                        .opacity(appear ? 1 : 0)

                    scriptureCard
                        .offset(y: appear ? 0 : 24)
                        .blur(radius: appear ? 0 : 8)
                        .opacity(appear ? 1 : 0)

                    reflectionCard
                        .offset(y: appear ? 0 : 26)
                        .opacity(appear ? 1 : 0)

                    rhythmCard
                        .offset(y: appear ? 0 : 26)
                        .opacity(appear ? 1 : 0)

                    dailyLimitControl
                        .offset(y: appear ? 0 : 22)
                        .opacity(appear ? 1 : 0)

                    snoozeSection
                        .offset(y: appear ? 0 : 18)
                        .opacity(appear ? 1 : 0)

                    continueAnywayButton
                        .padding(.top, 2)
                        .offset(y: appear ? 0 : 16)
                        .opacity(appear ? 1 : 0)

                    Spacer(minLength: 48)
                }
                .padding(.horizontal, 18)
                .blur(radius: velocityBlur)
            }
            .coordinateSpace(name: "selahScroll")
            .onPreferenceChange(SelahScrollOffsetKey.self) { value in
                let delta = value - lastScrollY
                lastScrollY = value
                if abs(value - scrollY) >= 0.5 { scrollY = value }
                // Velocity (Velocity Blur). Debounced reset so the effect is
                // "removed instantly after stop."
                scrollVelocity = delta
                velocityToken += 1
                let token = velocityToken
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                    guard token == velocityToken else { return }
                    withAnimation(.easeOut(duration: 0.28)) { scrollVelocity = 0 }
                }
            }
            // Adaptive blur header — frost condenses at the top edge on scroll.
            .scrollEdgeTopBlur(scrollOffset: scrollY, panelHeight: 104, rampDistance: 72)

            // Pinned compact title that fades in as the hero header collapses.
            compactHeader
                .frame(maxHeight: .infinity, alignment: .top)

            // Close affordance — dismisses the break screen (top-trailing).
            closeButton
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            // Dynamic-Island-style toast.
            toastOverlay
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showContinueConfirmation) {
            continueConfirmationSheet
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            withAnimation(.spring(response: 0.62, dampingFraction: 0.82).delay(0.04)) {
                appear = true
            }
            withAnimation(.spring(response: 0.95, dampingFraction: 0.82).delay(0.18)) {
                ringProgress = usageFraction
            }
            startAmbientMotion()
        }
        .onChange(of: usageFraction) { _, newValue in
            withAnimation(.spring(response: 0.75, dampingFraction: 0.78)) {
                ringProgress = newValue
            }
        }
    }

    /// 0 (header expanded) → 1 (collapsed) as the user scrolls the content up.
    private var headerCollapse: CGFloat {
        min(1, max(0, -scrollY / 70))
    }

    /// Velocity Blur — a whisper of directional blur during fast scroll, capped low
    /// so the screen stays calm. Cleared the instant scrolling stops.
    private var velocityBlur: CGFloat {
        guard !reduceMotion else { return 0 }
        return min(1.8, abs(scrollVelocity) * 0.05)
    }

    /// Parallax shift for the hero scene as the content scrolls (Parallax Hero Depth).
    private func parallax(_ factor: CGFloat) -> CGFloat {
        guard !reduceMotion else { return 0 }
        return max(-26, min(26, scrollY * factor))
    }

    private func startAmbientMotion() {
        guard !reduceMotion else { return }
        // Living background — a long, barely-perceptible drift.
        withAnimation(.easeInOut(duration: 22).repeatForever(autoreverses: true)) {
            ambientPhase = 1
        }
        // Ambient hero zoom — 1.00 → 1.03 over 20s, almost invisible.
        withAnimation(.easeInOut(duration: 20).repeatForever(autoreverses: true)) {
            heroZoom = 1.03
        }
    }

    /// Begins a Selah break: dismisses the modal and gently suspends the app so
    /// the user can step away. Shared by the hero pill and the confirmation sheet.
    private func beginBreak() {
        isBreakStarting = true
        haptic(.takeBreak)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            tracker.showLimitReachedDialog = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if UIApplication.shared.connectedScenes.first is UIWindowScene {
                UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
            }
        }
    }

    /// Distinct haptic per action class (Smart Haptics).
    private func haptic(_ kind: SelahHaptic) {
        switch kind {
        case .adjust:   UISelectionFeedbackGenerator().selectionChanged()
        case .snooze:   UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .takeBreak: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .reflect:  UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }

    private enum SelahHaptic { case adjust, snooze, takeBreak, reflect }

    private func presentToast(_ icon: String, _ text: String) {
        toastToken += 1
        let token = toastToken
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            toast = SelahToast(icon: icon, text: text)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) {
            guard token == toastToken else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                toast = nil
            }
        }
    }

    // MARK: Background (Living, near-white)

    private var background: some View {
        ZStack {
            // Clean white base with the faintest warm floor.
            LinearGradient(
                colors: [
                    Color.white,
                    Color(red: 0.995, green: 0.985, blue: 0.965),
                    Color.white
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Warm glow — drifts slowly down/across.
            RadialGradient(
                colors: [Color(red: 1.00, green: 0.86, blue: 0.42).opacity(0.16), .clear],
                center: .top,
                startRadius: 40,
                endRadius: 440
            )
            .offset(y: ambientPhase * 36 - 18)
            .opacity(0.85 + Double(ambientPhase) * 0.15)
            .ignoresSafeArea()

            // Cool counter-glow — drifts the opposite way.
            RadialGradient(
                colors: [Color(red: 0.63, green: 0.80, blue: 1.00).opacity(0.10), .clear],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 380
            )
            .offset(x: ambientPhase * -28 + 14, y: ambientPhase * -24 + 12)
            .ignoresSafeArea()
        }
    }

    // MARK: Headers

    // MARK: Mood system (time-aware hero palette)

    private enum SelahMood {
        case morning, afternoon, evening, night

        /// Vertical sky gradient for the hero scene.
        var skyColors: [Color] {
            switch self {
            case .morning:
                return [Color(red: 1.00, green: 0.90, blue: 0.76),
                        Color(red: 1.00, green: 0.84, blue: 0.58),
                        Color(red: 0.97, green: 0.74, blue: 0.50)]
            case .afternoon:
                return [Color(red: 0.74, green: 0.86, blue: 1.00),
                        Color(red: 0.83, green: 0.91, blue: 1.00),
                        Color(red: 0.70, green: 0.82, blue: 0.97)]
            case .evening:
                return [Color(red: 1.00, green: 0.70, blue: 0.48),
                        Color(red: 0.91, green: 0.55, blue: 0.55),
                        Color(red: 0.43, green: 0.36, blue: 0.62)]
            case .night:
                return [Color(red: 0.07, green: 0.10, blue: 0.22),
                        Color(red: 0.10, green: 0.15, blue: 0.31),
                        Color(red: 0.14, green: 0.21, blue: 0.40)]
            }
        }

        /// Soft "sun"/moon glow tint.
        var glowColor: Color {
            switch self {
            case .morning:   return Color(red: 1.00, green: 0.93, blue: 0.66)
            case .afternoon: return Color.white
            case .evening:   return Color(red: 1.00, green: 0.78, blue: 0.52)
            case .night:     return Color(red: 0.55, green: 0.66, blue: 1.00)
            }
        }

        var glowCenter: UnitPoint {
            switch self {
            case .morning:   return UnitPoint(x: 0.78, y: 0.30)
            case .afternoon: return UnitPoint(x: 0.50, y: 0.18)
            case .evening:   return UnitPoint(x: 0.24, y: 0.34)
            case .night:     return UnitPoint(x: 0.74, y: 0.26)
            }
        }

        /// Lower horizon band tint.
        var horizonColor: Color {
            switch self {
            case .morning:   return Color(red: 0.93, green: 0.66, blue: 0.40)
            case .afternoon: return Color(red: 0.62, green: 0.76, blue: 0.92)
            case .evening:   return Color(red: 0.33, green: 0.26, blue: 0.47)
            case .night:     return Color(red: 0.04, green: 0.06, blue: 0.16)
            }
        }
    }

    private var mood: SelahMood {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return .morning
        case 12..<17: return .afternoon
        case 17..<21: return .evening
        default:      return .night
        }
    }

    // MARK: Hero (large editorial, mood-aware scene)

    private var heroCard: some View {
        ZStack {
            heroScene
                .scaleEffect(reduceMotion ? 1 : heroZoom)
                .offset(y: parallax(0.06))

            // Legibility scrim under the editorial text.
            LinearGradient(
                colors: [.clear, .black.opacity(0.06), .black.opacity(0.38)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(greeting)
                            .font(.systemScaled(12, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(.white.opacity(0.88))
                        Text("Selah Break")
                            .font(.systemScaled(30, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("\(displayedUsageMinutes) minutes today")
                            .font(.systemScaled(14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.84))
                        Text("Your soul deserves rest more than the feed.")
                            .font(.systemScaled(13, weight: .regular))
                            .foregroundStyle(.white.opacity(0.74))
                            .padding(.top, 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                    Spacer(minLength: 8)
                }
                .padding(20)
            }
        }
        .frame(height: 380)
        .clipShape(RoundedRectangle(cornerRadius: 38, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            heroTakeBreakPill
                .padding(20)
        }
        .overlay(
            // Glass edge treatment — soft internal highlight + hairline.
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .stroke(
                    LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.12)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
        )
        .selahLightSweep(cornerRadius: 38, delay: 0.6)
        .shadow(color: .black.opacity(0.12), radius: 40, y: 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(greeting). Selah Break. \(displayedUsageMinutes) minutes today. Your soul deserves rest more than the feed.")
    }

    private var heroScene: some View {
        let m = mood
        return ZStack {
            LinearGradient(colors: m.skyColors, startPoint: .top, endPoint: .bottom)

            RadialGradient(colors: [m.glowColor.opacity(0.85), .clear],
                           center: m.glowCenter, startRadius: 6, endRadius: 280)
                .offset(y: ambientPhase * 12 - 6)
                .opacity(0.85 + Double(ambientPhase) * 0.15)

            // Distant horizon band grounds the scene.
            VStack {
                Spacer()
                LinearGradient(colors: [.clear, m.horizonColor.opacity(0.6)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 168)
            }
        }
    }

    /// Floating glass "Take Break" pill — black translucent material, VisionOS style.
    private var heroTakeBreakPill: some View {
        Button {
            beginBreak()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isBreakStarting ? "pause.fill" : "hands.sparkles.fill")
                    .font(.systemScaled(14, weight: .semibold))
                Text(isBreakStarting ? "Starting" : "Take Break")
                    .font(.systemScaled(15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                    Capsule().fill(.black.opacity(0.34))
                    Capsule().stroke(.white.opacity(0.22), lineWidth: 1)
                }
            )
            .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
        }
        .buttonStyle(SelahPressButtonStyle())
        .selahBreathing()
        .accessibilityLabel("Take a break")
        .accessibilityHint("Closes AMEN so you can step away for prayer or rest")
    }

    private var compactHeader: some View {
        Text("Selah Break")
            .font(.systemScaled(16, weight: .semibold, design: .rounded))
            .foregroundStyle(.black.opacity(0.82))
            .padding(.top, 60)
            .opacity(Double(headerCollapse))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var toastOverlay: some View {
        VStack {
            if let toast {
                HStack(spacing: 9) {
                    Image(systemName: toast.icon)
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(Color(red: 0.62, green: 0.46, blue: 0.12))
                    Text(toast.text)
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.80))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .selahWhiteGlass(cornerRadius: 22, tint: Color(red: 1.0, green: 0.97, blue: 0.88))
                .shadow(color: .black.opacity(0.10), radius: 16, y: 8)
                .padding(.top, 58)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityLabel(toast.text)
            }
        }
    }

    // MARK: Milestone (replaces the giant progress ring)

    private var milestoneCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("TODAY")
                        .font(.systemScaled(10, weight: .semibold))
                        .tracking(1.6)
                        .foregroundStyle(.black.opacity(0.40))
                    Text("\(displayedUsageMinutes) min")
                        .font(.systemScaled(32, weight: .medium, design: .rounded))
                        .foregroundStyle(.black.opacity(0.86))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }

                Spacer(minLength: 8)

                Text(milestoneSubtitle)
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(milestoneTint)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(milestoneTint.opacity(0.14)))
            }

            progressBar
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .selahWhiteGlass(cornerRadius: 30)
        .selahLightSweep(cornerRadius: 30, delay: 1.2)
        .shadow(color: .black.opacity(0.07), radius: 30, y: 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today, \(displayedUsageMinutes) minutes. \(milestoneSubtitle).")
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.06))
                Capsule()
                    .fill(
                        LinearGradient(colors: milestoneBarColors,
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: max(12, geo.size.width * CGFloat(min(1, ringProgress))))
            }
        }
        .frame(height: 10)
    }

    private var milestoneSubtitle: String {
        if overGoalMinutes > 0 {
            return "\(overGoalMinutes) min above goal"
        }
        let toGoal = max(0, tracker.dailyLimitMinutes - displayedUsageMinutes)
        return toGoal == 0 ? "At your goal" : "\(toGoal) min to goal"
    }

    private var milestoneTint: Color {
        overGoalMinutes > 0
            ? Color(red: 0.78, green: 0.52, blue: 0.10)
            : Color(red: 0.30, green: 0.56, blue: 0.36)
    }

    private var milestoneBarColors: [Color] {
        overGoalMinutes > 0
            ? [Color(red: 0.98, green: 0.81, blue: 0.31), Color(red: 0.90, green: 0.58, blue: 0.16)]
            : [Color(red: 0.55, green: 0.80, blue: 0.60), Color(red: 0.34, green: 0.64, blue: 0.42)]
    }

    // MARK: Scripture (premium quote card)

    private var scriptureCard: some View {
        VStack(spacing: 12) {
            Text("\u{201C}\(verse.text)\u{201D}")
                .font(.systemScaled(21, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(.black.opacity(0.78))
                .multilineTextAlignment(.center)
                .lineSpacing(6)
            Text(verse.reference)
                .font(.systemScaled(11, weight: .semibold))
                .tracking(2.0)
                .foregroundStyle(.black.opacity(0.36))
        }
        .padding(.vertical, 36)
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity)
        .selahWhiteGlass(cornerRadius: 34)
        .selahLightSweep(cornerRadius: 34, delay: 2.0)
        .shadow(color: .black.opacity(0.06), radius: 30, y: 14)
        .id(verse.reference)
        .transition(.opacity)
    }

    // MARK: Reflection (Apple Journal style — invitation, not warning)

    private var reflectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "leaf.fill")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.36, green: 0.62, blue: 0.40))
                Text("Reflection")
                    .font(.systemScaled(13, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(.black.opacity(0.50))
            }

            Text(reflectionBody)
                .font(.systemScaled(17, weight: .regular))
                .foregroundStyle(.black.opacity(0.74))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ForEach(["Walk", "Pray", "Breathe", "Reflect"], id: \.self) { word in
                    Text(word)
                        .font(.systemScaled(13, weight: .medium))
                        .foregroundStyle(.black.opacity(0.58))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.black.opacity(0.045)))
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .selahWhiteGlass(cornerRadius: 34)
        .shadow(color: .black.opacity(0.06), radius: 30, y: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reflection. \(reflectionBody)")
    }

    private var reflectionBody: String {
        if overageSeverity >= 1.0 {
            return "You've spent more time than usual today. Take five quiet minutes to step away and let your pace settle."
        }
        if overGoalMinutes > 0 {
            return "You're a little past your rhythm. A short pause now keeps the rest of your day unhurried."
        }
        return "You're moving gently today. A brief Selah keeps your heart present and your pace your own."
    }

    // MARK: Today's Rhythm (minimal, honest day timeline — no charts)

    private struct RhythmSegment {
        let label: String
        let fill: CGFloat
        let isCurrent: Bool
    }

    private var rhythmSegments: [RhythmSegment] {
        let hour = Calendar.current.component(.hour, from: Date())
        func segment(_ label: String, start: Int, end: Int) -> RhythmSegment {
            let span = CGFloat(end - start)
            let fill: CGFloat
            if hour >= end { fill = 1.0 }
            else if hour < start { fill = 0.08 }
            else { fill = max(0.12, min(1.0, CGFloat(hour - start) / span)) }
            return RhythmSegment(label: label, fill: fill, isCurrent: hour >= start && hour < end)
        }
        return [
            segment("Morning", start: 5, end: 12),
            segment("Afternoon", start: 12, end: 17),
            segment("Evening", start: 17, end: 24)
        ]
    }

    private var rhythmCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Today\u{2019}s Rhythm")
                .font(.systemScaled(13, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(.black.opacity(0.50))

            ForEach(rhythmSegments, id: \.label) { seg in
                VStack(alignment: .leading, spacing: 7) {
                    Text(seg.label)
                        .font(.systemScaled(12, weight: .medium))
                        .foregroundStyle(seg.isCurrent ? .black.opacity(0.80) : .black.opacity(0.44))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.black.opacity(0.05))
                            Capsule()
                                .fill(rhythmFill(seg.isCurrent))
                                .frame(width: max(8, geo.size.width * seg.fill))
                        }
                    }
                    .frame(height: 8)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(seg.label)\(seg.isCurrent ? ", current" : "")")
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .selahWhiteGlass(cornerRadius: 34)
        .shadow(color: .black.opacity(0.06), radius: 30, y: 14)
    }

    private func rhythmFill(_ isCurrent: Bool) -> AnyShapeStyle {
        if isCurrent {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color(red: 0.98, green: 0.81, blue: 0.31), Color(red: 0.90, green: 0.62, blue: 0.16)],
                    startPoint: .leading, endPoint: .trailing
                )
            )
        }
        return AnyShapeStyle(Color.black.opacity(0.16))
    }

    private var dailyLimitControl: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Daily Limit")
                    .font(.systemScaled(11, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(.black.opacity(0.42))
                Text("\(tracker.dailyLimitMinutes) min")
                    .font(.systemScaled(22, weight: .medium, design: .rounded))
                    .foregroundStyle(.black.opacity(0.86))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Daily limit, \(tracker.dailyLimitMinutes) minutes")

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                limitButton(systemName: "minus", label: "Decrease daily limit") {
                    let newValue = max(15, tracker.dailyLimitMinutes - 15)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        tracker.updateDailyLimit(newValue)
                    }
                    presentToast("timer", "Daily limit · \(newValue) min")
                }

                limitButton(systemName: "plus", label: "Increase daily limit") {
                    let newValue = min(240, tracker.dailyLimitMinutes + 15)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        tracker.updateDailyLimit(newValue)
                    }
                    presentToast("timer", "Daily limit · \(newValue) min")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                )
        )
    }

    private func limitButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            haptic(.adjust)
        } label: {
            Image(systemName: systemName)
                .font(.systemScaled(15, weight: .semibold))
                .foregroundStyle(Color(red: 0.14, green: 0.48, blue: 0.87))
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.78))
                        .overlay(Circle().stroke(Color.black.opacity(0.06), lineWidth: 1))
                )
        }
        .buttonStyle(SelahPressButtonStyle())
        .accessibilityLabel(label)
    }

    private var snoozeSection: some View {
        VStack(spacing: 10) {
            Text("Snooze Reminder")
                .font(.systemScaled(11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.black.opacity(0.35))

            HStack(spacing: 10) {
                ForEach([15, 30, 60], id: \.self) { minutes in
                    Button {
                        haptic(.snooze)
                        tracker.snooze(minutes: minutes)
                    } label: {
                        Text(minutes == 60 ? "1 hour" : "\(minutes) min")
                            .font(.systemScaled(15, weight: .semibold))
                            .foregroundStyle(Color(red: 0.15, green: 0.50, blue: 0.90))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .padding(.horizontal, 8)
                            .selahWhiteGlass(cornerRadius: 24, capsule: true)
                            .shadow(color: .black.opacity(0.045), radius: 10, y: 4)
                    }
                    .buttonStyle(SelahPressButtonStyle())
                    .accessibilityLabel("Snooze reminder for \(minutes == 60 ? "1 hour" : "\(minutes) minutes")")
                }
            }
        }
    }

    private var continueAnywayButton: some View {
        Button {
            showContinueConfirmation = true
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } label: {
            Text("Continue Anyway")
                .font(.systemScaled(15, weight: .semibold))
                .foregroundStyle(.black.opacity(0.58))
                .frame(maxWidth: .infinity, minHeight: 52)
                .selahWhiteGlass(cornerRadius: 26, capsule: true)
                .shadow(color: .black.opacity(0.05), radius: 12, y: 5)
        }
        .buttonStyle(SelahPressButtonStyle())
        .accessibilityLabel("Continue anyway")
        .accessibilityHint("Shows a confirmation before continuing without a break")
    }

    /// Small frosted close control, top-trailing. Dismisses the break screen.
    private var closeButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                tracker.showLimitReachedDialog = false
            }
        } label: {
            Image(systemName: "xmark")
                .font(.systemScaled(14, weight: .semibold))
                .foregroundStyle(.black.opacity(0.55))
                .frame(width: 38, height: 38)
                .selahWhiteGlass(cornerRadius: 19, capsule: true)
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        }
        .buttonStyle(SelahPressButtonStyle())
        .padding(.top, 56)
        .padding(.trailing, 18)
        .accessibilityLabel("Close")
    }

    private var continueConfirmationSheet: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(Color.black.opacity(0.10))
                .frame(width: 42, height: 5)
                .padding(.top, 6)

            Image(systemName: "hand.raised.fill")
                .font(.systemScaled(28, weight: .medium))
                .foregroundStyle(Color(red: 0.77, green: 0.53, blue: 0.12))
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color(red: 1.00, green: 0.91, blue: 0.62).opacity(0.34)))

            VStack(spacing: 8) {
                Text("Continue with intention?")
                    .font(.systemScaled(22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.88))
                Text("A short Selah Break can help you return with prayer, presence, and a clearer pace.")
                    .font(.systemScaled(15, weight: .regular))
                    .foregroundStyle(.black.opacity(0.58))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            HStack(spacing: 12) {
                Button("Take a Break") {
                    showContinueConfirmation = false
                    isBreakStarting = true
                    haptic(.takeBreak)
                    tracker.showLimitReachedDialog = false
                }
                .font(.systemScaled(16, weight: .semibold))
                .foregroundStyle(.black.opacity(0.86))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Capsule().fill(Color(red: 1.00, green: 0.90, blue: 0.56).opacity(0.58)))

                Button("Continue") {
                    showContinueConfirmation = false
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        tracker.showLimitReachedDialog = false
                    }
                }
                .font(.systemScaled(16, weight: .semibold))
                .foregroundStyle(.black.opacity(0.54))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Capsule().fill(Color.black.opacity(0.055)))
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 22)
        .background(Color.white)
    }
}

// MARK: - Selah Glass Motion Primitives
//
// File-local helpers backing the redesigned Selah Break screen. Kept here (not
// in a new file) per the repo's synced-folder rule — new top-level files don't
// reliably join the target. Each is Reduce-Motion / Reduce-Transparency aware.

/// Tracks the Selah Break ScrollView's content offset for the adaptive header.
private struct SelahScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Bright, frosted WHITE Liquid Glass surface — the redesign's core material.
/// Falls back to a solid near-white fill when Reduce Transparency is on.
private struct SelahWhiteGlass: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color
    var capsule: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background { surface }
            .overlay { strokeOverlay }
    }

    @ViewBuilder private var surface: some View {
        if reduceTransparency {
            shapedFill(colorScheme == .dark ? Color(white: 0.16) : Color.white)
        } else {
            ZStack {
                shapedMaterial
                shapedFill(tint.opacity(colorScheme == .dark ? 0.06 : 0.55))
                // Top gloss — the bright highlight that reads as glass.
                shape.fill(
                    LinearGradient(
                        colors: [.white.opacity(colorScheme == .dark ? 0.10 : 0.45), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            }
        }
    }

    private var strokeOverlay: some View {
        shape.stroke(
            LinearGradient(
                colors: [.white.opacity(0.85), .white.opacity(0.28)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            lineWidth: 1
        )
    }

    @ViewBuilder private var shapedMaterial: some View {
        if capsule { Capsule().fill(.ultraThinMaterial) }
        else { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(.ultraThinMaterial) }
    }

    private func shapedFill(_ color: Color) -> some View {
        Group {
            if capsule { Capsule().fill(color) }
            else { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(color) }
        }
    }

    private var shape: AnyShape {
        capsule ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Periodic diagonal gloss that sweeps across a glass card (Card Edge Reflection).
private struct SelahLightSweep: ViewModifier {
    var cornerRadius: CGFloat
    var delay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1.4

    func body(content: Content) -> some View {
        content.overlay {
            if !reduceMotion {
                GeometryReader { geo in
                    let w = geo.size.width
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.0), .white.opacity(0.30), .white.opacity(0.0), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: w * 0.55)
                    .rotationEffect(.degrees(18))
                    .offset(x: phase * w * 1.6)
                    .blendMode(.plusLighter)
                    .mask(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .allowsHitTesting(false)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 5.5).repeatForever(autoreverses: false).delay(delay)) {
                        phase = 1.4
                    }
                }
            }
        }
    }
}

/// Almost-imperceptible breathing scale for a primary CTA (1.00 → 1.02).
private struct SelahBreathing: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) {
                    scale = 1.02
                }
            }
    }
}

private extension View {
    func selahWhiteGlass(cornerRadius: CGFloat = 34, tint: Color = .white, capsule: Bool = false) -> some View {
        modifier(SelahWhiteGlass(cornerRadius: cornerRadius, tint: tint, capsule: capsule))
    }

    func selahLightSweep(cornerRadius: CGFloat, delay: Double = 0) -> some View {
        modifier(SelahLightSweep(cornerRadius: cornerRadius, delay: delay))
    }

    func selahBreathing() -> some View {
        modifier(SelahBreathing())
    }
}

private struct SelahPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1.0)
            .opacity(configuration.isPressed ? 0.82 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

/// Magnetic Button — the primary CTA grows toward the finger on touch (attraction)
/// and deepens its shadow, rather than shrinking. The closest touch-only analogue
/// to pointer-proximity magnetism on iPhone.
private struct SelahMagneticButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.035 : 1.0)
            .shadow(
                color: Color(red: 0.95, green: 0.72, blue: 0.20).opacity(configuration.isPressed ? 0.34 : 0.0),
                radius: configuration.isPressed ? 22 : 0,
                y: configuration.isPressed ? 10 : 0
            )
            .animation(.spring(response: 0.28, dampingFraction: 0.62), value: configuration.isPressed)
    }
}
