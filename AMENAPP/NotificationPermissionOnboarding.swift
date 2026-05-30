// NotificationPermissionOnboarding.swift
// AMENAPP
//
// 3-step glassmorphic notification permission onboarding sheet.
//
// Step 1 — Value prop: what notifications the user will receive
// Step 2 — System permission prompt: triggers UNUserNotificationCenter.requestAuthorization
// Step 3 — Quiet hours: pick start/end time, saved to SmartNotificationService
//
// Usage:
//   anyView.notificationOnboarding(isPresented: $showOnboarding)
//
// Trigger condition (suggested in AMENAPPApp or ContentView .onAppear):
//   if !UserDefaults.standard.bool(forKey: "notifOnboardingShown") {
//       showOnboarding = true
//   }

import SwiftUI
import UserNotifications
import FirebaseAuth
import FirebaseFirestore

// MARK: - View Extension

extension View {
    func notificationOnboarding(isPresented: Binding<Bool>) -> some View {
        self.sheet(isPresented: isPresented) {
            NotificationPermissionOnboardingSheet(isPresented: isPresented)
                .interactiveDismissDisabled(true)
        }
    }
}

// MARK: - Sheet

struct NotificationPermissionOnboardingSheet: View {
    @Binding var isPresented: Bool
    @State private var step: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var quietStart = Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var quietEnd   = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var quietEnabled = true
    @State private var permissionStatus: UNAuthorizationStatus = .notDetermined
    @State private var isSaving = false
    @State private var quietHoursSource: String = "manual"
    @State private var appliedSuggestion: AdaptiveQuietHoursEngine.QuietHoursSuggestion?
    @State private var isApplyingSuggestion = false
    @ObservedObject private var adaptiveEngine = AdaptiveQuietHoursEngine.shared

    private let steps = 3

