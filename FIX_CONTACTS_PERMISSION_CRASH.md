# Fix: Contacts Permission Crash

## Error
```
This app has crashed because it attempted to access privacy-sensitive data without a usage description.
The app's Info.plist must contain an NSContactsUsageDescription key with a string value explaining to the user how the app uses this data.
```

## Solution

You need to add a Contacts usage description to your Info.plist file.

### Method 1: Using Xcode's Visual Editor (Easiest)

1. **Open your project in Xcode**
2. **Click on AMENAPP** (the blue project icon at the top of the Project Navigator)
3. **Select AMENAPP target** (under TARGETS in the left sidebar)
4. **Click the "Info" tab** at the top
5. **Hover over any item and click the "+" button**
6. **Search for:** `Privacy - Contacts Usage Description`
7. **Set the value to:**
   ```
   Find and connect with your friends who are already on AMEN
   ```

### Method 2: Edit Info.plist as Source Code

1. **Find Info.plist** in your Project Navigator
2. **Right-click on Info.plist** → **Open As** → **Source Code**
3. **Add these lines** inside the `<dict>` tags (before the closing `</dict>`):

```xml
<key>NSContactsUsageDescription</key>
<string>Find and connect with your friends who are already on AMEN</string>
```

### Complete Info.plist Example

Here's what your Info.plist should include for all the permissions your app needs:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Photo Library Access -->
    <key>NSPhotoLibraryUsageDescription</key>
    <string>Choose a photo to personalize your AMEN profile and connect with your faith community</string>
    
    <!-- Camera Access -->
    <key>NSCameraUsageDescription</key>
    <string>Take a photo to personalize your AMEN profile and help others recognize you</string>
    
    <!-- Contacts Access (NEW - REQUIRED TO FIX CRASH) -->
    <key>NSContactsUsageDescription</key>
    <string>Find and connect with your friends who are already on AMEN</string>
    
    <!-- Face ID (if using biometric auth) -->
    <key>NSFaceIDUsageDescription</key>
    <string>Use Face ID to securely sign in to your AMEN account</string>
    
    <!-- Location (if implementing nearby features) -->
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>Find Christians and faith communities near you</string>
    
    <!-- Apple Music (if using MusicKit) -->
    <key>NSAppleMusicUsageDescription</key>
    <string>Access worship music to enhance your prayer and devotional time</string>
    
    <!-- Microphone (if adding audio features) -->
    <key>NSMicrophoneUsageDescription</key>
    <string>Record audio messages or voice prayers to share with your community</string>
    
    <!-- ... other existing keys ... -->
</dict>
</plist>
```

## Why This Happens

Your app is trying to access the user's Contacts (probably in the messaging feature to find friends), but iOS requires you to explain WHY you need this access before showing the permission dialog.

## Where Is Contacts Being Accessed?

Likely locations in your code:
- **MessagesView.swift** - Finding friends feature
- **CreateGroupView** - Adding contacts to groups
- **User search functionality** - Syncing with contacts

## After Adding the Description

1. **Clean Build Folder**: Press `⇧⌘K` (Shift + Command + K)
2. **Delete the app from simulator/device**
3. **Rebuild**: Press `⌘B` (Command + B)
4. **Run the app**: Press `⌘R` (Command + R)

When the app tries to access Contacts, iOS will now show a permission dialog with your description.

## Permission Dialog Example

When you try to access contacts, the user will see:

```
"AMENAPP" Would Like to Access Your Contacts

Find and connect with your friends who are already on AMEN

[Don't Allow]  [OK]
```

## Better Usage Descriptions

Choose one that fits your app's use case:

### Simple and Direct
```xml
<string>Find your friends who are already on AMEN</string>
```

### Community-Focused
```xml
<string>Connect with your friends and invite them to join your faith community</string>
```

### Feature-Specific
```xml
<string>Easily find and message your contacts who are on AMEN</string>
```

### Privacy-Focused
```xml
<string>We'll help you find friends on AMEN. Your contacts stay private and are never stored on our servers.</string>
```

## Handling Contact Access in Code

If you're implementing contact syncing, make sure to request permission properly:

```swift
import Contacts

func requestContactsAccess() async -> Bool {
    let store = CNContactStore()
    
    do {
        let granted = try await store.requestAccess(for: .contacts)
        return granted
    } catch {
        print("Error requesting contacts access: \(error)")
        return false
    }
}
```

## Important Notes

- ⚠️ **Users can deny this permission** - Make sure your app works without it
- ⚠️ **Don't ask for contacts immediately** - Wait until the user wants to use the feature
- ⚠️ **Provide value without contacts** - Core messaging should work even if denied
- ✅ **Show context first** - Explain the benefit before triggering the system dialog

## Testing Checklist

After adding the description:

- [ ] Clean build folder
- [ ] Delete app from device/simulator
- [ ] Rebuild and run
- [ ] Trigger contacts access (search for friends, etc.)
- [ ] Verify permission dialog shows your custom message
- [ ] Test "Allow" flow
- [ ] Test "Don't Allow" flow
- [ ] Verify app doesn't crash anymore

## If It Still Crashes

1. **Make sure you saved Info.plist**
2. **Clean build folder** (⇧⌘K)
3. **Delete derived data**:
   - Xcode → Preferences → Locations
   - Click arrow next to Derived Data path
   - Delete the AMENAPP folder
4. **Quit Xcode completely**
5. **Reopen and rebuild**

## Privacy Policy Update

Remember to update your privacy policy to mention:

"Our app may request access to your contacts to help you find friends who are already using AMEN. We do not store or share your contact information."

---

## Quick Fix Summary

**Add this ONE line to your Info.plist:**

```xml
<key>NSContactsUsageDescription</key>
<string>Find and connect with your friends who are already on AMEN</string>
```

**Then:**
1. Clean Build (⇧⌘K)
2. Delete app from device
3. Run again

**That's it!** ✅
