# Console Filter Guide - See Only What Matters

## Quick Setup (30 seconds)

### Option 1: Filter to Show ONLY Reaction Logs (Recommended)

1. **Open Xcode Console** (bottom panel)
2. **Click the search/filter field** at the bottom right
3. **Paste this regex**:
   ```
   (💾|💬|🔁|💡|🙏|⚡️|SAVE|COMMENT|REPOST|LIGHTBULB|AMEN|REACTION|USER_ACTION)
   ```
4. **Enable regex mode** - Click the magnifying glass icon and select "Regular Expression"

This will show **ONLY** your reaction button logs and hide all system noise.

### Option 2: Filter to Hide System Noise

If you want to see most logs but hide the noisy ones:

1. Click the filter field
2. Paste this regex:
   ```
   ^(?!.*(nw_|Synchronous|Updating selectors|TCP Conn|Class.*overrides|commcenter|xpc was invalidated))
   ```
3. Enable "Regular Expression" mode

This **hides**:
- `nw_*` network framework logs
- `Synchronous remote object` errors
- `Updating selectors` errors
- `TCP Conn` warnings
- `Class ... overrides` warnings
- CoreTelephony XPC errors

### Option 3: Xcode Scheme-Level Suppression

For a cleaner build from the start:

1. **Product → Scheme → Edit Scheme**
2. **Run → Arguments → Environment Variables**
3. **Add these** (click + button):
   - Name: `OS_ACTIVITY_MODE`, Value: `disable`
   - Name: `OS_ACTIVITY_DT_MODE`, Value: `NO`
4. **Click Close**

## What Each Emoji Means in Logs

When using the AppLogger utility:

- 💾 **SAVE** - Save/bookmark button actions
- 💬 **COMMENT** - Comment button actions
- 🔁 **REPOST** - Repost button actions
- 💡 **LIGHTBULB** - Lightbulb reaction actions
- 🙏 **AMEN** - Amen reaction actions
- ⚡️ **REACTION** - Generic reaction actions
- ✅ **SUCCESS** - Successful operations
- ❌ **ERROR** - Error messages
- ⚠️ **WARNING** - Warning messages
- 🔍 **DEBUG** - Debug information

## Example: Filter Just Save Button Logs

Want to see ONLY save button logs? Use this filter:
```
💾|SAVE
```

## Example: Filter Just Comments and Reposts

```
💬|🔁|COMMENT|REPOST
```

## Example: See All Reactions (No System Logs)

```
💾|💬|🔁|💡|🙏|⚡️
```

## Pro Tips

### Tip 1: Save Your Filters
Xcode remembers recent searches. Once you set up a filter, you can quickly switch between:
- **All logs** (clear filter)
- **Reactions only** (your custom filter)
- **Errors only** (`❌|ERROR`)

### Tip 2: Use Multiple Console Tabs
1. Right-click the console area
2. Select "New Console"
3. Set different filters in each tab:
   - Tab 1: All reactions
   - Tab 2: Save button only
   - Tab 3: Errors and warnings only

### Tip 3: Keyboard Shortcut
- **⌘L** - Clear console (keeps filter active)
- **⌘K** - Also clears console
- **⌘F** - Jump to filter field

## Current Log Format in PostCard.swift

Your save button logs look like this:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
USER_ACTION #1: toggleSave() called
  postId: abc12345
  currentUserId: user123
  BEFORE: isSaved=false
  savedPostIds.contains: false
  Source: User tap on bookmark button
  Timestamp: 2026-02-11 10:30:45
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

To see these, use filter: `USER_ACTION|toggleSave`

## Optional: Use AppLogger for Even Cleaner Logs

Instead of:
```swift
print("⚠️ [SAVE-GUARD-1] Blocked duplicate save attempt")
```

Use:
```swift
AppLogger.logSave("Guard #1: Blocked duplicate save attempt", postId: post.firestoreId)
```

Output:
```
[💾 SAVE] [abc12345] Guard #1: Blocked duplicate save attempt
```

This makes filtering even easier!

## Quick Reference Table

| What You Want to See | Filter Regex |
|---------------------|--------------|
| All reactions | `💾\|💬\|🔁\|💡\|🙏\|⚡️` |
| Save button only | `💾\|SAVE\|toggleSave` |
| Comments only | `💬\|COMMENT` |
| Reposts only | `🔁\|REPOST` |
| Errors only | `❌\|ERROR\|Failed\|failed` |
| User actions | `USER_ACTION` |
| Firebase logs | `🔥\|Firebase` |
| Network logs | `🌐\|NETWORK` |
| Hide all system noise | `^(?!.*(nw_\|Synchronous\|TCP\|xpc))` |

## What NOT to Filter Out

Keep these visible for debugging:
- ✅ Firebase configuration logs
- ✅ Authentication state changes
- ✅ Post loading confirmations
- ✅ Real-time listener status
- ✅ Error messages from your code

## System Logs You CAN Safely Ignore

These are Apple framework internals (safe to filter out):
- `nw_connection_*` - Network framework internals
- `nw_flow_*` - Network flow management
- `Synchronous remote object proxy` - XPC communication
- `Updating selectors failed` - CoreTelephony (simulator only)
- `TCP Conn ... Failed` - Network retry logic
- `Class ... overrides` - UIKit warnings
- `Connection to service ... invalidated` - XPC errors (simulator)

## Still Too Noisy?

If you're still seeing too many logs, try this **nuclear option** filter that shows ONLY your explicit reaction logs:

```
^\[💾\|^\[💬\|^\[🔁\|^\[💡\|^\[🙏\|^\[⚡️\|USER_ACTION
```

This matches lines that **start with** your emoji categories.
