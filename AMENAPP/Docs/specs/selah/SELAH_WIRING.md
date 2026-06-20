# Selah Contextual — Shared-File Wiring Patch

The Selah Contextual runtime (`AIIntelligence/SelahContextual/`, committed) needs four
edits in shared files to be live. Those files (ContentView, AMENFeatureFlags,
AppUsageTracker) are **heavily co-edited by other agents** (800+ interleaved lines), so
the wiring is NOT whole-file committed — capturing those files wholesale would pull in
other agents' in-flight work. This doc is the source of truth: the snippets below are
already applied in the working tree; re-apply them on the quiet tree if a concurrent
rewrite clobbers them (it already happened once to ContentView).

`SettingsView.swift` (nav row) and `SelahContextualGatingTests.swift` are 100% Selah and
ARE committed directly alongside this doc.

---

## 1. ContentView.swift — host overlay + bulletin route

**a. Mount the ambient host.** In `contentWithEnvironmentObjects`, after the last
`.environmentObject(...)`:

```swift
            .environmentObject(NotificationService.shared)
            .environmentObject(contextManager)
            .selahContextualHost()        // ← ADD
    }
```

**b. Bulletin-capture → Camera OS.** Next to the other navigation `.onReceive` handlers
in `mainContent` (after the `.navigateToFindChurch` handler):

```swift
        // Selah Contextual: bulletin-capture suggestion opens Camera OS (gated on cameraOSEnabled)
        .onReceive(NotificationCenter.default.publisher(for: .selahOpenBulletinCapture)) { _ in
            guard featureFlags.cameraOSEnabled else { return }
            showCameraOS = true
        }
```

---

## 2. AMENFeatureFlags.swift — 9 flags (master + 5 cluster + 3 sensitive), all default OFF

**a. `@Published` accessors** (after the Sabbath cluster vars):

```swift
    @Published private(set) var selahContextualEnabled: Bool = false
    @Published private(set) var selahContextualInTheRoomEnabled: Bool = false
    @Published private(set) var selahContextualAcrossTheWeekEnabled: Bool = false
    @Published private(set) var selahContextualFlowOfLifeEnabled: Bool = false
    @Published private(set) var selahContextualRestraintSpineEnabled: Bool = false
    @Published private(set) var selahContextualTrustDepthEnabled: Bool = false
    @Published private(set) var selahContextualPhotosEnabled: Bool = false
    @Published private(set) var selahContextualScreenTimeEnabled: Bool = false
    @Published private(set) var selahContextualHealthEnabled: Bool = false
```

**b. Remote Config defaults dict** (after `"sabbath_trigger_manual_enabled"`):

```swift
            "selah_contextual_enabled": false as NSObject,
            "selah_contextual_in_the_room_enabled": false as NSObject,
            "selah_contextual_across_the_week_enabled": false as NSObject,
            "selah_contextual_flow_of_life_enabled": false as NSObject,
            "selah_contextual_restraint_spine_enabled": false as NSObject,
            "selah_contextual_trust_depth_enabled": false as NSObject,
            "selah_contextual_photos_enabled": false as NSObject,
            "selah_contextual_screentime_enabled": false as NSObject,
            "selah_contextual_health_enabled": false as NSObject,
```

**c. Remote Config fetch/apply** (after `sabbathTriggerManualEnabled = ...`):

```swift
        selahContextualEnabled = config["selah_contextual_enabled"].boolValue
        selahContextualInTheRoomEnabled = config["selah_contextual_in_the_room_enabled"].boolValue
        selahContextualAcrossTheWeekEnabled = config["selah_contextual_across_the_week_enabled"].boolValue
        selahContextualFlowOfLifeEnabled = config["selah_contextual_flow_of_life_enabled"].boolValue
        selahContextualRestraintSpineEnabled = config["selah_contextual_restraint_spine_enabled"].boolValue
        selahContextualTrustDepthEnabled = config["selah_contextual_trust_depth_enabled"].boolValue
        selahContextualPhotosEnabled = config["selah_contextual_photos_enabled"].boolValue
        selahContextualScreenTimeEnabled = config["selah_contextual_screentime_enabled"].boolValue
        selahContextualHealthEnabled = config["selah_contextual_health_enabled"].boolValue
```

---

## 3. AppUsageTracker.swift — continuous-session accessor

Additive computed property (uses the existing `currentSessionStartTime`):

```swift
    /// Read-only continuous (foreground) session length in seconds; 0 when no session
    /// is active. Consumed by Selah Contextual to drive rest / doomscroll cues.
    var continuousSessionSeconds: TimeInterval {
        guard let start = currentSessionStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }
```

---

## 4. SettingsView.swift — Wellbeing nav row (committed directly)

In `WellbeingGroupView`:

```swift
                SDNavRow(icon: "sparkles", label: "Contextual Selah") { SelahContextualSettingsView() }
```

---

## Verification

All four seams' external symbols were statically confirmed present against the live tree
(host modifier, 9 flag accessors × 3 sites, `continuousSessionSeconds`,
`SelahContextualSettingsView`). Full build is HUMAN-PENDING on a quiet tree. Flip
`selah_contextual_enabled` (+ the relevant cluster/sensitive flags) only after a green
quiet-tree build and reconciliation with the parallel Selah evaluator-service work.
