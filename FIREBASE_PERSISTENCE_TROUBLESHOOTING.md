# Firebase Persistence Troubleshooting Guide

## If You Still Get "setPersistenceEnabled" Errors

### Step 1: Verify the Error Location
Check the stack trace to find WHERE the database is being accessed first. Look for:
- File name and line number
- The call that triggered the error
- Any service or ViewModel initialization

### Step 2: Check for Direct Database Access
Search your codebase for any direct calls to `Database.database()` outside of `RealtimeDatabaseService`:

```bash
# In Xcode, search for:
Database.database(

# Should ONLY appear in RealtimeDatabaseService.swift
```

### Step 3: Check Service Initialization Order
If you have other services that use Realtime Database, make sure they:
- ✅ Use `RealtimeDatabaseService.shared` (not their own Database instance)
- ✅ Don't access database in their `init()` method
- ✅ Use lazy properties for database references

### Step 4: Verify Static Property Order
The order matters! In `RealtimeDatabaseService`:

```swift
// ✅ CORRECT ORDER:
private static var _configuredDatabase: Database?  // 1. Declare cache first
private static let databaseURL = "..."             // 2. Then URL

private var database: Database {                   // 3. Then getter
    if let db = Self._configuredDatabase {
        return db
    }
    
    let db = Database.database(url: Self.databaseURL)  // 4. Get instance
    db.isPersistenceEnabled = true                      // 5. Enable IMMEDIATELY
    Self._configuredDatabase = db                       // 6. Cache it
    
    return db
}
```

### Step 5: Nuclear Option - Disable Persistence Temporarily
If you need to launch the app urgently, you can temporarily disable persistence:

```swift
// In RealtimeDatabaseService.swift
private var database: Database {
    if let db = Self._configuredDatabase {
        return db
    }
    
    let db = Database.database(url: Self.databaseURL)
    // db.isPersistenceEnabled = true  // COMMENTED OUT TEMPORARILY
    Self._configuredDatabase = db
    
    return db
}
```

**⚠️ WARNING**: This removes offline support! Only use temporarily for debugging.

## Common Causes

### Cause 1: Service Used in @StateObject
If a service is initialized in a SwiftUI view using `@StateObject`, it might be created during view initialization:

```swift
// ⚠️ POTENTIAL ISSUE:
struct SomeView: View {
    @StateObject var realtimeService = RealtimeDatabaseService.shared
    
    // This can trigger during SwiftUI's layout phase!
}
```

**Solution**: Use `@EnvironmentObject` or access via computed property instead.

### Cause 2: Static Property Access
If you have static properties that access the database:

```swift
// ❌ BAD:
class SomeService {
    static let database = Database.database(url: "...")  // Created at app launch!
}
```

**Solution**: Use instance properties or lazy statics.

### Cause 3: Global Variables
Any global variable that accesses the database will be initialized early:

```swift
// ❌ BAD:
let globalDatabase = Database.database(url: "...")  // Created immediately!
```

**Solution**: Use singletons or dependency injection instead.

## Verification Checklist

After making changes, verify:

- [ ] App launches without crashes
- [ ] Console shows: "🔥 Configuring Realtime Database persistence..."
- [ ] Console shows: "✅ Realtime Database configured with persistence enabled"
- [ ] No error messages about `setPersistenceEnabled`
- [ ] Data loads when offline (test by enabling Airplane Mode)
- [ ] Data syncs when coming back online

## Still Having Issues?

### Add Debug Logging
Add this to the top of `RealtimeDatabaseService`:

```swift
private var database: Database {
    print("⚠️ DEBUG: database getter called")
    print("   Thread: \(Thread.current)")
    print("   Stack trace: \(Thread.callStackSymbols)")
    
    if let db = Self._configuredDatabase {
        print("   Using cached database instance")
        return db
    }
    
    print("   Creating NEW database instance")
    // ... rest of code
}
```

This will help identify:
- When the database is first accessed
- What code is triggering it
- If it's being called multiple times

### Test in Isolation
Create a minimal test app with just Firebase setup to verify the pattern works:

```swift
import FirebaseDatabase

class TestService {
    static let shared = TestService()
    private static var _db: Database?
    
    private var database: Database {
        if let db = Self._db {
            return db
        }
        let db = Database.database(url: "YOUR_URL")
        db.isPersistenceEnabled = true
        Self._db = db
        return db
    }
}
```

If this works in isolation but not in your app, the issue is timing/initialization order.

---

**Last Updated**: January 24, 2026
**For Help**: Review FIREBASE_PERSISTENCE_FIX.md for the full solution
