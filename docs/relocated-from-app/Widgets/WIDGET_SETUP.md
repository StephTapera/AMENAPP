# AMEN Widget Extension — Setup Reference

## Status

The Xcode project already contains a fully-configured Widget Extension target:
- **Target name**: `AMENWidgetExtensionExtension`
- **Display name**: `AMENWidgetExtension`
- **Bundle ID**: `tapera.AMENAPP.AMENWidgetExtension`
- **Deployment target**: iOS 17.0
- **Auto-sync**: `PBXFileSystemSynchronizedRootGroup` covers `AMENAPP/AMENWidgetExtension/` — any `.swift` file dropped in compiles automatically; no pbxproj edits needed.

**What is missing**: The `AMENWidgetExtension/` directory does not exist on disk. Create it and populate it with the files listed below.

---

## Step 1 — Create the directory

Create this directory (relative to the Xcode project file):

```
AMENAPP/AMENWidgetExtension/
```

Do NOT add a new Xcode target. `AMENWidgetExtensionExtension` already exists in the project.

---

## Step 2 — Create Info.plist

Build setting `INFOPLIST_FILE = AMENWidgetExtension/Info.plist` expects this file.

**`AMENAPP/AMENWidgetExtension/Info.plist`**:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.widgetkit-extension</string>
    </dict>
    <key>NSSupportsLiveActivities</key>
    <true/>
    <key>NSSupportsLiveActivitiesFrequentUpdates</key>
    <true/>
</dict>
</plist>
```

---

## Step 3 — Create the entitlements file

**`AMENAPP/AMENWidgetExtension/AMENWidgetExtension.entitlements`**:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.amen.app</string>
        <string>group.com.amenapp.shared</string>
    </array>
</dict>
</plist>
```

App Group IDs match the main app's `AMENAPP.entitlements`. Required so the widget can read `UserDefaults(suiteName:)` data written by the host.

After creating the file, wire it in Xcode:
- Target `AMENWidgetExtensionExtension` > Build Settings > `CODE_SIGN_ENTITLEMENTS`
- Set value: `AMENWidgetExtension/AMENWidgetExtension.entitlements`

---

## Step 4 — Create the WidgetBundle entry point

**`AMENAPP/AMENWidgetExtension/AMENWidgetBundle.swift`**:

```swift
import WidgetKit
import SwiftUI
import ActivityKit

@main
struct AMENWidgetBundle: WidgetBundle {
    var body: some Widget {
        SelahVerseWidget()         // Home/Lock Screen verse widget
        AmenLiveActivityWidget()   // Dynamic Island — Amen Live Activities
        ReplyAssistWidget()        // Dynamic Island — Reply Assist
    }
}
```

---

## Step 5 — Create the Selah verse widget

**`AMENAPP/AMENWidgetExtension/SelahVerseWidget.swift`**:

Reads the payload written by `SelahLockScreenWidgetPublisher` via App Group UserDefaults.
Model: `SelahLockScreenWidgetPayload` in `SelahScripture/SelahLockScreenWidgetPayload.swift`.

```swift
import WidgetKit
import SwiftUI

struct SelahVerseProvider: TimelineProvider {
    let suite = "group.com.amenapp.shared"
    let key   = "selah.lockScreen.payload.v1"

    func placeholder(in context: Context) -> SelahVerseEntry {
        .init(date: Date(), payload: .placeholder)
    }
    func getSnapshot(in context: Context, completion: @escaping (SelahVerseEntry) -> Void) {
        completion(.init(date: Date(), payload: load() ?? .placeholder))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SelahVerseEntry>) -> Void) {
        let entry   = SelahVerseEntry(date: Date(), payload: load() ?? .placeholder)
        let refresh = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
    private func load() -> SelahLockScreenWidgetPayload? {
        guard let d = UserDefaults(suiteName: suite),
              let data = d.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SelahLockScreenWidgetPayload.self, from: data)
    }
}

struct SelahVerseEntry: TimelineEntry {
    let date: Date
    let payload: SelahLockScreenWidgetPayload
}

struct SelahVerseWidgetView: View {
    let entry: SelahVerseEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.payload.headline)
                .font(.caption2).foregroundStyle(.secondary)
            Text(entry.payload.snippet)
                .font(.caption).lineLimit(3)
            Text(entry.payload.reference)
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct SelahVerseWidget: Widget {
    let kind = "SelahVerseWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SelahVerseProvider()) { entry in
            SelahVerseWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily Verse")
        .description("Continue reading or see today's verse from Selah.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}
```

---

## Step 6 — Add target membership for existing files

These files live in the main app source tree and must also compile in the widget extension.
In Xcode: select each file > File Inspector > check `AMENWidgetExtensionExtension`.

| File | Location | Provides |
|------|----------|---------|
| `AmenLiveActivityView.swift` | `AMENAPP/AMENAPP/Intelligence/` | `AmenLiveActivityWidget` + Dynamic Island UI |
| `AmenLiveActivityAttributes.swift` | `AMENAPP/AMENAPP/Intelligence/` | Shared `AmenLiveActivityAttributes` type |
| `BereanActivityAttributes.swift` | `AMENAPP/` | `BereanActivityAttributes` (already in pbxproj exception set — verify it builds) |
| `LiveActivityViews.swift` | `AMENAPP/` | `ReplyAssistWidget` + all Dynamic Island views |
| `LiveActivityAttributes.swift` | `AMENAPP/` | `ChurchServiceAttributes`, `PrayerReminderAttributes`, `WorshipMusicAttributes` |
| `SelahLockScreenWidgetPayload.swift` | `AMENAPP/SelahScripture/` | `SelahLockScreenWidgetPayload` model for `SelahVerseWidget` |

---

## Step 7 — App Group provisioning

- [ ] developer.apple.com > Identifiers > App Groups
- [ ] Confirm `group.com.amen.app` and `group.com.amenapp.shared` exist (create if missing)
- [ ] Assign both groups to App ID `tapera.AMENAPP`
- [ ] Assign both groups to App ID `tapera.AMENAPP.AMENWidgetExtension`
- [ ] Download updated provisioning profiles for both IDs
- [ ] Xcode: target `AMENWidgetExtensionExtension` > Signing & Capabilities > `+` App Groups > add both IDs

---

## Step 8 — Wire WidgetCenter reload in host app

In `SelahLockScreenWidgetPublisher` (`SelahScripture/SelahLockScreenWidgetPayload.swift`):

1. Change `appGroupSuite` from `nil` to `"group.com.amenapp.shared"`.
2. After `defaults.set(data, forKey: payloadKey)`, add:

```swift
import WidgetKit
WidgetCenter.shared.reloadTimelines(ofKind: "SelahVerseWidget")
```

---

## Files to create (summary)

| Path | Required |
|------|---------|
| `AMENAPP/AMENWidgetExtension/Info.plist` | Yes — referenced by pbxproj build setting |
| `AMENAPP/AMENWidgetExtension/AMENWidgetExtension.entitlements` | Yes — App Group UserDefaults sharing |
| `AMENAPP/AMENWidgetExtension/AMENWidgetBundle.swift` | Yes — `@main` entry point |
| `AMENAPP/AMENWidgetExtension/SelahVerseWidget.swift` | Yes — verse widget implementation |
