import Foundation
import Firebase
import FirebaseFirestore
import FirebaseAuth

// MARK: - Data Migration Service

class DataMigrationService {
    static let shared = DataMigrationService()
    private let db = Firestore.firestore()
    
    // MARK: - Migration Functions
    
    /// Run all migrations
    func runAllMigrations() async throws {
        print("🚀 Starting data migrations...")
        
        try await migrateUserDocuments()
        try await migrateConversationDocuments()
        try await migrateFollowDocuments()
        
        print("✅ All migrations completed successfully!")
    }
    
    // MARK: - 1. Migrate User Documents (Add messagePrivacy)
    
    /// Add messagePrivacy field to all existing user documents
    func migrateUserDocuments() async throws {
        print("📝 Migrating user documents...")
        
        let users = try await db.collection("users").getDocuments()
        let batch = db.batch()
        var count = 0
        
        for doc in users.documents {
            let data = doc.data()
            
            // Only update if messagePrivacy doesn't exist
            if data["messagePrivacy"] == nil {
                batch.updateData([
                    "messagePrivacy": "followers",  // Default to followers
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: doc.reference)
                count += 1
            }
            
            // Commit batch every 500 documents (Firestore limit)
            if count % 500 == 0 && count > 0 {
                try await batch.commit()
                print("  ✓ Migrated \(count) users...")
            }
        }
        
        // Commit remaining documents
        if count % 500 != 0 {
            try await batch.commit()
        }
        
        print("✅ Migrated \(count) user documents")
    }
    
    // MARK: - 2. Migrate Conversation Documents (Add messageCounts)
    
    /// Add messageCounts field to all existing conversation documents
    func migrateConversationDocuments() async throws {
        print("📝 Migrating conversation documents...")
        
        let conversations = try await db.collection("conversations").getDocuments()
        var count = 0
        
        for doc in conversations.documents {
            let data = doc.data()
            
            // Only update if messageCounts doesn't exist
            if data["messageCounts"] == nil {
                let participantIds = data["participantIds"] as? [String] ?? []
                
                // Count existing messages for each participant
                let messageCounts = try await countMessagesForParticipants(
                    conversationId: doc.documentID,
                    participantIds: participantIds
                )
                
                try await doc.reference.updateData([
                    "messageCounts": messageCounts,
                    "updatedAt": FieldValue.serverTimestamp()
                ])
                
                count += 1
                
                if count % 100 == 0 {
                    print("  ✓ Migrated \(count) conversations...")
                }
            }
        }
        
        print("✅ Migrated \(count) conversation documents")
    }
    
    /// Count existing messages for each participant
    private func countMessagesForParticipants(conversationId: String, participantIds: [String]) async throws -> [String: Int] {
        var messageCounts: [String: Int] = [:]
        
        // Initialize counts to 0
        for participantId in participantIds {
            messageCounts[participantId] = 0
        }
        
        // Get all messages in this conversation
        let messages = try await db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .getDocuments()
        
        // Count messages per sender
        for message in messages.documents {
            if let senderId = message.data()["senderId"] as? String {
                messageCounts[senderId, default: 0] += 1
            }
        }
        
        return messageCounts
    }
    
    // MARK: - 3. Migrate Follow Documents (Update to new ID format)
    
    /// Migrate follow documents to use {followerId}_{followingId} format
    func migrateFollowDocuments() async throws {
        print("📝 Migrating follow documents...")
        
        let follows = try await db.collection("follows").getDocuments()
        let batch = db.batch()
        var count = 0
        var migratedIds: Set<String> = []
        
        for doc in follows.documents {
            let data = doc.data()
            
            guard let followerId = data["followerId"] as? String ?? data["followerUserId"] as? String,
                  let followingId = data["followingId"] as? String ?? data["followingUserId"] as? String else {
                print("⚠️ Skipping document \(doc.documentID) - missing required fields")
                continue
            }
            
            let expectedId = "\(followerId)_\(followingId)"
            
            // Check if document ID matches expected format
            if doc.documentID != expectedId {
                // Create new document with correct ID
                let newRef = db.collection("follows").document(expectedId)
                
                // Only migrate if new document doesn't already exist
                if !migratedIds.contains(expectedId) {
                    batch.setData([
                        "followerId": followerId,
                        "followerUserId": followerId,      // Backward compatibility
                        "followingId": followingId,
                        "followingUserId": followingId,    // Backward compatibility
                        "createdAt": data["createdAt"] ?? FieldValue.serverTimestamp()
                    ], forDocument: newRef)
                    
                    // Delete old document
                    batch.deleteDocument(doc.reference)
                    
                    migratedIds.insert(expectedId)
                    count += 1
                }
            } else {
                // Document ID is correct, but ensure all fields exist
                var updateData: [String: Any] = [:]
                
                if data["followerUserId"] == nil {
                    updateData["followerUserId"] = followerId
                }
                if data["followingUserId"] == nil {
                    updateData["followingUserId"] = followingId
                }
                
                if !updateData.isEmpty {
                    batch.updateData(updateData, forDocument: doc.reference)
                    count += 1
                }
            }
            
            // Commit batch every 500 operations
            if count % 250 == 0 && count > 0 {  // 250 because we're doing 2 operations per migration
                try await batch.commit()
                print("  ✓ Migrated \(count) follows...")
            }
        }
        
        // Commit remaining documents
        if count % 250 != 0 {
            try await batch.commit()
        }
        
        print("✅ Migrated \(count) follow documents")
    }
    
    // MARK: - Verification Functions
    
    /// Verify all migrations completed successfully
    func verifyMigrations() async throws {
        print("\n🔍 Verifying migrations...")
        
        try await verifyUserMigration()
        try await verifyConversationMigration()
        try await verifyFollowMigration()
        
        print("✅ All verifications passed!")
    }
    
    private func verifyUserMigration() async throws {
        let users = try await db.collection("users").limit(to: 10).getDocuments()
        
        for doc in users.documents {
            let data = doc.data()
            if data["messagePrivacy"] == nil {
                print("⚠️ User \(doc.documentID) missing messagePrivacy")
            }
        }
        
        print("✓ User documents verified")
    }
    
    private func verifyConversationMigration() async throws {
        let conversations = try await db.collection("conversations").limit(to: 10).getDocuments()
        
        for doc in conversations.documents {
            let data = doc.data()
            if data["messageCounts"] == nil {
                print("⚠️ Conversation \(doc.documentID) missing messageCounts")
            }
        }
        
        print("✓ Conversation documents verified")
    }
    
    private func verifyFollowMigration() async throws {
        let follows = try await db.collection("follows").limit(to: 10).getDocuments()
        
        for doc in follows.documents {
            let data = doc.data()
            
            // Check for proper ID format
            if !doc.documentID.contains("_") {
                print("⚠️ Follow \(doc.documentID) has incorrect ID format")
            }
            
            // Check for required fields
            if data["followerId"] == nil || data["followerUserId"] == nil ||
               data["followingId"] == nil || data["followingUserId"] == nil {
                print("⚠️ Follow \(doc.documentID) missing required fields")
            }
        }
        
        print("✓ Follow documents verified")
    }
    
    // MARK: - Helper: Add messagePrivacy to a single user
    
    /// Add messagePrivacy to a specific user (useful for new user creation)
    func addMessagePrivacyToUser(userId: String, privacy: MessagePrivacy = .followers) async throws {
        try await db.collection("users").document(userId).updateData([
            "messagePrivacy": privacy.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }
    
    // MARK: - Helper: Initialize messageCounts for a conversation
    
    /// Initialize messageCounts for a specific conversation
    func initializeMessageCounts(conversationId: String, participantIds: [String]) async throws {
        var messageCounts: [String: Int] = [:]
        
        for participantId in participantIds {
            messageCounts[participantId] = 0
        }
        
        try await db.collection("conversations").document(conversationId).updateData([
            "messageCounts": messageCounts,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }
}

// MARK: - Migration Runner (Call this from your app)

class MigrationRunner {
    
    /// Run migrations with progress tracking
    static func runMigrations() async {
        do {
            print("=" * 50)
            print("🚀 STARTING DATA MIGRATION")
            print("=" * 50)
            
            try await DataMigrationService.shared.runAllMigrations()
            
            print("\n")
            try await DataMigrationService.shared.verifyMigrations()
            
            print("\n" + "=" * 50)
            print("✅ MIGRATION COMPLETED SUCCESSFULLY")
            print("=" * 50)
        } catch {
            print("\n" + "=" * 50)
            print("❌ MIGRATION FAILED")
            print("Error: \(error.localizedDescription)")
            print("=" * 50)
        }
    }
}

// Helper for string repetition
extension String {
    static func * (left: String, right: Int) -> String {
        return String(repeating: left, count: right)
    }
}

// MARK: - SwiftUI View for Running Migrations

import SwiftUI

struct DataMigrationView: View {
    @State private var isMigrating = false
    @State private var migrationLog: [String] = []
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Warning banner
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Data Migration Required")
                            .font(.headline)
                    }
                    
                    Text("This will update your existing database to support the new messaging system. Make sure you have a backup before proceeding.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal)
                
                // What will be updated
                VStack(alignment: .leading, spacing: 12) {
                    Text("What will be updated:")
                        .font(.headline)
                    
                    MigrationItem(
                        icon: "person.circle",
                        title: "User Documents",
                        description: "Add 'messagePrivacy' field (default: followers)"
                    )
                    
                    MigrationItem(
                        icon: "message.circle",
                        title: "Conversation Documents",
                        description: "Add 'messageCounts' field with current message counts"
                    )
                    
                    MigrationItem(
                        icon: "arrow.triangle.2.circlepath.circle",
                        title: "Follow Documents",
                        description: "Update to use '{followerId}_{followingId}' format"
                    )
                }
                .padding()
                
                // Migration log
                if !migrationLog.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(migrationLog, id: \.self) { log in
                                Text(log)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                    }
                    .frame(maxHeight: 200)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }
                
                Spacer()
                
                // Run migration button
                Button {
                    runMigration()
                } label: {
                    HStack {
                        if isMigrating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "play.circle.fill")
                        }
                        Text(isMigrating ? "Migrating..." : "Run Migration")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isMigrating ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isMigrating)
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Data Migration")
            .alert("Migration Result", isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    private func runMigration() {
        isMigrating = true
        migrationLog = []
        
        Task {
            do {
                addLog("🚀 Starting migration...")
                
                addLog("📝 Migrating user documents...")
                try await DataMigrationService.shared.migrateUserDocuments()
                addLog("✅ Users migrated")
                
                addLog("📝 Migrating conversations...")
                try await DataMigrationService.shared.migrateConversationDocuments()
                addLog("✅ Conversations migrated")
                
                addLog("📝 Migrating follows...")
                try await DataMigrationService.shared.migrateFollowDocuments()
                addLog("✅ Follows migrated")
                
                addLog("🔍 Verifying migrations...")
                try await DataMigrationService.shared.verifyMigrations()
                addLog("✅ Verification complete")
                
                addLog("✅ ALL MIGRATIONS COMPLETED!")
                
                alertMessage = "Migration completed successfully! Your database is now ready for the new messaging system."
                showAlert = true
            } catch {
                addLog("❌ Migration failed: \(error.localizedDescription)")
                alertMessage = "Migration failed: \(error.localizedDescription)"
                showAlert = true
            }
            
            isMigrating = false
        }
    }
    
    private func addLog(_ message: String) {
        DispatchQueue.main.async {
            migrationLog.append(message)
        }
    }
}

struct MigrationItem: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    DataMigrationView()
}
