//
//  SettingsView.swift
//  AMENAPP
//
//  Full settings hub — all sections from Account → Wellbeing → AI → Creator → Legal.
//

import SwiftUI
import FirebaseAuth

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var showSignOutConfirmation = false
    @State private var navigateToAccountSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        accountSection
                        privacySafetySection
                        notificationsSection
                        securitySection
                        contentFeedSection
                        wellbeingSection
                        bereanAISection
                        creatorSection
                        importDataSection
                        helpLegalSection
                        accessibilitySection
                        signOutButton
                        deleteAccountFooter
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $navigateToAccountSettings) {
                AccountSettingsView()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        HapticManager.impact(style: .light)
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.white)
                }
            }
            .confirmationDialog("Sign Out", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { signOut() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToAccountSettings)) { _ in
                navigateToAccountSettings = true
            }
        }
    }

    // MARK: - Section: Account

    private var accountSection: some View {
        AmenSettingsSectionView(header: "ACCOUNT") {
            AmenSettingsRow(icon: "person.circle.fill", iconColor: .blue, title: "Edit Profile") {
                AccountSettingsView()
            }
            SettingsDivider()
            AmenSettingsRow(icon: "person.crop.rectangle.fill", iconColor: Color(red: 0.4, green: 0.6, blue: 1.0), title: "Account Type") {
                AccountTypeSettingsView()
            }
            SettingsDivider()
            AmenSettingsRow(icon: "hand.raised.fill", iconColor: .red, title: "Blocked Accounts") {
                BlockedUsersView()
            }
            SettingsDivider()
            AmenSettingsRow(icon: "speaker.slash.fill", iconColor: Color(red: 0.7, green: 0.4, blue: 0.9), title: "Muted Accounts") {
                MutedAccountsView()
            }
            SettingsDivider()
            AmenSettingsRow(icon: "eye.slash.fill", iconColor: .gray, title: "Hidden Words & Filters") {
                HiddenWordsSettingsView()
            }
        }
    }

    // MARK: - Section: Privacy & Safety

    private var privacySafetySection: some View {
        AmenSettingsSectionView(header: "PRIVACY & SAFETY") {
            AmenSettingsRow(icon: "lock.shield.fill", iconColor: .green, title: "Privacy Settings") {
                PrivacySettingsView()
            }
            SettingsDivider()
            AmenSettingsRow(icon: "message.fill", iconColor: Color(red: 0.3, green: 0.75, blue: 0.55), title: "Message Controls") {
                MessageControlsSettingsView()
            }
            SettingsDivider()
            AmenSettingsRow(icon: "eye.fill", iconColor: Color(red: 0.4, green: 0.7, blue: 1.0), title: "Activity Status") {
                ActivityStatusSettingsView()
            }
            SettingsDivider()
            AmenSettingsRow(icon: "shield.lefthalf.filled.badge.checkmark", iconColor: Color(red: 0.3, green: 0.6, blue: 1.0), title: "Transparency Centre") {
                TransparencyCentreView()
            }
            SettingsDivider()
            AmenSettingsRow(icon: "hand.point.up.left.fill", iconColor: Color(red: 0.9, green: 0.6, blue: 0.2), title: "Sensitive Content") {
                SensitiveContentSettingsView()
            }
            SettingsDivider()
            AmenSettingsRow(icon: "shield.checkered", iconColor: .purple, title: "Safety & Community") {
                SafetyDashboardView()
            }
        }
    }

    // MARK: - Section: Notifications

    private var notificationsSection: some View {
        AmenSettingsSectionView(header: "NOTIFICATIONS") {
            AmenSettingsRow(icon: "bell.badge.fill", iconColor: .orange, title: "Push Notifications") {
                NotificationSettingsView()
            }
            SettingsDivider()
            AmenSettingsRow(icon: "moon.fill", iconColor: Color(red: 0.4, green: 0.4, blue: 0.9), title: "Quiet Mode") {
                QuietModeSettingsView()
            }
            SettingsDivider()
            AmenSettingsRow(icon: "alarm.fill", iconColor: Color(red: 0.9, green: 0.5, blue: 0.3), title: "Prayer Reminders") {
                PrayerReminderSettingsView()
            }
        }
    }

    // MARK: - Section: Security

    private var securitySection: some View {
        AmenSettingsSectionView(header: "SECURITY") {
            AmenSettingsRow(icon: "key.fill", iconColor: Color(red: 0.9, green: 0.75, blue: 0.2), title: "Change Password") {
                ChangePasswordView()
            }
            SettingsDivider()
            AmenSettingsRow(icon: "lock.app.dashed", iconColor: .green, title: "Two-Factor Authentication") {
                TwoFactorAuthView()
            }
            SettingsDivider()
            AmenSettingsRow(icon: "iphone.gen3", iconColor: Color(red: 0.4, green: 0.8, blue: 0.9), title: "Login Activity & Devices") {
                ActiveSessionsView()
            }
            SettingsDivider()
            AmenSettingsRow(icon: "arrow.down.circle.fill", iconColor: Color(red: 0.5, green: 0.6, blue: 0.8), title: "Download Your Data") {
                DownloadDataView()
            }
            SettingsDivider()
            AmenSettingsRow(icon: "checkmark.shield.fill", iconColor: Color(red: 0.3, green: 0.75, blue: 0.5), title: "Account Status") {
                AccountStatusView()
            }
            SettingsDivider()
            SettingsRowExternal(icon: "camera.fill", iconColor: .gray, title: "App Permissions") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    // MARK: - Section: Content & Feed

    private var contentFeedSection: some View {
        AmenSettingsSectionView(header: "CONTENT & FEED") {
            AmenSettingsRow(icon: "text.word.spacing", iconColor: Color(red: 0.6, green: 0.4, blue: 0.9), title: "Muted Words & Topics") {
                HiddenWordsSettingsView()
            }
            SettingsDivider()
            AmenSettingsRow(icon: "slider.horizontal.3", iconColor: Color(red: 0.3, green: 0.65, blue: 0.9), title: "Feed Preferences") {
                HeyFeedControlsSheet()
            }
            SettingsDivider()
            AmenSettingsRow(icon: "character.bubble.fill", iconColor: Color(red: 0.8, green: 0.5, blue: 0.3), title: "Language & Translation") {
                LanguageSettingsView()
            }
            SettingsDivider()
            AmenSettingsRow(icon: "gear.badge", iconColor: .gray, title: "Default Post Settings") {
                DefaultPostSettingsView()
            }
        }
    }

    // MARK: - Section: Wellbeing

    private var wellbeingSection: some View {
        AmenSettingsSectionView(header: "WELLBEING") {
            AmenSettingsRow(icon: "chart.bar.fill", iconColor: Color(red: 0.3, green: 0.8, blue: 0.6), title: "Screen Time & Usage") {
                ScrollBudgetSettingsView()
            }
            SettingsDivider()
            AmenSettingsRow(icon: "building.columns.fill", iconColor: Color(red: 0.9, green: 0.7, blue: 0.3), title: "Sunday Focus Mode") {
                SundayFocusModeSettingsView()
            }
            SettingsDivider()
            AmenSettingsRow(icon: "hand.raised.app.fill", iconColor: Color(red: 0.6, green: 0.5, blue: 0.9), title: "Take a Break Reminders") {
                TakeABreakSettingsView()
            }
        }
    }

    // MARK: - Section: Berean AI

    private var bereanAISection: some View {
        AmenSettingsSectionView(header: "BEREAN AI") {
            AmenSettingsRow(icon: "sparkles", iconColor: Color(red: 0.5, green: 0.6, blue: 1.0), title: "AI Preferences") {
                BereanAISettingsView()
            }
        }
    }

    // MARK: - Section: Creator

    private var creatorSection: some View {
        AmenSettingsSectionView(header: "CREATOR") {
            AmenSettingsRow(icon: "chart.line.uptrend.xyaxis", iconColor: Color(red: 0.4, green: 0.75, blue: 0.9), title: "Insights & Analytics") {
                CreatorInsightsView()
            }
            SettingsDivider()
            AmenSettingsRow(icon: "doc.text.fill", iconColor: Color(red: 0.8, green: 0.6, blue: 0.3), title: "Drafts") {
                DraftsSettingsView()
            }
        }
    }

    // MARK: - Section: Import Data

    private var importDataSection: some View {
        AmenSettingsSectionView(header: "YOUR DATA") {
            NavigationLink {
                ImportLauncherView()
                    .navigationTitle("Import Content")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "square.and.arrow.down.on.square")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.blue)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import Your Content")
                            .font(.system(size: 16, weight: .regular))
                        Text("From Instagram, X, or others")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Section: Help & Legal

    private var helpLegalSection: some View {
        AmenSettingsSectionView(header: "HELP & LEGAL") {
            AmenSettingsRow(icon: "questionmark.circle.fill", iconColor: .purple, title: "Help & Support") {
                HelpSupportView()
            }
            SettingsDivider()
            AmenSettingsRow(icon: "flag.fill", iconColor: .orange, title: "Report a Problem") {
                ReportProblemView()
            }
            SettingsDivider()
            AmenSettingsRow(icon: "book.closed.fill", iconColor: Color(red: 0.4, green: 0.7, blue: 0.5), title: "Community Guidelines") {
                LegalDocView(title: "Community Guidelines", urlString: "https://amenapp.com/community-guidelines")
            }
            SettingsDivider()
            AmenSettingsRow(icon: "lock.doc.fill", iconColor: .gray, title: "Privacy Policy") {
                LegalDocView(title: "Privacy Policy", urlString: "https://amenapp.com/privacy")
            }
            SettingsDivider()
            AmenSettingsRow(icon: "doc.plaintext.fill", iconColor: .gray, title: "Terms of Service") {
                LegalDocView(title: "Terms of Service", urlString: "https://amenapp.com/terms")
            }
            SettingsDivider()
            AmenSettingsRow(icon: "info.circle.fill", iconColor: .gray, title: "About AMEN") {
                AboutAmenView()
            }
        }
    }

    // MARK: - Section: Accessibility

    private var accessibilitySection: some View {
        AmenSettingsSectionView(header: "ACCESSIBILITY") {
            AmenSettingsRow(icon: "figure.walk.motion", iconColor: Color(red: 0.4, green: 0.7, blue: 0.9), title: "Motion & Animations") {
                AccessibilitySettingsView()
            }
            SettingsDivider()
            AmenSettingsRow(icon: "textformat.size", iconColor: Color(red: 0.7, green: 0.5, blue: 0.9), title: "Text Size & Display") {
                TextSizeSettingsView()
            }
            SettingsDivider()
            AmenSettingsRow(icon: "captions.bubble.fill", iconColor: Color(red: 0.4, green: 0.75, blue: 0.55), title: "Captions & Alt Text") {
                CaptionsAltTextSettingsView()
            }
        }
    }

    // MARK: - Sign Out

    private var signOutButton: some View {
        Button(role: .destructive) {
            HapticManager.impact(style: .medium)
            showSignOutConfirmation = true
        } label: {
            HStack {
                Spacer()
                Label {
                    Text("Sign Out")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(.red)
                } icon: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(.red)
                }
                Spacer()
            }
            .padding(16)
        }
        .glassEffect(GlassEffectStyle.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var deleteAccountFooter: some View {
        NavigationLink {
            DeleteAccountView()
        } label: {
            Text("Deactivate or Delete Account")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.red.opacity(0.7))
        }
        .padding(.bottom, 8)
    }

    // MARK: - Sign Out Logic

    private func signOut() {
        HapticManager.notification(type: .success)
        Task {
            await PushNotificationManager.shared.removeFCMTokenFromFirestore()
            PushNotificationManager.shared.clearBadge()
            await MainActor.run {
                // Stop all RTDB & Firestore listeners BEFORE signing out
                // to prevent permission_denied floods and stale listener state.
                // Must mirror AuthenticationViewModel.signOut() cleanup list.
                PostInteractionsService.shared.stopAllObservers()
                RealtimeRepostsService.shared.stopAllObservers()
                RealtimeSavedPostsService.shared.removeSavedPostsListener()
                RealtimeDatabaseService.shared.cleanup()
                RealtimePostService.shared.stopAllObserving()
                FollowService.shared.stopListening()
                NotificationService.shared.stopListening()
                BlockService.shared.stopListening()
                RealtimeCommentsService.shared.removeAllListeners()
                ActivityFeedService.shared.stopAllObservers()
                do {
                    try Auth.auth().signOut()
                } catch {
                    Logger.error("Sign out failed", error: error)
                }
                dismiss()
            }
        }
    }
}

// MARK: - Reusable Settings Section Container

struct AmenSettingsSectionView<Content: View>: View {
    let header: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(header)
                .font(.custom("OpenSans-Bold", size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .glassEffect(GlassEffectStyle.regular, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - Reusable Settings Row (NavigationLink)

struct AmenSettingsRow<Destination: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination()) {
            settingsRowContent(icon: icon, iconColor: iconColor, title: title)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reusable Settings Row (external / action)

struct SettingsRowExternal: View {
    let icon: String
    let iconColor: Color
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                settingsRowContent(icon: icon, iconColor: iconColor, title: title)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.trailing, 16)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared row inner layout

@ViewBuilder
private func settingsRowContent(icon: String, iconColor: Color, title: String) -> some View {
    HStack(spacing: 12) {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(iconColor.opacity(0.18))
                .frame(width: 32, height: 32)
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(iconColor)
        }

        Text(title)
            .font(.custom("OpenSans-SemiBold", size: 15))
            .foregroundStyle(.white)

        Spacer()

        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.3))
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 13)
    .contentShape(Rectangle())
}

// MARK: - Divider helper

struct SettingsDivider: View {
    var body: some View {
        Divider()
            .background(Color.white.opacity(0.08))
            .padding(.leading, 58)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SettingsView()
    }
}
