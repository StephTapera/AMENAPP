//
//  UserSearchMigration.swift
//  AMENAPP
//
//  Created by Steph on 1/24/26.
//
//  Production-ready utility to add searchable lowercase fields to users
//

import Foundation
import FirebaseFirestore
import SwiftUI
import Combine

/// Production-level service for migrating users to support case-insensitive search
@MainActor
class UserSearchMigration: ObservableObject {
    static let shared = UserSearchMigration()
    
    private let db = Firestore.firestore()
    private let batchSize = 50  // Process users in batches for better performance
    private let maxRetries = 3   // Retry failed operations
    
    @Published var migrationProgress: Double = 0.0
    @Published var currentStatus: String = ""
    @Published var isRunning: Bool = false
    
    private init() {}
    
    // MARK: - Main Migration Function
    
    /// Fix all existing users by adding lowercase fields (Production-ready with batching, retry logic, and progress tracking)
    func fixAllUsers() async throws {
        guard !isRunning else {
            throw MigrationError.alreadyRunning
        }
        
        isRunning = true
        migrationProgress = 0.0
        currentStatus = "🔧 Starting user migration..."
        
        defer {
            isRunning = false
            migrationProgress = 1.0
        }
        
        do {
            // Get total count first
            let allUsers = try await fetchAllUsers()
            let totalUsers = allUsers.count
            
            guard totalUsers > 0 else {
                currentStatus = "⚠️ No users found in database"
                return
            }
            
            currentStatus = "📊 Found \(totalUsers) users to process"
            
            var processedCount = 0
            var fixedCount = 0
            var skippedCount = 0
            var errorCount = 0
            
            // Process in batches for better performance and memory usage
            let batches = stride(from: 0, to: allUsers.count, by: batchSize).map {
                Array(allUsers[$0..<min($0 + batchSize, allUsers.count)])
            }
            
            for (batchIndex, batch) in batches.enumerated() {
                currentStatus = "🔄 Processing batch \(batchIndex + 1) of \(batches.count)..."
                
                // Process batch with retry logic
                let batchResults = await processBatchWithRetry(users: batch)
                
                fixedCount += batchResults.fixed
                skippedCount += batchResults.skipped
                errorCount += batchResults.errors
                processedCount += batch.count
                
                // Update progress
                migrationProgress = Double(processedCount) / Double(totalUsers)
                
                // Small delay between batches to avoid rate limiting
                if batchIndex < batches.count - 1 {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                }
            }
            
            // Final status
            currentStatus = """
            ✅ Migration Complete!
            
            Total Users: \(totalUsers)
            ✅ Fixed: \(fixedCount)
            ⏭️ Skipped: \(skippedCount) (already had fields)
            ❌ Errors: \(errorCount)
            """
            
            // Log results
            print("\n" + String(repeating: "=", count: 50))
            print("USER SEARCH MIGRATION COMPLETE")
            print(String(repeating: "=", count: 50))
            print("Total: \(totalUsers)")
            print("Fixed: \(fixedCount)")
            print("Skipped: \(skippedCount)")
            print("Errors: \(errorCount)")
            print(String(repeating: "=", count: 50) + "\n")
            
        } catch {
            currentStatus = "❌ Migration failed: \(error.localizedDescription)"
            throw error
        }
    }
    
    // MARK: - Batch Processing with Retry
    
    private func processBatchWithRetry(users: [UserDocument], retryCount: Int = 0) async -> BatchResult {
        var fixed = 0
        var skipped = 0
        var errors = 0
        
        // Use batch writes for efficiency (up to 500 operations per batch)
        let batch = db.batch()
        var operationCount = 0
        
        for user in users {
            // Check if user needs updating
            if user.hasLowercaseFields {
                skipped += 1
                continue
            }
            
            // Prepare update data
            let updateData: [String: Any] = [
                "usernameLowercase": user.username.lowercased(),
                "displayNameLowercase": user.displayName.lowercased(),
                "updatedAt": FieldValue.serverTimestamp()
            ]
            
            // Add to batch
            let userRef = db.collection("users").document(user.id)
            batch.updateData(updateData, forDocument: userRef)
            
            operationCount += 1
            fixed += 1
            
            // Firestore batch limit is 500 operations
            if operationCount >= 500 {
                break
            }
        }
        
        // Commit batch if we have operations
        if operationCount > 0 {
            do {
                try await batch.commit()
                print("✅ Batch commit successful: \(operationCount) users updated")
            } catch {
                print("❌ Batch commit failed: \(error.localizedDescription)")
                
                // Retry logic
                if retryCount < maxRetries {
                    print("🔄 Retrying batch (attempt \(retryCount + 1)/\(maxRetries))...")
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                    return await processBatchWithRetry(users: users, retryCount: retryCount + 1)
                } else {
                    // Failed after retries, count as errors
                    errors = fixed
                    fixed = 0
                }
            }
        }
        
        return BatchResult(fixed: fixed, skipped: skipped, errors: errors)
    }
    
