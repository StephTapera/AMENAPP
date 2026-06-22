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
    // Living-background drift phase + AI-orb orbit phase.
    @State private var ambientPhase: CGFloat = 0
    @State private var orbPhase: CGFloat = 0
    // Dynamic-Island-style in-screen toast.
    @State private var toast: SelahToast?
    @State private var toastToken = 0

    private enum BreakPresentationState {
        case underLimit
        case overLimit(minutes: Int)
        case snoozed(until: Date)
        case breakStarted
        case confirmingContinue
    }

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

    private var overageFraction: Double {
        guard tracker.dailyLimitMinutes > 0 else { return 0 }
        return min(0.74, Double(overGoalMinutes) / Double(tracker.dailyLimitMinutes))
    }

    private var presentationState: BreakPresentationState {
        if isBreakStarting { return .breakStarted }
        if showContinueConfirmation { return .confirmingContinue }
        if let snoozeUntil = tracker.snoozeUntil, Date() < snoozeUntil { return .snoozed(until: snoozeUntil) }
        if overGoalMinutes > 0 { return .overLimit(minutes: overGoalMinutes) }
        return .underLimit
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

    private var statusChipText: String {
        switch presentationState {
        case .underLimit:
            return "Within today's rhythm"
        case .overLimit(let minutes):
            return "Over goal by \(minutes) min"
        case .snoozed(let until):
            return "Snoozed until \(until.formatted(date: .omitted, time: .shortened))"
        case .breakStarted:
            return "Break started"
        case .confirmingContinue:
            return "Choose with intention"
        }
    }

    private var subtitleText: String {
        if overGoalMinutes == 0 {
            return "You're moving gently — \(displayedUsageMinutes) of \(tracker.dailyLimitMinutes) min today."
        }
        if overageSeverity >= 1.0 {
            return "You've spent \(displayedUsageMinutes) min here today. Your soul deserves rest more than the feed."
        }
        if overGoalMinutes <= 15 {
            return "Just past your \(tracker.dailyLimitMinutes)-min goal. A short pause keeps your rhythm."
        }
        return "You're \(overGoalMinutes) min over your \(tracker.dailyLimitMinutes)-min goal today. Selah — let's breathe."
    }

    /// True when the moment warrants a gentle, non-judgmental nudge toward rest.
    private var showsGentleSuggestion: Bool { overageSeverity >= 0.66 }

    var body: some View {
        ZStack {
            background

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    // Scroll probe — reports content offset in the named space.
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: SelahScrollOffsetKey.self,
                            value: geo.frame(in: .named("selahScroll")).minY
                        )
                    }
                    .frame(height: 0)

                    header
                        .padding(.top, 64)
                        .scaleEffect(1 - 0.14 * headerCollapse, anchor: .top)
                        .opacity((appear ? 1 : 0) * Double(1 - headerCollapse))
                        .offset(y: appear ? 0 : 18)

                    heroUsageCard
                        .offset(y: appear ? 0 : 24)
                        .scaleEffect(appear ? 1 : 0.96)
                        .blur(radius: appear ? 0 : 8)
                        .opacity(appear ? 1 : 0)

                    mainBreakCard
                        .offset(y: appear ? 0 : 28)
                        .scaleEffect(appear ? 1 : 0.97)
                        .blur(radius: appear ? 0 : 10)
                        .opacity(appear ? 1 : 0)

                    snoozeSection
                        .offset(y: appear ? 0 : 18)
                        .opacity(appear ? 1 : 0)

                    Spacer(minLength: 118)
                }
                .padding(.horizontal, 18)
                .blur(radius: velocityBlur)
            }
            .coordinateSpace(name: "selahScroll")
            .onPreferenceChange(SelahScrollOffsetKey.self) { value in
                let delta = value - lastScrollY
                lastScrollY = value
                if abs(value - scrollY) >= 0.5 { scrollY = value }
                // Velocity (Velocity Blur + Floating Tuck). Debounced reset so the
                // effect is "removed instantly after stop."
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

            // Dynamic-Island-style toast.
            toastOverlay
                .frame(maxHeight: .infinity, alignment: .top)

            continueAnywayPinnedButton
                .padding(.horizontal, 48)
                .padding(.bottom, 92)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .offset(y: appear ? 0 : 18)
                .opacity(appear ? 1 : 0)

            floatingTabBar
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .offset(y: appear ? 0 : 30)
                .opacity(appear ? 1 : 0)
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

    /// 0 (tab bar expanded) → 1 (compressed) — slightly slower ramp than the header.
    private var tabCollapse: CGFloat {
        min(1, max(0, -scrollY / 110))
    }

    /// Floating Tuck: the bar drops away on a fast downward flick, returns when slow.
    private var tabTuckOffset: CGFloat {
        guard !reduceMotion else { return 0 }
        // scrollVelocity < 0 == content moving up == scrolling down.
        return scrollVelocity < -10 ? 46 : 0
    }

    /// Velocity Blur — a whisper of directional blur during fast scroll, capped low
    /// so the screen stays calm. Cleared the instant scrolling stops.
    private var velocityBlur: CGFloat {
        guard !reduceMotion else { return 0 }
        return min(1.8, abs(scrollVelocity) * 0.05)
    }

    /// Sub-pixel parallax shift for inner hero layers (Parallax Hero Depth).
    private func parallax(_ factor: CGFloat) -> CGFloat {
        guard !reduceMotion else { return 0 }
        return max(-8, min(8, scrollY * factor))
    }

    private func startAmbientMotion() {
        guard !reduceMotion else { return }
        // Living background — a long, barely-perceptible drift.
        withAnimation(.easeInOut(duration: 22).repeatForever(autoreverses: true)) {
            ambientPhase = 1
        }
        // AI-orb orbit on the "+" fab.
        withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
            orbPhase = 1
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

    private var header: some View {
        VStack(spacing: 7) {
            Text(greeting)
                .font(.systemScaled(11, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Color(red: 0.62, green: 0.46, blue: 0.12).opacity(0.85))
            Text("Selah Break")
                .font(.systemScaled(22, weight: .semibold, design: .rounded))
                .foregroundStyle(.black.opacity(0.86))
            Text("A gentle pause before continuing.")
                .font(.systemScaled(13, weight: .regular))
                .foregroundStyle(.black.opacity(0.46))

            contextTags
                .padding(.top, 4)
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(greeting). Selah Break. A gentle pause before continuing.")
    }

    /// Dynamic Glass Tags — small frosted chips describing the moment. They tilt
    /// subtly with scroll velocity for a living, physical feel.
    private var contextTags: some View {
        HStack(spacing: 8) {
            contextTag(icon: "clock", text: rhythmTagText)
            contextTag(icon: overGoalMinutes > 0 ? "circle.bottomhalf.filled" : "leaf",
                       text: "\(displayedUsageMinutes) min")
        }
        .rotation3DEffect(
            .degrees(reduceMotion ? 0 : Double(max(-6, min(6, scrollVelocity * 0.18)))),
            axis: (x: 1, y: 0, z: 0),
            anchor: .top
        )
    }

    private var rhythmTagText: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return "Morning rhythm"
        case 12..<17: return "Midday rhythm"
        case 17..<22: return "Evening rhythm"
        default:      return "Night rhythm"
        }
    }

    private func contextTag(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.systemScaled(10, weight: .semibold))
            Text(text)
                .font(.systemScaled(11, weight: .semibold))
        }
        .foregroundStyle(Color(red: 0.50, green: 0.38, blue: 0.10).opacity(0.85))
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .selahWhiteGlass(cornerRadius: 14, tint: Color(red: 1.0, green: 0.97, blue: 0.88), capsule: true)
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

    private var heroUsageCard: some View {
        VStack(spacing: 16) {
            progressRing

            Text(statusChipText)
                .font(.systemScaled(12, weight: .semibold))
                .foregroundStyle(Color(red: 0.48, green: 0.32, blue: 0.05))
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(
                    Capsule()
                        .fill(Color(red: 1.00, green: 0.90, blue: 0.56).opacity(0.32))
                        .overlay(Capsule().stroke(Color(red: 0.83, green: 0.61, blue: 0.16).opacity(0.22), lineWidth: 1))
                )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
        .selahWhiteGlass(cornerRadius: 34)
        .selahLightSweep(cornerRadius: 34, delay: 0.5)
        .shadow(color: Color(red: 0.60, green: 0.45, blue: 0.14).opacity(0.10), radius: 30, y: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Daily usage, \(displayedUsageMinutes) minutes today, \(statusChipText)")
    }

    private var progressRing: some View {
        ZStack {
            // Background rings — the "far" parallax layer (moves less).
            Group {
                Circle()
                    .stroke(Color.black.opacity(0.055), lineWidth: 9)

                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.98, green: 0.81, blue: 0.21),
                                Color(red: 0.88, green: 0.62, blue: 0.13),
                                Color(red: 1.00, green: 0.91, blue: 0.52)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                if overageFraction > 0 {
                    Circle()
                        .trim(from: 0.06, to: 0.06 + min(0.82, overageFraction * 0.82))
                        .stroke(
                            Color(red: 0.88, green: 0.46, blue: 0.18).opacity(0.50),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-72))
                }
            }
            .offset(y: parallax(0.04))

            // Foreground readout — the "near" parallax layer (moves more).
            VStack(spacing: 3) {
                Text("\(displayedUsageMinutes)")
                    .font(.systemScaled(52, weight: .ultraLight, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.black.opacity(0.88))
                    .contentTransition(.numericText())
                Text("MIN TODAY")
                    .font(.systemScaled(11, weight: .medium))
                    .tracking(1.6)
                    .foregroundStyle(.black.opacity(0.44))
            }
            .padding(.horizontal, 18)
            .offset(y: parallax(-0.05))
        }
        .frame(width: 190, height: 190)
    }

    private var mainBreakCard: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Time for a Break")
                    .font(.systemScaled(28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.88))
                    .multilineTextAlignment(.center)

                Text(subtitleText)
                    .font(.systemScaled(15, weight: .regular))
                    .foregroundStyle(.black.opacity(0.56))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Divider().overlay(Color.black.opacity(0.06))

            VStack(spacing: 7) {
                Text("\"\(verse.text)\"")
                    .font(.systemScaled(15, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(.black.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                Text(verse.reference)
                    .font(.systemScaled(10, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(.black.opacity(0.34))
            }
            .padding(.horizontal, 8)
            .id(verse.reference)
            .transition(.opacity)

            if showsGentleSuggestion {
                gentleSuggestion
            }

            dailyLimitControl

            takeBreakButton
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .selahWhiteGlass(cornerRadius: 34)
        .selahLightSweep(cornerRadius: 34, delay: 2.4)
        .shadow(color: .black.opacity(0.07), radius: 34, y: 18)
    }

    private var gentleSuggestion: some View {
        HStack(spacing: 9) {
            Image(systemName: "leaf.fill")
                .font(.systemScaled(13, weight: .semibold))
                .foregroundStyle(Color(red: 0.36, green: 0.62, blue: 0.40))
            Text("You've gone well past today — even five quiet minutes can reset your pace.")
                .font(.systemScaled(13, weight: .regular))
                .foregroundStyle(.black.opacity(0.60))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.93, green: 0.97, blue: 0.93).opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color(red: 0.36, green: 0.62, blue: 0.40).opacity(0.18), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
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

    private var takeBreakButton: some View {
        Button {
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
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isBreakStarting ? "pause.fill" : "hands.sparkles.fill")
                    .font(.systemScaled(16, weight: .semibold))
                Text(isBreakStarting ? "Starting Break" : "Take a Break")
                    .font(.systemScaled(17, weight: .semibold))
            }
            .foregroundStyle(.black.opacity(0.86))
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.95), Color(red: 1.00, green: 0.94, blue: 0.68).opacity(0.78)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color(red: 0.95, green: 0.72, blue: 0.20).opacity(0.36), lineWidth: 1)
                    )
                    .shadow(color: Color(red: 0.95, green: 0.72, blue: 0.20).opacity(0.26), radius: 20, y: 8)
            )
        }
        .buttonStyle(SelahMagneticButtonStyle())
        .selahBreathing()
        .accessibilityLabel("Take a break")
        .accessibilityHint("Closes AMEN so you can step away for prayer or rest")
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

    private var continueAnywayPinnedButton: some View {
        Button {
            showContinueConfirmation = true
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } label: {
            Text("Continue Anyway")
                .font(.systemScaled(15, weight: .semibold))
                .foregroundStyle(.black.opacity(0.62))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.86))
                        .overlay(Capsule(style: .continuous).stroke(Color.black.opacity(0.08), lineWidth: 0.75))
                        .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
                )
        }
        .buttonStyle(SelahPressButtonStyle())
        .accessibilityLabel("Continue anyway")
        .accessibilityHint("Shows a confirmation before continuing without a break")
    }

    private var floatingTabBar: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .center, spacing: 0) {
                navItem(icon: "house", label: "Home", isSelected: false)
                navItem(icon: "magnifyingglass", label: "Search", isSelected: false)
                navItem(icon: "bubble.left.and.bubble.right.fill", label: "Messages", isSelected: true)
                    .padding(.top, 18 * (1 - tabCollapse))
                navItem(icon: "books.vertical", label: "Resources", isSelected: false)
                navItem(icon: "person.circle", label: "Profile", isSelected: false)
            }
            // Compress: icons pull inward as the bar shrinks.
            .padding(.horizontal, 10 + 16 * tabCollapse)
            .padding(.top, 14 - 6 * tabCollapse)
            .padding(.bottom, 10 - 4 * tabCollapse)
            .frame(maxWidth: .infinity, minHeight: 86 - 20 * tabCollapse)
            .selahWhiteGlass(cornerRadius: 34)
            // Glass becomes slightly more opaque when compressed.
            .overlay(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(.white.opacity(0.12 * tabCollapse))
                    .allowsHitTesting(false)
            )
            .shadow(color: .black.opacity(0.10 + 0.04 * tabCollapse), radius: 28, y: 14)

            Button {
                haptic(.reflect)
            } label: {
                Image(systemName: "plus")
                    .font(.systemScaled(24 - 3 * tabCollapse, weight: .medium))
                    .foregroundStyle(.black.opacity(0.82))
                    .frame(width: 62 - 8 * tabCollapse, height: 62 - 8 * tabCollapse)
                    .selahWhiteGlass(cornerRadius: 31, capsule: true)
                    .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
            }
            .buttonStyle(SelahPressButtonStyle())
            // AI-orb motion — a barely-there orbit so the create action feels alive.
            .offset(
                x: reduceMotion ? 0 : sin(orbPhase * .pi * 2) * 1.0,
                y: (-28 + 8 * tabCollapse) + (reduceMotion ? 0 : cos(orbPhase * .pi * 2) * 1.0)
            )
            .accessibilityLabel("Create")
        }
        // Floating Tuck — bar drops away on a fast flick, springs back when slow.
        .offset(y: tabTuckOffset)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: tabTuckOffset)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: tabCollapse)
    }

    private func navItem(icon: String, label: String, isSelected: Bool) -> some View {
        VStack(spacing: 4 * (1 - tabCollapse)) {
            Image(systemName: icon)
                .font(.systemScaled(isSelected ? 25 : 23, weight: isSelected ? .semibold : .regular))
                .frame(height: 25)
                .scaleEffect(1 - 0.12 * tabCollapse)
            // Labels fade out and collapse their height as the bar compresses.
            Text(label)
                .font(.systemScaled(12, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .opacity(Double(1 - tabCollapse))
                .frame(height: 15 * (1 - tabCollapse))
        }
        .foregroundStyle(isSelected ? .black : .black.opacity(0.38))
        .frame(maxWidth: .infinity, minHeight: 54 - 16 * tabCollapse)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) tab\(isSelected ? ", selected" : "")")
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
