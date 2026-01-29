# 🔧 Fix: Ambiguous init() Error

## The Problem

The error `Ambiguous use of 'init()'` occurs because there are **two definitions** of the same structs:

1. **Temporary stubs** in `MessagesView.swift` (lines 1450-1540)
2. **Real implementations** in `MessagingPlaceholders.swift` (commented out)

When both exist, Swift can't determine which one to use.

## The Solution

### Step 1: Fix MessagingPlaceholders.swift

The file has a syntax error on **line 219**:

**❌ Current (broken):**
```swift
.onChange(of: selectedItem, initial: false) { newValue,<#arg#>  in
```

**✅ Fixed:**
```swift
.onChange(of: selectedItem) { _, newValue in
```

### Step 2: Uncomment MessagingPlaceholders.swift

Remove the `/*` at the top and `*/` at the bottom of the file.

### Step 3: Remove Temporary Stubs from MessagesView.swift

Delete these sections from MessagesView.swift:

**Delete lines ~1450-1540:**
```swift
// MARK: - TEMPORARY STUBS (Remove when MessagingPlaceholders.swift is fixed)

struct MessageRequest: Identifiable, Hashable {
    // ... delete entire struct
}

enum RequestAction {
    // ... delete entire enum
}

struct MessageRequestRow: View {
    // ... delete entire struct
}

struct CreateGroupView: View {
    // ... delete entire struct
}

struct MessageSettingsView: View {
    // ... delete entire struct
}

// MARK: - END TEMPORARY STUBS
```

## Quick Fix Script

If you want to do it programmatically:

```swift
// 1. Fix MessagingPlaceholders.swift line 219
// Find:
.onChange(of: selectedItem, initial: false) { newValue,<#arg#>  in

// Replace with:
.onChange(of: selectedItem) { _, newValue in

// 2. Uncomment the entire file
// Remove /* from top
// Remove */ from bottom

// 3. Delete stub section from MessagesView.swift
// Find: // MARK: - TEMPORARY STUBS
// Delete everything until: // MARK: - END TEMPORARY STUBS
```

## Verification

After fixing, you should have:

✅ `MessagingPlaceholders.swift` - Uncommented with fixed onChange
✅ `MessagesView.swift` - No stub definitions
✅ No compilation errors
✅ All sheets working (CreateGroupView, MessageSettingsView, etc.)

## Alternative: Keep Stubs Temporarily

If you're not ready to fix MessagingPlaceholders.swift yet, you can keep the stubs by:

1. Keeping MessagingPlaceholders.swift commented
2. Keeping stubs in MessagesView.swift
3. Renaming stubs to avoid conflicts:

```swift
// In MessagesView.swift, rename to:
struct TemporaryCreateGroupView: View { ... }
struct TemporaryMessageSettingsView: View { ... }

// Then use:
.sheet(isPresented: $showCreateGroup) {
    TemporaryCreateGroupView()
}
```

But this is **not recommended** - fix properly instead!

---

**Status:** Follow these steps to resolve the ambiguous init() error completely.