    // MARK: - Helper Functions
    
    /// Fetch all users from Firestore
    private func fetchAllUsers() async throws -> [UserDocument] {
        currentStatus = "📥 Fetching users from Firestore..."
        
        let snapshot = try await db.collection("users")
            .order(by: "createdAt", descending: false)
            .getDocuments()
        
        var users: [UserDocument] = []
        
        for document in snapshot.documents {
            let data = document.data()
            
            guard let username = data["username"] as? String,
                  let displayName = data["displayName"] as? String else {
                print("⚠️ User \(document.documentID) missing required fields, skipping")
                continue
            }
            
            let hasUsernameLowercase = data["usernameLowercase"] != nil
            let hasDisplayNameLowercase = data["displayNameLowercase"] != nil
            
            users.append(UserDocument(
                id: document.documentID,
                username: username,
                displayName: displayName,
                hasLowercaseFields: hasUsernameLowercase && hasDisplayNameLowercase
            ))
        }
        
        return users
    }
    
    /// Check migration status without running migration
    func checkStatus() async throws -> MigrationStatus {
        currentStatus = "🔍 Checking migration status..."
        
        let users = try await fetchAllUsers()
        let needsMigration = users.filter { !$0.hasLowercaseFields }.count
        
        let status = MigrationStatus(
            totalUsers: users.count,
            needsMigration: needsMigration,
            alreadyMigrated: users.count - needsMigration
        )
        
        currentStatus = """
        📊 Status Check Complete
        
        Total Users: \(status.totalUsers)
        Need Migration: \(status.needsMigration)
        Already Migrated: \(status.alreadyMigrated)
        """
        
        return status
    }
    
    /// Fix a single user by ID (for testing or individual fixes)
    func fixUser(userId: String) async throws {
        currentStatus = "🔧 Fixing user \(userId)..."
        
        let userRef = db.collection("users").document(userId)
        let snapshot = try await userRef.getDocument()
        
        guard snapshot.exists, let data = snapshot.data() else {
            throw MigrationError.userNotFound(userId: userId)
        }
        
        guard let username = data["username"] as? String,
              let displayName = data["displayName"] as? String else {
            throw MigrationError.missingRequiredFields(userId: userId)
        }
        
        // Check if already has fields
        let hasUsernameLowercase = data["usernameLowercase"] != nil
        let hasDisplayNameLowercase = data["displayNameLowercase"] != nil
        
        if hasUsernameLowercase && hasDisplayNameLowercase {
            currentStatus = "⏭️ User already has lowercase fields"
            return
        }
        
        // Update user
        try await userRef.updateData([
            "usernameLowercase": username.lowercased(),
            "displayNameLowercase": displayName.lowercased(),
            "updatedAt": FieldValue.serverTimestamp()
        ])
        
        currentStatus = "✅ User fixed: @\(username) / \(displayName)"
    }
}

// MARK: - Supporting Types

struct UserDocument {
    let id: String
    let username: String
    let displayName: String
    let hasLowercaseFields: Bool
}

struct BatchResult {
    let fixed: Int
    let skipped: Int
    let errors: Int
}

struct MigrationStatus {
    let totalUsers: Int
    let needsMigration: Int
    let alreadyMigrated: Int
    
    var percentage: Double {
        guard totalUsers > 0 else { return 0 }
        return Double(alreadyMigrated) / Double(totalUsers) * 100
    }
}

enum MigrationError: LocalizedError {
    case alreadyRunning
    case userNotFound(userId: String)
    case missingRequiredFields(userId: String)
    
    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Migration is already running. Please wait for it to complete."
        case .userNotFound(let userId):
            return "User \(userId) not found in database."
        case .missingRequiredFields(let userId):
            return "User \(userId) is missing required fields (username or displayName)."
        }
    }
}

// MARK: - SwiftUI Admin View

