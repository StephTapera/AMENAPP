# Required Info.plist Configuration for Find a Local Church

To enable location services and notifications in your AMENAPP, add the following keys to your `Info.plist` file:

## Location Services

### 1. Location When In Use Usage Description
**Key:** `NSLocationWhenInUseUsageDescription`  
**Type:** String  
**Value:** "We need your location to find nearby churches and calculate distances."

### 2. Location Always and When In Use Usage Description (Optional for location-based reminders)
**Key:** `NSLocationAlwaysAndWhenInUseUsageDescription`  
**Type:** String  
**Value:** "We can notify you when you're near saved churches and provide service reminders."

### 3. Location Always Usage Description (Optional)
**Key:** `NSLocationAlwaysUsageDescription`  
**Type:** String  
**Value:** "Enable background location to receive notifications when near your saved churches."

## Example Info.plist XML:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location to find nearby churches and calculate distances.</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>We can notify you when you're near saved churches and provide service reminders.</string>

<key>UIBackgroundModes</key>
<array>
    <string>location</string>
</array>
```

## Capabilities Required:

### In Xcode:
1. Select your project in the navigator
2. Select your target
3. Go to "Signing & Capabilities" tab
4. Click "+ Capability"
5. Add:
   - **Location** (if needed for background location)
   - **Push Notifications** (if using remote push notifications)

## Notes:

- **When In Use**: Permission to use location only when the app is active
- **Always**: Permission to use location even when the app is in the background
- The description strings should clearly explain why you need location access
- Users will see these messages when prompted for location permission
- Be transparent and specific about how you'll use their location data

## Privacy Manifest (Required for App Store)

If your app targets iOS 17+, you may also need to include a Privacy Manifest file (`PrivacyInfo.xcprivacy`) that declares your use of:
- Location data
- Reason for tracking
- Data collection practices
