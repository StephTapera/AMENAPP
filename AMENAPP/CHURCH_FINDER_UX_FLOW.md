# Church Finder - Smart Permission & Notification Flow

## Visual Flow Diagram

```
User Opens "Find a Local Church"
         |
         v
[Check Location Permission]
         |
         |---- NOT Authorized ------> [Show Blue Location Banner]
         |                                    |
         |                                    v
         |                            User Taps "Enable"
         |                                    |
         |                                    v
         |                            [iOS Permission Dialog]
         |                                    |
         |                                    v
         |                            [Location Authorized ✓]
         |                                    |
         v                                    v
[Location IS Authorized] <-------------------+
         |
         v
[Calculate Distances & Sort Churches]
         |
         v
[Check Notification Permission]
         |
         |---- NOT Authorized ------> [Show Orange Notification Banner]
         |                                    |
         |                                    v
         |                            User Taps "Enable"
         |                                    |
         |                                    v
         |                            [iOS Permission Dialog]
         |                                    |
         v                                    v
[Notifications Authorized ✓] <---------------+
         |
         v
[Ready to Save Churches]
         |
         v
User Bookmarks a Church
         |
         v
[Automatically Schedule 3 Smart Notifications]
         |
         |--- Weekly Reminder (Saturday 7PM)
         |--- Pre-Service (1 hour before)
         |--- Location-Based (within 500m)
         |
         v
[Show "Smart Features Active" Banner]
```

## Permission Banner Hierarchy

### Stage 1: Location Permission (Blue)
```
┌──────────────────────────────────────────────────┐
│ 📍  Enable Location              [Enable]        │
│     Find churches near you                       │
└──────────────────────────────────────────────────┘
```

