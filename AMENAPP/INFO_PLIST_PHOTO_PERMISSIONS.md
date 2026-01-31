# 📸 Add Photo Library Permissions to Info.plist

## Issue
The app needs permission to access the user's photo library for profile picture upload during onboarding. Without the proper `Info.plist` entries, iOS will **crash the app** when the user tries to select a photo.

## Solution

You need to add two privacy usage descriptions to your `Info.plist` file:

### Step 1: Locate Info.plist in Xcode

1. In Xcode, click on your **AMENAPP** project in the Project Navigator
2. Select the **AMENAPP** target
3. Click the **Info** tab at the top

### Step 2: Add Privacy Permissions

#### Option A: Using Xcode's Visual Editor (Recommended)

1. In the **Info** tab, you'll see a list of keys
2. Click the **+** button or hover over any row and click the small **+** that appears
3. Add these two entries:

| Key | Type | Value |
|-----|------|-------|
| **Privacy - Photo Library Usage Description** | String | `We need access to your photo library to select a profile picture.` |
| **Privacy - Camera Usage Description** | String | `We need access to your camera to take a profile picture.` |

#### Option B: Using Source Code (XML)

If you prefer to edit the raw XML:

1. Right-click `Info.plist` in Project Navigator
2. Choose **Open As** → **Source Code**
3. Add these lines inside the `<dict>` tag:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>We need access to your photo library to select a profile picture.</string>

<key>NSCameraUsageDescription</key>
<string>We need access to your camera to take a profile picture.</string>
```

### Step 3: Verify the Changes

Your `Info.plist` should now include these keys. When viewed as source code, it should look like:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Your existing keys... -->
    
    <!-- Photo Library Permission -->
    <key>NSPhotoLibraryUsageDescription</key>
    <string>We need access to your photo library to select a profile picture.</string>
    
    <!-- Camera Permission -->
    <key>NSCameraUsageDescription</key>
    <string>We need access to your camera to take a profile picture.</string>
    
    <!-- Your other keys... -->
</dict>
</plist>
```

### Step 4: Clean and Rebuild

1. **Clean Build Folder**: Press `Shift + Cmd + K`
2. **Rebuild**: Press `Cmd + B`
3. **Run the app**: Press `Cmd + R`

### Step 5: Test the Permission Dialog

1. Run the app and go through onboarding
2. On the "Add a Profile Photo" page, tap **"Choose Photo"**
3. You should now see a **permission dialog** that says:
   - **"AMENAPP" Would Like to Access Your Photos**
   - With the description you added
   - Options: **Select Photos...**, **Allow Access to All Photos**, **Don't Allow**

## ✅ What This Fixes

### Before (Without Info.plist entries):
- ❌ App **crashes** when user taps "Choose Photo"
- ❌ No permission dialog shown
- ❌ Error in console: "This app has crashed because it attempted to access privacy-sensitive data..."

### After (With Info.plist entries):
- ✅ Permission dialog appears
- ✅ User can grant/deny access
- ✅ PhotosPicker works correctly
- ✅ User can select profile picture

## 📝 Custom Message Suggestions

You can customize the permission messages to be more friendly and aligned with your app's tone:

### Examples:

**Friendly & Casual:**
```
"Choose a photo to personalize your AMEN profile!"
```

**Detailed & Transparent:**
```
"AMEN needs permission to access your photos so you can choose a profile picture. We only access photos you select and never share them without your permission."
```

**Faith-Focused:**
```
"Help others recognize you in the AMEN community by adding a profile picture from your photo library."
```

**Current (Professional):**
```
"We need access to your photo library to select a profile picture."
```

Choose whichever fits your app's voice best!

## 🔍 Troubleshooting

### Issue: Permission dialog still not appearing
**Solution:** 
1. Delete the app from your simulator/device
2. Clean build folder (Shift + Cmd + K)
3. Rebuild and run again

### Issue: App still crashes
**Solution:**
1. Check that the keys are spelled exactly as shown
2. Make sure they're inside the `<dict>` tag
3. Verify the Info.plist file is included in your target

### Issue: PhotosPicker not showing photos
**Solution:**
1. Check simulator/device has photos in the library
2. Try selecting "Allow Access to All Photos" when prompted
3. Check console for any permission errors

## 🎯 Next Steps

After adding these permissions, you should also consider:

1. **Add a fallback UI** if user denies permission
2. **Provide option to open Settings** if they want to change permission later
3. **Test on real device** to ensure permission flow works as expected

## Related Files

- `OnboardingOnboardingView.swift` - Profile photo page (line 524+)
- `ProfilePhotoEditView.swift` - Profile photo editing
- `AccountSettingsView.swift` - Settings where users can change photo later

---

✅ **Once you've added these entries, the photo picker will work correctly and show the permission dialog!**