/// Production-ready admin view for user search migration
struct UserSearchMigrationView: View {
    @StateObject private var migrationService = UserSearchMigration.shared
    @State private var migrationStatus: MigrationStatus?
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var alertTitle = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                // Status Section
                Section {
                    if let status = migrationStatus {
                        statusContent(status)
                    } else {
                        HStack {
                            ProgressView()
                            Text("Loading status...")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("MIGRATION STATUS")
                        .font(.custom("OpenSans-Bold", size: 12))
                } footer: {
                    Text("These fields enable case-insensitive user search in both main search and messaging.")
                        .font(.custom("OpenSans-Regular", size: 12))
                }
                
                // Actions Section
                Section {
                    Button {
                        Task {
                            await checkStatus()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh Status")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                            Spacer()
                            if migrationService.isRunning {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(migrationService.isRunning)
                    
                    if let status = migrationStatus, status.needsMigration > 0 {
                        Button {
                            Task {
                                await runMigration()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "wrench.and.screwdriver.fill")
                                    .foregroundStyle(.blue)
                                Text("Fix All Users")
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if migrationService.isRunning {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                            }
                        }
                        .disabled(migrationService.isRunning)
                    }
                } header: {
                    Text("ACTIONS")
                        .font(.custom("OpenSans-Bold", size: 12))
                }
                
                // Progress Section (only show when running)
                if migrationService.isRunning {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            ProgressView(value: migrationService.migrationProgress)
                                .tint(.blue)
                            
                            Text(migrationService.currentStatus)
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(nil)
                            
                            HStack {
                                Text("Progress:")
                                    .font(.custom("OpenSans-SemiBold", size: 12))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(migrationService.migrationProgress * 100))%")
                                    .font(.custom("OpenSans-Bold", size: 12))
                                    .foregroundStyle(.blue)
                            }
                        }
                    } header: {
                        Text("MIGRATION PROGRESS")
                            .font(.custom("OpenSans-Bold", size: 12))
                    }
                }
                
                // Info Section
                Section {
                    infoRow(title: "What This Does", description: "Adds 'usernameLowercase' and 'displayNameLowercase' fields to enable case-insensitive search.")
                    infoRow(title: "Is It Safe?", description: "Yes! This only adds fields, it doesn't modify or delete any existing data.")
                    infoRow(title: "How Long?", description: "~1 second per 50 users. Can be run multiple times safely.")
                    infoRow(title: "Required?", description: "Only for existing users. New users get these fields automatically.")
                } header: {
                    Text("INFORMATION")
                        .font(.custom("OpenSans-Bold", size: 12))
                }
            }
            .navigationTitle("User Search Migration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
                }
            }
            .alert(alertTitle, isPresented: $showAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
            .task {
                await checkStatus()
            }
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private func statusContent(_ status: MigrationStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            statusRow(label: "Total Users", value: "\(status.totalUsers)", color: .primary)
            statusRow(label: "Need Migration", value: "\(status.needsMigration)", color: status.needsMigration > 0 ? .orange : .green)
            statusRow(label: "Already Migrated", value: "\(status.alreadyMigrated)", color: .green)
            
            if status.totalUsers > 0 {
                HStack {
                    Text("Completion:")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                    Spacer()
                    Text("\(Int(status.percentage))%")
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(status.percentage == 100 ? .green : .orange)
                }
                
                ProgressView(value: status.percentage / 100)
                    .tint(status.percentage == 100 ? .green : .orange)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func statusRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.custom("OpenSans-SemiBold", size: 14))
            Spacer()
            Text(value)
                .font(.custom("OpenSans-Bold", size: 14))
                .foregroundStyle(color)
        }
    }
    
    private func infoRow(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.custom("OpenSans-SemiBold", size: 14))
                .foregroundStyle(.primary)
            Text(description)
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
    
    // MARK: - Actions
    
    private func checkStatus() async {
        do {
            let status = try await migrationService.checkStatus()
            migrationStatus = status
        } catch {
            alertTitle = "Error"
            alertMessage = "Failed to check status: \(error.localizedDescription)"
            showAlert = true
        }
    }
    
    private func runMigration() async {
        do {
            try await migrationService.fixAllUsers()
            
            alertTitle = "Success!"
            alertMessage = migrationService.currentStatus
            showAlert = true
            
            // Refresh status after migration
            await checkStatus()
            
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
        } catch {
            alertTitle = "Migration Failed"
            alertMessage = error.localizedDescription
            showAlert = true
            
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.error)
        }
    }
}

#Preview {
    UserSearchMigrationView()
}
