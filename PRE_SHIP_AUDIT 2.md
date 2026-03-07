# AMEN Pre-Ship Audit — Action Plan
**Audit Date**: February 26, 2026
**Auditor**: Senior iOS Staff Engineer
**Scope**: Complete codebase review for production readiness

---

## Executive Summary

**Overall Status**: 🟡 NEEDS WORK BEFORE SHIPPING

This audit identifies **36 build errors**, **5456+ print statements**, **64 Firestore listeners**, and **266 TODO/FIXME comments** that must be addressed before production release.

**Critical Findings**:
- **P0**: 36 build errors (EnhancedPostCard.swift, InteractionHelpers.swift) blocking compilation
- **P0**: 5456+ print statements revealing sensitive data and debug info
- **P1**: 64 Firestore listeners requiring lifecycle audit
- **P1**: Multiple @ObservedObject singletons in ContentView causing performance issues
- **P2**: 266 TODO/FIXME comments requiring resolution or documentation

**Recommendation**: Address all P0 issues immediately. P1 issues should be resolved before beta. P2 issues can be tracked for future releases.

---

## P0 ISSUES (Must Fix Before Any Release)

### P0-1: Build Errors Blocking Compilation
**Priority**: P0 (BLOCKER)
**Category**: Build + Release Readiness
**Files**: `EnhancedPostCard.swift`, `InteractionHelpers.swift`

**Symptom**:
- 36 compilation errors preventing app build
- Errors in template files created in previous session
- Invalid redeclaration of `ToastManager` and `ToastView`

**Root Cause**:
EnhancedPostCard.swift and InteractionHelpers.swift are TEMPLATE FILES from the native interactions implementation that were never meant to be compiled as-is. They contain placeholder code that doesn't match the actual AMEN app models and APIs.

**Evidence**:
```
AMENAPP/EnhancedPostCard.swift:85 - Value of type 'Post' has no member 'timestamp'
AMENAPP/EnhancedPostCard.swift:137 - Value of type 'Post' has no member 'reactionCounts'
AMENAPP/InteractionHelpers.swift:57 - Invalid redeclaration of 'ToastManager'
```

**Fix**:
1. REMOVE the template files that don't integrate with existing code:
   - Delete `AMENAPP/EnhancedPostCard.swift` (template - not adapted)
   - Delete `AMENAPP/EnhancedCommentRow.swift` (template - not adapted)
   - Delete `AMENAPP/EnhancedNotificationsView.swift` (template - not adapted)
   - Delete `InteractionHelpers.swift` (conflicts with existing ToastManager)

2. KEEP the production-ready integration files:
   - Keep `DeepLinkRouter.swift` (production-ready)
   - Keep `ToastManagerExtensions.swift` (extends existing ToastManager)

**Verification**:
```bash
# Build the project
xcodebuild -scheme AMENAPP -configuration Debug clean build

# Expected: Build succeeds with 0 errors
```

**Risk**: HIGH - App cannot be built or run until fixed

---

### P0-2: Production Print Statements Exposing Sensitive Data
**Priority**: P0 (SECURITY + PERFORMANCE)
**Category**: Security + Privacy
**Impact**: 5456+ print statements across codebase

**Symptom**:
Excessive logging of sensitive user data, authentication tokens, and debug information visible in production logs.

**Root Cause**:
Development print statements left in production code, including:
- User IDs and authentication tokens
- Firestore document data
- API keys and credentials
- Personal user information

**Evidence**:
```swift
// FirebaseManager.swift:87
print("🔐 FirebaseManager: Creating new user account...")
print("✅ FirebaseManager: Auth user created with ID: \(user.uid)")

// ContentView.swift:115-116
print("🔑 User authenticated: \(user.uid)")
print("📧 Email: \(user.email ?? "none")")

// PostCard.swift (multiple locations)
print("✅ Loaded user profile: \(userProfile)")
```

**Fix**:
1. **Immediate**: Replace all print statements with proper logging:
```swift
// Before
print("✅ User authenticated: \(user.uid)")

// After
#if DEBUG
os_log(.debug, log: .auth, "User authenticated: %{private}@", user.uid)
#endif
```

