//
//  SavedSearchNotificationIntegration.swift
//  AMENAPP
//
//  Created by Steph on 1/29/26.
//
//  Integrates Saved Search Alerts with existing notification system
//

import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Extension to Notification Settings

extension NotificationSettingsView {
    /// Add this to your notification types section in NotificationSettingsView.swift
    /// Insert after prayerReminderNotifications toggle
    
    static var savedSearchAlertsToggle: some View {
        Toggle(isOn: .constant(true)) { // Replace with @State var savedSearchAlertNotifications
            HStack {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(.blue)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Saved Search Alerts")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                    Text("When new results match your saved searches")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tint(.blue)
    }
}

// MARK: - Extension to SavedSearchService
// NOTE: SavedSearchService already has a private sendNotificationForSearchAlert method
// that handles notification sending. No additional extension needed here.

// MARK: - Extension to AppNotification (Add new type)

extension AppNotification {
    
    /// Check if this is a saved search alert
    var isSavedSearchAlert: Bool {
        type == .savedSearchAlert
    }
    
    /// Get saved search details from notification
    /// Note: This requires adding additional fields to AppNotification struct
    /// For now, we can use postId to store searchId and commentText to store query
    var savedSearchData: (searchId: String, query: String, resultCount: Int)? {
        guard isSavedSearchAlert,
              let searchId = postId,
              let query = commentText else {
            return nil
        }
        // ResultCount would need to be parsed from actorName or stored elsewhere
        // For now, return a default of 1
        return (searchId, query, 1)
    }
}

// MARK: - Extension to NotificationType (Add new case)

extension AppNotification.NotificationType {
    static let savedSearchAlert = AppNotification.NotificationType(rawValue: "savedSearchAlert")
}

// MARK: - UI Extension for NotificationsView

extension NotificationsView {
    
    /// Handle saved search alert tap
    func handleSavedSearchAlertTap(_ notification: AppNotification) {
        guard let searchData = notification.savedSearchData else { return }
        
        // Show saved searches view and scroll to this alert
        // You can pass this info to SavedSearchesView
        
        print("🔍 Opening saved search: \(searchData.query)")
        
        // Post notification for navigation
        NotificationCenter.default.post(
            name: Notification.Name("openSavedSearch"),
            object: nil,
            userInfo: [
                "searchId": searchData.searchId,
                "query": searchData.query
            ]
        )
    }
}

// MARK: - Update Search Notification Icon & Color

extension AppNotification {
    
    var enhancedIcon: String {
        if isSavedSearchAlert {
            return "bookmark.fill"
        }
        return icon
    }
    
    var enhancedColor: Color {
        if isSavedSearchAlert {
            return .blue
        }
        return color
    }
    
    var enhancedActionText: String {
        if isSavedSearchAlert, let data = savedSearchData {
            return "New results for \"\(data.query)\" - \(data.resultCount) found"
        }
        return actionText
    }
}

// MARK: - Integration Helper

struct SavedSearchNotificationHelper {
    
    /// Register saved search notification observer
    static func registerObserver() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("openSavedSearch"),
            object: nil,
            queue: .main
        ) { notification in
            guard let userInfo = notification.userInfo,
                  let searchId = userInfo["searchId"] as? String,
                  let query = userInfo["query"] as? String else {
                return
            }
            
            print("📍 Navigating to saved search: \(query)")
            
            // TODO: Present SavedSearchesView and highlight this search
            // You can use a coordinator or navigation helper here
        }
    }
}

// MARK: - Usage Instructions

/*
 
 📚 INTEGRATION STEPS:
 
 1. UPDATE NotificationSettingsView.swift:
    - Add @State var savedSearchAlertNotifications = true
    - Add the toggle in notification types section:
      
      Toggle(isOn: $savedSearchAlertNotifications) {
          HStack {
              Image(systemName: "bookmark.fill")
                  .foregroundStyle(.blue)
                  .frame(width: 24)
              
              VStack(alignment: .leading, spacing: 4) {
                  Text("Saved Search Alerts")
                      .font(.custom("OpenSans-SemiBold", size: 15))
                  Text("When new results match your saved searches")
                      .font(.custom("OpenSans-Regular", size: 13))
                      .foregroundStyle(.secondary)
              }
          }
      }
      .tint(.blue)
      .disabled(!pushManager.notificationPermissionGranted)
    
    - Add to saveNotificationSettings():
      "savedSearchAlertNotifications": savedSearchAlertNotifications
 
 
 2. SavedSearchService.swift:
    - ✅ Already configured! The service automatically sends notifications
      when creating search alerts (see sendNotificationForSearchAlert method)
    - No changes needed here
 
 
 3. UPDATE RealNotificationRow in NotificationsView.swift:
    - In handleNotificationTap(), add case for saved search:
      
      case .savedSearchAlert:
          if let searchData = notification.savedSearchData {
              // Open saved searches and highlight this one
              NotificationCenter.default.post(
                  name: Notification.Name("openSavedSearch"),
                  object: nil,
                  userInfo: [
                      "searchId": searchData.searchId,
                      "query": searchData.query
                  ]
              )
          }
 
 
 4. UPDATE Your ContentView or Main App:
    - Add observer in .onAppear:
      
      SavedSearchNotificationHelper.registerObserver()
 
 
 5. OPTIONAL - Add Cloud Function:
    - Create functions/src/savedSearchAlerts.ts:
      
      export const onSearchAlertCreated = functions.firestore
          .document('searchAlerts/{alertId}')
          .onCreate(async (snap, context) => {
              const alert = snap.data();
              const userId = alert.userId;
              
              // Get user's FCM token
              const userDoc = await admin.firestore()
                  .collection('users')
                  .doc(userId)
                  .get();
                  
              const userData = userDoc.data();
              if (!userData?.savedSearchAlertNotifications) {
                  return null;
              }
              
              const fcmToken = userData.fcmToken;
              if (!fcmToken) {
                  return null;
              }
              
              // Send push notification
              const message = {
                  token: fcmToken,
                  notification: {
                      title: `New Results: "${alert.query}"`,
                      body: `${alert.resultCount} new result${alert.resultCount === 1 ? '' : 's'} found`,
                  },
                  data: {
                      type: 'savedSearchAlert',
                      alertId: context.params.alertId,
                      query: alert.query,
                  },
              };
              
              await admin.messaging().send(message);
              return null;
          });
 
 
 6. TEST:
    - Save a search with notifications enabled
    - Trigger background check manually
    - Verify notification appears in NotificationsView
    - Tap notification and verify navigation
    - Check badge count updates
 
 
 ✅ THAT'S IT! Saved search alerts now integrate with your existing notification system!
 
 */
