# Info.plist Configuration for MusicKit

## Required Entry

Add this to your `Info.plist` file:

### Option 1: Using Xcode's Info Tab
1. Select your target
2. Go to the **Info** tab
3. Hover over any item and click the **+** button
4. Add: `Privacy - Media Library Usage Description`
5. Value: `AMENAPP uses Apple Music to provide worship songs and hymns for your spiritual journey.`

### Option 2: Edit Info.plist Directly

If editing the XML directly, add:

```xml
<key>NSAppleMusicUsageDescription</key>
<string>AMENAPP uses Apple Music to provide worship songs and hymns for your spiritual journey.</string>
```

## Full Info.plist Example

Here's how your Info.plist might look with all permissions:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- App Name -->
    <key>CFBundleName</key>
    <string>AMENAPP</string>
    
    <!-- Display Name -->
    <key>CFBundleDisplayName</key>
    <string>AMEN</string>
    
    <!-- Location Permission (for finding churches) -->
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>AMENAPP uses your location to find churches near you.</string>
    
    <!-- Notification Permission (for service reminders) -->
    <key>NSUserNotificationsUsageDescription</key>
    <string>AMENAPP sends you reminders for church services and prayer times.</string>
    
    <!-- Apple Music Permission (NEW - for worship music) -->
    <key>NSAppleMusicUsageDescription</key>
    <string>AMENAPP uses Apple Music to provide worship songs and hymns for your spiritual journey.</string>
    
    <!-- Other standard entries... -->
    <key>UIApplicationSceneManifest</key>
    <dict>
        <key>UIApplicationSupportsMultipleScenes</key>
        <false/>
    </dict>
</dict>
</plist>
```

## Privacy Descriptions - Best Practices

### Good Examples ✅
- "AMENAPP uses Apple Music to provide worship songs and hymns for your spiritual journey."
- "Access worship music, hymns, and gospel songs to enhance your faith experience."
- "Play worship music during prayer, devotionals, and church service preparation."

### Bad Examples ❌
- "We need access to music" (too vague)
- "For music" (not descriptive)
- "Required for app to work" (not truthful)

## Alternative Descriptions by Feature

Choose the one that best fits your app's focus:

### Focus on Worship
```xml
<key>NSAppleMusicUsageDescription</key>
<string>Access worship music to enhance your prayer and devotional time.</string>
```

### Focus on Church Services
```xml
<key>NSAppleMusicUsageDescription</key>
<string>Preview worship songs used in church services and prepare for Sunday worship.</string>
```

### Focus on Spiritual Growth
```xml
<key>NSAppleMusicUsageDescription</key>
<string>Enhance your spiritual journey with worship music, hymns, and gospel songs.</string>
```

### Comprehensive Description
```xml
<key>NSAppleMusicUsageDescription</key>
<string>AMENAPP uses Apple Music to provide worship songs, hymns, and gospel music for prayer, devotionals, and church service preparation.</string>
```

## Verification Checklist

Before submitting to App Store:

- [ ] Info.plist includes `NSAppleMusicUsageDescription`
- [ ] Description is user-friendly and truthful
- [ ] Description explains WHY you need access
- [ ] Description mentions specific features (worship, prayer, etc.)
- [ ] MusicKit capability is enabled in Xcode
- [ ] App ID has MusicKit enabled in Developer Portal
- [ ] Tested authorization flow on device
- [ ] Tested with and without Apple Music subscription

## Common Issues

### Issue: "Missing NSAppleMusicUsageDescription"
**Solution:** Add the key to Info.plist as shown above

### Issue: "App crashes when requesting authorization"
**Solution:** Ensure Info.plist entry exists before calling `requestAuthorization()`

### Issue: "Can't play music"
**Solution:** 
1. Check if user has Apple Music subscription
2. Verify MusicKit capability is added
3. Confirm authorization was granted

## Testing Steps

1. **Clean Build**
   - Product → Clean Build Folder
   - Rebuild project

2. **Test Authorization**
   - First launch should show permission dialog
   - Dialog should show your custom message
   - Test "Allow" flow
   - Test "Don't Allow" flow

3. **Test Music Playback**
   - With Apple Music subscription
   - Without subscription (preview only)
   - In Simulator
   - On physical device

## Xcode Capability Setup

In addition to Info.plist:

1. **Select your target**
2. **Signing & Capabilities tab**
3. **Click "+ Capability"**
4. **Add "MusicKit"**
5. **Verify it appears in capabilities list**

You should see:
```
Capabilities
├── MusicKit
└── Other capabilities...
```

## Developer Portal Setup

1. Go to [developer.apple.com](https://developer.apple.com/account/)
2. Certificates, Identifiers & Profiles
3. Select your App ID
4. Edit
5. Check **MusicKit** under App Services
6. Save

## Important Notes

- ⚠️ Users can revoke permission in Settings
- ⚠️ Handle denied state gracefully
- ⚠️ Show clear UI when authorization is needed
- ⚠️ Don't repeatedly ask for permission (bad UX)
- ✅ Provide value even without music (core church features)

## Privacy Policy Update

Remember to update your privacy policy to mention:

"Our app uses Apple Music to provide worship songs and hymns. We do not collect or store any information about your music listening habits."