2. **Create logging utility**:
```swift
// Logger.swift
import OSLog

extension Logger {
    static let auth = Logger(subsystem: "com.amen.app", category: "authentication")
    static let database = Logger(subsystem: "com.amen.app", category: "database")
    static let network = Logger(subsystem: "com.amen.app", category: "network")
}
```

3. **Bulk replace strategy**:
```bash
# Find all print statements
grep -r "print(" AMENAPP/ --include="*.swift" | wc -l

# Replace with proper logging (requires manual review for sensitive data)
```

**Verification**:
```bash
# Search for remaining print statements
grep -r "print(" AMENAPP/AMENAPP/*.swift | grep -v "\/\/" | wc -l
# Expected: 0 in production code
```

**Risk**: CRITICAL - Exposing user PII, authentication tokens, and debug info in production logs

---

### P0-3: API Keys and Secrets in Source Code
**Priority**: P0 (SECURITY)
**Category**: Security + Compliance
**Impact**: 135+ files with API_KEY/SECRET/TOKEN references

**Symptom**:
API keys, secrets, and tokens potentially hardcoded in source files.

**Root Cause**:
Development keys left in code or configuration files that will be bundled with the app.

**Evidence**:
```bash
# Found in codebase
grep -r "API_KEY\|SECRET\|TOKEN" AMENAPP/ --include="*.swift"
# Result: 135 files with potential secrets
```

**Fix**:
1. **Audit all secret references**:
```bash
# Create secret audit
grep -r "API_KEY\|SECRET\|TOKEN\|api[Kk]ey\|private[Kk]ey" \
  AMENAPP/AMENAPP/*.swift -n > secret_audit.txt
```

2. **Move secrets to environment configuration**:
```swift
// Config.swift
enum Config {
    enum OpenAI {
        static var apiKey: String {
            guard let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] else {
                fatalError("OPENAI_API_KEY not found in environment")
            }
            return key
        }
    }
}
```

3. **Use Xcode configuration files**:
- Create `Config.xcconfig` for secrets (NOT checked into git)
- Add `Config.xcconfig` to `.gitignore`
- Use `$(OPENAI_API_KEY)` in Info.plist
- Read from Bundle at runtime

4. **Verify no secrets in git history**:
```bash
git log -p | grep -i "api.key\|secret" | head -20
```

**Verification**:
```bash
# No hardcoded secrets
grep -r "sk-[a-zA-Z0-9]" AMENAPP/ --include="*.swift"
grep -r "AIza[a-zA-Z0-9_-]" AMENAPP/ --include="*.swift"
# Expected: 0 results
```

**Risk**: CRITICAL - Exposed API keys lead to unauthorized access and billing fraud

---

## P1 ISSUES (Should Fix Before Beta)

### P1-1: Firestore Listener Lifecycle Management
**Priority**: P1 (MEMORY LEAKS + PERFORMANCE)
**Category**: Real-time Correctness
**Impact**: 64 Firestore listeners across codebase

**Symptom**:
- Memory leaks from listeners not being removed
- Multiple duplicate listeners causing excessive Firestore reads
- Race conditions between listener setup and teardown

**Root Cause**:
Not all Firestore listeners are properly cleaned up when views disappear or when the app backgrounds.

**Evidence**:
```swift
// FollowService.swift:63 - Good pattern with protection
private var isListening = false  // ✅ Prevents duplicates

// But many other services don't have this protection
// MessageService.swift - 4 listeners
// FirebaseMessagingService.swift - 5 listeners
// NotificationService.swift - 1 listener
```

**Services with listeners**:
- FirebaseMessagingService: 5 listeners
- MessageService: 4 listeners
- FollowService: 2 listeners
- ChurchNotesService: 2 listeners
- And 50+ more across the app

**Fix**:
1. **Audit all listener registrations**:
```bash
# Create listener audit
grep -rn "\.addSnapshotListener" AMENAPP/AMENAPP/*.swift > listener_audit.txt

# Review each listener for:
# - Is it stored in a ListenerRegistration property?
# - Is it removed in deinit or stopListening()?
# - Is there duplicate prevention (isListening flag)?
```

