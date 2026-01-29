//
//  UserProfileUpdateFix.swift
//  AMENAPP
//
//  Helper functions to ensure user profiles are searchable
//

import Foundation
import FirebaseFirestore

extension FirebaseManager {
    
    /// Update user profile with searchable fields
    /// Call this whenever username or display name changes
    func updateUserProfileForSearch(
        userId: String,
        displayName: String? = nil,
        username: String? = nil
    ) async throws {
        var updateData: [String: Any] = [:]
        
        // Update display name and lowercase version
        if let displayName = displayName {
            updateData["displayName"] = displayName
            updateData["displayNameLowercase"] = displayName.lowercased()
        }
        
        // Update username and lowercase version
        if let username = username {
            updateData["username"] = username
            updateData["usernameLowercase"] = username.lowercased()
        }
        
        // Always update the timestamp
        updateData["updatedAt"] = Timestamp(date: Date())
        
        guard !updateData.isEmpty else {
            print("⚠️ No fields to update")
            return
        }
        
        try await firestore.collection(CollectionPath.users)
            .document(userId)
            .updateData(updateData)
        
        print("✅ Updated user profile for search: \(updateData.keys)")
    }
    
    /// Verify all users have searchable fields
    /// Run this once to migrate existing users
    func migrateUsersForSearch() async throws {
        print("🔄 Starting user search migration...")
        
        let snapshot = try await firestore.collection(CollectionPath.users)
            .getDocuments()
        
        var migratedCount = 0
        var errorCount = 0
        
        for document in snapshot.documents {
            do {
                let data = document.data()
                var updateData: [String: Any] = [:]
                
                // Check if lowercase fields exist
                if let displayName = data["displayName"] as? String,
                   data["displayNameLowercase"] == nil {
                    updateData["displayNameLowercase"] = displayName.lowercased()
                }
                
                if let username = data["username"] as? String,
                   data["usernameLowercase"] == nil {
                    updateData["usernameLowercase"] = username.lowercased()
                }
                
                // If no username exists, create one from email
                if data["username"] == nil,
                   let email = data["email"] as? String {
                    let username = email.components(separatedBy: "@").first?.lowercased() ?? "user"
                    updateData["username"] = username
                    updateData["usernameLowercase"] = username
                }
                
                if !updateData.isEmpty {
                    try await firestore.collection(CollectionPath.users)
                        .document(document.documentID)
                        .updateData(updateData)
                    migratedCount += 1
                    print("✅ Migrated user: \(document.documentID)")
                }
                
            } catch {
                errorCount += 1
                print("❌ Failed to migrate user \(document.documentID): \(error)")
            }
        }
        
        print("✅ Migration complete: \(migratedCount) users updated, \(errorCount) errors")
    }
}

// MARK: - Usage Examples

/*
 
 // Example 1: Update user profile during onboarding
 Task {
     try await FirebaseManager.shared.updateUserProfileForSearch(
         userId: currentUser.uid,
         displayName: "John Smith",
         username: "johnsmith"
     )
 }
 
 // Example 2: Run migration for existing users (one-time)
 Task {
     try await FirebaseManager.shared.migrateUsersForSearch()
 }
 
 */
