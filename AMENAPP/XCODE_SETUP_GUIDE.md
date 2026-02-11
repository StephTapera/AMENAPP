# Xcode Setup Guide for Find Church

## ✅ Sample Data Removed

All sample church data has been removed! Now the app will:
- Show **empty state** on first launch
- Prompt user to grant location permission
- Enable "Live Search" to find real churches via Apple Maps
- Display previously saved churches

---

## 📋 Required Xcode Configuration

### 1️⃣ Info.plist Configuration

Add these keys to your `Info.plist`:

#### Method A: Using Source Code Editor
1. Right-click `Info.plist` → **Open As** → **Source Code**
2. Add this inside the `<dict>` tag:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location to find churches near you and provide smart service reminders.</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>We need your location to send you reminders when you're near your saved churches.</string>

<key>NSUserNotificationsUsageDescription</key>
<string>We'll send you reminders about church service times and when you're near your saved churches.</string>
```

#### Method B: Using Property List Editor
1. Open `Info.plist`
2. Click the **+** button
3. Add these keys one by one:
   - `Privacy - Location When In Use Usage Description`
   - `Privacy - Location Always and When In Use Usage Description`
   - `Privacy - User Notifications Usage Description`
4. Set the values to the descriptions above

---

### 2️⃣ Enable Background Modes

**Step-by-step:**

1. **Open your project** in Xcode
2. Select your **app target** (AMENAPP) in the project navigator
3. Click on **Signing & Capabilities** tab
4. Click **+ Capability** button (top left)
5. Search for **"Background Modes"**
6. Click to add it
7. Check these boxes:
   - ✅ **Location updates**
   
**Screenshot reference:**
```
Signing & Capabilities
├── + Capability
└── Background Modes
    ├── ☐ Audio, AirPlay, and Picture in Picture
    ├── ☐ Background fetch
    ├── ☑ Location updates  ← CHECK THIS
    ├── ☐ Remote notifications
    └── ☐ ...other options
```

**Why this is needed:**
- Location-based notifications require the app to monitor geofences
- When user enters a church's 500m radius, the system wakes your app
- Without this, location reminders won't work

---

### 3️⃣ Enable Push Notifications (Optional)

**If not already enabled:**

1. Same **Signing & Capabilities** tab
2. Click **+ Capability**
3. Search for **"Push Notifications"**
4. Click to add it

**Note:** This is for local notifications too, not just remote push notifications.

---

## ❓ MapKit Questions Answered

### Does Find Church need a MapKit API Key?

**No!** ✅

Here's why:

1. **MapKit is built into iOS**
   - No API key required
   - No registration needed
   - No usage limits or billing

2. **What you're using:**
   - `import MapKit` - Apple's native framework
   - `MKMapView` / `Map` - Displays the map
   - `MKLocalSearch` - Searches for places (churches)
   - `MKMapItem` - Represents a location

3. **Comparison to Google Maps:**
   - ❌ Google Maps: Needs API key + billing
   - ✅ Apple Maps: Free, built-in, no setup

4. **What you have in your code:**
```swift
import MapKit  // ← Native Apple framework, no key needed

// Searching for churches
let search = MKLocalSearch(request: request)
let response = try await search.start()  // ← Completely free!

