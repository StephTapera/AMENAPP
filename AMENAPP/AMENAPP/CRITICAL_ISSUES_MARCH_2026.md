# Critical Issues - March 24, 2026

## P0 Issues (Critical - Breaks User Experience)

### 1. ✅ RESOLVED - Multiple Sheet Presentation Conflict
**Issue**: "Currently, only presenting a single sheet is supported" appears 40+ times in logs
**Status**: ✅ FIXED on March 24, 2026
**Solution Applied**:
- Consolidated sheet modifiers in BereanAIAssistantView (15+ sheets → 1 coordinator)
- Consolidated sheet modifiers in ContentView (4 modals → 1 coordinator)  
- Added timing coordination in AMENAPPApp to prevent onboarding conflicts
- Used enum-based ActiveModal pattern with Identifiable protocol

**Verification**: App logs show zero sheet presentation warnings ✅

**Fix Pattern Used**:
```swift
// Instead of multiple .sheet() modifiers:
.sheet(isPresented: $showSheet1) { ... }
.sheet(isPresented: $showSheet2) { ... }
.sheet(isPresented: $showSheet3) { ... }

// Use single sheet with enum:
enum ActiveSheet { case sheet1, sheet2, sheet3 }
@State private var activeSheet: ActiveSheet?

.sheet(item: $activeSheet) { sheet in
    switch sheet {
    case .sheet1: Sheet1View()
    case .sheet2: Sheet2View()
    case .sheet3: Sheet3View()
    }
}
```

## P1 Issues (High Priority - Affects Functionality)

### 2. Missing Firestore Indexes
**Queries Failing**:
1. `authorId + lastCommentAt` (posts collection)
2. `authorId + lastEchoAt` (posts collection)
3. `category + topicTag + authorId` (posts collection with "Praise Report")

**Impact**: Queries fail silently, features don't work as expected
**Fix**: Create indexes via Firebase Console links provided in logs

### 3. Firestore Permission Errors
**Issue**: Write at `posts/999CFA55-F05F-4AB3-AB18-6D93BE34F384` failed
**Impact**: Post migration failing, some posts can't be updated
**Fix**: Update Firestore security rules to allow these writes OR fix migration logic to skip unauthorized posts

### 4. Missing Firestore Subcollection Permissions
**Issue**: Listen for query at `posts/F19E3F14-39E8-42C7-ADDF-ADE63F01E391/fasts` failed
**Impact**: Fasts subcollection can't be accessed
**Fix**: Add security rules for `/posts/{postId}/fasts` subcollection

## P2 Issues (Medium Priority - Polish/UX)

### 5. AVHapticClient Errors
**Issue**: `AVHapticClient.mm:447 - Player was not running`
**Impact**: Haptic feedback not working properly
**Root Cause**: Trying to stop haptic engine that wasn't started
**Fix**: Add proper haptic engine state management, check if engine is running before stopping

### 6. Network Protocol Warnings
**Issue**: `nw_protocol_instance_set_output_handler Not calling remove_input_handler`
**Impact**: Potential network connection leaks
**Fix**: Ensure proper network connection cleanup

### 7. StoreKit Error
**Issue**: `<SKPaymentQueue> Error in remote proxy while checking server queue`
**Impact**: In-app purchases may not work properly
**Fix**: Verify StoreKit configuration, check sandbox/production environment

### 8. Firebase Analytics Warning
**Issue**: "Failed to get the compatible conversion service"
**Impact**: Analytics conversion tracking not working
**Fix**: Link Google Ads account to Firebase Analytics (optional)

## Warnings (Low Priority - No Immediate Impact)

### 9. dSYM Warning
**Issue**: "empty dSYM file detected, dSYM was created with an executable with no debug info"
**Impact**: Crash symbolication won't work for this build
**Fix**: Enable debug symbols in build settings for Release builds

### 10. App Delegate Proxy Disabled
**Impact**: Some Firebase features require manual integration
**Status**: Intentional configuration (already handled manually)

## Resolution Priority

1. **Immediate**: Fix sheet presentation conflict (P0 #1)
2. **Today**: Create missing Firestore indexes (P1 #2)
3. **This Week**: Fix Firestore permissions (P1 #3-4)
4. **This Week**: Fix haptic feedback (P2 #5)
5. **When Needed**: Other P2/Warning items

## Next Steps

1. Find ContentView or main container view with multiple sheets
2. Audit all `.sheet()`, `.fullScreenCover()`, and `.alert()` modifiers
3. Consolidate to single presentation point per view hierarchy
4. Test thoroughly after fix
