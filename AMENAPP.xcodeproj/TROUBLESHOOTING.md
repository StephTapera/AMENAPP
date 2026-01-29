# 🔧 Troubleshooting Guide - Daily Spiritual Check-In

## Common Issues and Solutions

---

## Issue: Popup Doesn't Appear

### Symptoms
- App launches but no check-in popup shows
- Blank screen or jumps straight to main app

### Possible Causes & Solutions

**1. Already Answered Today**
```
Problem: User answered earlier, won't show again
Solution: This is expected behavior!

To test:
1. Shake device
2. Open debug panel
3. Tap "Reset Check-In"
4. Close app and reopen
```

**2. State Not Updating**
```
Problem: shouldShowCheckIn stuck at false
Solution: 

// Check in console:
print(DailyCheckInManager.shared.shouldShowCheckIn)

// Force update:
DailyCheckInManager.shared.checkIfShouldShowCheckIn()
```

**3. Delay Too Long**
```
Problem: 0.5s delay might seem too long
Solution: Reduce in AMENAPPApp.swift line 73

Change:
DispatchQueue.main.asyncAfter(deadline: .now() + 0.5)

To:
DispatchQueue.main.asyncAfter(deadline: .now() + 0.2)
```

**4. View Hierarchy Issue**
```
Problem: Other views covering popup
Solution: Check z-index values

DailyCheckInView should have highest:
.zIndex(2)  // Check-in (highest)
.zIndex(1)  // Welcome screen
.zIndex(0)  // Main content
```

---

## Issue: Block Screen Not Showing

### Symptoms
- User taps "No" but app still works
- No block screen appears

### Possible Causes & Solutions

**1. State Variable Not Set**
```
Problem: showSpiritualBlock = false
Solution:

In AMENAPPApp.swift, check handleCheckInAnswer():

if !answeredYes {
    withAnimation(.easeInOut(duration: 0.4)) {
        showSpiritualBlock = true  // ← Make sure this line exists
    }
}
```

**2. Condition Not Met**
```
Problem: Logic error in if statement
Solution:

Check onReceive notification handler:
else if !checkInManager.userAnsweredYes && checkInManager.hasAnsweredToday {
    // This should show block screen
}
```

**3. Animation Issue**
```
Problem: Block screen shows but invisible
Solution:

Check SpiritualBlockView.swift:
.opacity(isAnimating ? 1.0 : 0)
.onAppear {
    withAnimation {
        isAnimating = true  // ← Make sure this runs
    }
}
```

---

## Issue: App Crashes on Launch

### Symptoms
- App crashes immediately
- Xcode shows error message

### Possible Causes & Solutions

**1. Missing File**
```
Problem: File not added to target
Solution:

1. Select file in Xcode
2. Open File Inspector (⌥⌘1)
3. Check "Target Membership"
4. Enable your app target
```

**2. Import Error**
```
Problem: Missing import statement
Solution:

Add to files that need it:
import SwiftUI
import Combine  // For @Published
```

**3. Manager Not Initialized**
```
Problem: Singleton accessed before init
Solution:

Make sure DailyCheckInManager uses:
static let shared = DailyCheckInManager()
private init() { }  // Private constructor
```

**4. UserDefaults Error**
```
Problem: Corrupted UserDefaults
Solution:

Reset UserDefaults:
UserDefaults.standard.removePersistentDomain(
    forName: Bundle.main.bundleIdentifier!
)
```

---

## Issue: Wrong Day Detection

### Symptoms
- Shows check-in twice in same day
- Doesn't show check-in on new day

### Possible Causes & Solutions

**1. Time Zone Issues**
```
Problem: Server time vs device time mismatch
Solution:

Use device's calendar:
let calendar = Calendar.current
let today = calendar.startOfDay(for: Date())

Avoid:
let today = Date()  // Wrong! Has time component
```

**2. Date Comparison Error**
```
Problem: Using wrong comparison operator
Solution:

Correct:
if today > lastCheckInDay {
    // New day
}

Wrong:
if today != lastCheckInDay {
    // Could be earlier!
}
```

**3. UserDefaults Not Saving**
```
Problem: Data not persisted
Solution:

Force synchronize:
UserDefaults.standard.synchronize()

Or check disk space:
// Low storage can prevent saves
```

---

## Issue: Animations Laggy

### Symptoms
- Popup appears with stutter
- Block screen animations choppy

### Possible Causes & Solutions

**1. Too Many Animations**
```
Problem: Multiple animations running simultaneously
Solution:

Use .animation() modifier sparingly:
// Good:
.scaleEffect(isAnimating ? 1.0 : 0.8)
.animation(.spring(), value: isAnimating)

// Bad:
.animation(.spring())  // Animates ALL changes
```

