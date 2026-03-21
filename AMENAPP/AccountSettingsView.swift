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
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text(biometricService.isBiometricEnabled ? "Enabled for quick sign-in" : "Tap to enable")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .tint(.green)
            .alert("Enable \(biometricService.biometricType.displayName)?", isPresented: $showBiometricSetup) {
                Button("Cancel", role: .cancel) { }
                Button("Enable") {
                    Task {
                        let success = await biometricService.authenticate(reason: "Enable \(biometricService.biometricType.displayName) for AMEN")
                        if success {
                            biometricService.enableBiometric()
                        }
                    }
                }
            } message: {
                Text("You'll be able to sign in quickly using \(biometricService.biometricType.displayName) instead of entering your password.")
            }
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
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                        
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
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
                        .font(.custom("OpenSans-SemiBold", size: 15))
                    Text("Sundays 6am - 4pm · Focus on worship")
                        .font(.custom("OpenSans-Regular", size: 13))
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
    @StateObject private var userService = UserService()
    
    @State private var showChangeUsername = false
    @State private var showChangeDisplayName = false
    @State private var showChangeEmail = false
    @State private var showChangePassword = false
    @State private var showDeleteAccount = false
    @State private var showPrivacyDashboard = false
    @State private var isPrivateAccount = false
    @State private var isTogglingPrivacy = false

    // Age / DOB (read-only, loaded from Firestore)
    @State private var birthYear: Int? = nil
    @State private var ageTierRaw: String? = nil

    private var ageTierDisplayName: String {
        guard let raw = ageTierRaw, let tier = AgeTier(rawValue: raw) else { return "Unknown" }
        return tier.displayName
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    // Display Name
                    Button {
                        showChangeDisplayName = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Display Name")
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                                    .foregroundStyle(.primary)
                                
                                if let user = userService.currentUser {
                                    Text(user.displayName)
                                        .font(.custom("OpenSans-Regular", size: 13))
                                        .foregroundStyle(.secondary)
                                    
                                    if let pending = user.pendingDisplayNameChange {
                                        Text("Pending: \(pending)")
                                            .font(.custom("OpenSans-Regular", size: 12))
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Username
                    Button {
                        showChangeUsername = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Username")
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                                    .foregroundStyle(.primary)
                                
                                if let user = userService.currentUser {
                                    Text("@\(user.username)")
                                        .font(.custom("OpenSans-Regular", size: 13))
                                        .foregroundStyle(.secondary)
                                    
                                    if let pending = user.pendingUsernameChange {
                                        Text("Pending: @\(pending)")
                                            .font(.custom("OpenSans-Regular", size: 12))
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Email
                    Button {
                        showChangeEmail = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Email")
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                                    .foregroundStyle(.primary)
                                
                                if let user = userService.currentUser {
                                    Text(user.email ?? "No email")
                                        .font(.custom("OpenSans-Regular", size: 13))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Date of Birth (read-only)
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Date of Birth")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(.primary)

                            if let year = birthYear {
                                HStack(spacing: 6) {
                                    Text("Born \(year)")
                                        .font(.custom("OpenSans-Regular", size: 13))
                                        .foregroundStyle(.secondary)
                                    Text("·")
                                        .foregroundStyle(.secondary)
                                    Text(ageTierDisplayName)
                                        .font(.custom("OpenSans-Regular", size: 13))
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("Not set")
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                } header: {
                    Text("ACCOUNT INFORMATION")
                        .font(.custom("OpenSans-Bold", size: 12))
                }
                
                Section {
                    Button {
                        showChangePassword = true
                    } label: {
                        HStack {
                            Image(systemName: "lock")
                                .frame(width: 24)
                            Text("Change Password")
                                .font(.custom("OpenSans-Regular", size: 15))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(PlainButtonStyle())
                } header: {
                    Text("SECURITY")
                        .font(.custom("OpenSans-Bold", size: 12))
                }
                
                // ✅ Biometric Authentication & Account Linking
                Section {
                    BiometricSettingRow()
                    
                    NavigationLink(destination: AccountLinkingView()) {
                        HStack {
                            Image(systemName: "link.circle.fill")
                                .frame(width: 24)
                                .foregroundStyle(.blue)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Linked Accounts")
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                                Text("Manage sign-in methods")
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    NavigationLink(destination: ActiveSessionsView()) {
                        HStack {
                            Image(systemName: "iphone.and.arrow.forward")
                                .frame(width: 24)
                                .foregroundStyle(.purple)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Active Sessions")
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                                Text("View signed-in devices")
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    NavigationLink(destination: TwoFactorAuthView()) {
                        HStack {
                            Image(systemName: "lock.shield.fill")
                                .frame(width: 24)
                                .foregroundStyle(.orange)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Two-Factor Authentication")
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                                Text("Extra security with SMS")
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("AUTHENTICATION")
                        .font(.custom("OpenSans-Bold", size: 12))
                }
                
                Section {
                    // P0 FIX: Private Account Toggle
                    Toggle(isOn: $isPrivateAccount) {
                        HStack(spacing: 12) {
                            Image(systemName: isPrivateAccount ? "lock.fill" : "lock.open.fill")
                                .frame(width: 24)
                                .foregroundStyle(isPrivateAccount ? .blue : .secondary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Private Account")
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                                
                                Text(isPrivateAccount ? "Only approved followers can see your posts" : "Anyone can see your posts")
                                    .font(.custom("OpenSans-Regular", size: 13))
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
                    
                    NavigationLink(destination: ProfileVisibilitySettingsView()) {
                        HStack {
                            Image(systemName: "eye")
                                .frame(width: 24)
                            Text("Profile Visibility")
                                .font(.custom("OpenSans-Regular", size: 15))
                        }
                    }
                    
                    // ✅ Privacy & Contact Controls
                    NavigationLink(destination: PrivacyControlsSettingsView()) {
                        HStack {
                            Image(systemName: "hand.raised.fill")
                                .frame(width: 24)
                                .foregroundStyle(.blue)
                            Text("Privacy & Contact")
                                .font(.custom("OpenSans-Regular", size: 15))
                        }
                    }
                } header: {
                    Text("PRIVACY")
                        .font(.custom("OpenSans-Bold", size: 12))
                } footer: {
                    Text(isPrivateAccount 
                        ? "When your account is private, only people you approve can follow you and see your posts. You'll receive follow requests that you can accept or decline."
                        : "Control who can message you, comment on your posts, and mention you")
                        .font(.custom("OpenSans-Regular", size: 12))
                }
                
                Section {
                    Button {
                        showPrivacyDashboard = true
                    } label: {
                        HStack {
                            Image(systemName: "shield.checkered")
                                .frame(width: 24)
                                .foregroundStyle(.blue)
                            Text("Privacy Dashboard")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(.primary)
                        }
                    }
                } header: {
                    Text("PRIVACY & DATA")
                        .font(.custom("OpenSans-Bold", size: 12))
                }
                
                // ✅ Sunday Church Focus Mode Setting
                Section {
                    SundayChurchFocusSettingRow()
                } header: {
                    Text("CHURCH FOCUS")
                        .font(.custom("OpenSans-Bold", size: 12))
                } footer: {
                    Text("When enabled, social features are limited on Sundays from 6:00 AM - 4:00 PM to encourage church focus. Church Notes and Find a Church remain available.")
                        .font(.custom("OpenSans-Regular", size: 12))
                }
                
                // Translation & Language
                Section {
                    NavigationLink(destination: TranslationSettingsView()) {
                        HStack {
                            Image(systemName: "globe")
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Translation & Language")
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                                Text(TranslationSettingsManager.shared.preferences.contentTranslationMode.displayLabel)
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("LANGUAGE")
                        .font(.custom("OpenSans-Bold", size: 12))
                }

                // ✅ Scroll Budget & Wellbeing Controls
                Section {
                    NavigationLink(destination: ScrollBudgetSettingsView()) {
                        HStack {
                            Image(systemName: "hourglass")
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Scroll Budget")
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                                if ScrollBudgetManager.shared.isEnabled {
                                    Text("\(ScrollBudgetManager.shared.dailyBudgetMinutes) min daily")
                                        .font(.custom("OpenSans-Regular", size: 13))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("WELLBEING")
                        .font(.custom("OpenSans-Bold", size: 12))
                } footer: {
                    Text("Set daily limits for feed scrolling time with supportive nudges and mindful breaks.")
                        .font(.custom("OpenSans-Regular", size: 12))
                }
                
                Section {
                    Button(role: .destructive) {
                        showDeleteAccount = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                                .frame(width: 24)
                            Text("Delete Account")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                        }
                    }
                } header: {
                    Text("DANGER ZONE")
                        .font(.custom("OpenSans-Bold", size: 12))
                }
            }
            .navigationTitle("Account Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
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
            .sheet(isPresented: $showDeleteAccount) {
                DeleteAccountView()
            }
            .sheet(isPresented: $showPrivacyDashboard) {
                PrivacyDashboardView()
            }
            .onAppear {
                Task {
                    await userService.fetchCurrentUser()
                    await loadPrivateAccountStatus()
                    await loadAgeInfo()
                }
            }
        }
    }
    
    // MARK: - Private Account Helpers
    
    private func loadPrivateAccountStatus() async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let db = Firestore.firestore()
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
            let db = Firestore.firestore()
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
                            .font(.system(size: 60))
                            .foregroundStyle(.blue)
                            .padding(.top, 20)
                        
                        Text("Change Display Name")
                            .font(.custom("OpenSans-Bold", size: 24))
                        
                        if let user = userService.currentUser {
                            Text("Current: \(user.displayName)")
                                .font(.custom("OpenSans-Regular", size: 15))
                                .foregroundStyle(.secondary)
                            
                            if let pending = user.pendingDisplayNameChange {
                                VStack(spacing: 8) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "clock.fill")
                                            .foregroundStyle(.orange)
                                        Text("Pending Review")
                                            .font(.custom("OpenSans-Bold", size: 14))
                                            .foregroundStyle(.orange)
                                    }
                                    
                                    Text("New name: \(pending)")
                                        .font(.custom("OpenSans-Regular", size: 14))
                                        .foregroundStyle(.secondary)
                                    
                                    Text("Your request is being reviewed. This may take 24-48 hours.")
                                        .font(.custom("OpenSans-Regular", size: 12))
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
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(.secondary)
                            
                            TextField("Enter new display name", text: $newDisplayName)
                                .font(.custom("OpenSans-Regular", size: 15))
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
                                        .font(.custom("OpenSans-Bold", size: 14))
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
                                            .font(.custom("OpenSans-Bold", size: 16))
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
                                .font(.system(size: 50))
                                .foregroundStyle(.orange)
                            
                            Text("Please Wait")
                                .font(.custom("OpenSans-Bold", size: 20))
                            
                            Text("You can change your display name again in \(daysUntilNextChange) day\(daysUntilNextChange == 1 ? "" : "s")")
                                .font(.custom("OpenSans-Regular", size: 15))
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
                            .font(.system(size: 60))
                            .foregroundStyle(.purple)
                            .padding(.top, 20)
                        
                        Text("Change Username")
                            .font(.custom("OpenSans-Bold", size: 24))
                        
                        if let user = userService.currentUser {
                            Text("Current: @\(user.username)")
                                .font(.custom("OpenSans-Regular", size: 15))
                                .foregroundStyle(.secondary)
                            
                            if let pending = user.pendingUsernameChange {
                                VStack(spacing: 8) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "clock.fill")
                                            .foregroundStyle(.orange)
                                        Text("Pending Review")
                                            .font(.custom("OpenSans-Bold", size: 14))
                                            .foregroundStyle(.orange)
                                    }
                                    
                                    Text("New username: @\(pending)")
                                        .font(.custom("OpenSans-Regular", size: 14))
                                        .foregroundStyle(.secondary)
                                    
                                    Text("Your request is being reviewed. This may take 24-48 hours.")
                                        .font(.custom("OpenSans-Regular", size: 12))
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
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(.secondary)
                            
                            HStack {
                                Text("@")
                                    .font(.custom("OpenSans-Regular", size: 15))
                                    .foregroundStyle(.secondary)
                                
                                TextField("username", text: $newUsername)
                                    .font(.custom("OpenSans-Regular", size: 15))
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
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(available ? .green : .red)
                            }
                            
                            // Info Card
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: "info.circle.fill")
                                        .foregroundStyle(.purple)
                                    Text("Important Information")
                                        .font(.custom("OpenSans-Bold", size: 14))
                                }
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    InfoRow(icon: "textformat", text: "3-20 characters, lowercase letters, numbers, and underscores only")
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
                                            .font(.custom("OpenSans-Bold", size: 16))
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
                                .font(.system(size: 50))
                                .foregroundStyle(.orange)
                            
                            Text("Please Wait")
                                .font(.custom("OpenSans-Bold", size: 20))
                            
                            Text("You can change your username again in \(daysUntilNextChange) day\(daysUntilNextChange == 1 ? "" : "s")")
                                .font(.custom("OpenSans-Regular", size: 15))
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
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            
            Text(text)
                .font(.custom("OpenSans-Regular", size: 12))
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
                            .font(.system(size: 60))
                            .foregroundStyle(isPasswordlessUser ? .orange : .blue)
                            .padding(.top, 20)
                        
                        Text(isPasswordlessUser ? "Email Change Not Available" : "Change Email")
                            .font(.custom("OpenSans-Bold", size: 24))
                        
                        Text(isPasswordlessUser ? "You signed in with \(authProviderName)" : "Enter your new email address")
                            .font(.custom("OpenSans-Regular", size: 14))
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
                                    .font(.custom("OpenSans-Bold", size: 16))
                            }
                            
                            Text("Your account is managed by \(authProviderName). To change your email, update it through your \(authProviderName) account settings.")
                                .font(.custom("OpenSans-Regular", size: 14))
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
                                    .font(.custom("OpenSans-SemiBold", size: 13))
                                    .foregroundStyle(.secondary)
                                
                                TextField("", text: $newEmail)
                                    .textContentType(.emailAddress)
                                    .keyboardType(.emailAddress)
                                    .autocapitalization(.none)
                                    .font(.custom("OpenSans-Regular", size: 16))
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(newEmail.isEmpty ? Color.clear : (isValidEmail ? Color.green : Color.red), lineWidth: 1)
                                    )
                                
                                if !newEmail.isEmpty && !isValidEmail {
                                    Text("Please enter a valid email address")
                                        .font(.custom("OpenSans-Regular", size: 12))
                                        .foregroundStyle(.red)
                                }
                            }
                            
                            // Current Password Field (for re-authentication)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Current Password")
                                    .font(.custom("OpenSans-SemiBold", size: 13))
                                    .foregroundStyle(.secondary)
                                
                                SecureField("", text: $password)
                                    .textContentType(.password)
                                    .font(.custom("OpenSans-Regular", size: 16))
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
                                            .font(.custom("OpenSans-SemiBold", size: 16))
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
                            .font(.system(size: 60))
                            .foregroundStyle(isPasswordlessUser ? .orange : .blue)
                            .padding(.top, 20)
                        
                        Text(isPasswordlessUser ? "Password Not Available" : "Change Password")
                            .font(.custom("OpenSans-Bold", size: 24))
                        
                        Text(isPasswordlessUser ? "You signed in with \(authProviderName)" : "Choose a strong password to keep your account secure")
                            .font(.custom("OpenSans-Regular", size: 14))
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
                                    .font(.custom("OpenSans-Bold", size: 16))
                            }
                            
                            VStack(alignment: .leading, spacing: 12) {
                                InfoRow(icon: authProviderName == "Apple ID" ? "apple.logo" : "globe", text: "Your account is secured by \(authProviderName)")
                                InfoRow(icon: "lock.shield", text: "\(authProviderName) manages your authentication")
                                InfoRow(icon: "checkmark.shield", text: "No password needed - your account is secure")
                            }
                            
                            Text("To change your authentication method, you would need to create a new account with email and password.")
                                .font(.custom("OpenSans-Regular", size: 13))
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
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                                    .foregroundStyle(.secondary)
                                
                                SecureField("Enter current password", text: $currentPassword)
                                    .font(.custom("OpenSans-Regular", size: 15))
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                    )
                            }
                        
                        // New Password
                        VStack(alignment: .leading, spacing: 8) {
                            Text("New Password")
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(.secondary)
                            
                            SecureField("Enter new password", text: $newPassword)
                                .font(.custom("OpenSans-Regular", size: 15))
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
                                    .font(.custom("OpenSans-SemiBold", size: 12))
                                    .foregroundStyle(passwordStrength.color)
                            }
                        }
                        
                        // Confirm Password
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Confirm New Password")
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(.secondary)
                            
                            SecureField("Confirm new password", text: $confirmPassword)
                                .font(.custom("OpenSans-Regular", size: 15))
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
                                        .font(.custom("OpenSans-Regular", size: 12))
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
                                .font(.custom("OpenSans-Bold", size: 14))
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
                                        .font(.custom("OpenSans-Bold", size: 16))
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
                .font(.system(size: 14))
                .foregroundStyle(met ? .green : .gray)
            
            Text(text)
                .font(.custom("OpenSans-Regular", size: 13))
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