// Displaying map
Map(coordinateRegion: $region, ...)  // ← No configuration needed
```

### What you DO need:
- ✅ Location permission (already implemented)
- ✅ Internet connection (for map tiles and search)
- ✅ That's it!

---

## 🚀 Complete Setup Checklist

### Required (App won't work without these)
- [ ] Add `NSLocationWhenInUseUsageDescription` to Info.plist
- [ ] Add `NSUserNotificationsUsageDescription` to Info.plist

### Recommended (For full functionality)
- [ ] Add `NSLocationAlwaysAndWhenInUseUsageDescription` to Info.plist
- [ ] Enable **Background Modes** → **Location updates**
- [ ] Enable **Push Notifications** capability

### Optional (Nice to have)
- [ ] Test on physical device (simulator has limited location)
- [ ] Add app icon
- [ ] Configure app display name

---

## 🧪 Testing Your Setup

### Test 1: Location Permission
1. Run the app
2. You should see a location permission banner
3. Tap "Enable"
4. System alert should appear asking for location permission
5. Grant permission
6. Map should center on your location

### Test 2: Live Search
1. With location enabled
2. Tap "Live Search" toggle
3. Wait a few seconds
4. Real churches should appear from Apple Maps

### Test 3: Notifications
1. Save a church (tap bookmark icon)
2. A notification banner should appear (if not already granted)
3. Grant notification permission
4. Go to Settings → Notifications → Your App
5. Verify notifications are enabled

### Test 4: Background Location
1. Save a church
2. Go to Settings → Privacy & Security → Location Services → Your App
3. You should see "While Using the App" or "Always"
4. This enables location-based notifications

---

## 🐛 Troubleshooting

### Problem: Location permission never asked
**Solution:**
- Check Info.plist has `NSLocationWhenInUseUsageDescription`
- Reset simulator: Device → Erase All Content and Settings
- On device: Settings → General → Reset → Reset Location & Privacy

### Problem: "Live Search" doesn't appear
**Solution:**
- Grant location permission first
- Check `locationManager.isAuthorized` is true
- Verify internet connection

### Problem: No churches found
**Solution:**
- Make sure you're in a populated area
- Try increasing search radius in `ChurchSearchService.swift`
- Check internet connection
- Apple Maps may have limited data in some regions

### Problem: App crashes on search
**Solution:**
- Check Xcode console for error messages
- Verify `ChurchSearchService.swift` is in your project
- Make sure location is available before searching

### Problem: Notifications not working
**Solution:**
- Check Info.plist has `NSUserNotificationsUsageDescription`
- Grant notification permission
- Verify `ChurchNotificationManager.swift` is in project
- Check notification settings in iOS Settings app

---

## 📱 Device vs Simulator

### Simulator Limitations:
- ❌ Can't test real GPS movement
- ❌ Can't test geofencing properly
- ❌ Limited location simulation
- ❌ Push notifications unreliable

### Physical Device Advantages:
- ✅ Real GPS tracking
- ✅ Actual movement detection
- ✅ Geofencing works correctly
- ✅ Full notification support
- ✅ Real-world testing

**Recommendation:** Test on a physical device for location features!

---

## 🎯 What Happens After Setup

### First Launch (No location):
```
User opens app
    ↓
Empty state appears
    ↓
Banner: "Enable Location Access"
    ↓
User taps "Enable"
    ↓
System prompt appears
    ↓
User grants permission
    ↓
Map centers on user
    ↓
"Live Search" button appears
```

### Using Live Search:
```
User taps "Live Search"
    ↓
App searches Apple Maps
    ↓
Real churches appear
    ↓
User can save churches
    ↓
Notifications scheduled
```

### Saved Churches:
```
User saves a church
    ↓
Stored in UserDefaults
    ↓
3 notifications scheduled:
  - Weekly (Saturday 7PM)
  - Pre-service (1hr before)
  - Location (within 500m)
    ↓
Persists across app launches
```

---

## 📚 Additional Resources

### Apple Documentation:
- [Requesting Location Permissions](https://developer.apple.com/documentation/corelocation/requesting_authorization_to_use_location_services)
- [MapKit Documentation](https://developer.apple.com/documentation/mapkit)
- [Local Notifications](https://developer.apple.com/documentation/usernotifications/scheduling_local_notifications)

### Your Implementation:
- `LocationManager.swift` - Handles location tracking
- `ChurchSearchService.swift` - Searches Apple Maps
- `ChurchNotificationManager.swift` - Manages notifications
- `ChurchPersistenceManager.swift` - Saves churches

---

## ✅ Summary

### You DON'T need:
- ❌ MapKit API key
- ❌ Google Maps API
- ❌ External mapping service
- ❌ Credit card for map usage
- ❌ App Store Connect configuration for MapKit

### You DO need:
- ✅ Info.plist privacy strings
- ✅ Background Modes → Location updates
- ✅ Location permission at runtime
- ✅ Notification permission at runtime
- ✅ Internet connection for search

---

**Your Find Church feature is ready to go!** 🎉

Just add the Info.plist keys and enable Background Modes, and you're all set!
