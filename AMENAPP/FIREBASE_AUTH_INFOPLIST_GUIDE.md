# Info.plist Configuration for Firebase Authentication

## 📋 Overview

This guide shows you how to configure your `Info.plist` file for Firebase Authentication, including:
- ✅ Email/Password Sign-In (already working!)
- ✅ Google Sign-In
- ✅ Sign in with Apple
- ✅ Photo Library (for profile pictures)
- ✅ Camera Access (for taking photos)

---

## 🔥 Current Setup (Email/Password)

Your app already supports **Email/Password authentication** with Firebase! No additional `Info.plist` entries needed for this. ✅

The code you have in `AuthenticationViewModel` and `SignInView` already handles:
- Sign up with email/password
- Sign in with email/password
- Password reset
- Sign out

---

## 📸 Add Photo & Camera Access (For Profile Pictures)

Add these entries to support uploading profile pictures:

### Option 1: Using Xcode UI (Recommended)

1. Open your project in Xcode
2. Click on your **AMENAPP** target
3. Select the **Info** tab
4. Click the **+** button to add new entries
5. Add these keys:

| Key | Value |
|-----|-------|
| **Privacy - Photo Library Usage Description** | `AMENAPP needs access to your photos to set your profile picture.` |
| **Privacy - Camera Usage Description** | `AMENAPP needs access to your camera to take profile pictures.` |

### Option 2: Edit Info.plist XML Directly

If you prefer to edit the raw XML file:

```xml
<!-- Photo Library Access -->
<key>NSPhotoLibraryUsageDescription</key>
<string>AMENAPP needs access to your photos to set your profile picture.</string>

<!-- Camera Access -->
<key>NSCameraUsageDescription</key>
<string>AMENAPP needs access to your camera to take profile pictures.</string>
```

---

## 🍎 Sign in with Apple (Optional)

If you want to add **Sign in with Apple** (recommended for App Store):

### Step 1: Enable in Xcode

1. Select your **AMENAPP** target
2. Go to **Signing & Capabilities** tab
3. Click **+ Capability**
4. Add **Sign in with Apple**

### Step 2: No Info.plist Changes Needed!

Sign in with Apple doesn't require any Info.plist entries. ✅

### Step 3: Add Code (I can help you with this later)

```swift
// Example - not needed right now
import AuthenticationServices

// Apple Sign In is handled natively
```

---

## 🔐 Google Sign-In (Optional)

If you want to add **Google Sign-In**:

### Step 1: Get Your Google Client ID

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Go to **Project Settings** (gear icon)
4. Scroll to **Your apps** section
5. Find your iOS app
6. Look for **GoogleService-Info.plist** → Open it
7. Find `REVERSED_CLIENT_ID` value (looks like: `com.googleusercontent.apps.123456789-xxxxx`)

### Step 2: Add URL Schemes to Info.plist

#### Option A: Using Xcode UI

1. Select your **AMENAPP** target
2. Go to **Info** tab
3. Expand **URL Types** section
4. Click **+** to add a new URL Type
5. Set:
   - **Identifier**: `com.google`
   - **URL Schemes**: Paste your `REVERSED_CLIENT_ID` value

#### Option B: Edit Info.plist XML

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <!-- Replace with your REVERSED_CLIENT_ID from GoogleService-Info.plist -->
            <string>com.googleusercontent.apps.123456789-xxxxxxxxxxxxxxxxxxxxx</string>
        </array>
        <key>CFBundleURLName</key>
        <string>com.google</string>
    </dict>
</array>
```

**⚠️ Important**: Replace `com.googleusercontent.apps.123456789-xxxxxxxxxxxxxxxxxxxxx` with YOUR actual `REVERSED_CLIENT_ID` from your `GoogleService-Info.plist` file!

### Step 3: Add Google Sign-In to Queries Schemes

```xml
<key>LSApplicationQueriesSchemes</key>
<array>
    <string>googlechrome</string>
    <string>googleplus</string>
