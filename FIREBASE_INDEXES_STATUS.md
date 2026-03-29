# Firebase Indexes Status

## Summary
All required Firebase indexes are already defined in `firestore.indexes.json`. The errors in the logs indicate the indexes are still building after deployment.

## Index Status

### ✅ Already Defined (Building)

1. **prayers: userId + createdAt**
   - Location: `firestore.indexes.json` lines 551-557
   - Status: Defined, currently building in Firebase Console
   - Query: `.whereField("userId", isEqualTo: uid).order(by: "createdAt", descending: true)`

2. **posts: authorId + lastCommentAt**
   - Location: `firestore.indexes.json` lines 601-609
   - Status: Defined, currently building in Firebase Console
   - Query: `.whereField("authorId", isEqualTo: authorId).order(by: "lastCommentAt")`

3. **posts: authorId + lastEchoAt**
   - Location: `firestore.indexes.json` lines 593-600
   - Status: Defined, currently building in Firebase Console
   - Query: `.whereField("authorId", isEqualTo: authorId).order(by: "lastEchoAt")`

## Firestore Rules Fixed

### ✅ stats/global Read Permission
- **Issue**: `stats/global: Missing or insufficient permissions`
- **Fix**: Added rule to `firestore 18.rules` (lines 4196-4201):
```javascript
match /stats/global {
  allow read: if isAuthenticated();
  allow write: if false;  // Server-managed only
}
```

## Action Required

1. **Deploy updated Firestore rules**:
   ```bash
   firebase deploy --only firestore:rules
   ```

2. **Wait for index builds to complete**:
   - Indexes typically take 5-30 minutes to build
   - Check status in Firebase Console → Firestore → Indexes tab
   - Or click the index creation links from the Xcode console logs

3. **Verify**:
   - After indexes finish building, the errors should disappear
   - Test queries that use these indexes in the app

## Additional Contacts Feature

### ✅ NSContactsUsageDescription Added
- **Location**: `Info.plist` line 85-86
- **Description**: "AMEN uses your contacts to help you find friends who are already on the app."
- **Feature**: Onboarding "Find Your People" contact discovery (already implemented)

## Non-Issues in Logs

The following log entries are normal iOS/Xcode behavior and can be ignored:
- `Message from debugger: killed` = Xcode stopped the session manually
- `nw_connection_copy_protocol_metadata_internal` = iOS networking internals
- `Reporter disconnected` = Xcode debugger communication
- `variant selector cell index number could not be found` = Emoji keyboard internals
- `RBSServiceErrorDomain Code=1 "Client not entitled"` = Simulator limitation

## P2: Profile Image Double Upload

**Issue**: `GTMSessionFetcher was already running for profile image`
**Root Cause**: Profile image upload may be triggered twice during onboarding completion
**Impact**: Low priority - doesn't break functionality, just creates duplicate upload attempt
**Fix**: Audit `OnboardingOnboardingView.swift` and `ProfilePhotoService.swift` to ensure upload is called once