2. **Implement listener lifecycle pattern**:
```swift
@MainActor
class SafeListenerService: ObservableObject {
    private var listeners: [ListenerRegistration] = []
    private var isListening = false

    func startListening() {
        guard !isListening else {
            print("⚠️ Already listening, skipping duplicate")
            return
        }

        isListening = true
        let listener = db.collection("posts")
            .addSnapshotListener { [weak self] snapshot, error in
                // Handle updates
            }
        listeners.append(listener)
    }

    func stopListening() {
        guard isListening else { return }
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        isListening = false
    }

    deinit {
        stopListening()
    }
}
```

3. **Add SwiftUI lifecycle hooks**:
```swift
.onAppear {
    service.startListening()
}
.onDisappear {
    service.stopListening()
}
```

**Verification**:
```bash
# Count listener registrations
grep -r "addSnapshotListener" AMENAPP/AMENAPP/*.swift | wc -l

# For each file, verify:
# 1. Listener is stored: private var listener: ListenerRegistration?
# 2. Listener is removed: listener?.remove() in deinit or stopListening()
# 3. Duplicate prevention: guard !isListening pattern
```

**Risk**: HIGH - Memory leaks, excessive Firestore costs, battery drain

---

### P1-2: ContentView Performance - Multiple @ObservedObject Singletons
**Priority**: P1 (PERFORMANCE)
**Category**: Performance + UI Smoothness
**File**: `AMENAPP/ContentView.swift:5679`

**Symptom**:
ContentView observes 6+ singleton ObservableObjects, causing excessive view updates and UI lag.

**Root Cause**:
Every @Published change in ANY of these singletons triggers ContentView body recomputation:

**Evidence**:
```swift
// ContentView.swift
@ObservedObject private var appUsageTracker = AppUsageTracker.shared
@ObservedObject private var notificationManager = NotificationManager.shared
@ObservedObject private var badgeCountManager = BadgeCountManager.shared
@ObservedObject private var churchFocusManager = SundayChurchFocusManager.shared
@ObservedObject private var messagingService = FirebaseMessagingService.shared
@ObservedObject private var postsManager = PostsManager.shared

// PROBLEM: Any @Published change in ANY of these services
// triggers ContentView.body to recompute (expensive!)
```

**Impact**:
- ContentView recomputes on every post like/comment
- ContentView recomputes on every notification badge change
- ContentView recomputes on every message received
- This causes tab switching lag and animation jank

**Fix**:
1. **Use @StateObject only for owned objects**:
```swift
// ContentView should NOT observe these - they're not owned by ContentView
// ❌ WRONG
@ObservedObject private var notificationManager = NotificationManager.shared

// ✅ CORRECT - Pass down or use @EnvironmentObject
.environmentObject(NotificationManager.shared)
```

2. **Extract specific state needs**:
```swift
// Instead of observing entire NotificationManager
@ObservedObject private var notificationManager = NotificationManager.shared

// Extract only the state you need
@State private var notificationBadge: Int = 0

var body: some View {
    // ...
    .onReceive(NotificationManager.shared.$unreadCount) { count in
        notificationBadge = count
    }
}
```

3. **Use @EnvironmentObject for singletons**:
```swift
// AMENAPPApp.swift
@main
struct AMENAPPApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(NotificationManager.shared)
                .environmentObject(PostsManager.shared)
                .environmentObject(BadgeCountManager.shared)
        }
    }
}

// ContentView.swift
@EnvironmentObject private var notificationManager: NotificationManager
@EnvironmentObject private var postsManager: PostsManager
```

**Verification**:
```bash
# Check for @ObservedObject in ContentView
grep "@ObservedObject" AMENAPP/AMENAPP/ContentView.swift

# Expected: 0 singleton observables (use @EnvironmentObject instead)
```

**Risk**: MEDIUM - UI lag, battery drain, poor user experience

---

### P1-3: Duplicate Follow/Comment/Post Creation
**Priority**: P1 (DATA INTEGRITY)
**Category**: Data Integrity + UX
**Files**: Multiple service files

**Symptom**:
Rapid taps can create duplicate follows, comments, or posts.