</array>
```

---

## 📄 Complete Info.plist Example

Here's a complete example with all authentication methods:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- App Identity -->
    <key>CFBundleName</key>
    <string>AMENAPP</string>
    
    <key>CFBundleDisplayName</key>
    <string>AMEN</string>
    
    <!-- Privacy Descriptions for Photos/Camera -->
    <key>NSPhotoLibraryUsageDescription</key>
    <string>AMENAPP needs access to your photos to set your profile picture.</string>
    
    <key>NSCameraUsageDescription</key>
    <string>AMENAPP needs access to your camera to take profile pictures.</string>
    
    <!-- Google Sign-In URL Scheme (OPTIONAL - only if using Google Sign-In) -->
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <!-- Replace with YOUR REVERSED_CLIENT_ID from GoogleService-Info.plist -->
                <string>com.googleusercontent.apps.YOUR-CLIENT-ID-HERE</string>
            </array>
            <key>CFBundleURLName</key>
            <string>com.google</string>
        </dict>
    </array>
    
    <!-- Queries Schemes for Google Sign-In (OPTIONAL) -->
    <key>LSApplicationQueriesSchemes</key>
    <array>
        <string>googlechrome</string>
        <string>googleplus</string>
    </array>
    
    <!-- Standard iOS Configuration -->
    <key>UIApplicationSceneManifest</key>
    <dict>
        <key>UIApplicationSupportsMultipleScenes</key>
        <false/>
        <key>UISceneConfigurations</key>
        <dict>
            <key>UIWindowSceneSessionRoleApplication</key>
            <array>
                <dict>
                    <key>UISceneConfigurationName</key>
                    <string>Default Configuration</string>
                    <key>UISceneDelegateClassName</key>
                    <string>$(PRODUCT_MODULE_NAME).SceneDelegate</string>
                </dict>
            </array>
        </dict>
    </dict>
</dict>
</plist>
```

---

## 🎯 What You Need Right Now

For your current setup with **Email/Password authentication**, you only need:

### Minimum Required (For Profile Pictures):

```xml
<!-- Photo Library Access -->
<key>NSPhotoLibraryUsageDescription</key>
<string>AMENAPP needs access to your photos to set your profile picture.</string>

<!-- Camera Access -->
<key>NSCameraUsageDescription</key>
<string>AMENAPP needs access to your camera to take profile pictures.</string>
```

That's it! ✅

---

## 📝 How to Add These in Xcode

### Method 1: Using Xcode's Info Tab (Easiest)

1. Open Xcode
2. Select your **AMENAPP** project in the navigator
3. Select the **AMENAPP** target
4. Click the **Info** tab
5. Right-click in the list and select **Add Row**
6. Start typing "Privacy - Photo Library" and select it
7. Enter the description: `AMENAPP needs access to your photos to set your profile picture.`
8. Repeat for Camera access

### Method 2: Edit Info.plist File Directly

1. In Xcode, find **Info.plist** in the Project Navigator
2. Right-click → **Open As** → **Source Code**
3. Add the entries shown above
4. Save the file

---

## 🧪 Testing

After adding these entries:

1. **Clean Build**: Product → Clean Build Folder (⌘+Shift+K)
2. **Rebuild**: Product → Build (⌘+B)
3. **Run on Device/Simulator**
4. **Trigger Photo Picker** - You should see permission dialog with your custom message
5. **Trigger Camera** - You should see permission dialog with your custom message

---

## 🚨 Common Issues

### Issue: "This app has crashed because it attempted to access privacy-sensitive data..."

**Solution**: You forgot to add the privacy description to Info.plist. Add the keys shown above.

### Issue: Permission dialog doesn't show

**Solution**: 
1. Clean build folder
2. Delete app from simulator/device
3. Rebuild and run

### Issue: Google Sign-In not working

**Solution**:
1. Make sure `REVERSED_CLIENT_ID` matches exactly from `GoogleService-Info.plist`
2. Check that URL scheme is added correctly
3. Verify GoogleService-Info.plist is in your Xcode project

---

## 📚 What's Next?

After adding Info.plist entries:

1. ✅ **Email/Password** - Already working!
2. 📸 **Add photo picker** to ProfileView for uploading profile pictures
3. 🍎 **Add Sign in with Apple** (optional, but recommended for App Store)
4. 🔐 **Add Google Sign-In** (optional)

---

## 🎁 Quick Copy-Paste

**For right now, just add these two:**

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>AMENAPP needs access to your photos to set your profile picture.</string>

<key>NSCameraUsageDescription</key>
<string>AMENAPP needs access to your camera to take profile pictures.</string>
```

That's all you need to get started! 🚀

---

## 💡 Pro Tips

1. **Keep descriptions user-friendly** - Explain WHY you need access
2. **Be specific** - "to set your profile picture" vs "to access photos"
3. **Test on device** - Simulators sometimes behave differently
4. **Handle denials gracefully** - Show helpful UI if user denies permission

---

Need help adding Google Sign-In or Sign in with Apple? Let me know! 😊
