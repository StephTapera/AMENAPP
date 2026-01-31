# NotificationService Migration Guide

## Quick Migration Checklist

If you're updating from the old NotificationService to the new production-ready version, follow these steps:

## 1. Update Method Calls to Use `try await`

### Before ❌
```swift
Task {
    await NotificationService.shared.markAsRead(id)
}
```

### After ✅
```swift
Task {
    do {
        try await NotificationService.shared.markAsRead(id)
    } catch {
        print("Error: \(error.localizedDescription)")
    }
}
```

## 2. Update Notification Type Handling

### Before ❌
```swift
if notification.type == "follow" {
    // Handle follow
}
```

### After ✅
```swift
switch notification.type {
case .follow:
    // Handle follow
case .amen:
    // Handle amen
case .comment:
    // Handle comment
default:
    // Handle unknown
}
```

## 3. Remove PushNotificationManager Badge Calls

### Before ❌
```swift
NotificationService.shared.startListening()
PushNotificationManager.shared.updateBadgeCount()
```

### After ✅
```swift
NotificationService.shared.startListening()
// Badge is automatically updated by NotificationService
```

## 4. Update Error Handling

### Before ❌
```swift
await NotificationService.shared.markAllAsRead()
// No error handling
```

### After ✅
```swift
do {
    try await NotificationService.shared.markAllAsRead()
    showSuccessMessage = true
} catch NotificationError.notAuthenticated {
    showLoginPrompt = true
} catch {
    errorMessage = error.localizedDescription
    showErrorAlert = true
}
```

## 5. Use Published Error Property

### After ✅
```swift
struct NotificationsView: View {
    @StateObject private var service = NotificationService.shared
    
    var body: some View {
        List(service.notifications) { notification in
            // ...
        }
        .alert(
            "Error",
            isPresented: .constant(service.error != nil),
            presenting: service.error
        ) { _ in
            Button("OK") { }
        } message: { error in
            Text(error.localizedDescription)
        }
    }
}
```

## 6. Remove AI Service References

### Before ❌
```swift
private let aiService = NotificationGenkitService.shared
```

### After ✅
```swift
// AI is now managed internally
// Just use the toggle if needed:
NotificationService.shared.toggleAINotifications()
```

## 7. Update SwiftUI Bindings

### Before ❌
```swift
@ObservedObject var service = NotificationService.shared
```

### After ✅
```swift
@StateObject private var service = NotificationService.shared
```

## 8. Handle Loading State

### After ✅
```swift
.overlay {
    if service.isLoading {
        ProgressView("Loading notifications...")
    }
}
```

## Common Patterns

### Swipe Actions with Error Handling
```swift
.swipeActions(edge: .trailing) {
    Button(role: .destructive) {
        Task {
            do {
                try await service.deleteNotification(notification.id!)
                // Success haptic
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            } catch {
                errorMessage = "Failed to delete notification"
                showError = true
            }
        }
    } label: {
        Label("Delete", systemImage: "trash")
    }
}
```

### Pull to Refresh
```swift
.refreshable {
    await service.refresh()
}
```

### Mark All as Read Button
```swift
Button("Mark All Read") {
    Task {
        do {
            try await service.markAllAsRead()
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
.disabled(service.unreadCount == 0)
```

## Breaking Changes Summary

1. ✅ Methods now throw errors (add `try`)
2. ✅ `type` is now `NotificationType` enum (not `String`)
3. ✅ Badge management is internal (remove external calls)
4. ✅ Published properties are now `private(set)`
5. ✅ Added `error` published property

## No Breaking Changes For

- ✅ `startListening()` / `stopListening()`
- ✅ `notifications` array structure
- ✅ `unreadCount` property
- ✅ Singleton pattern (`NotificationService.shared`)
- ✅ Firebase integration

## Testing Your Migration

1. **Build the project** - Should compile without errors
2. **Check error handling** - All async methods should be in `do-catch`
3. **Test network failures** - Turn off WiFi and verify retry logic
4. **Verify badge updates** - Check badge count matches unread
5. **Test swipe actions** - Delete and mark as read should work
6. **Check memory** - Use Instruments to verify no leaks

## If You Encounter Issues

### Error: "Property 'type' requires that 'String' conform to 'NotificationType'"
**Fix**: Update notification type checking to use enum cases

### Error: "Call can throw but is not marked with 'try'"
**Fix**: Wrap in `do-catch` or add `try?` for non-critical operations

### Error: "Cannot assign to property: 'notifications' is a get-only property"
**Fix**: Don't try to modify `notifications` directly - use service methods

## Need Help?

Check the console logs - all NotificationService operations are logged with emojis:
- ✅ Success operations
- ❌ Errors
- 🔄 Retry attempts
- 📡 Listener events
- 🛑 Cleanup operations

---

**Migration Time**: ~15 minutes
**Difficulty**: Easy
**Benefits**: Better error handling, type safety, automatic retries
