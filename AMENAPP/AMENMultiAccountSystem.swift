//
//  AMENMultiAccountSystem.swift
//  AMENAPP
//
//  Multi-account management system similar to Instagram/Threads.
//  Allows users to:
//  - Add multiple accounts (Personal, Church, Business)
//  - Switch between accounts instantly
//  - Each account maintains separate data, profile, and settings
//  - Fast account switching without full re-authentication
//

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore
import Foundation

// MARK: - Account Model

struct AMENAccount: Identifiable, Codable, Equatable {
    let id: String // Firebase UID
    var name: String
    var username: String
    var email: String
    var profileImageURL: String?
    var accountType: String // "Personal", "Church", "Business", "School", "University"
    var isVerified: Bool
    var lastAccessedAt: Date
    
    static func == (lhs: AMENAccount, rhs: AMENAccount) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Multi-Account Manager

@MainActor
class AMENMultiAccountManager: ObservableObject {
    static let shared = AMENMultiAccountManager()
    
    @Published var accounts: [AMENAccount] = []
    @Published var currentAccount: AMENAccount?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showAccountSwitcher = false
    
    private lazy var db = Firestore.firestore()
    private let maxAccounts = 5 // Instagram allows 5 accounts
    private let accountsKey = "amen.multiaccounts.stored"
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        loadStoredAccounts()
    }
    
    // MARK: - Account Management
    
    /// Load accounts from UserDefaults
    private func loadStoredAccounts() {
        guard let data = UserDefaults.standard.data(forKey: accountsKey),
              let stored = try? JSONDecoder().decode([AMENAccount].self, from: data) else {
            // No stored accounts, try to create one from current user
            if let currentUser = Auth.auth().currentUser {
                Task { await fetchAccountInfo(for: currentUser.uid) }
            }
            return
        }
        
        accounts = stored.sorted { $0.lastAccessedAt > $1.lastAccessedAt }
        
        // Set current account to the most recently accessed
        if let current = accounts.first {
            currentAccount = current
        }
        
        dlog("✅ Loaded \(accounts.count) stored accounts")
    }
    
    /// Save accounts to UserDefaults
    private func saveAccounts() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        UserDefaults.standard.set(data, forKey: accountsKey)
        dlog("💾 Saved \(accounts.count) accounts to storage")
    }
    
    /// Fetch account info from Firestore
    func fetchAccountInfo(for userId: String) async {
        do {
            let doc = try await db.document("users/\(userId)").getDocument()
            guard let data = doc.data() else { return }
            
            let account = AMENAccount(
                id: userId,
                name: data["name"] as? String ?? "User",
                username: data["username"] as? String ?? "",
                email: data["email"] as? String ?? "",
                profileImageURL: data["profileImageURL"] as? String,
                accountType: data["accountType"] as? String ?? "Personal",
                isVerified: data["isVerified"] as? Bool ?? false,
                lastAccessedAt: Date()
            )
            
            // Add or update account
            if let index = accounts.firstIndex(where: { $0.id == userId }) {
                accounts[index] = account
            } else {
                accounts.append(account)
            }
            
            currentAccount = account
            saveAccounts()
            
        } catch {
            dlog("⚠️ Failed to fetch account info: \(error.localizedDescription)")
            errorMessage = "Failed to load account information"
        }
    }
    
    /// Switch to a different account
    func switchAccount(to account: AMENAccount) async -> Bool {
        guard account.id != currentAccount?.id else {
            dlog("ℹ️ Already on account: \(account.username)")
            return true
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // AUTH-02: Tear down all service listeners and flush in-memory caches
            // (PostsManager, UserProfileImageCache, BlockService, notification state, etc.)
            // BEFORE signing out. Without this, User B could see User A's cached posts,
            // profile images, saved posts, or notification badges on first load.
            AppLifecycleManager.shared.performFullSignOutCleanup()

            try Auth.auth().signOut()

            // Update last accessed time for the target account.
            var updatedAccount = account
            updatedAccount.lastAccessedAt = Date()
            
            if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                accounts[index] = updatedAccount
            }
            
            currentAccount = updatedAccount
            saveAccounts()
            
            // Trigger app to show login for this account
            // The app should detect no current user and show auth screen
            
            dlog("✅ Switched to account: \(account.username)")
            return true
            
        } catch {
            dlog("⚠️ Failed to switch account: \(error.localizedDescription)")
            errorMessage = "Failed to switch accounts"
            return false
        }
    }
    
    /// Add a new account
    func addAccount() async -> Bool {
        guard accounts.count < maxAccounts else {
            errorMessage = "Maximum of \(maxAccounts) accounts allowed"
            return false
        }
        
        // Trigger the app to show login screen for adding new account
        // The calling view should handle navigation to login
        return true
    }
    
    /// Remove an account
    func removeAccount(_ account: AMENAccount) {
        accounts.removeAll { $0.id == account.id }
        
        // If removing current account, switch to another
        if currentAccount?.id == account.id {
            currentAccount = accounts.first
        }
        
        saveAccounts()
        dlog("🗑️ Removed account: \(account.username)")
    }
    
    /// Check if can add more accounts
    var canAddAccount: Bool {
        accounts.count < maxAccounts
    }
    
    /// Get account by ID
    func getAccount(by id: String) -> AMENAccount? {
        accounts.first { $0.id == id }
    }
}

