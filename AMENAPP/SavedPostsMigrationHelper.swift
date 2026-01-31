//
//  SavedPostsMigrationHelper.swift
//  AMENAPP
//
//  Created by Steph on 1/29/26.
//
//  Helper to migrate saved posts from Firestore to RTDB (if needed)
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

/// One-time migration helper to move saved posts from Firestore to RTDB
struct SavedPostsMigrationHelper {
    
    /// Migrate all saved posts from Firestore to RTDB for current user
    @MainActor
    static func migrateFromFirestoreToRTDB() async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "SavedPostsMigrationHelper", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "User not authenticated"
            ])
        }
        
        print("🔄 Starting migration from Firestore to RTDB...")
        
        let db = Firestore.firestore()
        let rtdbService = RealtimeSavedPostsService.shared
        
        // Fetch saved posts from Firestore
        let snapshot = try await db.collection("savedPosts")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        
        print("📥 Found \(snapshot.documents.count) saved posts in Firestore")
        
        var migratedCount = 0
        var errorCount = 0
        
        for document in snapshot.documents {
            do {
                let data = document.data()
                
                guard let postId = data["postId"] as? String else {
                    print("⚠️ Skipping document \(document.documentID) - missing postId")
                    errorCount += 1
                    continue
                }
                
                // Check if already in RTDB
                let isAlreadySaved = try await rtdbService.isPostSaved(postId: postId)
                
                if isAlreadySaved {
                    print("⏭️ Post \(postId) already in RTDB, skipping")
                    continue
                }
                
                // Save to RTDB
                _ = try await rtdbService.toggleSavePost(postId: postId)
                
                migratedCount += 1
                print("✅ Migrated post \(postId)")
                
                // Small delay to avoid rate limiting
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                
            } catch {
                errorCount += 1
                print("❌ Error migrating document \(document.documentID): \(error)")
            }
        }
        
        print("✅ Migration complete!")
        print("   - Migrated: \(migratedCount)")
        print("   - Skipped/Errors: \(errorCount)")
        print("   - Total in Firestore: \(snapshot.documents.count)")
    }
    
    /// Clean up Firestore saved posts after successful migration
    @MainActor
    static func cleanupFirestoreSavedPosts() async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "SavedPostsMigrationHelper", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "User not authenticated"
            ])
        }
        
        print("🗑️ Cleaning up Firestore saved posts...")
        
        let db = Firestore.firestore()
        
        let snapshot = try await db.collection("savedPosts")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        
        let batch = db.batch()
        
        for document in snapshot.documents {
            batch.deleteDocument(document.reference)
        }
        
        try await batch.commit()
        
        print("✅ Deleted \(snapshot.documents.count) saved posts from Firestore")
    }
    
    /// Verify migration was successful by comparing counts
    @MainActor
    static func verifyMigration() async throws -> MigrationVerificationResult {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "SavedPostsMigrationHelper", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "User not authenticated"
            ])
        }
        
        print("🔍 Verifying migration...")
        
        let db = Firestore.firestore()
        let rtdbService = RealtimeSavedPostsService.shared
        
        // Count in Firestore
        let firestoreSnapshot = try await db.collection("savedPosts")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        let firestoreCount = firestoreSnapshot.documents.count
        
        // Count in RTDB
        let rtdbCount = try await rtdbService.getSavedPostsCount()
        
        let result = MigrationVerificationResult(
            firestoreCount: firestoreCount,
            rtdbCount: rtdbCount,
            isSuccessful: rtdbCount >= firestoreCount
        )
        
        print("📊 Migration Verification:")
        print("   - Firestore: \(firestoreCount)")
        print("   - RTDB: \(rtdbCount)")
        print("   - Status: \(result.isSuccessful ? "✅ SUCCESS" : "⚠️ MISMATCH")")
        
        return result
    }
}

// MARK: - Migration Result

struct MigrationVerificationResult {
    let firestoreCount: Int
    let rtdbCount: Int
    let isSuccessful: Bool
    
    var message: String {
        if isSuccessful {
            return "Migration successful! \(rtdbCount) posts in RTDB."
        } else {
            return "⚠️ Mismatch: Firestore has \(firestoreCount), RTDB has \(rtdbCount)"
        }
    }
}

// MARK: - Migration View

import SwiftUI