**Appears when**: Location not authorized  
**Auto-hides when**: User grants location permission  
**Color**: Blue (#007AFF)  
**Purpose**: Enable distance calculation and sorting

---

### Stage 2: Notification Permission (Orange)
```
┌──────────────────────────────────────────────────┐
│ 🔔  Enable Notifications         [Enable]        │
│     Get reminders for service times              │
└──────────────────────────────────────────────────┘
```

**Appears when**: Notifications not authorized (after location granted)  
**Auto-hides when**: User grants notification permission  
**Color**: Orange (#FF9500)  
**Purpose**: Enable smart service reminders

---

## Smart Features Banner (Appears After Saving Churches)

### Collapsed State
```
┌──────────────────────────────────────────────────┐
│ ✨ Smart Reminders Active                    ℹ️  │
│    2 churches saved • Tap for details           │
└──────────────────────────────────────────────────┘
```

### Expanded State
```
┌──────────────────────────────────────────────────┐
│ ✨ Smart Reminders Active                    🔽  │
│                                                  │
│ 🔔 Service Reminders                            │
│    1 hour before services                       │
│                                                  │
│ 📅 Weekly Alerts                                │
│    Saturday evening preview                     │
│                                                  │
│ 📍 Nearby Alerts                                │
│    When you're near your church                 │
└──────────────────────────────────────────────────┘
```

**Appears when**: User has saved 1+ churches  
**Color**: Orange with transparency  
**Interactive**: Tap to expand/collapse  

---

## Notification Types & Timing

### 1️⃣ Weekly Service Preview
**Trigger**: Every Saturday at 7:00 PM  
**Title**: "Service This Sunday"  
**Body**: "[Church Name] - [Service Time]"  
**Example**:
```
╔════════════════════════════════════════╗
║  AMEN APP                     Sat 7PM  ║
╟────────────────────────────────────────╢
║  Service This Sunday                   ║
║  Grace Community Church                ║
║  Sunday 9:00 AM & 11:00 AM            ║
╚════════════════════════════════════════╝
```

---

### 2️⃣ Pre-Service Reminder
**Trigger**: 60 minutes before service starts  
**Title**: "Service Starting Soon"  
**Body**: "[Church Name] service starts in 60 minutes"  
**Actions**: "Get Directions" | "Dismiss"  
**Example**:
```
╔════════════════════════════════════════╗
║  AMEN APP                     Sun 8AM  ║
╟────────────────────────────────────────╢
║  Service Starting Soon                 ║
║  Grace Community Church service        ║
║  starts in 60 minutes                  ║
║                                        ║
║  [Get Directions]        [Dismiss]    ║
╚════════════════════════════════════════╝
```

---

### 3️⃣ Location-Based Alert
**Trigger**: When entering 500m radius of church  
**Title**: "You're Near [Church Name]"  
**Body**: "Stop by for a visit or check service times"  
**Example**:
```
╔════════════════════════════════════════╗
║  AMEN APP                     Now      ║
╟────────────────────────────────────────╢
║  You're Near Grace Community Church   ║
║  Stop by for a visit or check         ║
║  service times                        ║
╚════════════════════════════════════════╝
```

---

## Quick Stats Banner (Location Enabled)

```
┌──────────────────────────────────────────────────┐
│ 🏢 5                │  📍 0.5 miles away         │
│    Churches Found   │     Nearest Church         │
└──────────────────────────────────────────────────┘
```

**Shows when**: Location is authorized  
**Updates**: Real-time as filters change  
**Info**:
- Left: Total churches matching current filters
- Right: Distance to closest church from user

---

## Map View Features

### Church Annotations
```
     📍 Grace Community
     ●  (Blue = Regular, Pink = Saved)
```

### User Location
```
     ◉  (Blue pulsing dot)
     You are here
```

### Center Button (Floating)
```
     ╭───╮
     │ ⊙ │  ← Tap to center on user
     ╰───╯
```

---

## Church Card States

### Collapsed View
```
┌──────────────────────────────────────────────────┐
│ 🏢  Grace Community Church            🔖   ⌄    │
│     Non-Denominational                           │
│     📍 0.5 miles away                            │
└──────────────────────────────────────────────────┘
```

### Expanded View
```
┌──────────────────────────────────────────────────┐
│ 🏢  Grace Community Church            🔖   ⌃    │
│     Non-Denominational                           │
│     📍 0.5 miles away                            │
├──────────────────────────────────────────────────┤
│ 📍 123 Main St, San Francisco, CA 94102         │
│ 🕐 Sunday 9:00 AM & 11:00 AM                    │
│    Next service in 2 days                       │
│ ☎️  (415) 555-0123                               │
│ 🌐 gracechurch.org                               │
│                                                  │
│  [📞 Call]          [📍 Directions]              │
└──────────────────────────────────────────────────┘
```

---

## Filter Chips

### View Mode Toggle
```
[ 🗺️ Map ]  ← Active (Blue)
[ 📋 List ]  ← Inactive (Gray)
```

### Saved Filter
```
[ 🔖 Saved ]  ← Active when filtering saved churches
```

### Denomination Filters
```
[ All ]  [ Baptist ]  [ Catholic ]  [ Non-Denom ]  [ Pentecostal ]
  ▲          ○            ○              ○               ○
Active    Inactive    Inactive      Inactive        Inactive
```

---

## User Journey Example

**Sarah's Experience:**

1. **Opens Church Finder**
   - Sees blue location banner
   - Taps "Enable" → Grants permission
   - Banner disappears ✓

2. **Location Enabled**
   - Churches now sorted by distance
   - "0.5 miles away" appears on nearest church
   - Quick stats show: "5 Churches Found | 0.5 miles away"
   - Orange notification banner appears

3. **Enables Notifications**
   - Taps "Enable" on notification banner
   - Grants permission
   - Banner disappears ✓

4. **Saves a Church**
   - Taps bookmark on "Grace Community Church"
   - Icon turns pink ✓
   - Smart features banner appears

5. **Receives Smart Reminders**
   - **Saturday 7 PM**: "Service This Sunday at Grace Community"
   - **Sunday 8 AM**: "Service starting in 60 minutes"
   - **Walking by church**: "You're near Grace Community Church"

6. **One-Tap Actions**
   - From notification: Taps "Get Directions"
   - Apple Maps opens with driving directions
   - Arrives at church on time! 🙏

---

## Color Legend

| Color | Use Case | Hex Code |
|-------|----------|----------|
| 🔵 Blue | Location, Primary Actions, Regular Churches | #007AFF |
| 🟠 Orange | Notifications, Smart Features | #FF9500 |
| 🩷 Pink | Saved Churches, Favorites | #FF2D55 |
| 🟢 Green | Active Status, "Nearest" Stats | #34C759 |
| ⚫ Black | Call Button, Primary Text | #000000 |
| ⚪ Gray | Secondary Actions, Inactive States | #8E8E93 |

---

## Progressive Disclosure Strategy

**Why this order matters:**

1. **Location First** - Required for core functionality (distance calc)
2. **Notifications Second** - Optional enhancement, only shown after location
3. **Smart Features Last** - Only shown when user saves churches
4. **No Overwhelm** - One permission at a time
5. **Clear Benefits** - Each banner explains why permission is needed

---

## Accessibility Features

### VoiceOver Labels
- "Enable location to find churches near you"
- "Enable notifications for service reminders"
- "Bookmark this church, currently not saved"
- "Expand to see church details"

### Dynamic Type Support
- All text scales with system font size
- Minimum touch targets: 44x44 points
- Clear visual hierarchy

### Color Contrast
- All text meets WCAG AA standards
- Icons paired with labels
- Not relying on color alone

---

## Technical Details

### Permission Checking (Async)
```swift
// Check notification status asynchronously
let settings = await UNUserNotificationCenter.current().notificationSettings()
let authorized = settings.authorizationStatus == .authorized
```

### Location Authorization
```swift
switch manager.authorizationStatus {
case .authorizedWhenInUse, .authorizedAlways:
    isAuthorized = true
case .notDetermined:
    // Show banner
case .denied:
    // Don't show banner, already denied
}
```

### Smart Notification Scheduling
```swift
// Weekly reminder
var dateComponents = DateComponents()
dateComponents.weekday = 7 // Saturday
dateComponents.hour = 19    // 7 PM
let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
```

### Geofencing
```swift
let region = CLCircularRegion(
    center: church.coordinate,
    radius: 500, // meters
    identifier: "church-\(church.id)"
)
region.notifyOnEntry = true
```

---

## Summary

The Church Finder now provides:
- 🎯 **Smart Permission Flow** - Progressive, non-intrusive
- 📍 **Location Features** - Real-time distance, map view
- 🔔 **Intelligent Reminders** - Weekly, pre-service, proximity
- 💾 **Save Functionality** - Bookmark favorite churches
- 📊 **Quick Stats** - At-a-glance information
- 🎨 **Beautiful UI** - Consistent, accessible design
- ⚡ **One-Tap Actions** - Call, directions, save
- 🚀 **Zero Friction** - Auto-scheduling, smart defaults

**Result**: A delightful, helpful experience that makes finding and connecting with local churches effortless! 🙏✨
