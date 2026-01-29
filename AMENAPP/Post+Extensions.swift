//
//  Post+Extensions.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  Extensions for Post model to work with Firestore
//

import Foundation

extension Post {
    /// Convert Post's UUID to String for Firestore operations
    var firestoreId: String {
        id.uuidString
    }
    
    /// Check if user has amened this post (requires checking amenUserIds from Firestore)
    func hasAmened(by userId: String) -> Bool {
        amenUserIds.contains(userId)
    }
    
    /// Check if user has lit lightbulb (requires checking lightbulbUserIds from Firestore)
    func hasLitLightbulb(by userId: String) -> Bool {
        lightbulbUserIds.contains(userId)
    }
    
    /// Get amenUserIds and lightbulbUserIds (these should be added to Post model)
    var amenUserIds: [String] {
        // TODO: This should be fetched from Firestore or stored in the Post model
        []
    }
    
    var lightbulbUserIds: [String] {
        // TODO: This should be fetched from Firestore or stored in the Post model
        []
    }
}

extension FirestorePost {
    /// Check if current user has amened this post
    func hasAmened(by userId: String) -> Bool {
        amenUserIds.contains(userId)
    }
    
    /// Check if current user has lit lightbulb
    func hasLitLightbulb(by userId: String) -> Bool {
        lightbulbUserIds.contains(userId)
    }
}