// MARK: - Account Switcher View

struct AMENAccountSwitcherView: View {
    @ObservedObject var manager = AMENMultiAccountManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingRemoveAlert = false
    @State private var accountToRemove: AMENAccount?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Current Account Section
                        if let current = manager.currentAccount {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("CURRENT ACCOUNT")
                                    .font(AMENFont.semiBold(11))
                                    .foregroundColor(Color(white: 0.65))
                                    .tracking(1.2)
                                    .padding(.horizontal, 20)
                                
                                AccountRow(
                                    account: current,
                                    isCurrent: true,
                                    onTap: {},
                                    onRemove: nil
                                )
                            }
                            .padding(.top, 24)
                        }
                        
                        // Other Accounts Section
                        if manager.accounts.count > 1 {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("YOUR ACCOUNTS")
                                    .font(AMENFont.semiBold(11))
                                    .foregroundColor(Color(white: 0.65))
                                    .tracking(1.2)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 32)
                                
                                ForEach(manager.accounts.filter { $0.id != manager.currentAccount?.id }) { account in
                                    AccountRow(
                                        account: account,
                                        isCurrent: false,
                                        onTap: {
                                            Task {
                                                let success = await manager.switchAccount(to: account)
                                                if success {
                                                    dismiss()
                                                }
                                            }
                                        },
                                        onRemove: {
                                            accountToRemove = account
                                            showingRemoveAlert = true
                                        }
                                    )
                                }
                            }
                        }
                        
                        // Add Account Button
                        if manager.canAddAccount {
                            Button(action: {
                                Task {
                                    let canAdd = await manager.addAccount()
                                    if canAdd {
                                        // Navigate to login screen
                                        // This should be handled by the calling view
                                        dismiss()
                                    }
                                }
                            }) {
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle()
                                            .fill(Color(white: 0.94))
                                            .frame(width: 48, height: 48)
                                        
                                        Image(systemName: "plus")
                                            .font(.systemScaled(18, weight: .semibold))
                                            .foregroundColor(.black)
                                    }
                                    
                                    Text("Add Account")
                                        .font(AMENFont.semiBold(16))
                                        .foregroundColor(.black)
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                            }
                            .padding(.top, 24)
                        }
                        
                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("Switch Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(AMENFont.semiBold(16))
                    .foregroundColor(.black)
                }
            }
        }
        .alert("Remove Account?", isPresented: $showingRemoveAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                if let account = accountToRemove {
                    manager.removeAccount(account)
                }
            }
        } message: {
            if let account = accountToRemove {
                Text("Remove @\(account.username)? You can always add it back later.")
            }
        }
    }
}

// MARK: - Account Row

private struct AccountRow: View {
    let account: AMENAccount
    let isCurrent: Bool
    let onTap: () -> Void
    let onRemove: (() -> Void)?
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Profile Image
                ZStack {
                    Circle()
                        .fill(Color(white: 0.94))
                        .frame(width: 48, height: 48)
                    
                    if let urlString = account.profileImageURL,
                       let url = URL(string: urlString) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            Image(systemName: "person.fill")
                                .foregroundColor(Color(white: 0.7))
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.fill")
                            .foregroundColor(Color(white: 0.7))
                    }
                }
                
                // Account Info
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(account.username)
                            .font(AMENFont.semiBold(16))
                            .foregroundColor(.black)
                        
                        if account.isVerified {
                            let verificationType = VerificationType(rawValue: account.accountType.lowercased()) ?? .none
                            VerifiedBadge(type: verificationType, size: 14)
                        }
                    }
                    
                    Text(account.accountType)
                        .font(AMENFont.regular(14))
                        .foregroundColor(Color(white: 0.55))
                }
                
                Spacer()
                
                // Checkmark for current account
                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.systemScaled(22))
                        .foregroundColor(.black)
                } else if let onRemove = onRemove {
                    // Remove button for other accounts
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.systemScaled(22))
                            .foregroundColor(Color(white: 0.75))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isCurrent)
    }
}

// MARK: - Account Switcher Button (for Profile/Settings)

struct AMENAccountSwitcherButton: View {
    @ObservedObject var manager = AMENMultiAccountManager.shared
    @State private var showingSwitcher = false
    
    var body: some View {
        Button(action: {
            showingSwitcher = true
        }) {
            HStack(spacing: 8) {
                if let current = manager.currentAccount {
                    Text("@\(current.username)")
                        .font(AMENFont.semiBold(16))
                        .foregroundColor(.black)
                } else {
                    Text("Account")
                        .font(AMENFont.semiBold(16))
                        .foregroundColor(.black)
                }
                
                Image(systemName: "chevron.down")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundColor(Color(white: 0.45))
                
                if manager.accounts.count > 1 {
                    ZStack {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 18, height: 18)
                        
                        Text("\(manager.accounts.count)")
                            .font(.systemScaled(10, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(white: 0.96))
            .cornerRadius(8)
        }
        .sheet(isPresented: $showingSwitcher) {
            AMENAccountSwitcherView()
        }
    }
}

// MARK: - Previews

struct AMENAccountSwitcherView_Previews: PreviewProvider {
    static var previews: some View {
        AMENAccountSwitcherView()
    }
}