**Root Cause**:
Most services have implemented duplicate prevention (✅), but some critical paths may still have gaps.

**Evidence - Services WITH protection**:
```swift
// FollowService.swift:70 ✅
private var followOperationsInProgress = Set<String>()

// CommentService.swift:39 ✅
private var inFlightCommentRequests: Set<String> = []

// UnifiedChatView.swift:P0-1 FIX ✅
@State private var isSendingMessage = false
```

**Evidence - Services NEEDING audit**:
```swift
// CreatePostView.swift - Check for duplicate post prevention
// PostCard.swift - Check reaction double-tap handling
// PrayerView.swift - Check prayer submission
```

**Fix**:
1. **Audit all user action entry points**:
```bash
# Find all user action handlers
grep -rn "func.*follow\|func.*comment\|func.*post\|func.*send" \
  AMENAPP/AMENAPP/*.swift | grep -i "async\|throws"
```

2. **Apply idempotent pattern to all user actions**:
```swift
// Standard pattern for ALL user actions
@State private var isActionInProgress = false

func handleUserAction() async {
    guard !isActionInProgress else {
        print("⚠️ Action already in progress")
        return
    }

    isActionInProgress = true
    defer { isActionInProgress = false }

    // Perform action
    try await service.performAction()
}
```

3. **Add visual feedback**:
```swift
Button("Follow") {
    Task { await handleFollow() }
}
.disabled(isActionInProgress)
.opacity(isActionInProgress ? 0.5 : 1.0)
```

**Verification**:
- Tap follow button 10 times rapidly → Only 1 follow created
- Tap send message 10 times rapidly → Only 1 message sent
- Tap submit post 5 times rapidly → Only 1 post created

**Risk**: MEDIUM - Duplicate data, confused users, increased Firestore costs

---

### P1-4: New Account Restrictions - Rate Limit Edge Cases
**Priority**: P1 (ABUSE PREVENTION)
**Category**: Safety + Moderation
**File**: `AMENAPP/NewAccountRestrictionService.swift`

**Symptom**:
New account rate limits are implemented (✅) but may have edge cases around timezone boundaries and clock changes.

**Root Cause**:
Rate limit resets use "today's date" which can be exploited by changing device timezone or may fail during DST transitions.

**Evidence**:
```swift
// NewAccountRestrictionService.swift:190
private func getTodayKey() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date())
}

// ISSUE: What happens if user changes timezone?
// ISSUE: What happens during DST transition?
```

**Fix**:
1. **Use server timestamp for rate limit tracking**:
```swift
// Store rate limit data with server timestamp
try await docRef.setData([
    "userId": userId,
    "date": today,
    actionKey: FieldValue.increment(Int64(1)),
    "lastUpdated": FieldValue.serverTimestamp(),  // ✅ Server time
    "timezone": TimeZone.current.identifier        // ✅ Track timezone
])
```

2. **Validate rate limit on backend**:
```javascript
// Cloud Function to validate rate limits server-side
exports.validateRateLimit = functions.https.onCall(async (data, context) => {
  const userId = context.auth.uid;
  const serverDate = admin.firestore.Timestamp.now().toDate();

  // Use SERVER date for rate limit checks
  const todayKey = formatDateUTC(serverDate);

  // Check against server-side limits
  const rateLimitDoc = await admin.firestore()
    .collection('user_rate_limits')
    .doc(userId)
    .get();

  // Return allowed: true/false
});
```

3. **Add rate limit bypass for verified accounts**:
```swift
// Skip rate limits for phone-verified accounts
if await PhoneVerificationService.shared.isPhoneVerified {
    return RateLimitResult(allowed: true, ...)
}
```

**Verification**:
- Create new account
- Attempt to follow 11 users (limit is 10 for newborn tier)
- Expected: 11th follow is rejected with friendly message
- Change device timezone +12 hours
- Attempt to follow again
- Expected: Still rate limited (uses server time)

**Risk**: MEDIUM - Spam accounts can bypass rate limits

---

### P1-5: Phone Verification - SMS OTP Security
**Priority**: P1 (SECURITY)
**Category**: Security + Auth
**File**: `AMENAPP/PhoneVerificationService.swift`