    var body: some View {
        ZStack {
            // Glassmorphic background
            Color.clear
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Step indicator
                HStack(spacing: 6) {
                    ForEach(0..<steps, id: \.self) { i in
                        Capsule()
                            .fill(i <= step ? Color(.label) : Color(.systemGray4))
                            .frame(width: i == step ? 24 : 8, height: 4)
                            .animation(reduceMotion ? .none : .spring(response: 0.3), value: step)
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 32)

                // Content
                Group {
                    switch step {
                    case 0:  valuePropStep
                    case 1:  permissionStep
                    default: quietHoursStep
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))
                .animation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.85), value: step)

                Spacer()

                // CTA button
                ctaButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 36)
            }
        }
        .task {
            await fetchPermissionStatus()
            await adaptiveEngine.loadLearnedPattern()
        }
    }

    // MARK: - Step 1: Value Prop

    private var valuePropStep: some View {
        VStack(spacing: 28) {
            Image(systemName: "bell.badge.fill")
                .font(.systemScaled(56))
                .foregroundStyle(Color(.label))

            VStack(spacing: 10) {
                Text("Stay Connected")
                    .font(.systemScaled(28, weight: .bold))
                    .foregroundStyle(Color(.label))
                Text("Get notified when your community prays for you, responds to your posts, and more.")
                    .font(.systemScaled(16))
                    .foregroundStyle(Color(.secondaryLabel))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            VStack(spacing: 0) {
                ForEach(valuePropRows, id: \.icon) { row in
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(row.color.opacity(0.12))
                                .frame(width: 40, height: 40)
                            Image(systemName: row.icon)
                                .font(.systemScaled(16))
                                .foregroundStyle(row.color)
                        }
                        Text(row.label)
                            .font(.systemScaled(15))
                            .foregroundStyle(Color(.label))
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(nil)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    Divider().padding(.leading, 78)
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 20)
        }
    }

    private var valuePropRows: [(icon: String, label: String, color: Color)] {
        [
            ("hands.sparkles.fill", "Prayers and amens from your community", .purple),
            ("bubble.left.and.bubble.right.fill", "Comments and replies on your posts", .blue),
            ("person.fill.badge.plus", "New followers and follow requests", Color(.label)),
            ("calendar.badge.clock", "Church events and reminders", .orange),
            ("sparkles", "Daily scripture insights from Berean", Color(red: 0.42, green: 0.24, blue: 0.82)),
        ]
    }

    // MARK: - Step 2: System Permission

    private var permissionStep: some View {
        VStack(spacing: 32) {
            ZStack {
                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 100, height: 100)
                Image(systemName: permissionStatus == .authorized ? "bell.badge.fill" : "bell.slash.fill")
                    .font(.systemScaled(44))
                    .foregroundStyle(permissionStatus == .authorized ? Color.green : Color(.label))
            }

            VStack(spacing: 10) {
                Text(permissionStatus == .authorized ? "You're all set!" : "Enable Notifications")
                    .font(.systemScaled(28, weight: .bold))
                    .foregroundStyle(Color(.label))
                Text(permissionStatus == .authorized
                    ? "Notifications are enabled. You'll never miss a moment."
                    : "AMEN will ask for permission to send you notifications. You can always change this in Settings.")
                    .font(.systemScaled(16))
                    .foregroundStyle(Color(.secondaryLabel))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            if permissionStatus == .denied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Open Settings", systemImage: "gear")
                        .font(.systemScaled(15, weight: .semibold))
                }
                .foregroundStyle(Color(.label))
            }
        }
    }

    // MARK: - Step 3: Quiet Hours

    private var quietHoursStep: some View {
        VStack(spacing: 28) {
            Image(systemName: "moon.stars.fill")
                .font(.systemScaled(56))
                .foregroundStyle(Color(.label))

            VStack(spacing: 10) {
                Text("Quiet Hours")
                    .font(.systemScaled(28, weight: .bold))
                    .foregroundStyle(Color(.label))
                Text("Choose when AMEN should pause notifications so you can rest without interruption.")
                    .font(.systemScaled(16))
                    .foregroundStyle(Color(.secondaryLabel))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            if let recommendation = smartRecommendation {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.orange)
                        Text("Smart Recommendation")
                            .font(.systemScaled(15, weight: .semibold))
                            .foregroundStyle(Color(.label))
                        Spacer()
                        Text("\(Int(recommendation.confidence * 100))%")
                            .font(.systemScaled(12, weight: .semibold))
                            .foregroundStyle(.orange)
                    }

                    HStack {
                        Text("\(recommendation.startTime) – \(recommendation.endTime)")
                            .font(.systemScaled(16, weight: .semibold))
                            .foregroundStyle(Color(.label))
                        Spacer()
                        Button("Use Recommended") {
                            applySmartRecommendation(recommendation)
                        }
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(Color(.label))
                    }

                    Text(recommendation.sourceLabel)
                        .font(.systemScaled(12))
                        .foregroundStyle(Color(.secondaryLabel))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)
            }

            VStack(spacing: 0) {
                Toggle(isOn: $quietEnabled) {
                    HStack(spacing: 8) {
                        Image(systemName: "moon.fill")
                            .font(.systemScaled(15))
                        Text("Enable Quiet Hours")
                            .font(.systemScaled(15))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .layoutPriority(1)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .tint(Color(.label))

                if quietEnabled {
                    Divider().padding(.leading, 20)
                    HStack {
                        HStack(spacing: 8) {
                            Image(systemName: "bed.double.fill")
                                .font(.systemScaled(15))
                            Text("Start")
                                .font(.systemScaled(15))
                                .foregroundStyle(Color(.label))
                                .lineLimit(1)
                                .minimumScaleFactor(0.9)
                                .layoutPriority(1)
                        }
                        .foregroundStyle(Color(.label))
                        Spacer()
                        DatePicker("", selection: $quietStart, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)

                    Divider().padding(.leading, 20)
                    HStack {
                        HStack(spacing: 8) {
                            Image(systemName: "sunrise.fill")
                                .font(.systemScaled(15))
                            Text("End")
                                .font(.systemScaled(15))
                                .foregroundStyle(Color(.label))
                                .lineLimit(1)
                                .minimumScaleFactor(0.9)
                                .layoutPriority(1)
                        }
                        .foregroundStyle(Color(.label))
                        Spacer()
                        DatePicker("", selection: $quietEnd, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 20)
            .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.8), value: quietEnabled)
        }
        .onChange(of: quietStart) { _, _ in
            markManualQuietHoursChange()
        }
        .onChange(of: quietEnd) { _, _ in
            markManualQuietHoursChange()
        }
    }

    // MARK: - CTA Button

    private var ctaButton: some View {
        Button {
            handleCTA()
        } label: {
            Group {
                if isSaving {
                    ProgressView().tint(.white)
                } else {
                    Text(ctaLabel)
                        .font(.systemScaled(17, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color(.label), in: RoundedRectangle(cornerRadius: 16))
            .foregroundStyle(Color(.systemBackground))
        }
        .disabled(isSaving)
    }

    private var ctaLabel: String {
        switch step {
        case 0: return "Continue"
        case 1: return permissionStatus == .authorized ? "Continue" : "Allow Notifications"
        default: return "Done"
        }
    }

    // MARK: - Actions

    private func handleCTA() {
        switch step {
        case 0:
            withAnimation(reduceMotion ? nil : .default) { step = 1 }
        case 1:
            if permissionStatus == .notDetermined {
                Task {
                    await requestPermission()
                    await MainActor.run {
                        withAnimation(reduceMotion ? nil : .default) { step = 2 }
                    }
                }
            } else {
                withAnimation(reduceMotion ? nil : .default) { step = 2 }
            }
        default:
            Task { await saveQuietHours() }
        }
    }

    private func requestPermission() async {
        let granted = await PushNotificationManager.shared.requestNotificationPermissions()
        await MainActor.run {
            permissionStatus = granted ? .authorized : .denied
        }
        if granted {
            await MainActor.run {
                PushNotificationManager.shared.setupFCMToken()
                UserDefaults.standard.set(true, forKey: "hasCompletedNotificationPermission")
            }
        }
    }

    private func fetchPermissionStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            permissionStatus = settings.authorizationStatus
        }
    }

    private func saveQuietHours() async {
        isSaving = true
        defer { isSaving = false }

        let cal   = Calendar.current
        let start = cal.component(.hour, from: quietStart) * 60 + cal.component(.minute, from: quietStart)
        let end   = cal.component(.hour, from: quietEnd)   * 60 + cal.component(.minute, from: quietEnd)

        // Persist to UserDefaults (read by SmartNotificationService)
        UserDefaults.standard.set(quietEnabled, forKey: "notifQuietHoursEnabled")
        UserDefaults.standard.set(start,        forKey: "notifQuietHoursStartMinutes")
        UserDefaults.standard.set(end,          forKey: "notifQuietHoursEndMinutes")
        UserDefaults.standard.set(quietHoursSource, forKey: "notifQuietHoursSource")
        UserDefaults.standard.set(true,         forKey: "notifOnboardingShown")

        // Persist to Firestore for cross-device sync
        if let uid = Auth.auth().currentUser?.uid {
            try? await Firestore.firestore().document("users/\(uid)").updateData([
                "notificationSettings.quietHoursEnabled":      quietEnabled,
                "notificationSettings.quietHoursStartMinutes": start,
                "notificationSettings.quietHoursEndMinutes":   end,
                "notificationSettings.quietHoursSource":       quietHoursSource
            ])
        }

        if let suggestion = appliedSuggestion {
            await adaptiveEngine.applySuggestion(suggestion)
        }

        await MainActor.run { isPresented = false }
    }
}

private extension NotificationPermissionOnboardingSheet {
    struct SmartQuietHoursRecommendation {
        let startTime: String
        let endTime: String
        let confidence: Double
        let sourceLabel: String
        let suggestion: AdaptiveQuietHoursEngine.QuietHoursSuggestion?
    }

    var smartRecommendation: SmartQuietHoursRecommendation? {
        if let suggestion = adaptiveEngine.suggestions.first {
            return SmartQuietHoursRecommendation(
                startTime: suggestion.startTime,
                endTime: suggestion.endTime,
                confidence: suggestion.confidence,
                sourceLabel: recommendationSourceLabel(for: suggestion.reason),
                suggestion: suggestion
            )
        }

        if let pattern = adaptiveEngine.learnedPattern {
            return SmartQuietHoursRecommendation(
                startTime: pattern.weekdayStart,
                endTime: pattern.weekdayEnd,
                confidence: pattern.confidence,
                sourceLabel: "Learned from your activity patterns",
                suggestion: nil
            )
        }

        return nil
    }

    func applySmartRecommendation(_ recommendation: SmartQuietHoursRecommendation) {
        isApplyingSuggestion = true
        quietEnabled = true
        quietStart = dateForTimeString(recommendation.startTime, fallback: quietStart)
        quietEnd = dateForTimeString(recommendation.endTime, fallback: quietEnd)
        quietHoursSource = recommendation.suggestion == nil ? "learned_pattern" : "adaptive_suggestion"
        appliedSuggestion = recommendation.suggestion
        isApplyingSuggestion = false
    }

    func dateForTimeString(_ timeString: String, fallback: Date) -> Date {
        let parts = timeString.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return fallback
        }
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? fallback
    }

    func markManualQuietHoursChange() {
        guard !isApplyingSuggestion else { return }
        appliedSuggestion = nil
        quietHoursSource = "manual"
    }

    func recommendationSourceLabel(for reason: AdaptiveQuietHoursEngine.QuietHoursSuggestion.SuggestionReason) -> String {
        switch reason {
        case .sleepPattern:
            return "Based on your sleep pattern"
        case .inactivityPattern:
            return "Based on inactivity"
        case .focusModeSync:
            return "Based on Focus Mode schedule"
        case .calendarEvents:
            return "Based on calendar events"
        case .locationPattern:
            return "Based on location patterns"
        }
    }
}
