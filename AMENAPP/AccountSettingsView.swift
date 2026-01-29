//
//  AccountSettingsView.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//

import SwiftUI

// MARK: - Account Settings View

struct AccountSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var userService = UserService()
    
    @State private var showChangeUsername = false
    @State private var showChangeDisplayName = false
    @State private var showChangeEmail = false
    @State private var showChangePassword = false
    @State private var showDeleteAccount = false
    
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
                    
                    // Email (read-only)
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Email")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(.primary)
                            
                            if let user = userService.currentUser {
                                Text(user.email)
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
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
                
                Section {
                    NavigationLink(destination: ProfileVisibilitySettingsView()) {
                        HStack {
                            Image(systemName: "eye")
                                .frame(width: 24)
                            Text("Profile Visibility")
                                .font(.custom("OpenSans-Regular", size: 15))
                        }
                    }
                } header: {
                    Text("PRIVACY")
                        .font(.custom("OpenSans-Bold", size: 12))
                } footer: {
                    Text("Control what information is visible on your public profile")
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
            .sheet(isPresented: $showChangePassword) {
                ChangePasswordView()
            }
            .sheet(isPresented: $showDeleteAccount) {
                DeleteAccountView()
            }
            .onAppear {
                Task {
                    await userService.fetchCurrentUser()
                }
            }
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

// MARK: - Change Password View

struct ChangePasswordView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showSuccess = false
    
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
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.blue)
                            .padding(.top, 20)
                        
                        Text("Change Password")
                            .font(.custom("OpenSans-Bold", size: 24))
                        
                        Text("Choose a strong password to keep your account secure")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    
                    // Password Fields
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
                    
                    // Change Button
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

// MARK: - Delete Account View

struct DeleteAccountView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @StateObject private var userService = UserService()
    
    @State private var password = ""
    @State private var confirmText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var agreedToTerms = false
    
    private let requiredText = "DELETE MY ACCOUNT"
    
    private var canDelete: Bool {
        !password.isEmpty && confirmText == requiredText && agreedToTerms
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Warning Header
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 70))
                            .foregroundStyle(.red)
                            .padding(.top, 20)
                        
                        Text("Delete Account")
                            .font(.custom("OpenSans-Bold", size: 28))
                            .foregroundStyle(.red)
                        
                        Text("This action is permanent and cannot be undone")
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    
                    // What will be deleted
                    VStack(alignment: .leading, spacing: 16) {
                        Text("What will be permanently deleted:")
                            .font(.custom("OpenSans-Bold", size: 16))
                        
                        VStack(alignment: .leading, spacing: 12) {
                            DeletedItemRow(icon: "person.fill", text: "Your profile and account information")
                            DeletedItemRow(icon: "doc.text.fill", text: "All your posts and testimonies")
                            DeletedItemRow(icon: "bubble.left.fill", text: "All your comments and replies")
                            DeletedItemRow(icon: "hands.sparkles.fill", text: "Your prayer requests and responses")
                            DeletedItemRow(icon: "bookmark.fill", text: "Your saved content")
                            DeletedItemRow(icon: "person.2.fill", text: "Your follower/following connections")
                            DeletedItemRow(icon: "message.fill", text: "Your direct messages")
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red.opacity(0.05))
                    )
                    .padding(.horizontal)
                    
                    // Confirmation Steps
                    VStack(alignment: .leading, spacing: 20) {
                        Text("To confirm, please:")
                            .font(.custom("OpenSans-Bold", size: 16))
                        
                        // Step 1: Password
                        VStack(alignment: .leading, spacing: 8) {
                            Text("1. Enter your password")
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(.secondary)
                            
                            SecureField("Password", text: $password)
                                .font(.custom("OpenSans-Regular", size: 15))
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                                )
                        }
                        
                        // Step 2: Type confirmation
                        VStack(alignment: .leading, spacing: 8) {
                            Text("2. Type '\(requiredText)' below")
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(.secondary)
                            
                            TextField("Type here", text: $confirmText)
                                .font(.custom("OpenSans-Regular", size: 15))
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(confirmText == requiredText ? Color.green : Color.red.opacity(0.3), lineWidth: 1)
                                )
                            
                            if !confirmText.isEmpty && confirmText != requiredText {
                                Text("Text doesn't match")
                                    .font(.custom("OpenSans-Regular", size: 12))
                                    .foregroundStyle(.red)
                            } else if confirmText == requiredText {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Match confirmed")
                                        .font(.custom("OpenSans-Regular", size: 12))
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        
                        // Step 3: Checkbox
                        Toggle(isOn: $agreedToTerms) {
                            Text("I understand this action is permanent and my data cannot be recovered")
                                .font(.custom("OpenSans-Regular", size: 14))
                        }
                        .toggleStyle(CheckboxToggleStyle())
                    }
                    .padding(.horizontal)
                    
                    // Delete Button
                    Button {
                        deleteAccount()
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "trash.fill")
                                Text("Permanently Delete My Account")
                                    .font(.custom("OpenSans-Bold", size: 16))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(canDelete ? Color.red : Color.gray)
                        )
                    }
                    .disabled(!canDelete || isLoading)
                    .padding(.horizontal)
                    .padding(.top)
                }
                .padding(.bottom, 40)
            }
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Failed to delete account")
            }
        }
    }
    
    private func deleteAccount() {
        isLoading = true
        
        Task {
            do {
                try await authViewModel.deleteAccount(password: password)
                
                // Account deleted, user will be signed out automatically
                await MainActor.run {
                    isLoading = false
                    dismiss()
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

struct DeletedItemRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.red)
                .frame(width: 24)
            
            Text(text)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.primary)
        }
    }
}

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 24))
                    .foregroundStyle(configuration.isOn ? .red : .gray)
                
                configuration.label
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Profile Visibility Settings View

struct ProfileVisibilitySettingsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var userService = UserService()
    
    @State private var showInterests = true
    @State private var showSocialLinks = true
    @State private var showBio = true
    @State private var showFollowerCount = true
    @State private var showFollowingCount = true
    @State private var showSavedPosts = false
    @State private var showReposts = true
    @State private var isLoading = false
    
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        Text("About Profile Visibility")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                    }
                    
                    Text("Control what information is visible on your public profile. Hidden items will only be visible to you.")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
            
            Section {
                Toggle(isOn: $showBio) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Show Bio")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Display your bio description")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .onChange(of: showBio) { _, _ in saveSettings() }
                
                Toggle(isOn: $showInterests) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Show Interests")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Display your interest tags")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .onChange(of: showInterests) { _, _ in saveSettings() }
                
                Toggle(isOn: $showSocialLinks) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Show Social Links")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Display links to your social media accounts")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .onChange(of: showSocialLinks) { _, _ in saveSettings() }
            } header: {
                Text("PROFILE INFORMATION")
                    .font(.custom("OpenSans-Bold", size: 12))
            }
            
            Section {
                Toggle(isOn: $showFollowerCount) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Show Follower Count")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Display how many followers you have")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .onChange(of: showFollowerCount) { _, _ in saveSettings() }
                
                Toggle(isOn: $showFollowingCount) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Show Following Count")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Display how many people you follow")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .onChange(of: showFollowingCount) { _, _ in saveSettings() }
            } header: {
                Text("STATISTICS")
                    .font(.custom("OpenSans-Bold", size: 12))
            }
            
            Section {
                Toggle(isOn: $showSavedPosts) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Show Saved Posts")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Allow others to see posts you've saved")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .onChange(of: showSavedPosts) { _, _ in saveSettings() }
                
                Toggle(isOn: $showReposts) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Show Reposts")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                        Text("Display posts you've reposted")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .onChange(of: showReposts) { _, _ in saveSettings() }
            } header: {
                Text("CONTENT")
                    .font(.custom("OpenSans-Bold", size: 12))
            } footer: {
                Text("Note: Hiding saved posts is recommended for privacy. This tab will still be visible to you.")
                    .font(.custom("OpenSans-Regular", size: 12))
            }
            
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Profile Visibility")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadSettings()
        }
    }
    
    private func loadSettings() {
        Task {
            await userService.fetchCurrentUser()
            
            if let user = userService.currentUser {
                await MainActor.run {
                    showInterests = user.showInterests
                    showSocialLinks = user.showSocialLinks
                    showBio = user.showBio
                    showFollowerCount = user.showFollowerCount
                    showFollowingCount = user.showFollowingCount
                    showSavedPosts = user.showSavedPosts
                    showReposts = user.showReposts
                }
            }
        }
    }
    
    private func saveSettings() {
        isLoading = true
        
        Task {
            do {
                try await userService.updateProfileVisibility(
                    showInterests: showInterests,
                    showSocialLinks: showSocialLinks,
                    showBio: showBio,
                    showFollowerCount: showFollowerCount,
                    showFollowingCount: showFollowingCount,
                    showSavedPosts: showSavedPosts,
                    showReposts: showReposts
                )
                
                await MainActor.run {
                    isLoading = false
                }
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            } catch {
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
}

#Preview {
    AccountSettingsView()
}
