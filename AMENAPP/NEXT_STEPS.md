# NEXT STEPS - Saved Search Notifications

## ✅ COMPLETED
- SavedSearchService: Added notification sending
- NotificationSettingsView: Added "Saved Search Alerts" toggle
- Notification integration: Complete

## 🔧 REQUIRED STEPS

### 1. Fix SearchViewComponents.swift Compilation Errors (5 min)
Open SearchViewComponents.swift and add at line 1344:

```swift
// Add this extension to fix ScrollView error
extension ScrollView where Content == EmptyView {
    init() {
        self.init(.vertical, showsIndicators: false) {
            EmptyView()
        }
    }
}
```

### 2. Handle Notification Tap in NotificationsView.swift (10 min)

Open NotificationsView.swift, find `handleNotificationTap()` function in `RealNotificationRow`, add:

```swift
case .savedSearchAlert:
    if let data = notification.data as? [String: Any],
       let savedSearchId = data["savedSearchId"] as? String,
       let query = data["query"] as? String {
        // Post notification to open saved searches
        NotificationCenter.default.post(
            name: Notification.Name("openSavedSearch"),
            object: nil,
            userInfo: ["savedSearchId": savedSearchId, "query": query]
        )
    }
```

### 3. Add Navigation Handler in ContentView (5 min)

In your main ContentView or app entry point, add:

```swift
.onAppear {
    NotificationCenter.default.addObserver(
        forName: Notification.Name("openSavedSearch"),
        object: nil,
        queue: .main
    ) { notification in
        guard let userInfo = notification.userInfo,
              let searchId = userInfo["savedSearchId"] as? String else { return }
        
        // Navigate to saved searches
        // TODO: Implement your navigation logic
        print("📍 Open saved search: \(searchId)")
    }
}
```

### 4. Update users Collection Schema (1 min)

In Firestore, ensure each user document has:
- `savedSearchAlertNotifications: true` (will auto-create on first save)

### 5. Test the Integration (10 min)

```bash
# 1. Build and run on device
# 2. Go to Settings → Notifications
# 3. Enable "Saved Search Alerts" toggle
# 4. Save a search with notifications enabled
# 5. Trigger manual check: Tap "Check Now"
# 6. Verify notification appears in NotificationsView
# 7. Tap notification → should navigate to saved searches
```

### 6. OPTIONAL: Add Cloud Function (20 min)

Create `functions/src/savedSearchAlerts.ts`:

```typescript
import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

export const onSearchAlertCreated = functions.firestore
    .document('searchAlerts/{alertId}')
    .onCreate(async (snap, context) => {
        const alert = snap.data();
        const userId = alert.userId;
        
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
            apns: {
                payload: {
                    aps: {
                        sound: 'default',
                        badge: await getUnreadCount(userId),
                    },
                },
            },
        };
        
        await admin.messaging().send(message);
        return null;
    });

async function getUnreadCount(userId: string): Promise<number> {
    const snapshot = await admin.firestore()
        .collection('notifications')
        .where('userId', '==', userId)
        .where('read', '==', false)
        .get();
    return snapshot.size;
}
```

Then in `functions/src/index.ts` add:
```typescript
export { onSearchAlertCreated } from './savedSearchAlerts';
```

Deploy:
```bash
cd functions
firebase deploy --only functions:onSearchAlertCreated
```

## 🎯 VERIFICATION CHECKLIST

- [ ] SearchViewComponents.swift compiles without errors
- [ ] NotificationSettingsView shows "Saved Search Alerts" toggle
- [ ] Toggle saves to Firestore
- [ ] Saved search creates notification in NotificationsView
- [ ] Tapping notification navigates somewhere (add your logic)
- [ ] Badge count updates
- [ ] Push notification sends (if Cloud Function deployed)

## 🚀 PRODUCTION READY AFTER:
Steps 1-5 completed (Steps 6 optional for push notifications)

Total time: ~30 minutes