**Symptom**:
Phone verification implemented but lacks brute-force protection and verification timeout handling.

**Root Cause**:
No rate limiting on SMS sends, no expiration on verification codes, no attempt limiting.

**Evidence**:
```swift
// PhoneVerificationService.swift:55
func sendVerificationCode(to phoneNumber: String) async throws {
    // ⚠️ No rate limiting - user can request unlimited SMS
    // ⚠️ No cooldown between requests

    let verificationID = try await PhoneAuthProvider.provider()
        .verifyPhoneNumber(phoneNumber, uiDelegate: nil)

    self.verificationID = verificationID
    // ⚠️ No expiration tracking
}
```

**Fix**:
1. **Add SMS rate limiting**:
```swift
private var lastSMSTime: Date?
private let SMSCooldownSeconds: TimeInterval = 60

func sendVerificationCode(to phoneNumber: String) async throws {
    // Rate limit: 1 SMS per minute
    if let lastTime = lastSMSTime,
       Date().timeIntervalSince(lastTime) < SMSCooldownSeconds {
        let remaining = Int(SMSCooldownSeconds - Date().timeIntervalSince(lastTime))
        throw PhoneVerificationError.rateLimited(remainingSeconds: remaining)
    }

    lastSMSTime = Date()

    // Send SMS
    let verificationID = try await PhoneAuthProvider.provider()
        .verifyPhoneNumber(phoneNumber, uiDelegate: nil)

    self.verificationID = verificationID
    self.codeExpiresAt = Date().addingTimeInterval(300) // 5 min expiry
}
```

2. **Add verification attempt limiting**:
```swift
private var verificationAttempts: [String: Int] = [:] // phoneNumber: attemptCount

func verifyCode(_ code: String) async throws {
    guard let verificationID = verificationID else {
        throw PhoneVerificationError.noVerificationID
    }

    // Check expiration
    if let expiresAt = codeExpiresAt, Date() > expiresAt {
        throw PhoneVerificationError.codeExpired
    }

    // Limit attempts to 5
    let attempts = verificationAttempts[phoneNumber, default: 0]
    guard attempts < 5 else {
        throw PhoneVerificationError.tooManyAttempts
    }

    verificationAttempts[phoneNumber] = attempts + 1

    // Verify code
    let credential = PhoneAuthProvider.provider().credential(
        withVerificationID: verificationID,
        verificationCode: code
    )

    try await Auth.auth().currentUser?.link(with: credential)

    // Clear attempts on success
    verificationAttempts.removeValue(forKey: phoneNumber)
}
```

3. **Add backend validation**:
```javascript
// Cloud Function to prevent SMS abuse
exports.onPhoneVerificationRequest = functions.firestore
  .document('phone_verifications/{docId}')
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const phoneNumber = data.phoneNumber;

    // Check if this phone number was verified in last 24h
    const recentVerifications = await admin.firestore()
      .collection('phone_verifications')
      .where('phoneNumber', '==', phoneNumber)
      .where('createdAt', '>', Date.now() - 86400000)
      .get();

    if (recentVerifications.size > 5) {
      // Block this phone number - suspicious activity
      await snap.ref.update({ blocked: true });
    }
  });
```

**Verification**:
- Request SMS code
- Immediately request again
- Expected: "Please wait 60 seconds before requesting another code"
- Enter wrong code 6 times
- Expected: "Too many attempts. Please request a new code."

**Risk**: MEDIUM - SMS abuse, verification bypass attempts

---

## P2 ISSUES (Track for Future Releases)

### P2-1: TODO/FIXME Comments
**Priority**: P2 (TECH DEBT)
**Category**: Code Quality
**Impact**: 266 TODO/FIXME comments

**Symptom**:
266 TODO/FIXME comments scattered across codebase indicating incomplete work or known issues.

**Root Cause**:
Development TODOs not cleaned up before release.

**Evidence**:
```bash
grep -r "TODO\|FIXME" AMENAPP/ --include="*.swift" | wc -l
# Result: 266 comments
```

