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
    @State private var showDeleteAccountConfirmation = false
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
                            SDNavRow(icon: "person", label: "Edit Profile", subtitle: "Name, bio, links", iconBg: .blue) { EditProfileFromSettingsView() }
                            SDDivider()
                            SDNavRow(icon: "at", label: "Account", subtitle: "Email, username, password", iconBg: .gray) { AccountSettingsView() }
                            SDDivider()
                            SDNavRow(icon: "bell", label: "Notifications", subtitle: "Push, email, in-app", iconBg: .red) { NotificationSettingsView() }
                            SDDivider()
                            SDNavRow(icon: "square.grid.2x2", label: "Integrations", subtitle: "Widgets, Live Activities, Siri", iconBg: .indigo) { IntegrationSettingsView() }
                            SDDivider()
                            SDNavRow(icon: "lock", label: "Privacy & Safety", subtitle: "Who can see your content", iconBg: .green) { PrivacySettingsView() }
                            SDDivider()
                            SDNavRow(icon: "shield", label: "Security", subtitle: "2FA, active sessions", iconBg: .yellow) { SecurityGroupView() }
                        }
                        .opacity(groupsVisible ? 1 : 0)
                        .offset(y: groupsVisible ? 0 : 18)
                        .animation(.spring(response: 0.46, dampingFraction: 0.82).delay(0.08), value: groupsVisible)

                        // ── Group 2: Preferences ────────────────────────────
                        SDGroup {
                            SDNavRow(icon: "sparkles", label: "Berean AI", subtitle: "AI settings, Scripture sources", iconBg: .purple) { BereanAISettingsView() }
                            SDDivider()
                            SDNavRow(icon: "slider.horizontal.3", label: "Feed & Content", subtitle: "What you see and when", iconBg: .orange) { ContentFeedGroupView() }
                            SDDivider()
                            SDNavRow(icon: "heart.text.square", label: "Wellbeing", subtitle: "Screen time, daily limits", iconBg: .teal) { WellbeingGroupView() }
                            SDDivider()
                            SDNavRow(icon: "character.bubble", label: "Language", subtitle: "Translation preferences", iconBg: .indigo) { TranslationSettingsView() }
                        }
                        .opacity(groupsVisible ? 1 : 0)
                        .offset(y: groupsVisible ? 0 : 18)
                        .animation(.spring(response: 0.46, dampingFraction: 0.82).delay(0.13), value: groupsVisible)

                        // ── Group 3: Tools & Data ───────────────────────────
                        SDGroup {
                            SDNavRow(icon: "chart.line.uptrend.xyaxis", label: "Creator & Insights", subtitle: "Analytics, reach, growth", iconBg: Color(.darkGray)) { CreatorGroupView() }
                            SDDivider()
                            SDNavRow(icon: "square.and.arrow.down.on.square", label: "Import Content", subtitle: "Bring in from other platforms", iconBg: Color(.darkGray)) { ImportLauncherView() }
                        }
                        .opacity(groupsVisible ? 1 : 0)
                        .offset(y: groupsVisible ? 0 : 18)
                        .animation(.spring(response: 0.46, dampingFraction: 0.82).delay(0.17), value: groupsVisible)

                        // ── Group 4: Help & Legal ───────────────────────────
                        SDGroup {
                            SDNavRow(icon: "questionmark.circle", label: "Help & Support", subtitle: "FAQs, contact us") { HelpSupportView() }
                            SDDivider()
                            SDNavRow(icon: "flag", label: "Report a Problem", subtitle: "Bugs, feedback") { ReportProblemView() }
                            SDDivider()
                            SDNavRow(icon: "info.circle", label: "About AMEN", subtitle: "v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")") { AboutAmenView() }
                        }
                        .opacity(groupsVisible ? 1 : 0)
                        .offset(y: groupsVisible ? 0 : 18)
                        .animation(.spring(response: 0.46, dampingFraction: 0.82).delay(0.20), value: groupsVisible)

                        // ── Sign Out / Delete Account ───────────────────────
                        SDGroup {
                            SDActionRow(icon: "rectangle.portrait.and.arrow.right",
                                        label: "Sign Out",
                                        style: .danger) {
                                HapticManager.impact(style: .medium)
                                showSignOutConfirmation = true
                            }
                            SDDivider()
                            SDNavRow(icon: "trash",
                                     label: "Delete Account",
                                     subtitle: "Permanent — cannot be undone",
                                     iconBg: SD.danger) {
                                DeleteAccountView()
                            }
                        }
                        .opacity(groupsVisible ? 1 : 0)
                        .offset(y: groupsVisible ? 0 : 18)
                        .animation(.spring(response: 0.46, dampingFraction: 0.82).delay(0.23), value: groupsVisible)

                        // ── App Version ─────────────────────────────────────
                        HStack {
                            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                                .font(.system(size: 12))
                                .foregroundStyle(SD.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
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
            .alert("Delete Account", isPresented: $showDeleteAccountConfirmation) {
                Button("Delete Account", role: .destructive) {
                    // Navigate to DeleteAccountView for full flow with re-auth
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action is permanent and cannot be undone.")
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
        HStack(spacing: 14) {
            // Avatar: read-only display in Settings — camera/edit lives in EditProfileView only.
            // Resolves photo URL from Firebase Auth first, then falls back to UserDefaults cache.
            let resolvedPhotoURL: URL? = {
                if let url = Auth.auth().currentUser?.photoURL { return url }
                if let cached = UserProfileImageCache.shared.cachedProfileImageURL {
                    return URL(string: cached)
                }
                return nil
            }()

            Group {
                if let photoURL = resolvedPhotoURL {
                    AsyncImage(url: photoURL) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                                .frame(width: 52, height: 52)
                                .clipShape(Circle())
                        default:
                            avatarFallback
                        }
                    }
                } else {
                    avatarFallback
                }
            }

            // Name + email — navigates to AccountSettingsView on text tap
            NavigationLink(destination: AccountSettingsView()) {
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
            }
            .buttonStyle(SDPressStyle())

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

    private var avatarFallback: some View {
        let initials: String = {
            let name = Auth.auth().currentUser?.displayName ?? ""
            let parts = name.split(separator: " ")
            if parts.count >= 2 {
                return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
            } else if let first = parts.first {
                return String(first.prefix(2)).uppercased()
            }
            return "A"
        }()
        return ZStack {
            Circle()
                .fill(SD.panel)
                .frame(width: 52, height: 52)
                .overlay(Circle().stroke(SD.panelEdge, lineWidth: 1))
            Text(initials)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(SD.label)
        }
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
    var subtitle: String? = nil
    var iconBg: Color? = nil
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
            if let bg = iconBg {
                RoundedRectangle(cornerRadius: 8)
                    .fill(bg)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                    )
            } else {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(SD.label)
                    .frame(width: 22, alignment: .center)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(SD.label)
                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 12))
                        .foregroundStyle(SD.label.opacity(0.45))
                }
            }

            Spacer()

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SD.chevron)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, subtitle != nil ? 10 : 13)
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