**2. Heavy Background Tasks**
```
Problem: CPU busy with other work
Solution:

Profile with Instruments:
⌘ + I → Time Profiler
Look for bottlenecks

Ensure animations on main thread:
DispatchQueue.main.async {
    withAnimation { ... }
}
```

**3. Debug Mode Slower**
```
Problem: Running in debug configuration
Solution:

Test in Release mode:
Edit Scheme → Run → Build Configuration → Release
```

---

## Issue: Debug Panel Won't Open

### Symptoms
- Shake device but nothing happens
- Sheet doesn't appear

### Possible Causes & Solutions

**1. Shake Not Detected**
```
Problem: Simulator shake not working
Solution:

In iOS Simulator:
Device → Shake (⌃⌘Z)

Or programmatically:
NotificationCenter.default.post(
    name: .deviceDidShake,
    object: nil
)
```

**2. Sheet State Not Updating**
```
Problem: showDebugPanel stays false
Solution:

Check .onShake modifier exists:
.onShake {
    showDebugPanel = true
}

Check sheet binding:
.sheet(isPresented: $showDebugPanel) {
    DebugCheckInPanel()
}
```

**3. On Physical Device**
```
Problem: Shake too gentle
Solution:

Shake more vigorously!
Or lower threshold in UIWindow extension
```

---

## Issue: UserDefaults Not Persisting

### Symptoms
- Answer forgotten after app restart
- Check-in shows every time

### Possible Causes & Solutions

**1. Keys Mismatch**
```
Problem: Reading/writing different keys
Solution:

Use constants:
private let lastCheckInDateKey = "lastCheckInDate"

Not:
UserDefaults.standard.set(value, forKey: "lastCheckInDate")
UserDefaults.standard.object(forKey: "lastCheckinDate")
                                      // ↑ Typo!
```

**2. App Group Issue**
```
Problem: Using wrong UserDefaults suite
Solution:

Use standard:
UserDefaults.standard

Not app group (unless needed):
UserDefaults(suiteName: "group.com.app")
```

**3. Corrupted Data**
```
Problem: Bad data in UserDefaults
Solution:

Reset specific keys:
UserDefaults.standard.removeObject(forKey: "lastCheckInDate")
UserDefaults.standard.removeObject(forKey: "lastCheckInAnswer")
UserDefaults.standard.removeObject(forKey: "hasAnsweredToday")
```

---

## Issue: Build Errors

### Symptoms
- Xcode shows red errors
- Can't build project

### Common Errors & Solutions

**1. "Cannot find DailyCheckInManager in scope"**
```
Solution: Make sure file is added to target
Check: File Inspector → Target Membership
```

**2. "Type 'DailyCheckInManager' has no member 'shared'"**
```
Solution: Check singleton implementation

Should have:
static let shared = DailyCheckInManager()
```

**3. "Use of unresolved identifier 'DailyCheckInView'"**
```
Solution: Import SwiftUI at top of file

Add:
import SwiftUI
```

**4. "Cannot convert value of type 'Bool' to expected argument type 'Binding<Bool>'"**
```
Solution: Use $ prefix for binding

Change:
DailyCheckInView(isPresented: showCheckIn)

To:
DailyCheckInView(isPresented: $showCheckIn)
```

---

## Issue: Performance Problems

### Symptoms
- App feels slow
- Battery drain
- Heating

### Possible Causes & Solutions

**1. Too Many State Updates**
```
Problem: Rapid @Published changes
Solution:

Debounce updates:
import Combine

private var cancellables = Set<AnyCancellable>()

$someProperty
    .debounce(for: 0.3, scheduler: RunLoop.main)
    .sink { value in
        // Handle
    }
    .store(in: &cancellables)
```

**2. Memory Leak**
```
Problem: Views not releasing
Solution:

Use Instruments:
⌘ + I → Leaks

Common issue:
Strong reference cycles in closures

Fix:
onAnswer: { [weak self] answer in
    self?.handleAnswer(answer)
}
```

**3. Animation Overhead**
```
Problem: Continuous animations
Solution:

Use .repeatForever sparingly:
.animation(.easeInOut(duration: 2.0).repeatForever())

Prefer triggered animations:
.animation(.spring(), value: isPressed)
```

---

## Issue: Integration Conflicts

### Symptoms
- Breaks existing features
- Navigation issues
- Layout problems

### Solutions

**1. z-index Conflicts**
```
Problem: Views overlap incorrectly
Solution:

Ensure proper layering:
.zIndex(0)  // Base layer
.zIndex(1)  // Middle
.zIndex(2)  // Top (Check-in)
```

