//
//  UserSearchFix.swift
//  AMENAPP
//
//  Created by Steph on 1/24/26.
//
//  Utility to fix existing users so they can be searched
//

import Foundation
import FirebaseFirestore

/// Utility class to add searchable lowercase fields to existing users
class UserSearchFix {
    static let shared = UserSearchFix()
    private let db = Firestore.firestore()
    
    private init() {}
    
    /// Fix all existing users by adding lowercase fields
    /// ⚠️ Run this ONCE to migrate existing users
    func fixAllUsers() async throws {
        print("🔧 Starting user search fix...")
        print("📊 This will add 'usernameLowercase' and 'displayNameLowercase' to all users")
        
        let usersRef = db.collection("users")
        let snapshot = try await usersRef.getDocuments()
        
        print("📥 Found \(snapshot.documents.count) users to process")
        
        var fixedCount = 0
        var skippedCount = 0
        var errorCount = 0
        
        for document in snapshot.documents {
            let userId = document.documentID
            let data = document.data()
            
            // Check if fields already exist
            let hasUsernameLowercase = data["usernameLowercase"] != nil
            let hasDisplayNameLowercase = data["displayNameLowercase"] != nil
            
            if hasUsernameLowercase && hasDisplayNameLowercase {
                print("⏭️  User \(userId) already has lowercase fields, skipping")
                skippedCount += 1
                continue
            }
            
            // Get current values
            guard let username = data["username"] as? String,
                  let displayName = data["displayName"] as? String else {
                print("⚠️ User \(userId) missing username or displayName, skipping")
                skippedCount += 1
                continue
            }
            
            // Update with lowercase fields
            do {
                try await usersRef.document(userId).updateData([
                    "usernameLowercase": username.lowercased(),
                    "displayNameLowercase": displayName.lowercased(),
                    "updatedAt": Date()
                ])
                
                print("✅ Fixed user \(userId): @\(username) / \(displayName)")
                fixedCount += 1
                
            } catch {
                print("❌ Failed to fix user \(userId): \(error)")
                errorCount += 1
            }
        }
        
        print("\n🎉 User search fix complete!")
        print("   ✅ Fixed: \(fixedCount) users")
        print("   ⏭️  Skipped: \(skippedCount) users (already had fields)")
        print("   ❌ Errors: \(errorCount) users")
        print("\n💡 Users can now be found in search!")
    }
    
    /// Fix a single user by ID
    func fixUser(userId: String) async throws {
        print("🔧 Fixing user: \(userId)")
        
        let userRef = db.collection("users").document(userId)
        let snapshot = try await userRef.getDocument()
        
        guard snapshot.exists, let data = snapshot.data() else {
            throw NSError(domain: "UserSearchFix", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "User not found"
            ])
        }
        
        guard let username = data["username"] as? String,
              let displayName = data["displayName"] as? String else {
            throw NSError(domain: "UserSearchFix", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "User missing username or displayName"
            ])
        }
        
        try await userRef.updateData([
            "usernameLowercase": username.lowercased(),
            "displayNameLowercase": displayName.lowercased(),
            "updatedAt": Date()
        ])
        
        print("✅ Fixed user \(userId): @\(username) / \(displayName)")
    }
    
    /// Check how many users need fixing
    func checkUsersNeedingFix() async throws -> (needsFix: Int, total: Int) {
        print("🔍 Checking users...")
        
        let snapshot = try await db.collection("users").getDocuments()
        let total = snapshot.documents.count
        
        var needsFix = 0
        
        for document in snapshot.documents {
            let data = document.data()
            let hasUsernameLowercase = data["usernameLowercase"] != nil
            let hasDisplayNameLowercase = data["displayNameLowercase"] != nil
            
            if !hasUsernameLowercase || !hasDisplayNameLowercase {
                needsFix += 1
            }
        }
        
        print("📊 Results:")
        print("   Total users: \(total)")
        print("   Need fix: \(needsFix)")
        print("   Already fixed: \(total - needsFix)")
        
        return (needsFix, total)
    }
}

// MARK: - SwiftUI View to Run the Fix

import SwiftUI

/// Admin view to fix user search
struct UserSearchFixView: View {
    @State private var isRunning = false
    @State private var showResult = false
    @State private var resultMessage = ""
    @State private var checkResults: (needsFix: Int, total: Int)?
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("This tool adds searchable lowercase fields to existing users in Firestore.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    
                    Text("New users automatically get these fields, but existing users need to be migrated.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("About")
                }
                
                Section {
                    Button {
                        Task {
                            await checkUsers()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "magnifyingglass")
                            Text("Check Users")
                            Spacer()
                            if isRunning {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isRunning)
                    
                    if let results = checkResults {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Total Users:")
                                Spacer()
                                Text("\(results.total)")
                                    .bold()
                            }
                            
                            HStack {
                                Text("Need Fix:")
                                Spacer()
                                Text("\(results.needsFix)")
                                    .bold()
                                    .foregroundStyle(results.needsFix > 0 ? .orange : .green)
                            }
                            
                            HStack {
                                Text("Already Fixed:")
                                Spacer()
                                Text("\(results.total - results.needsFix)")
                                    .bold()
                                    .foregroundStyle(.green)
                            }
                        }
                        .font(.footnote)
                        .padding(.vertical, 8)
                    }
                } header: {
                    Text("Status Check")
                }
                
                Section {
                    Button {
                        Task {
                            await fixAllUsers()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "wrench.and.screwdriver.fill")
                            Text("Fix All Users")
                            Spacer()
                            if isRunning {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isRunning || checkResults?.needsFix == 0)
                    
                    Text("⚠️ Only run this once! It will update all users in Firestore.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } header: {
                    Text("Fix Users")
                }
            }
            .navigationTitle("User Search Fix")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Result", isPresented: $showResult) {
                Button("OK") {
                    // Refresh check after fix
                    Task {
                        await checkUsers()
                    }
                }
            } message: {
                Text(resultMessage)
            }
        }
    }
    
    private func checkUsers() async {
        isRunning = true
        defer { isRunning = false }
        
        do {
            let results = try await UserSearchFix.shared.checkUsersNeedingFix()
            checkResults = results
        } catch {
            resultMessage = "Error checking users: \(error.localizedDescription)"
            showResult = true
        }
    }
    
    private func fixAllUsers() async {
        isRunning = true
        defer { isRunning = false }
        
        do {
            try await UserSearchFix.shared.fixAllUsers()
            resultMessage = "✅ Successfully fixed all users! They can now be found in search."
            showResult = true
        } catch {
            resultMessage = "❌ Error: \(error.localizedDescription)"
            showResult = true
        }
    }
}

#Preview {
    UserSearchFixView()
}
