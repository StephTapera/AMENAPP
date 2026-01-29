//
//  UserKeywordsMigration.swift
//  AMENAPP
//
//  One-time migration script to add nameKeywords to existing users
//  Run this once if you have existing users created before the nameKeywords feature
//

import Foundation
import FirebaseFirestore

/// Migration utility to add nameKeywords to existing users
struct UserKeywordsMigration {
    
    /// Run the migration to update all existing users
    /// Call this from a debug button or on app launch (once)
    static func migrateAllUsers() async throws {
        let db = Firestore.firestore()
        
        print("🔄 Starting user migration to add nameKeywords...")
        
        let usersSnapshot = try await db.collection("users").getDocuments()
        
        print("📊 Found \(usersSnapshot.documents.count) users to check")
        
        var updatedCount = 0
        var skippedCount = 0
        var errorCount = 0
        
        for document in usersSnapshot.documents {
            let data = document.data()
            
            // Skip if already has keywords
            if data["nameKeywords"] != nil {
                skippedCount += 1
                continue
            }
            
            guard let displayName = data["displayName"] as? String else {
                print("⚠️ Skipping user \(document.documentID) - no displayName")
                skippedCount += 1
                continue
            }
            
            do {
                // Generate keywords
                let keywords = createNameKeywords(from: displayName)
                
                // Update document
                try await document.reference.updateData([
                    "nameKeywords": keywords,
                    "updatedAt": Timestamp(date: Date())
                ])
                
                updatedCount += 1
                print("✅ Updated user: \(displayName) with keywords: \(keywords)")
                
            } catch {
                errorCount += 1
                print("❌ Error updating user \(displayName): \(error)")
            }
        }
        
        print("""
        
        🎉 Migration Complete!
        ✅ Updated: \(updatedCount) users
        ⏭️  Skipped: \(skippedCount) users (already had keywords)
        ❌ Errors: \(errorCount) users
        
        """)
    }
    
    /// Create searchable keywords from a display name
    private static func createNameKeywords(from displayName: String) -> [String] {
        var keywords: [String] = []
        let lowercasedName = displayName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Add full name
        keywords.append(lowercasedName)
        
        // Add individual words
        let words = lowercasedName.components(separatedBy: " ").filter { !$0.isEmpty }
        keywords.append(contentsOf: words)
        
        // Add first name + last name combinations
        if words.count >= 2 {
            let firstName = words[0]
            let lastName = words[words.count - 1]
            keywords.append("\(firstName) \(lastName)")
        }
        
        // Remove duplicates and return
        return Array(Set(keywords))
    }
    
    /// Check how many users need migration (read-only)
    static func checkMigrationStatus() async throws -> (needsMigration: Int, hasKeywords: Int) {
        let db = Firestore.firestore()
        
        let usersSnapshot = try await db.collection("users").getDocuments()
        
        var needsMigration = 0
        var hasKeywords = 0
        
        for document in usersSnapshot.documents {
            let data = document.data()
            
            if data["nameKeywords"] != nil {
                hasKeywords += 1
            } else {
                needsMigration += 1
            }
        }
        
        print("""
        📊 Migration Status:
        ✅ Already migrated: \(hasKeywords) users
        ⚠️ Need migration: \(needsMigration) users
        📈 Total users: \(usersSnapshot.documents.count)
        """)
        
        return (needsMigration, hasKeywords)
    }
}

// MARK: - Usage Example

/*
 
 How to use this migration:
 
 1. Add a debug button in your app (Settings or Admin panel):
 
 Button("Migrate Users (Admin Only)") {
     Task {
         do {
             try await UserKeywordsMigration.migrateAllUsers()
         } catch {
             print("Migration error: \(error)")
         }
     }
 }
 
 2. Or check status first:
 
 Task {
     let status = try await UserKeywordsMigration.checkMigrationStatus()
     if status.needsMigration > 0 {
         print("⚠️ \(status.needsMigration) users need migration")
         // Optionally run migration automatically
     }
 }
 
 3. Or run once on app launch (for testing):
 
 .task {
     // Only run if needed
     let status = try? await UserKeywordsMigration.checkMigrationStatus()
     if let status = status, status.needsMigration > 0 {
         try? await UserKeywordsMigration.migrateAllUsers()
     }
 }
 
 */