**2. Navigation Stack Issues**
```
Problem: Can't navigate after check-in
Solution:

Wrap ContentView in NavigationStack:
NavigationStack {
    ContentView()
}
```

**3. Sheet Presentation Conflict**
```
Problem: Multiple sheets competing
Solution:

Use separate bindings:
.sheet(isPresented: $showA) { ViewA() }
.sheet(isPresented: $showB) { ViewB() }

Not:
.sheet(isPresented: $show) {
    if conditionA { ViewA() }
    if conditionB { ViewB() }
}
```

---

## Debugging Checklist

When something doesn't work:

- [ ] Check console for errors
- [ ] Verify file added to target
- [ ] Confirm imports present
- [ ] Review state variable values
- [ ] Test in debug panel
- [ ] Try clean build (⌘⇧K)
- [ ] Reset UserDefaults
- [ ] Restart Xcode
- [ ] Restart simulator
- [ ] Test on physical device

---

## Debug Commands

### Check Current State
```swift
print("Should show: \(DailyCheckInManager.shared.shouldShowCheckIn)")
print("Has answered: \(DailyCheckInManager.shared.hasAnsweredToday)")
print("Answered yes: \(DailyCheckInManager.shared.userAnsweredYes)")
```

### View UserDefaults
```swift
print(UserDefaults.standard.dictionaryRepresentation())
```

### Force Reset
```swift
DailyCheckInManager.shared.reset()
```

### Simulate New Day
```swift
UserDefaults.standard.removeObject(forKey: "lastCheckInDate")
DailyCheckInManager.shared.checkIfShouldShowCheckIn()
```

### Test Animations
```swift
withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
    // Your state change
}
```

---

## Still Having Issues?

### Quick Fixes

**1. Clean Build Folder**
```
⌘ + Shift + K
Then rebuild: ⌘ + B
```

**2. Reset Simulator**
```
Device → Erase All Content and Settings
```

**3. Delete Derived Data**
```
Xcode → Preferences → Locations
Click arrow next to Derived Data
Delete AMENAPP folder
```

**4. Restart Everything**
```
1. Quit Xcode
2. Quit Simulator
3. Restart Mac (if desperate!)
4. Open Xcode
5. Clean build
6. Run
```

---

## Getting Help

### Before Asking for Help

Gather this info:
1. Xcode version
2. iOS version (simulator/device)
3. Error messages (exact text)
4. Steps to reproduce
5. What you've tried
6. Console logs

### Where to Get Help

1. **Documentation**
   - README_DAILY_CHECKIN.md
   - IMPLEMENTATION_SUMMARY.md
   - This file

2. **Debug Panel**
   - Shake device
   - View current state
   - Test functions

3. **Console Logs**
   - Look for errors
   - Check warnings
   - Print debug info

---

## Common Misconceptions

**❌ "Should show popup every time I open app"**
✅ Only shows once per day (resets at midnight)

**❌ "Block screen should disappear after a few minutes"**
✅ Stays until next day if user answered "No"

**❌ "Should work without authentication"**
✅ Works independently, but can be tied to auth if desired

**❌ "UserDefaults syncs across devices"**
✅ Local only unless you implement iCloud sync

**❌ "Debug panel should work in production"**
✅ Remove debug panel before shipping!

---

## Prevention Tips

### Before You Start
- [ ] Read documentation thoroughly
- [ ] Understand state flow
- [ ] Know how UserDefaults works
- [ ] Test in simulator first

### During Development
- [ ] Test after each change
- [ ] Use debug panel frequently
- [ ] Check console regularly
- [ ] Comment your changes

### Before Shipping
- [ ] Remove debug panel
- [ ] Test on physical device
- [ ] Test day change scenarios
- [ ] Verify animations smooth
- [ ] Check memory usage
- [ ] Test offline behavior

---

## Success Checklist

When everything works correctly:

✅ Popup appears 0.5s after first launch each day
✅ Answer "Yes" → App works normally
✅ Answer "No" → Block screen appears
✅ Block screen persists on reopen (same day)
✅ New day → Fresh popup
✅ Animations smooth (60 FPS)
✅ No memory leaks
✅ No crashes
✅ Debug panel accessible (dev only)
✅ UserDefaults persisting correctly

---

**If all else fails:**

```swift
// Nuclear option - start fresh
DailyCheckInManager.shared.reset()
UserDefaults.standard.removePersistentDomain(
    forName: Bundle.main.bundleIdentifier!
)
// Clean build
// Restart Xcode
// Try again
```

---

**Remember:** Most issues are simple fixes! Check the basics first before diving deep.

🙏 May your debugging be swift and your app be blessed!
