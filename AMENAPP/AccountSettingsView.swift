//
//  AccountSettingsView.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Biometric Setting Row

struct BiometricSettingRow: View {
    @ObservedObject private var biometricService = BiometricAuthService.shared
    @State private var showBiometricSetup = false
    
    var body: some View {
        if biometricService.isBiometricAvailable {
            Toggle(isOn: Binding(
                get: { biometricService.isBiometricEnabled },
                set: { newValue in
                    if newValue {
                        showBiometricSetup = true
                    } else {
                        biometricService.disableBiometric()
                    }
                }
            )) {
                HStack(spacing: 12) {
                    Image(systemName: biometricService.biometricType.icon)
                        .frame(width: 24)
                        .foregroundStyle(biometricService.isBiometricEnabled ? .green : .secondary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(biometricService.biometricType.displayName)
                            .font(AMENFont.semiBold(15))
                        Text(biometricService.isBiometricEnabled ? "Enabled for quick sign-in" : "Tap to enable")
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .tint(.green)
            .amenAlert(isPresented: $showBiometricSetup, config: LiquidGlassAlertConfig(
                title: "Enable \(biometricService.biometricType.displayName)?",
                message: "You'll be able to sign in quickly using \(biometricService.biometricType.displayName) instead of entering your password.",
                icon: "faceid",
                primaryButton: LiquidGlassAlertButton("Enable", tone: .spiritual) {
                    Task {
                        let success = await biometricService.authenticate(reason: "Enable \(biometricService.biometricType.displayName) for AMEN")
                        if success {
                            biometricService.enableBiometric()
                        }
                    }
                },
                secondaryButton: .cancel()
            ))
        }
    }
}

// MARK: - Shabbat Mode Setting Row

struct SundayChurchFocusSettingRow: View {
    @ObservedObject private var focusManager = SundayChurchFocusManager.shared
    
    var body: some View {
        Toggle(isOn: Binding(
            get: { focusManager.isEnabled },
            set: { focusManager.setEnabled($0) }
        )) {
            HStack(spacing: 12) {
                // Candle icon — P2-1 FIX: Drive animation via .animation modifier
                // instead of imperative withAnimation(.repeatForever) in onAppear.
                // The old approach stacked new animations on every re-appear and never
                // stopped them when the toggle was disabled.
                ZStack {
                    // Glow effect (only when enabled)
                    if focusManager.isEnabled {
                        Circle()
                            .fill(Color.orange.opacity(0.2))
                            .frame(width: 30, height: 30)
                    }
                    
                    // Candle with flame
                    ZStack {
                        Image(systemName: "flame.fill")
                            .font(.systemScaled(14))
                            .foregroundStyle(.white)
                        
                        Image(systemName: "flame.fill")
                            .font(.systemScaled(10))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.yellow, .orange],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .scaleEffect(focusManager.isEnabled ? 1.05 : 1.0)
                            .animation(
                                focusManager.isEnabled
                                    ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true)
                                    : .default,
                                value: focusManager.isEnabled
                            )
                    }
                }
                .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shabbat Mode")
                        .font(AMENFont.semiBold(15))
                    Text("Sundays 6am - 4pm · Focus on worship")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tint(.orange)
    }
}

// MARK: - Account Settings View

struct AccountSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var authViewModel: AuthenticationViewModel
    @StateObject private var userService = UserService()
    
    @State private var showChangeUsername = false
    @State private var showChangeDisplayName = false
    @State private var showChangeEmail = false
    @State private var showChangePassword = false
    @State private var showDeleteAccount = false
    @State private var showDeactivateAccount = false
    @State private var showPrivacyDashboard = false
    @State private var showSignOutConfirmation = false
    @State private var isPrivateAccount = false
    @State private var isTogglingPrivacy = false

    // AMEN-specific content privacy
    @State private var prayerRequestsVisibility: String = "followers"   // "everyone" | "followers" | "only_me"
    @State private var testimoniesVisibility: String = "followers"
    @State private var isSavingPrivacy = false

    // Interaction controls
    @State private var mentionPermission: String = "everyone"   // "everyone" | "following" | "nobody"
    @State private var replyPermission: String   = "everyone"   // "everyone" | "following" | "nobody"

    // Content preferences
    @State private var filterMatureContent = true
    @State private var showFaithBasedSuggestions = true
    @State private var autoPlayVideos = true

    // App info
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    // Age / DOB (read-only, loaded from Firestore)
    @State private var birthYear: Int? = nil
    @State private var ageTierRaw: String? = nil

    private var ageTierDisplayName: String {
        guard let raw = ageTierRaw, let tier = AMENAgeAssuranceTier(rawValue: raw) else { return "Unknown" }
        switch tier {
        case .underMinimum: return "Under Minimum"
        case .teen: return "Teen"
        case .adult: return "Adult"
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {

                    // MARK: — ACCOUNT INFORMATION
                    Text("ACCOUNT INFORMATION")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        // Display Name
                        Button {
                            showChangeDisplayName = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Display Name")
                                        .font(AMENFont.semiBold(15))
                                        .foregroundStyle(.primary)

                                    if let user = userService.currentUser {
                                        Text(user.displayName)
                                            .font(AMENFont.regular(13))
                                            .foregroundStyle(.secondary)

                                        if let pending = user.pendingDisplayNameChange {
                                            Text("Pending: \(pending)")
                                                .font(AMENFont.regular(12))
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.systemScaled(12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Divider().padding(.leading, 16)

                        // Username
                        Button {
                            showChangeUsername = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Username")
                                        .font(AMENFont.semiBold(15))
                                        .foregroundStyle(.primary)

                                    if let user = userService.currentUser {
                                        Text("@\(user.username)")
                                            .font(AMENFont.regular(13))
                                            .foregroundStyle(.secondary)

                                        if let pending = user.pendingUsernameChange {
                                            Text("Pending: @\(pending)")
                                                .font(AMENFont.regular(12))
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.systemScaled(12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Divider().padding(.leading, 16)

                        // Email
                        Button {
                            showChangeEmail = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Email")
                                        .font(AMENFont.semiBold(15))
                                        .foregroundStyle(.primary)

                                    if let user = userService.currentUser {
                                        Text(user.email ?? "No email")
                                            .font(AMENFont.regular(13))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.systemScaled(12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Divider().padding(.leading, 16)

                        // Date of Birth (read-only)
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Date of Birth")
                                    .font(AMENFont.semiBold(15))
                                    .foregroundStyle(.primary)

                                if let year = birthYear {
                                    HStack(spacing: 6) {
                                        Text("Born \(year)")
                                            .font(AMENFont.regular(13))
                                            .foregroundStyle(.secondary)
                                        Text("·")
                                            .foregroundStyle(.secondary)
                                        Text(ageTierDisplayName)
                                            .font(AMENFont.regular(13))
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    Text("Not set")
                                        .font(AMENFont.regular(13))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "lock.fill")
                                .font(.systemScaled(12))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    // MARK: — SECURITY
                    Text("SECURITY")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        // Security Center - Login History, Sessions, Events
                        NavigationLink {
                            SecurityCenterView()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "lock.shield.fill")
                                    .frame(width: 24)
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Security & Access")
                                        .font(AMENFont.semiBold(15))
                                    Text("Login history, active sessions, and security events")
                                        .font(AMENFont.regular(13))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.systemScaled(12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Divider().padding(.leading, 56)
                        
                        Button {
                            showChangePassword = true
                        } label: {
                            HStack {
                                Image(systemName: "lock")
                                    .frame(width: 24)
                                Text("Change Password")
                                    .font(AMENFont.regular(15))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.systemScaled(12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    // MARK: — AUTHENTICATION
                    Text("AUTHENTICATION")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        BiometricSettingRow()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                        Divider().padding(.leading, 16)

                        NavigationLink(destination: AccountLinkingView()) {
                            HStack {
                                Image(systemName: "link.circle.fill")
                                    .frame(width: 24)
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Linked Accounts")
                                        .font(AMENFont.semiBold(15))
                                    Text("Manage sign-in methods")
                                        .font(AMENFont.regular(13))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.systemScaled(12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Divider().padding(.leading, 16)

                        NavigationLink(destination: ActiveSessionsView()) {
                            HStack {
                                Image(systemName: "iphone.and.arrow.forward")
                                    .frame(width: 24)
                                    .foregroundStyle(.purple)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Active Sessions")
                                        .font(AMENFont.semiBold(15))
                                    Text("View signed-in devices")
                                        .font(AMENFont.regular(13))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.systemScaled(12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Divider().padding(.leading, 16)

                        NavigationLink(destination: TwoFactorAuthView()) {
                            HStack {
                                Image(systemName: "lock.shield.fill")
                                    .frame(width: 24)
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Two-Factor Authentication")
                                        .font(AMENFont.semiBold(15))
                                    Text("Extra security with SMS")
                                        .font(AMENFont.regular(13))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.systemScaled(12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Divider().padding(.leading, 56)
                        
                        NavigationLink {
                            PhoneVerificationView()
                        } label: {
                            HStack {
                                Image(systemName: "phone.badge.checkmark.fill")
                                    .frame(width: 24)
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Verify Phone Number")
                                        .font(AMENFont.semiBold(15))
                                    Text("Add verified phone for recovery & 2FA")
                                        .font(AMENFont.regular(13))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.systemScaled(12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    // MARK: — PRIVACY
                    Text("PRIVACY")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        // P0 FIX: Private Account Toggle
                        Toggle(isOn: $isPrivateAccount) {
                            HStack(spacing: 12) {
                                Image(systemName: isPrivateAccount ? "lock.fill" : "lock.open.fill")
                                    .frame(width: 24)
                                    .foregroundStyle(isPrivateAccount ? .blue : .secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Private Account")
                                        .font(AMENFont.semiBold(15))
                                    Text(isPrivateAccount ? "Only approved followers can see your posts" : "Anyone can see your posts")
                                        .font(AMENFont.regular(13))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tint(.blue)
                        .disabled(isTogglingPrivacy)
                        .onChange(of: isPrivateAccount) { oldValue, newValue in
                            Task {
                                await togglePrivateAccount(newValue: newValue)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        Divider().padding(.leading, 16)

                        NavigationLink(destination: ProfileVisibilitySettingsView()) {
                            HStack {
                                Image(systemName: "eye")
                                    .frame(width: 24)
                                Text("Profile Visibility")
                                    .font(AMENFont.regular(15))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.systemScaled(12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Divider().padding(.leading, 16)

                        // Privacy & Contact Controls
                        NavigationLink(destination: PrivacyControlsSettingsView()) {
                            HStack {
                                Image(systemName: "hand.raised.fill")
                                    .frame(width: 24)
                                    .foregroundStyle(.blue)
                                Text("Privacy & Contact")
                                    .font(AMENFont.regular(15))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.systemScaled(12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    Text(isPrivateAccount
                        ? "When your account is private, only people you approve can follow you and see your posts. You'll receive follow requests that you can accept or decline."
                        : "Control who can message you, comment on your posts, and mention you")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    // MARK: — INTERACTIONS
                    Text("INTERACTIONS")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        // Who can mention me
                        interactionPermissionRow(
                            icon: "at",
                            iconColor: .orange,
                            title: "Who can mention me",
                            current: mentionPermission
                        ) { selected in
                            mentionPermission = selected
                            Task { await savePrivacySetting("mentionPermission", value: selected) }
                        }

                        Divider().padding(.leading, 16)

                        // Who can reply to my posts
                        interactionPermissionRow(
                            icon: "arrowshape.turn.up.left.fill",
                            iconColor: .blue,
                            title: "Who can reply to my posts",
                            current: replyPermission
                        ) { selected in
                            replyPermission = selected
                            Task { await savePrivacySetting("replyPermission", value: selected) }
                        }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    Text("These settings apply to people who aren't blocked. Followers-only settings apply even on public accounts.")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    // MARK: — PRIVACY & DATA
                    Text("PRIVACY & DATA")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        Button {
                            showPrivacyDashboard = true
                        } label: {
                            HStack {
                                Image(systemName: "shield.checkered")
                                    .frame(width: 24)
                                    .foregroundStyle(.blue)
                                Text("Privacy Dashboard")
                                    .font(AMENFont.semiBold(15))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.systemScaled(12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    // MARK: — CHURCH FOCUS
                    Text("CHURCH FOCUS")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        SundayChurchFocusSettingRow()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    Text("When enabled, social features are limited on Sundays from 6:00 AM - 4:00 PM to encourage church focus. Church Notes and Find a Church remain available.")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    // MARK: — LANGUAGE
                    Text("LANGUAGE")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        NavigationLink(destination: TranslationSettingsView()) {
                            HStack {
                                Image(systemName: "globe")
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Translation & Language")
                                        .font(AMENFont.semiBold(15))
                                    Text(TranslationSettingsManager.shared.preferences.contentTranslationMode.displayLabel)
                                        .font(AMENFont.regular(13))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.systemScaled(12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    // MARK: — WELLBEING
                    Text("WELLBEING")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        NavigationLink(destination: ScrollBudgetSettingsView()) {
                            HStack {
                                Image(systemName: "hourglass")
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Scroll Budget")
                                        .font(AMENFont.semiBold(15))
                                    if ScrollBudgetManager.shared.isEnabled {
                                        Text("\(ScrollBudgetManager.shared.dailyBudgetMinutes) min daily")
                                            .font(AMENFont.regular(13))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.systemScaled(12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    Text("Set daily limits for feed scrolling time with supportive nudges and mindful breaks.")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    // MARK: — NOTIFICATIONS
                    Text("NOTIFICATIONS")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        NavigationLink(destination: NotificationsSettingsView()) {
                            HStack(spacing: 12) {
                                Image(systemName: "bell.badge.fill")
                                    .frame(width: 24)
                                    .foregroundStyle(.red)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Notifications")
                                        .font(AMENFont.semiBold(15))
                                    Text("Push, email & in-app alerts")
                                        .font(AMENFont.regular(13))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.systemScaled(12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    // MARK: — AMEN PRIVACY
                    Text("AMEN PRIVACY")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        // Who can see Prayer Requests
                        Picker(selection: $prayerRequestsVisibility) {
                            Text("Everyone").tag("everyone")
                            Text("Followers").tag("followers")
                            Text("Only Me").tag("only_me")
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "hands.sparkles.fill")
                                    .frame(width: 24)
                                    .foregroundStyle(Color(red: 0.4, green: 0.25, blue: 0.8))
                                Text("Who Can See Prayer Requests")
                                    .font(AMENFont.semiBold(15))
                            }
                        }
                        .onChange(of: prayerRequestsVisibility) { _, val in
                            Task { await savePrivacySetting("prayerRequestsVisibility", value: val) }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        Divider().padding(.leading, 16)

                        // Who can see Testimonies
                        Picker(selection: $testimoniesVisibility) {
                            Text("Everyone").tag("everyone")
                            Text("Followers").tag("followers")
                            Text("Only Me").tag("only_me")
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "text.badge.star")
                                    .frame(width: 24)
                                    .foregroundStyle(Color(red: 0.9, green: 0.55, blue: 0.1))
                                Text("Who Can See Testimonies")
                                    .font(AMENFont.semiBold(15))
                            }
                        }
                        .onChange(of: testimoniesVisibility) { _, val in
                            Task { await savePrivacySetting("testimoniesVisibility", value: val) }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    Text("Control who can see your spiritual content. Changes apply to new posts and existing ones.")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    // MARK: — CONTENT PREFERENCES
                    Text("CONTENT PREFERENCES")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        // Personalized Greeting Settings
                        NavigationLink {
                            GreetingSettingsView()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "hand.wave.fill")
                                    .frame(width: 24)
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Personalized Greeting")
                                        .font(AMENFont.semiBold(15))
                                    Text("Customize your welcome message")
                                        .font(AMENFont.regular(13))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.systemScaled(12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        Divider().padding(.leading, 16)

                        Toggle(isOn: $filterMatureContent) {
                            HStack(spacing: 12) {
                                Image(systemName: "shield.fill")
                                    .frame(width: 24)
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Filter Mature Content")
                                        .font(AMENFont.semiBold(15))
                                    Text("Hide potentially sensitive posts")
                                        .font(AMENFont.regular(13))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tint(.blue)
                        .onChange(of: filterMatureContent) { _, val in
                            Task { await savePreference("filterMatureContent", value: val) }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        Divider().padding(.leading, 16)

                        Toggle(isOn: $showFaithBasedSuggestions) {
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles")
                                    .frame(width: 24)
                                    .foregroundStyle(Color(red: 0.5, green: 0.3, blue: 0.9))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Faith-Based Suggestions")
                                        .font(AMENFont.semiBold(15))
                                    Text("Personalized scripture & community")
                                        .font(AMENFont.regular(13))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tint(Color(red: 0.5, green: 0.3, blue: 0.9))
                        .onChange(of: showFaithBasedSuggestions) { _, val in
                            Task { await savePreference("faithSuggestions", value: val) }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        Divider().padding(.leading, 16)

                        Toggle(isOn: $autoPlayVideos) {
                            HStack(spacing: 12) {
                                Image(systemName: "play.circle.fill")
                                    .frame(width: 24)
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Auto-Play Videos")
                                        .font(AMENFont.semiBold(15))
                                    Text("Play videos without tapping")
                                        .font(AMENFont.regular(13))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tint(.green)
                        .onChange(of: autoPlayVideos) { _, val in
                            Task { await savePreference("autoPlayVideos", value: val) }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    // MARK: — DATA & PERMISSIONS
                    Text("DATA & PERMISSIONS")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        Button {
                            exportUserData()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "square.and.arrow.up")
                                    .frame(width: 24)
                                    .foregroundStyle(.blue)
                                Text("Export My Data")
                                    .font(AMENFont.regular(15))
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Divider().padding(.leading, 16)

                        Button {
                            clearCache()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .frame(width: 24)
                                    .foregroundStyle(.orange)
                                Text("Clear App Cache")
                                    .font(AMENFont.regular(15))
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Divider().padding(.leading, 16)

                        NavigationLink(destination: PrivacyControlsSettingsView()) {
                            HStack(spacing: 12) {
                                Image(systemName: "hand.raised.fill")
                                    .frame(width: 24)
                                    .foregroundStyle(.indigo)
                                Text("Data & Privacy Controls")
                                    .font(AMENFont.regular(15))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.systemScaled(12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    Text("Your data belongs to you. Export a copy or manage how AMEN uses your information.")
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    // MARK: — ABOUT
                    Text("ABOUT")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .frame(width: 24)
                                .foregroundStyle(.secondary)
                            Text("Version")
                                .font(AMENFont.regular(15))
                            Spacer()
                            Text("\(appVersion) (\(buildNumber))")
                                .font(AMENFont.regular(14))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        Divider().padding(.leading, 16)

                        Button {
                            if let url = URL(string: "https://amenapp.com/terms") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.text")
                                    .frame(width: 24)
                                    .foregroundStyle(.secondary)
                                Text("Terms of Service")
                                    .font(AMENFont.regular(15))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.systemScaled(11))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Divider().padding(.leading, 16)

                        Button {
                            if let url = URL(string: "https://amenapp.com/privacy") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "lock.doc.fill")
                                    .frame(width: 24)
                                    .foregroundStyle(.secondary)
                                Text("Privacy Policy")
                                    .font(AMENFont.regular(15))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.systemScaled(11))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Divider().padding(.leading, 16)

                        Button {
                            if let url = URL(string: "itms-apps://itunes.apple.com/app/id0000000000?action=write-review") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "star.fill")
                                    .frame(width: 24)
                                    .foregroundStyle(.yellow)
                                Text("Rate AMEN")
                                    .font(AMENFont.regular(15))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.systemScaled(11))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    // MARK: — ACCOUNT
                    Text("ACCOUNT")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        // Sign Out
                        Button {
                            showSignOutConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Sign Out")
                                        .font(AMENFont.semiBold(15))
                                    Text("You'll need to sign in again to access your account")
                                        .font(AMENFont.regular(12))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    // MARK: — DANGER ZONE
                    Text("DANGER ZONE")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        // Deactivate (temporary — 30-day reversible)
                        Button {
                            showDeactivateAccount = true
                        } label: {
                            HStack {
                                Image(systemName: "pause.circle")
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Deactivate Account")
                                        .font(AMENFont.semiBold(15))
                                    Text("Temporarily hide your profile · reversible for 30 days")
                                        .font(AMENFont.regular(12))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Divider().padding(.leading, 56)

                        // Delete (permanent)
                        Button {
                            showDeleteAccount = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                    .frame(width: 24)
                                Text("Delete Account")
                                    .font(AMENFont.semiBold(15))
                            }
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    Spacer(minLength: 32)
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Account Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(AMENFont.semiBold(16))
                }
            }
            .sheet(isPresented: $showChangeDisplayName) {
                ChangeDisplayNameView()
            }
            .sheet(isPresented: $showChangeUsername) {
                ChangeUsernameView()
            }
            .sheet(isPresented: $showChangeEmail) {
                ChangeEmailView()
            }
            .sheet(isPresented: $showChangePassword) {
                ChangePasswordView()
            }
            .sheet(isPresented: $showDeactivateAccount) {
                AccountDeactivationView()
            }
            .sheet(isPresented: $showDeleteAccount) {
                DeleteAccountView()
            }
            .sheet(isPresented: $showPrivacyDashboard) {
                PrivacyDashboardView()
            }
            .amenAlert(isPresented: $showSignOutConfirmation, config: LiquidGlassAlertConfig(
                title: "Sign Out?",
                message: "You'll need to sign in again to access your account.",
                icon: "rectangle.portrait.and.arrow.right",
                primaryButton: LiquidGlassAlertButton("Sign Out", tone: .destructive) {
                    authViewModel.signOut()
                },
                secondaryButton: .cancel()
            ))
            .onAppear {
                Task {
                    await userService.fetchCurrentUser()
                    await loadPrivateAccountStatus()
                    await loadAgeInfo()
                    await loadAMENPrivacySettings()
                    await loadContentPreferences()
                }
            }
        }
    }
    
    // MARK: - Interaction Permission Row

    @ViewBuilder
    private func interactionPermissionRow(
        icon: String,
        iconColor: Color,
        title: String,
        current: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        let labels: [String: String] = [
            "everyone":  "Everyone",
            "following": "People I Follow",
            "nobody":    "Nobody"
        ]
        let displayValue = labels[current] ?? "Everyone"

        Menu {
            ForEach(["everyone", "following", "nobody"], id: \.self) { option in
                Button {
                    HapticManager.impact(style: .light)
                    onSelect(option)
                } label: {
                    HStack {
                        Text(labels[option] ?? option)
                        if current == option {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .frame(width: 24)
                Text(title)
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(.primary)
                Spacer()
                Text(displayValue)
                    .font(AMENFont.regular(15))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Private Account Helpers

    private func loadPrivateAccountStatus() async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        do {
            lazy var db = Firestore.firestore()
            let userDoc = try await db.collection("users").document(currentUserId).getDocument()
            
            if let isPrivate = userDoc.data()?["isPrivateAccount"] as? Bool {
                await MainActor.run {
                    self.isPrivateAccount = isPrivate
                }
                dlog("✅ Loaded private account status: \(isPrivate)")
            }
        } catch {
            dlog("❌ Failed to load private account status: \(error)")
        }
    }
    
    private func togglePrivateAccount(newValue: Bool) async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        isTogglingPrivacy = true
        defer { isTogglingPrivacy = false }
        
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        do {
            lazy var db = Firestore.firestore()
            try await db.collection("users").document(currentUserId).updateData([
                "isPrivateAccount": newValue
            ])
            
            dlog("✅ Updated private account status to: \(newValue)")

            // Invalidate PrivacyAccessControl cache so all views immediately reflect the change.
            // This covers profile views, feed scoring, and comment gates for the current user.
            PrivacyAccessControl.shared.invalidateAll()
            NotificationCenter.default.post(name: .followRelationshipChanged, object: nil)

            // Success haptic
            let successHaptic = UINotificationFeedbackGenerator()
            successHaptic.notificationOccurred(.success)
            
        } catch {
            dlog("❌ Failed to update private account status: \(error)")
            
            // Rollback on error
            await MainActor.run {
                isPrivateAccount = !newValue
            }
            
            // Error haptic
            let errorHaptic = UINotificationFeedbackGenerator()
            errorHaptic.notificationOccurred(.error)
        }
    }

    private func loadAgeInfo() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let doc = try await Firestore.firestore().collection("users").document(uid).getDocument()
            let data = doc.data() ?? [:]
            await MainActor.run {
                birthYear   = data["birthYear"] as? Int
                ageTierRaw  = data["ageTier"]   as? String
            }
        } catch {
            dlog("❌ Failed to load age info: \(error)")
        }
    }

    // MARK: - AMEN Privacy Settings

    private func loadAMENPrivacySettings() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let doc = try await Firestore.firestore()
                .collection("users").document(uid)
                .collection("settings").document("privacy")
                .getDocument()
            let data = doc.data() ?? [:]
            await MainActor.run {
                prayerRequestsVisibility = data["prayerRequestsVisibility"] as? String ?? "followers"
                testimoniesVisibility    = data["testimoniesVisibility"]    as? String ?? "followers"
                mentionPermission        = data["mentionPermission"]        as? String ?? "everyone"
                replyPermission          = data["replyPermission"]          as? String ?? "everyone"
            }
        } catch {
            dlog("⚠️ loadAMENPrivacySettings: \(error.localizedDescription)")
        }
    }

    private func savePrivacySetting(_ key: String, value: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await Firestore.firestore()
                .collection("users").document(uid)
                .collection("settings").document("privacy")
                .setData([key: value, "updatedAt": FieldValue.serverTimestamp()], merge: true)
        } catch {
            dlog("⚠️ savePrivacySetting \(key): \(error.localizedDescription)")
        }
    }

    // MARK: - Content Preferences

    private func loadContentPreferences() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let doc = try await Firestore.firestore()
                .collection("users").document(uid)
                .collection("settings").document("contentPreferences")
                .getDocument()
            let data = doc.data() ?? [:]
            await MainActor.run {
                filterMatureContent       = data["filterMatureContent"]  as? Bool ?? true
                showFaithBasedSuggestions = data["faithSuggestions"]     as? Bool ?? true
                autoPlayVideos            = data["autoPlayVideos"]        as? Bool ?? true
            }
        } catch {
            dlog("⚠️ loadContentPreferences: \(error.localizedDescription)")
        }
    }

    private func savePreference(_ key: String, value: Bool) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await Firestore.firestore()
                .collection("users").document(uid)
                .collection("settings").document("contentPreferences")
                .setData([key: value, "updatedAt": FieldValue.serverTimestamp()], merge: true)
        } catch {
            dlog("⚠️ savePreference \(key): \(error.localizedDescription)")
        }
    }

    // MARK: - Data & Permissions Helpers

    private func exportUserData() {
        guard let uid = Auth.auth().currentUser?.uid,
              let email = Auth.auth().currentUser?.email else { return }
        let body = "Hi AMEN team,\n\nPlease send me a copy of all data associated with my account.\n\nUser ID: \(uid)\nEmail: \(email)\n\nThank you."
        let subject = "Data Export Request"
        let encoded = "mailto:privacy@amenapp.com?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&body=\(body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        if let url = URL(string: encoded) {
            UIApplication.shared.open(url)
        }
    }

    private func clearCache() {
        URLCache.shared.removeAllCachedResponses()
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }
}

// MARK: - Change Display Name View

struct ChangeDisplayNameView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var userService = UserService()
    
    @State private var newDisplayName = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showSuccess = false
    
    private var canChange: Bool {
        guard let user = userService.currentUser else { return false }
        
        // Check if there's a pending change
        if user.pendingDisplayNameChange != nil {
            return false
        }
        
        // Check 30-day cooldown
        if let lastChange = user.lastDisplayNameChange {
            let daysSinceLastChange = Calendar.current.dateComponents([.day], from: lastChange, to: Date()).day ?? 0
            return daysSinceLastChange >= 30
        }
        
        return true
    }
    
    private var daysUntilNextChange: Int {
        guard let user = userService.currentUser,
              let lastChange = user.lastDisplayNameChange else {
            return 0
        }
        
        let daysSinceLastChange = Calendar.current.dateComponents([.day], from: lastChange, to: Date()).day ?? 0
        return max(0, 30 - daysSinceLastChange)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Info Section
                    VStack(spacing: 16) {
                        Image(systemName: "person.circle.fill")
                            .font(.systemScaled(60))
                            .foregroundStyle(.blue)
                            .padding(.top, 20)
                        
                        Text("Change Display Name")
                            .font(AMENFont.bold(24))
                        
                        if let user = userService.currentUser {
                            Text("Current: \(user.displayName)")
                                .font(AMENFont.regular(15))
                                .foregroundStyle(.secondary)
                            
                            if let pending = user.pendingDisplayNameChange {
                                VStack(spacing: 8) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "clock.fill")
                                            .foregroundStyle(.orange)
                                        Text("Pending Review")
                                            .font(AMENFont.bold(14))
                                            .foregroundStyle(.orange)
                                    }
                                    
                                    Text("New name: \(pending)")
                                        .font(AMENFont.regular(14))
                                        .foregroundStyle(.secondary)
                                    
                                    Text("Your request is being reviewed. This may take 24-48 hours.")
                                        .font(AMENFont.regular(12))
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.orange.opacity(0.1))
                                )
                                .padding(.horizontal)
                            }
                        }
                    }
                    
                    if canChange {
                        // Change Form
                        VStack(alignment: .leading, spacing: 16) {
                            Text("New Display Name")
                                .font(AMENFont.semiBold(14))
                                .foregroundStyle(.secondary)
                            
                            TextField("Enter new display name", text: $newDisplayName)
                                .font(AMENFont.regular(15))
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                            
                            // Info Card
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: "info.circle.fill")
                                        .foregroundStyle(.blue)
                                    Text("Important Information")
                                        .font(AMENFont.bold(14))
                                }
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    InfoRow(icon: "clock", text: "Changes can be made once every 30 days")
                                    InfoRow(icon: "hourglass", text: "Review process takes 24-48 hours")
                                    InfoRow(icon: "checkmark.circle", text: "You'll be notified when approved")
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.blue.opacity(0.05))
                            )
                            
                            Button {
                                submitChange()
                            } label: {
                                HStack {
                                    if isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        Text("Submit Request")
                                            .font(AMENFont.bold(16))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .foregroundStyle(.white)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(newDisplayName.count >= 2 ? Color.blue : Color.gray)
                                )
                            }
                            .disabled(newDisplayName.count < 2 || isLoading)
                            .padding(.top)
                        }
                        .padding(.horizontal)
                    } else if daysUntilNextChange > 0 {
                        // Cooldown Message
                        VStack(spacing: 12) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.systemScaled(50))
                                .foregroundStyle(.orange)
                            
                            Text("Please Wait")
                                .font(AMENFont.bold(20))
                            
                            Text("You can change your display name again in \(daysUntilNextChange) day\(daysUntilNextChange == 1 ? "" : "s")")
                                .font(AMENFont.regular(15))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .padding()
                    }
                    
                    Spacer(minLength: 40)
                }
            }
            .navigationTitle("Change Display Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Success", isPresented: $showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Your display name change request has been submitted! We'll review it within 24-48 hours.")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
            .onAppear {
                Task {
                    await userService.fetchCurrentUser()
                }
            }
        }
    }
    
    private func submitChange() {
        guard !newDisplayName.isEmpty else { return }
        
        isLoading = true
        
        Task {
            // 🛡️ Profile name safety check before saving
            let safetyDecision = UnifiedSafetyGate.shared.evaluateProfileField(
                text: newDisplayName,
                surface: .profileName
            )
            switch safetyDecision {
            case .block(let reason, _), .escalate(let reason, _):
                await MainActor.run {
                    isLoading = false
                    errorMessage = reason
                    showError = true
                }
                return
            case .requireEdit(let violation, _):
                await MainActor.run {
                    isLoading = false
                    errorMessage = violation
                    showError = true
                }
                return
            default:
                break
            }

            do {
                // Request display name change (goes to pending)
                try await userService.requestDisplayNameChange(newDisplayName: newDisplayName)
                
                await MainActor.run {
                    isLoading = false
                    showSuccess = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

// MARK: - Change Username View

struct ChangeUsernameView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var userService = UserService()
    
    @State private var newUsername = ""
    @State private var isChecking = false
    @State private var isAvailable: Bool?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showSuccess = false
    
    private var canChange: Bool {
        guard let user = userService.currentUser else { return false }
        
        // Check if there's a pending change
        if user.pendingUsernameChange != nil {
            return false
        }
        
        // Check 30-day cooldown
        if let lastChange = user.lastUsernameChange {
            let daysSinceLastChange = Calendar.current.dateComponents([.day], from: lastChange, to: Date()).day ?? 0
            return daysSinceLastChange >= 30
        }
        
        return true
    }
    
    private var daysUntilNextChange: Int {
        guard let user = userService.currentUser,
              let lastChange = user.lastUsernameChange else {
            return 0
        }
        
        let daysSinceLastChange = Calendar.current.dateComponents([.day], from: lastChange, to: Date()).day ?? 0
        return max(0, 30 - daysSinceLastChange)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Info Section
                    VStack(spacing: 16) {
                        Image(systemName: "at.circle.fill")
                            .font(.systemScaled(60))
                            .foregroundStyle(.purple)
                            .padding(.top, 20)
                        
                        Text("Change Username")
                            .font(AMENFont.bold(24))
                        
                        if let user = userService.currentUser {
                            Text("Current: @\(user.username)")
                                .font(AMENFont.regular(15))
                                .foregroundStyle(.secondary)
                            
                            if let pending = user.pendingUsernameChange {
                                VStack(spacing: 8) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "clock.fill")
                                            .foregroundStyle(.orange)
                                        Text("Pending Review")
                                            .font(AMENFont.bold(14))
                                            .foregroundStyle(.orange)
                                    }
                                    
                                    Text("New username: @\(pending)")
                                        .font(AMENFont.regular(14))
                                        .foregroundStyle(.secondary)
                                    
                                    Text("Your request is being reviewed. This may take 24-48 hours.")
                                        .font(AMENFont.regular(12))
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.orange.opacity(0.1))
                                )
                                .padding(.horizontal)
                            }
                        }
                    }
                    
                    if canChange {
                        // Change Form
                        VStack(alignment: .leading, spacing: 16) {
                            Text("New Username")
                                .font(AMENFont.semiBold(14))
                                .foregroundStyle(.secondary)
                            
                            HStack {
                                Text("@")
                                    .font(AMENFont.regular(15))
                                    .foregroundStyle(.secondary)
                                
                                TextField("username", text: $newUsername)
                                    .font(AMENFont.regular(15))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .onChange(of: newUsername) { _, newValue in
                                        checkUsernameAvailability(newValue)
                                    }
                                
                                if isChecking {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else if let available = isAvailable {
                                    Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundStyle(available ? .green : .red)
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                            
                            // Availability feedback
                            if let available = isAvailable {
                                Text(available ? "✓ @\(newUsername) is available!" : "✗ @\(newUsername) is already taken")
                                    .font(AMENFont.regular(13))
                                    .foregroundStyle(available ? .green : .red)
                            }
                            
                            // Info Card
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: "info.circle.fill")
                                        .foregroundStyle(.purple)
                                    Text("Important Information")
                                        .font(AMENFont.bold(14))
                                }
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    InfoRow(icon: "textformat", text: "3-20 characters, lowercase letters, numbers, and underscores only")
                                    InfoRow(icon: "sparkles", text: "Example: sarah2025, john_smith, user123")
                                    InfoRow(icon: "clock", text: "Changes can be made once every 30 days")
                                    InfoRow(icon: "hourglass", text: "Review process takes 24-48 hours")
                                    InfoRow(icon: "checkmark.circle", text: "You'll be notified when approved")
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.purple.opacity(0.05))
                            )
                            
                            Button {
                                submitChange()
                            } label: {
                                HStack {
                                    if isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        Text("Submit Request")
                                            .font(AMENFont.bold(16))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .foregroundStyle(.white)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(isAvailable == true ? Color.purple : Color.gray)
                                )
                            }
                            .disabled(isAvailable != true || isLoading)
                            .padding(.top)
                        }
                        .padding(.horizontal)
                    } else if daysUntilNextChange > 0 {
                        // Cooldown Message
                        VStack(spacing: 12) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.systemScaled(50))
                                .foregroundStyle(.orange)
                            
                            Text("Please Wait")
                                .font(AMENFont.bold(20))
                            
                            Text("You can change your username again in \(daysUntilNextChange) day\(daysUntilNextChange == 1 ? "" : "s")")
                                .font(AMENFont.regular(15))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .padding()
                    }
                    
                    Spacer(minLength: 40)
                }
            }
            .navigationTitle("Change Username")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Success", isPresented: $showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Your username change request has been submitted! We'll review it within 24-48 hours.")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
            .onAppear {
                Task {
                    await userService.fetchCurrentUser()
                }
            }
        }
    }
    
    private func checkUsernameAvailability(_ username: String) {
        guard !username.isEmpty else {
            isAvailable = nil
            return
        }
        
        isChecking = true
        isAvailable = nil
        
        Task {
            // Debounce
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            let cleaned = username.lowercased().trimmingCharacters(in: .whitespaces)
            
            // Validate format
            let usernameRegex = "^[a-z0-9_]{3,20}$"
            let predicate = NSPredicate(format: "SELF MATCHES %@", usernameRegex)
            guard predicate.evaluate(with: cleaned) else {
                await MainActor.run {
                    isChecking = false
                    isAvailable = false
                }
                return
            }
            
            do {
                let available = try await userService.isUsernameAvailable(cleaned)
                await MainActor.run {
                    isChecking = false
                    isAvailable = available
                }
            } catch {
                await MainActor.run {
                    isChecking = false
                    isAvailable = false
                }
            }
        }
    }
    
    private func submitChange() {
        guard let isAvailable = isAvailable, isAvailable else { return }
        
        isLoading = true
        
        Task {
            do {
                // Request username change (goes to pending)
                try await userService.requestUsernameChange(newUsername: newUsername.lowercased())
                
                await MainActor.run {
                    isLoading = false
                    showSuccess = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

// MARK: - Helper Views

struct InfoRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.systemScaled(12))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            
            Text(text)
                .font(AMENFont.regular(12))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Change Email View

struct ChangeEmailView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var authViewModel = AuthenticationViewModel()
    @StateObject private var userService = UserService()
    
    @State private var newEmail = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showSuccess = false
    
    private var isPasswordlessUser: Bool {
        authViewModel.isPasswordlessUser()
    }
    
    private var authProviderName: String {
        authViewModel.getAuthProviderName()
    }
    
    private var isValidEmail: Bool {
        let emailRegex = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return predicate.evaluate(with: newEmail)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: isPasswordlessUser ? (authProviderName == "Apple ID" ? "apple.logo" : "globe") : "envelope.fill")
                            .font(.systemScaled(60))
                            .foregroundStyle(isPasswordlessUser ? .orange : .blue)
                            .padding(.top, 20)
                        
                        Text(isPasswordlessUser ? "Email Change Not Available" : "Change Email")
                            .font(AMENFont.bold(24))
                        
                        Text(isPasswordlessUser ? "You signed in with \(authProviderName)" : "Enter your new email address")
                            .font(AMENFont.regular(14))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    
                    // Show info card for passwordless users
                    if isPasswordlessUser {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(.blue)
                                Text("About Your Account")
                                    .font(AMENFont.bold(16))
                            }
                            
                            Text("Your account is managed by \(authProviderName). To change your email, update it through your \(authProviderName) account settings.")
                                .font(AMENFont.regular(14))
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    } else {
                        // Email change form for password-based users
                        VStack(spacing: 20) {
                            // New Email Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("New Email")
                                    .font(AMENFont.semiBold(13))
                                    .foregroundStyle(.secondary)
                                
                                TextField("", text: $newEmail)
                                    .textContentType(.emailAddress)
                                    .keyboardType(.emailAddress)
                                    .autocapitalization(.none)
                                    .font(AMENFont.regular(16))
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(newEmail.isEmpty ? Color.clear : (isValidEmail ? Color.green : Color.red), lineWidth: 1)
                                    )
                                
                                if !newEmail.isEmpty && !isValidEmail {
                                    Text("Please enter a valid email address")
                                        .font(AMENFont.regular(12))
                                        .foregroundStyle(.red)
                                }
                            }
                            
                            // Current Password Field (for re-authentication)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Current Password")
                                    .font(AMENFont.semiBold(13))
                                    .foregroundStyle(.secondary)
                                
                                SecureField("", text: $password)
                                    .textContentType(.password)
                                    .font(AMENFont.regular(16))
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                            }
                            
                            // Info
                            VStack(alignment: .leading, spacing: 12) {
                                InfoRow(icon: "checkmark.circle.fill", text: "You'll receive a verification email at your new address")
                                InfoRow(icon: "lock.fill", text: "For security, we need your current password")
                                InfoRow(icon: "envelope.badge.fill", text: "Your old email will receive a confirmation notice")
                            }
                            .padding(.vertical, 8)
                            
                            // Change Email Button
                            Button {
                                HapticManager.impact(style: .light)
                                changeEmail()
                            } label: {
                                ZStack {
                                    if isLoading {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Text("Change Email")
                                            .font(AMENFont.semiBold(16))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(isValidEmail && !password.isEmpty && !isLoading ? Color.blue : Color.gray)
                                )
                            }
                            .disabled(!isValidEmail || password.isEmpty || isLoading)
                            .padding(.top)
                        }
                        .padding(.horizontal)
                    }
                    
                    Spacer(minLength: 40)
                }
            }
            .navigationTitle("Change Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Success", isPresented: $showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Email updated successfully! Please check your new email for verification.")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
        }
    }
    
    private func changeEmail() {
        guard isValidEmail && !password.isEmpty else { return }
        
        isLoading = true
        
        Task {
            do {
                // Re-authenticate first
                try await authViewModel.reauthenticate(password: password)
                
                // Change email
                try await authViewModel.updateEmail(newEmail: newEmail)
                
                // Update in Firestore
                try await userService.updateUserEmail(newEmail: newEmail)
                
                await MainActor.run {
                    isLoading = false
                    showSuccess = true
                    HapticManager.notification(type: .success)
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                    HapticManager.notification(type: .error)
                }
            }
        }
    }
}

// MARK: - Change Password View

struct ChangePasswordView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var authViewModel = AuthenticationViewModel()
    
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showSuccess = false
    
    private var isPasswordlessUser: Bool {
        authViewModel.isPasswordlessUser()
    }
    
    private var authProviderName: String {
        authViewModel.getAuthProviderName()
    }
    
    private var isValidPassword: Bool {
        newPassword.count >= 8 && newPassword == confirmPassword
    }
    
    private var passwordStrength: PasswordStrength {
        if newPassword.isEmpty { return .none }
        if newPassword.count < 8 { return .weak }
        
        let hasUppercase = newPassword.range(of: "[A-Z]", options: .regularExpression) != nil
        let hasLowercase = newPassword.range(of: "[a-z]", options: .regularExpression) != nil
        let hasNumber = newPassword.range(of: "[0-9]", options: .regularExpression) != nil
        let hasSpecial = newPassword.range(of: "[!@#$%^&*(),.?\":{}|<>]", options: .regularExpression) != nil
        
        let criteria = [hasUppercase, hasLowercase, hasNumber, hasSpecial].filter { $0 }.count
        
        if criteria >= 3 && newPassword.count >= 12 { return .strong }
        if criteria >= 2 && newPassword.count >= 8 { return .medium }
        return .weak
    }
    
    enum PasswordStrength {
        case none, weak, medium, strong
        
        var color: Color {
            switch self {
            case .none: return .gray
            case .weak: return .red
            case .medium: return .orange
            case .strong: return .green
            }
        }
        
        var text: String {
            switch self {
            case .none: return ""
            case .weak: return "Weak"
            case .medium: return "Medium"
            case .strong: return "Strong"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: isPasswordlessUser ? (authProviderName == "Apple ID" ? "apple.logo" : "globe") : "lock.shield.fill")
                            .font(.systemScaled(60))
                            .foregroundStyle(isPasswordlessUser ? .orange : .blue)
                            .padding(.top, 20)
                        
                        Text(isPasswordlessUser ? "Password Not Available" : "Change Password")
                            .font(AMENFont.bold(24))
                        
                        Text(isPasswordlessUser ? "You signed in with \(authProviderName)" : "Choose a strong password to keep your account secure")
                            .font(AMENFont.regular(14))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    
                    // Show info card for passwordless users
                    if isPasswordlessUser {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(.blue)
                                Text("About Your Account")
                                    .font(AMENFont.bold(16))
                            }
                            
                            VStack(alignment: .leading, spacing: 12) {
                                InfoRow(icon: authProviderName == "Apple ID" ? "apple.logo" : "globe", text: "Your account is secured by \(authProviderName)")
                                InfoRow(icon: "lock.shield", text: "\(authProviderName) manages your authentication")
                                InfoRow(icon: "checkmark.shield", text: "No password needed - your account is secure")
                            }
                            
                            Text("To change your authentication method, you would need to create a new account with email and password.")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue.opacity(0.05))
                        )
                        .padding(.horizontal)
                        
                        Spacer()
                    }
                    
                    // Password Fields (only for email users)
                    if !isPasswordlessUser {
                        VStack(spacing: 20) {
                            // Current Password
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Current Password")
                                    .font(AMENFont.semiBold(14))
                                    .foregroundStyle(.secondary)
                                
                                SecureField("Enter current password", text: $currentPassword)
                                    .font(AMENFont.regular(15))
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                    )
                            }
                        
                        // New Password
                        VStack(alignment: .leading, spacing: 8) {
                            Text("New Password")
                                .font(AMENFont.semiBold(14))
                                .foregroundStyle(.secondary)
                            
                            SecureField("Enter new password", text: $newPassword)
                                .font(AMENFont.regular(15))
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                            
                            // Password Strength Indicator
                            if !newPassword.isEmpty {
                                HStack(spacing: 8) {
                                    ForEach(0..<3) { index in
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(index < strengthBars ? passwordStrength.color : Color.gray.opacity(0.2))
                                            .frame(height: 4)
                                    }
                                }
                                
                                Text(passwordStrength.text)
                                    .font(AMENFont.semiBold(12))
                                    .foregroundStyle(passwordStrength.color)
                            }
                        }
                        
                        // Confirm Password
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Confirm New Password")
                                .font(AMENFont.semiBold(14))
                                .foregroundStyle(.secondary)
                            
                            SecureField("Confirm new password", text: $confirmPassword)
                                .font(AMENFont.regular(15))
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                            
                            // Password Match Indicator
                            if !confirmPassword.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: newPassword == confirmPassword ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundStyle(newPassword == confirmPassword ? .green : .red)
                                    Text(newPassword == confirmPassword ? "Passwords match" : "Passwords don't match")
                                        .font(AMENFont.regular(12))
                                        .foregroundStyle(newPassword == confirmPassword ? .green : .red)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Requirements
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.blue)
                            Text("Password Requirements")
                                .font(AMENFont.bold(14))
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            RequirementRow(met: newPassword.count >= 8, text: "At least 8 characters")
                            RequirementRow(met: newPassword.range(of: "[A-Z]", options: .regularExpression) != nil, text: "One uppercase letter")
                            RequirementRow(met: newPassword.range(of: "[a-z]", options: .regularExpression) != nil, text: "One lowercase letter")
                            RequirementRow(met: newPassword.range(of: "[0-9]", options: .regularExpression) != nil, text: "One number")
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.05))
                    )
                        .padding(.horizontal)
                        
                        // Change Button (only for email users)
                        Button {
                            changePassword()
                        } label: {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text("Change Password")
                                        .font(AMENFont.bold(16))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .foregroundStyle(.white)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isValidPassword && !currentPassword.isEmpty ? Color.blue : Color.gray)
                            )
                        }
                        .disabled(!isValidPassword || currentPassword.isEmpty || isLoading)
                        .padding(.horizontal)
                        .padding(.top)
                    } // End if !isPasswordlessUser
                }
                .padding(.bottom, 40)
            }
            .navigationTitle("Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Success", isPresented: $showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Your password has been changed successfully!")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Failed to change password")
            }
        }
    }
    
    private var strengthBars: Int {
        switch passwordStrength {
        case .none, .weak: return 1
        case .medium: return 2
        case .strong: return 3
        }
    }
    
    private func changePassword() {
        isLoading = true
        
        Task {
            do {
                try await authViewModel.changePassword(
                    currentPassword: currentPassword,
                    newPassword: newPassword
                )
                
                await MainActor.run {
                    isLoading = false
                    showSuccess = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

struct RequirementRow: View {
    let met: Bool
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .font(.systemScaled(14))
                .foregroundStyle(met ? .green : .gray)
            
            Text(text)
                .font(AMENFont.regular(13))
                .foregroundStyle(met ? .primary : .secondary)
        }
    }
}

// MARK: - Preview

// DeleteAccountView is defined in DeleteAccountView.swift
// ProfileVisibilitySettingsView is defined in SettingsDestinationViews.swift

#Preview {
    AccountSettingsView()
}