**Fix**:
1. **Categorize all TODOs**:
```bash
# Generate TODO report
grep -rn "TODO\|FIXME\|HACK\|XXX" AMENAPP/AMENAPP/*.swift > todo_audit.txt

# Categorize each TODO as:
# - P0: Must fix before ship (move to P0/P1 sections above)
# - P1: Should fix soon (create tickets)
# - P2: Nice to have (document and defer)
# - OBSOLETE: Remove the comment
```

2. **Common patterns to address**:
```swift
// TODO: Add error handling → Create proper try/catch blocks
// FIXME: This is slow → Profile and optimize
// HACK: Temporary workaround → Replace with proper solution
// XXX: Check if this works → Add test to verify
```

3. **Replace with tickets**:
```swift
// Before
// TODO: Add offline support for messages

// After (if deferring)
// TICKET-1234: Offline message support planned for v2.0
```

**Verification**:
```bash
# Critical TODOs should be 0
grep -r "TODO.*critical\|FIXME.*urgent\|HACK.*temporary" \
  AMENAPP/AMENAPP/*.swift | wc -l
# Expected: 0
```

**Risk**: LOW - Technical debt tracking

---

### P2-2: Excessive Markdown Documentation Files
**Priority**: P2 (CODE HYGIENE)
**Category**: Build + Release
**Impact**: 50+ .md files in AMENAPP directory

**Symptom**:
Excessive documentation and status files committed to the app bundle.

**Root Cause**:
Development documentation files not excluded from production builds.

**Evidence**:
```bash
find AMENAPP/AMENAPP -name "*.md" | wc -l
# Result: 50+ markdown files

# Examples:
# AMENAPP/AMENAPP/CHAT_NOT_OPENING_FIX.md
# AMENAPP/AMENAPP/MESSAGING_PERFORMANCE_GUIDE.md
# AMENAPP/AMENAPP/PRODUCTION_READY_CHECKLIST.md
```

**Fix**:
1. **Move documentation to docs folder**:
```bash
mkdir -p docs/implementation-guides
mv AMENAPP/AMENAPP/*.md docs/implementation-guides/
```

2. **Exclude from Xcode build**:
- Select each .md file in Xcode
- Uncheck "Target Membership" for AMENAPP target
- Or add to .xcodeproj exclude list

3. **Add .md files to .gitignore for implementation notes**:
```
# .gitignore
*_FIX.md
*_GUIDE.md
*_STATUS.md
*_COMPLETE.md
```

**Verification**:
```bash
# Build app archive
xcodebuild -scheme AMENAPP -configuration Release archive

# Check .app bundle for .md files
find ~/Library/Developer/Xcode/Archives -name "*.md"
# Expected: 0 markdown files in bundle
```

**Risk**: LOW - Slightly increased app size, potential IP exposure

---

### P2-3: Haptic Feedback Inconsistency
**Priority**: P2 (UX POLISH)
**Category**: UX Consistency
**Files**: Multiple UI files

