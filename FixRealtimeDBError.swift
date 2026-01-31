//
//  FixRealtimeDBError.swift
//  AMENAPP
//
//  Utility to find and fix Realtime Database errors
//

import Foundation

/*
 🔍 HOW TO FIND THE ERROR:
 
 1. Press Cmd+Shift+F in Xcode (Find in Project)
 2. Search for: "Database.database()"
 3. Check each result for "updateChildValues"
 4. The line with updateChildValues is causing the error
 
 Common places to check:
 - Any file with "Presence" in the name
 - Any file with "Online" in the name  
 - AppDelegate.swift
 - SceneDelegate.swift
 - UserService.swift
 - ProfileService.swift
 
 🔧 QUICK FIX:
 
 If you find code like this:
 
 Database.database().ref("presence/\(userId)").updateChildValues(...)
 Database.database().ref("online/\(email)").updateChildValues(...)  // ← email contains '.'
 Database.database().ref("status/\(path)").updateChildValues(...)
 
 Either:
 A) DELETE the entire function (if it's online status tracking)
 B) Sanitize the key:
 
    let safeKey = userId.replacingOccurrences(of: ".", with: "_")
    Database.database().ref("presence/\(safeKey)").updateChildValues(...)
 
 📋 TO COMPLETELY REMOVE ONLINE STATUS:
 
 Delete or comment out any functions like:
 - setUserOnline()
 - setUserOffline()
 - updatePresence()
 - listenToUserPresence()
 - trackOnlineStatus()
 
 And remove their calls from:
 - applicationDidBecomeActive
 - applicationWillResignActive
 - viewDidAppear
 - onAppear
 */

// MARK: - Helper Extension (Add this to your project)

import FirebaseDatabase

extension DatabaseReference {
    /// Safe update that sanitizes keys automatically
    func safeUpdateChildValues(_ values: [String: Any], 
                               withCompletionBlock block: ((Error?, DatabaseReference) -> Void)? = nil) {
        var sanitized: [String: Any] = [:]
        
        for (key, value) in values {
            // Remove forbidden characters
            let safeKey = key
                .replacingOccurrences(of: ".", with: "_")
                .replacingOccurrences(of: "#", with: "_")
                .replacingOccurrences(of: "$", with: "_")
                .replacingOccurrences(of: "[", with: "_")
                .replacingOccurrences(of: "]", with: "_")
                .replacingOccurrences(of: "/", with: "_")
            
            sanitized[safeKey] = value
        }
        
        if let block = block {
            self.updateChildValues(sanitized, withCompletionBlock: block)
        } else {
            self.updateChildValues(sanitized)
        }
    }
}

// MARK: - Search Instructions

/*
 STEP-BY-STEP DEBUGGING:
 
 1. In Xcode, set an Exception Breakpoint:
    - Click the breakpoints icon in toolbar (or Cmd+8)
    - Click '+' at bottom left
    - Choose 'Exception Breakpoint'
    - Leave defaults
    - Run app
 
 2. When error occurs, Xcode will pause at the exact line
    - Look at the left panel for the file name
    - Look at the line number
    - Read the code causing the error
 
 3. Common culprits:
    a) User email as key: "user@example.com" contains '.'
    b) Conversation ID with slashes: "conv/abc/123" contains '/'
    c) URL as key: "https://..." contains '.', '/', ':'
    d) File path as key: "path/to/file" contains '/'
 
 4. Fix options:
    a) Use user ID instead of email
    b) Sanitize the key (replace forbidden chars)
    c) Delete the feature if it's online status tracking
 
 5. Test:
    - Run app again
    - No error should appear
    - Messaging should work
 */
