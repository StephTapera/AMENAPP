# Fix dSYM Upload Warnings for Firebase Frameworks

## Problem
You're seeing "Upload Symbols Failed" warnings for Firebase and Google frameworks during archive/upload to App Store Connect.

## Why This Happens
Firebase frameworks installed via Swift Package Manager don't include dSYM files. These warnings don't affect your app's functionality - only crash symbolication for Firebase's internal code.

## Solution Options

### Option 1: Ignore the Warnings (Recommended)
These warnings are safe to ignore because:
- Your app's own crash logs will still be properly symbolicated
- Only Firebase's internal framework crashes would lack symbols
- This is a common issue with SPM-installed Firebase

### Option 2: Add Build Settings to Skip Third-Party Symbols

Add these settings to your Release configuration:

1. Open Xcode
2. Select AMENAPP project → AMENAPP target → Build Settings
3. Search for "Strip Style"
4. Set to "Non-Global Symbols" for Release
5. Search for "Deployment Postprocessing"
6. Ensure it's set to "Yes" for Release

### Option 3: Disable Crashlytics Symbol Upload Script

If you have a Crashlytics upload script in Build Phases:
1. Go to Build Phases
2. Find "Upload Symbols to Crashlytics" or similar
3. Add this condition at the top of the script:

```bash
# Skip upload for third-party frameworks
if [ "${ENABLE_USER_SCRIPT_SANDBOXING}" = "YES" ]; then
    echo "Skipping symbol upload for sandboxed environment"
    exit 0
fi
```

### Option 4: Download dSYMs from Firebase Console

After each release:
1. Go to App Store Connect
2. Download the dSYMs for your build
3. Upload them to Firebase Crashlytics Console manually
4. Go to: Firebase Console → Crashlytics → Missing dSYMs

This gives you complete crash reports including framework symbols.

## Recommended Approach for AMEN App

Since you're using SPM and these warnings don't affect functionality:
- **Ignore the warnings for now**
- If you need better crash reporting later, use Option 4 to manually download and upload dSYMs from App Store Connect

## Verification

These warnings will only appear during:
- Archive builds
- TestFlight uploads
- App Store uploads

They will NOT appear during:
- Debug builds
- Simulator runs
- Device testing

Your app will work perfectly fine despite these warnings.
