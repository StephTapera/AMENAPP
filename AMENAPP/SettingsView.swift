//
//  SettingsView.swift
//  AMENAPP
//
//  Premium dark settings redesign.
//  Visual language: compact rounded dark-glass panels, monochrome icons,
//  minimal hierarchy, restrained animations — inspired by the reference.
//  All existing logic (sign-out, navigation, subviews) is fully preserved.
//

import SwiftUI
import FirebaseAuth

// MARK: - Design Tokens

private enum SD {
    static let bg         = Color(red: 0.07, green: 0.07, blue: 0.08)   // near-black
    static let panel      = Color(red: 0.12, green: 0.12, blue: 0.13)   // dark glass panel
    static let panelEdge  = Color.white.opacity(0.07)                    // hairline border
    static let rowHover   = Color.white.opacity(0.055)                   // press highlight
    static let label      = Color(white: 0.95)
    static let secondary  = Color(white: 0.5)
    static let chevron    = Color(white: 0.32)
    static let divider    = Color.white.opacity(0.07)
    static let danger     = Color(red: 1.0, green: 0.35, blue: 0.35)
    static let radius: CGFloat = 16
}

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var authViewModel: AuthenticationViewModel

    @State private var showSignOutConfirmation = false
    @State private var navigateToAccountSettings = false
    @State private var groupsVisible = false     // drives stagger entrance

    var body: some View {
        NavigationStack {
            ZStack {
                SD.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {

                        // ── Profile header ─────────────────────────────────
                        profileHeader
                            .opacity(groupsVisible ? 1 : 0)
                            .offset(y: groupsVisible ? 0 : 14)
                            .animation(.spring(response: 0.46, dampingFraction: 0.82).delay(0.04), value: groupsVisible)

                        // ── Group 1: Account ────────────────────────────────
                        SDGroup {
                            SDNavRow(icon: "person",          label: "Edit Profile")    { AccountSettingsView() }
                            SDDivider()
                            SDNavRow(icon: "at",              label: "Account")          { AccountSettingsView() }
                            SDDivider()
                            SDNavRow(icon: "bell",            label: "Notifications")    { NotificationSettingsView() }
                            SDDivider()
                            SDNavRow(icon: "lock",            label: "Privacy & Safety") { PrivacySettingsView() }
                            SDDivider()
                            SDNavRow(icon: "shield",          label: "Security")         { SecurityGroupView() }
                        }
                        .opacity(groupsVisible ? 1 : 0)
                        .offset(y: groupsVisible ? 0 : 18)
                        .animation(.spring(response: 0.46, dampingFraction: 0.82).delay(0.08), value: groupsVisible)

                        // ── Group 2: Preferences ────────────────────────────
                        SDGroup {
                            SDNavRow(icon: "sparkles",        label: "Berean AI")        { BereanAISettingsView() }
                            SDDivider()
                            SDNavRow(icon: "slider.horizontal.3", label: "Feed & Content") { ContentFeedGroupView() }
                            SDDivider()
                            SDNavRow(icon: "heart.text.square",   label: "Wellbeing")    { WellbeingGroupView() }
                            SDDivider()
                            SDNavRow(icon: "character.bubble",    label: "Language")     { TranslationSettingsView() }
                        }
                        .opacity(groupsVisible ? 1 : 0)
                        .offset(y: groupsVisible ? 0 : 18)
                        .animation(.spring(response: 0.46, dampingFraction: 0.82).delay(0.13), value: groupsVisible)

                        // ── Group 3: Tools & Data ───────────────────────────
                        SDGroup {
                            SDNavRow(icon: "chart.line.uptrend.xyaxis", label: "Creator & Insights") { CreatorGroupView() }
                            SDDivider()
                            SDNavRow(icon: "square.and.arrow.down.on.square", label: "Import Content") { ImportLauncherView() }
                        }
                        .opacity(groupsVisible ? 1 : 0)
                        .offset(y: groupsVisible ? 0 : 18)
                        .animation(.spring(response: 0.46, dampingFraction: 0.82).delay(0.17), value: groupsVisible)

                        // ── Group 4: Help & Legal ───────────────────────────
                        SDGroup {
                            SDNavRow(icon: "questionmark.circle", label: "Help & Support")       { HelpSupportView() }
                            SDDivider()
                            SDNavRow(icon: "flag",                label: "Report a Problem")     { ReportProblemView() }
                            SDDivider()
                            SDNavRow(icon: "info.circle",         label: "About AMEN")           { AboutAmenView() }
                        }
                        .opacity(groupsVisible ? 1 : 0)
                        .offset(y: groupsVisible ? 0 : 18)
                        .animation(.spring(response: 0.46, dampingFraction: 0.82).delay(0.20), value: groupsVisible)

                        // ── Sign Out ────────────────────────────────────────
                        SDGroup {
                            SDActionRow(icon: "rectangle.portrait.and.arrow.right",
                                        label: "Sign Out",
                                        style: .danger) {
                                HapticManager.impact(style: .medium)
                                showSignOutConfirmation = true
                            }
                        }
                        .opacity(groupsVisible ? 1 : 0)
                        .offset(y: groupsVisible ? 0 : 18)
                        .animation(.spring(response: 0.46, dampingFraction: 0.82).delay(0.23), value: groupsVisible)

                        // ── Delete account footer ───────────────────────────
                        NavigationLink {
                            DeleteAccountView()
                        } label: {
                            Text("Deactivate or delete account")
                                .font(.system(size: 12))
                                .foregroundStyle(SD.danger.opacity(0.60))
                        }
                        .padding(.top, 2)
                        .padding(.bottom, 32)
                        .opacity(groupsVisible ? 1 : 0)
                        .animation(.easeIn(duration: 0.2).delay(0.28), value: groupsVisible)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SD.label)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticManager.impact(style: .light)
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SD.label)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(SD.panel)
                                    .overlay(Capsule().stroke(SD.panelEdge, lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .toolbarBackground(SD.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationDestination(isPresented: $navigateToAccountSettings) {
                AccountSettingsView()
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
            .onAppear {
                withAnimation { groupsVisible = true }
            }
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        NavigationLink(destination: AccountSettingsView()) {
            HStack(spacing: 14) {
                // Avatar placeholder
                ZStack {
                    Circle()
                        .fill(SD.panel)
                        .frame(width: 52, height: 52)
                        .overlay(Circle().stroke(SD.panelEdge, lineWidth: 1))
                    Image(systemName: "person.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(SD.secondary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    if let user = Auth.auth().currentUser {
                        Text(user.displayName ?? "Your Account")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SD.label)
                        Text(user.email ?? "")
                            .font(.system(size: 12))
                            .foregroundStyle(SD.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Your Account")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SD.label)
                        Text("Manage profile & preferences")
                            .font(.system(size: 12))
                            .foregroundStyle(SD.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SD.chevron)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: SD.radius, style: .continuous)
                    .fill(SD.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: SD.radius, style: .continuous)
                            .stroke(SD.panelEdge, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(SDPressStyle())
    }

    // MARK: - Sign Out Logic

    private func signOut() {
        HapticManager.notification(type: .success)
        // P1 FIX: Delegate to AuthenticationViewModel.signOut() which performs full
        // teardown including 2FA state, phone auth, FCM deregistration, and all
        // listener cleanup via AppLifecycleManager. Previously this path did its own
        // partial teardown, leaving stale is2FAInProgress/pending2FACredential state.
        authViewModel.signOut()
        dismiss()
    }
}

// MARK: - Group Container

struct SDGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: SD.radius, style: .continuous)
                .fill(SD.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: SD.radius, style: .continuous)
                        .stroke(SD.panelEdge, lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: SD.radius, style: .continuous))
    }
}

// MARK: - Navigation Row

struct SDNavRow<Destination: View>: View {
    let icon: String
    let label: String
    @ViewBuilder let destination: () -> Destination
    @State private var isPressed = false

    var body: some View {
        NavigationLink(destination: destination()) {
            rowBody(showChevron: true)
        }
        .buttonStyle(SDPressStyle())
    }

    @ViewBuilder
    private func rowBody(showChevron: Bool) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(SD.label)
                .frame(width: 22, alignment: .center)

            Text(label)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(SD.label)

            Spacer()

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SD.chevron)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

// MARK: - Action Row (button — no navigation)

enum SDRowStyle { case standard, danger }

struct SDActionRow: View {
    let icon: String
    let label: String
    var style: SDRowStyle = .standard
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(style == .danger ? SD.danger : SD.label)
                    .frame(width: 22, alignment: .center)

                Text(label)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(style == .danger ? SD.danger : SD.label)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(SDPressStyle())
    }
}

// MARK: - Divider

struct SDDivider: View {
    var body: some View {
        SD.divider
            .frame(height: 0.5)
            .padding(.leading, 51)
    }
}

// MARK: - Press ButtonStyle

struct SDPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed
                    ? SD.rowHover
                    : Color.clear
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Grouped Detail Views
// These gather related settings under one destination to reduce top-level clutter.

// Security (was its own section — now one row)
struct SecurityGroupView: View {
    var body: some View {
        SDDetailScaffold(title: "Security") {
            SDGroup {
                SDNavRow(icon: "key",               label: "Change Password")            { ChangePasswordView() }
                SDDivider()
                SDNavRow(icon: "lock.app.dashed",   label: "Two-Factor Authentication")  { TwoFactorAuthView() }
                SDDivider()
                SDNavRow(icon: "iphone.gen3",       label: "Login Activity & Devices")   { ActiveSessionsView() }
                SDDivider()
                SDNavRow(icon: "arrow.down.circle", label: "Download Your Data")         { DownloadDataView() }
                SDDivider()
                SDNavRow(icon: "checkmark.shield",  label: "Account Status")             { AccountStatusView() }
                SDDivider()
                SDActionRow(icon: "camera", label: "App Permissions") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }
}

// Content & Feed + Accessibility (merged under Preferences)
struct ContentFeedGroupView: View {
    var body: some View {
        SDDetailScaffold(title: "Feed & Content") {
            SDGroup {
                SDNavRow(icon: "text.word.spacing",    label: "Muted Words & Topics")  { HiddenWordsSettingsView() }
                SDDivider()
                SDNavRow(icon: "slider.horizontal.3",  label: "Feed Preferences")      { HeyFeedControlsSheet() }
                SDDivider()
                SDNavRow(icon: "gear.badge",            label: "Default Post Settings") { DefaultPostSettingsView() }
            }

            SDGroup {
                SDNavRow(icon: "figure.walk.motion",   label: "Motion & Animations")   { AccessibilitySettingsView() }
                SDDivider()
                SDNavRow(icon: "textformat.size",       label: "Text Size & Display")   { TextSizeSettingsView() }
                SDDivider()
                SDNavRow(icon: "captions.bubble",      label: "Captions & Alt Text")    { CaptionsAltTextSettingsView() }
            }
        }
    }
}

// Wellbeing group
struct WellbeingGroupView: View {
    var body: some View {
        SDDetailScaffold(title: "Wellbeing") {
            SDGroup {
                SDNavRow(icon: "chart.bar",              label: "Screen Time & Usage")     { ScrollBudgetSettingsView() }
                SDDivider()
                SDNavRow(icon: "building.columns",       label: "Sunday Focus Mode")        { SundayFocusModeSettingsView() }
                SDDivider()
                SDNavRow(icon: "hand.raised.app",        label: "Take a Break Reminders")  { TakeABreakSettingsView() }
                SDDivider()
                SDNavRow(icon: "alarm",                  label: "Prayer Reminders")         { PrayerReminderSettingsView() }
                SDDivider()
                SDNavRow(icon: "moon",                   label: "Quiet Mode")               { QuietModeSettingsView() }
            }
        }
    }
}

// Creator group
struct CreatorGroupView: View {
    var body: some View {
        SDDetailScaffold(title: "Creator") {
            SDGroup {
                SDNavRow(icon: "chart.line.uptrend.xyaxis", label: "Insights & Analytics") { CreatorInsightsView() }
                SDDivider()
                SDNavRow(icon: "doc.text",                  label: "Drafts")               { DraftsSettingsView() }
            }
        }
    }
}

// MARK: - Shared detail page scaffold

struct SDDetailScaffold<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            SD.bg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    content()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(SD.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

// MARK: - Legacy aliases (keep compilation of unchanged subviews calling old components)

typealias AmenSettingsSectionView_Legacy = AmenSettingsSectionView
typealias SettingsDivider_Legacy         = SettingsDivider

// Keep old components alive so subviews that reference them still compile.
struct AmenSettingsSectionView<Content: View>: View {
    let header: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        SDGroup { content() }
    }
}

struct SettingsDivider: View {
    var body: some View { SDDivider() }
}

struct AmenSettingsRow<Destination: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    @ViewBuilder let destination: () -> Destination
    var body: some View {
        SDNavRow(icon: icon, label: title, destination: destination)
    }
}

struct SettingsRowExternal: View {
    let icon: String
    let iconColor: Color
    let title: String
    let action: () -> Void
    var body: some View {
        SDActionRow(icon: icon, label: title, style: .standard, action: action)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(AuthenticationViewModel())
}