// MARK: - Disabled Row (Coming Soon / unimplemented destinations)

struct SDDisabledRow: View {
    let icon: String
    let label: String
    var badge: String? = nil

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(SD.label.opacity(0.3))
                .frame(width: 22, alignment: .center)

            Text(label)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(SD.label.opacity(0.3))

            Spacer()

            if let badge {
                Text(badge)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SD.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(SD.panelEdge)
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .allowsHitTesting(false)  // tap-through: row is not interactive
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
                // Insights: Coming Soon — navigation disabled until feature is live
                SDDisabledRow(icon: "chart.line.uptrend.xyaxis", label: "Insights & Analytics", badge: "Coming Soon")
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

// MARK: - EditProfile wrapper (Settings → EditProfileView bridge)
// EditProfileView requires @Binding var profileData, so this wrapper owns the state.

private struct EditProfileFromSettingsView: View {
    private let user = Auth.auth().currentUser
    @State private var profileData: UserProfileData = UserProfileData(
        name: "", username: "", bio: "", bioURL: nil,
        initials: "", profileImageURL: nil, interests: [String](), socialLinks: [SocialLinkUI]()
    )
    @State private var loaded = false

    var body: some View {
        EditProfileView(profileData: $profileData)
            .task {
                guard !loaded, let uid = user?.uid else { return }
                loaded = true
                // Pre-fill from UserDefaults cache so the view opens instantly
                profileData = UserProfileData(
                    name:            UserDefaults.standard.string(forKey: "cached_displayName") ?? user?.displayName ?? "",
                    username:        UserDefaults.standard.string(forKey: "cached_username") ?? "",
                    bio:             UserDefaults.standard.string(forKey: "cached_bio") ?? "",
                    bioURL:          UserDefaults.standard.string(forKey: "cached_bioURL"),
                    initials:        UserDefaults.standard.string(forKey: "cached_initials") ?? String((user?.displayName ?? "?").prefix(1)),
                    profileImageURL: UserDefaults.standard.string(forKey: "cached_profileImageURL") ?? user?.photoURL?.absoluteString,
                    interests:       [String](),
                    socialLinks:     [SocialLinkUI]()
                )
                _ = uid // suppress unused warning
            }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(AuthenticationViewModel())
}