struct SavedPostsMigrationView: View {
    @State private var isRunning = false
    @State private var showResult = false
    @State private var resultMessage = ""
    @State private var verificationResult: MigrationVerificationResult?
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("This tool migrates your saved posts from Firestore to Firebase Realtime Database.")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                } header: {
                    Text("About")
                }
                
                Section {
                    Button {
                        runMigration()
                    } label: {
                        HStack {
                            if isRunning {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text("Migrate to RTDB")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                        }
                    }
                    .disabled(isRunning)
                    
                    Button {
                        runVerification()
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.shield")
                            Text("Verify Migration")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                        }
                    }
                    .disabled(isRunning)
                } header: {
                    Text("Migration")
                }
                
                if let result = verificationResult {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Firestore:")
                                Spacer()
                                Text("\(result.firestoreCount)")
                                    .font(.custom("OpenSans-Bold", size: 16))
                            }
                            
                            HStack {
                                Text("RTDB:")
                                Spacer()
                                Text("\(result.rtdbCount)")
                                    .font(.custom("OpenSans-Bold", size: 16))
                            }
                            
                            Divider()
                            
                            HStack {
                                Image(systemName: result.isSuccessful ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(result.isSuccessful ? .green : .orange)
                                Text(result.isSuccessful ? "Migration Successful" : "Mismatch Detected")
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                            }
                        }
                        .font(.custom("OpenSans-Regular", size: 14))
                    } header: {
                        Text("Verification Results")
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        cleanupFirestore()
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clean Up Firestore")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                        }
                    }
                    .disabled(isRunning || verificationResult?.isSuccessful != true)
                } header: {
                    Text("Cleanup")
                } footer: {
                    Text("⚠️ Only run after successful migration and verification. This will delete all saved posts from Firestore.")
                        .font(.custom("OpenSans-Regular", size: 12))
                }
            }
            .navigationTitle("Migrate Saved Posts")
            .alert("Migration Result", isPresented: $showResult) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(resultMessage)
            }
        }
    }
    
    private func runMigration() {
        isRunning = true
        
        Task {
            do {
                try await SavedPostsMigrationHelper.migrateFromFirestoreToRTDB()
                
                await MainActor.run {
                    resultMessage = "Migration completed successfully!"
                    showResult = true
                    isRunning = false
                }
                
                // Auto-verify after migration
                runVerification()
                
            } catch {
                await MainActor.run {
                    resultMessage = "Error: \(error.localizedDescription)"
                    showResult = true
                    isRunning = false
                }
            }
        }
    }
    
    private func runVerification() {
        Task {
            do {
                let result = try await SavedPostsMigrationHelper.verifyMigration()
                
                await MainActor.run {
                    verificationResult = result
                }
                
            } catch {
                await MainActor.run {
                    resultMessage = "Verification error: \(error.localizedDescription)"
                    showResult = true
                }
            }
        }
    }
    
    private func cleanupFirestore() {
        isRunning = true
        
        Task {
            do {
                try await SavedPostsMigrationHelper.cleanupFirestoreSavedPosts()
                
                await MainActor.run {
                    resultMessage = "Firestore cleanup completed!"
                    showResult = true
                    isRunning = false
                    verificationResult = nil
                }
                
            } catch {
                await MainActor.run {
                    resultMessage = "Cleanup error: \(error.localizedDescription)"
                    showResult = true
                    isRunning = false
                }
            }
        }
    }
}

#Preview {
    SavedPostsMigrationView()
}

// MARK: - Usage Instructions

/*
 
 📝 MIGRATION INSTRUCTIONS
 
 If you have existing saved posts in Firestore and want to migrate to RTDB:
 
 1. Add this view to your app (temporarily):
    ```swift
    NavigationLink("Migrate Saved Posts") {
        SavedPostsMigrationView()
    }
    ```
 
 2. Run the migration:
    - Open SavedPostsMigrationView
    - Tap "Migrate to RTDB"
    - Wait for completion
 
 3. Verify migration:
    - Tap "Verify Migration"
    - Check that counts match
    - Verify status shows "✅ Migration Successful"
 
 4. Clean up Firestore (optional):
    - Tap "Clean Up Firestore"
    - This deletes Firestore saved posts
    - Only do this after successful verification
 
 5. Remove migration view from app
 
 ⚠️ IMPORTANT NOTES:
 
 - This is a ONE-TIME migration
 - Users should be logged in
 - Migration is per-user (each user runs it once)
 - Backup your Firestore data before cleanup
 - Test with a few users first before rolling out
 
 If you're starting fresh (no existing saved posts in Firestore):
 - You can skip this migration entirely
 - Just use the new RTDB-based system
 - Delete SavedPostsService.swift (Firestore version)
 
 */
