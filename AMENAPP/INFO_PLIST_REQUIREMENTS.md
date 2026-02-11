# Required Info.plist Privacy Keys

Add these keys to your `Info.plist` file for the app to work properly:

## Location Services

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location to find churches near you and provide personalized recommendations.</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>We use your location to notify you when you're near a saved church and to find churches nearby.</string>

<key>NSLocationAlwaysUsageDescription</key>
<string>Allow location access to receive notifications when you're near your saved churches.</string>
```

## User Notifications

```xml
<key>NSUserNotificationsUsageDescription</key>
<string>We'll send you reminders for church services and notify you when you're near a saved church.</string>
```

## Optional: Background Modes

If you want location-based notifications:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>location</string>
    <string>remote-notification</string>
</array>
```

## Complete Example Info.plist Section

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Location Permissions -->
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>AMENAPP needs your location to find churches near you and provide personalized recommendations based on your area.</string>
    
    <key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
    <string>AMENAPP uses your location to send you helpful notifications when you're near a saved church and to help you discover new churches nearby.</string>
    
    <!-- Notification Permissions -->
    <key>NSUserNotificationsUsageDescription</key>
    <string>AMENAPP sends reminders for upcoming church services, weekly notifications, and alerts when you're near your saved churches.</string>
    
    <!-- Background Modes (Optional) -->
    <key>UIBackgroundModes</key>
    <array>
        <string>location</string>
        <string>remote-notification</string>
    </array>
    
    <!-- Other required keys... -->
</dict>
</plist>
```

## How to Add to Xcode

1. Open your project in Xcode
2. Select your target
3. Go to the "Info" tab
4. Click the "+" button to add new keys
5. Search for the key names above
6. Add the description strings

## Testing Checklist

- [ ] Location "When In Use" permission requests properly
- [ ] Notification permission requests properly
- [ ] Permissions can be changed in Settings
- [ ] App handles permission denial gracefully
- [ ] Background location (if enabled) works correctly