**Symptom**:
Inconsistent haptic feedback across similar actions (some follow buttons have haptics, some don't).

**Root Cause**:
No centralized haptic feedback standard or helper.

**Evidence**:
```swift
// FollowService.swift:190 - Has haptic
let haptic = UINotificationFeedbackGenerator()
haptic.notificationOccurred(.success)

// PostCard.swift - Some buttons lack haptics
// UserProfileView.swift - Inconsistent usage
```

**Fix**:
1. **Use HapticHelper from DeepLinkRouter implementation** (already created):
```swift
// HapticHelper is defined in DeepLinkRouter.swift
enum HapticHelper {
    static func light()
    static func medium()
    static func heavy()
    static func success()
    static func warning()
    static func error()
}
```

2. **Create haptic usage guidelines**:
```markdown
# Haptic Feedback Guidelines

- Button tap: HapticHelper.light()
- Toggle switch: HapticHelper.medium()
- Success action (follow, post): HapticHelper.success()
- Error/failure: HapticHelper.error()
- Long press detected: HapticHelper.medium()
- Pull to refresh trigger: HapticHelper.light()
```

3. **Audit and standardize all haptics**:
```bash
# Find all haptic usage
grep -rn "UINotificationFeedbackGenerator\|UIImpactFeedbackGenerator" \
  AMENAPP/AMENAPP/*.swift

# Replace with HapticHelper
```

**Verification**:
Manual testing:
- Tap follow button → Light haptic
- Post created → Success haptic
- Error occurs → Error haptic
- Toggle setting → Medium haptic

**Risk**: LOW - UX inconsistency

---

## Build + Release Checklist

### Pre-Build
- [ ] All P0 issues resolved
- [ ] All P1 issues resolved or documented with mitigation
- [ ] Build succeeds with 0 errors
- [ ] Build succeeds with 0 warnings (or all warnings documented)
- [ ] No print statements in production code
- [ ] No hardcoded API keys or secrets
- [ ] All TODO/FIXME comments triaged

### Release Configuration
- [ ] Release scheme uses Release configuration
- [ ] Bitcode enabled (if required)
- [ ] Debug symbols stripped
- [ ] Optimization level: -O (optimize for speed)
- [ ] App Store provisioning profile selected
- [ ] Version number incremented
- [ ] Build number incremented

### App Store Requirements
- [ ] Privacy Policy URL configured
- [ ] Terms of Service URL configured
- [ ] App Transport Security exceptions documented
- [ ] Background modes justified and minimal
- [ ] Push notification entitlements configured
- [ ] iCloud entitlements (if used) configured
- [ ] App Review contact information current

### Security Audit
- [ ] No exposed API keys in source
- [ ] No sensitive data in UserDefaults
- [ ] HTTPS enforced for all network requests
- [ ] Certificate pinning (if applicable)
- [ ] Keychain used for sensitive data storage
- [ ] Authentication tokens stored securely

### Performance
- [ ] App launch time < 2 seconds (cold start)
- [ ] No memory leaks detected (Instruments)
- [ ] No retain cycles (Instruments)
- [ ] Smooth scrolling in all lists (60fps)
- [ ] Images properly sized and compressed
- [ ] Network requests optimized (pagination, caching)

### Testing
- [ ] Manual QA on all critical flows
- [ ] Test on iPhone SE (smallest screen)
- [ ] Test on iPhone 15 Pro Max (largest screen)
- [ ] Test on iOS 15 (minimum supported version)
- [ ] Test in Airplane mode (offline handling)
- [ ] Test with poor network (3G simulation)
- [ ] Test rapid user actions (double-taps, spam)

---

## Stress Test Script

### 1. Rapid Action Test (Duplicate Prevention)
**Objective**: Verify no duplicate follows, comments, posts, or messages

Steps:
1. Navigate to a user profile
2. Tap "Follow" button 10 times rapidly (< 1 second)
3. Verify: Only 1 follow created
4. Check Firestore console: 1 follow document
5. Refresh user's followers count: +1 (not +10)

Repeat for:
- Post comment: Tap send 10 times → 1 comment
- Create post: Tap share 10 times → 1 post
- Send message: Tap send 10 times → 1 message
- React to post: Tap heart 10 times → Toggle correctly

### 2. Listener Lifecycle Test (Memory Leaks)
**Objective**: Verify listeners are cleaned up and don't accumulate

Steps:
1. Open app, navigate to feed
2. Open Xcode Memory Graph Debugger
3. Count Firestore listener objects
4. Navigate through 10 different views
5. Return to feed
6. Take another memory snapshot
7. Verify: Listener count did not increase (should be same)

### 3. Background/Foreground Test (State Persistence)
**Objective**: Verify app handles background transitions gracefully

Steps:
1. Open app, start typing a post
2. Background app (Home button)
3. Wait 10 seconds
4. Foreground app
5. Verify: Draft post text is preserved
6. Verify: No crashes or errors
7. Verify: Realtime listeners reconnect

### 4. Poor Network Test (Error Handling)
**Objective**: Verify graceful degradation on bad network

Steps:
1. Enable Network Link Conditioner (3G, 100ms delay, 10% loss)
2. Attempt to load feed
3. Verify: Loading indicators appear
4. Verify: Skeleton/shimmer UI shown
5. Verify: Cached content displays
6. Disable network completely
7. Verify: "Offline" message shown
8. Verify: User can still browse cached content

### 5. Rate Limit Test (New Account)
**Objective**: Verify rate limits enforce correctly

Steps:
1. Create new account (age: 0 days)
2. Attempt to follow 11 users (limit: 10)
3. Verify: 11th follow shows error
4. Verify: Error message is user-friendly
5. Attempt to post 4 times (limit: 3)
6. Verify: 4th post shows error
7. Verify: Rate limit resets after 24 hours

### 6. Rapid View Navigation (Performance)
**Objective**: Verify no lag or jank during rapid navigation

Steps:
1. Open app
2. Rapidly tap between tabs: Feed → Prayer → Profile → Messages → Feed
3. Repeat 10 times
4. Verify: No visible lag or frame drops
5. Verify: No memory spikes (Instruments)
6. Verify: Tab content loads instantly from cache

---

## Firestore Listener Audit Table

| Service/View | Listener Count | Protected? | Cleanup? | Risk |
|-------------|----------------|-----------|----------|------|
| FirebaseMessagingService | 5 | ✅ Yes | ✅ deinit | LOW |
| UnifiedChatView | 1 | ✅ Yes | ✅ Task | LOW |
| FollowService | 2 | ✅ Yes | ✅ deinit | LOW |
| CommentService | (Realtime DB) | N/A | N/A | LOW |
| PostsManager | ? | ⚠️ Check | ⚠️ Check | MEDIUM |
| NotificationService | 1 | ⚠️ Check | ⚠️ Check | MEDIUM |
| MessageService | 4 | ⚠️ Check | ⚠️ Check | MEDIUM |
| ChurchNotesService | 2 | ⚠️ Check | ⚠️ Check | MEDIUM |

**Action Required**: Audit each "⚠️ Check" service to verify:
1. Listener is stored: `private var listener: ListenerRegistration?`
2. Duplicate prevention: `guard !isListening` pattern
3. Cleanup: `deinit { listener?.remove() }`

---

## Acceptance Criteria

### P0 Criteria (MUST PASS)
- [ ] App builds successfully with 0 errors
- [ ] No print statements in production build
- [ ] No exposed API keys or secrets in source code
- [ ] No crashes during basic usage (feed, post, comment, message)

### P1 Criteria (SHOULD PASS)
- [ ] All Firestore listeners have cleanup in deinit
- [ ] ContentView observes ≤ 2 singleton objects (use @EnvironmentObject)
- [ ] No duplicate follows/comments/posts/messages (rapid tap test)
- [ ] Rate limits enforce correctly for new accounts
- [ ] Phone verification has SMS rate limiting

### P2 Criteria (NICE TO HAVE)
- [ ] All TODO/FIXME comments triaged and categorized
- [ ] No .md files included in app bundle
- [ ] Consistent haptic feedback across similar actions
- [ ] Smooth 60fps scrolling on iPhone SE

---

## Contact & Escalation

**Critical Issues**: Immediately block release, notify team
**P0 Issues**: Must fix before ANY release
**P1 Issues**: Should fix before beta release
**P2 Issues**: Track for future releases

**Next Review**: After P0 fixes are complete

---

## Appendix: File Reference

### Files Requiring Immediate Attention (P0)
```
AMENAPP/EnhancedPostCard.swift (DELETE - template file)
AMENAPP/EnhancedCommentRow.swift (DELETE - template file)
AMENAPP/EnhancedNotificationsView.swift (DELETE - template file)
InteractionHelpers.swift (DELETE - conflicts with existing ToastManager)
```

### Files With Good Patterns (Reference)
```
AMENAPP/UnifiedChatView.swift:P0-1,P0-2,P0-4 fixes (duplicate prevention, listener lifecycle)
AMENAPP/FollowService.swift:70,103 (operation in-progress tracking)
AMENAPP/CommentService.swift:39 (in-flight request prevention)
AMENAPP/FirebaseMessagingService.swift:99 (conversation creation lock)
```

### Files Needing Listener Audit (P1)
```
AMENAPP/PostsManager.swift
AMENAPP/NotificationService.swift
AMENAPP/MessageService.swift
AMENAPP/ChurchNotesService.swift
AMENAPP/UserService.swift
```

---

**END OF AUDIT**
