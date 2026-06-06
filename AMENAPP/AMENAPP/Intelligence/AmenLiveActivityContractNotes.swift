// AmenLiveActivityContractNotes.swift
// AMENAPP
//
// ============================================================
// NATIVE GAP DOCUMENTATION — Amen Live Activity Integration
// ============================================================
//
// All four Swift source files are complete and build-ready.
// The steps below CANNOT be automated from source files alone
// because they require Xcode project file (.pbxproj) GUI edits
// or xcodegen/tuist tooling. A human must perform each step.
//
// ============================================================
// STEP 1: Add NSSupportsLiveActivities to Info.plist
// ============================================================
//
// File:    AMENAPP/Info.plist
// Action:  Add the key   NSSupportsLiveActivities
//          with value    YES  (Boolean)
//
// This opts the app into Live Activities. Without it, all
// Activity.request() calls will fail silently at runtime.
//
// Xcode path: Target AMENAPP → Info tab → Custom iOS Target Properties
//   + Key: NSSupportsLiveActivities
//   + Type: Boolean
//   + Value: YES
//
// ============================================================
// STEP 2: Add AmenLiveActivityView.swift to AMENWidgetExtension
// ============================================================
//
// File:    AMENAPP/AMENAPP/Intelligence/AmenLiveActivityView.swift
// Action:  Add this file to the AMENWidgetExtension target's
//          compile sources (File Inspector → Target Membership).
//
// ALSO add AmenLiveActivityAttributes.swift to the widget extension
// target so both files share the same AmenLiveActivityAttributes type.
//
// Option A (Recommended): Reuse the existing AMENWidgetExtension target.
//   - Open Xcode file navigator
//   - Select AmenLiveActivityView.swift
//   - In File Inspector (right panel), check AMENWidgetExtension
//   - Repeat for AmenLiveActivityAttributes.swift
//
// Option B: Create a new "Widget Extension" target for Live Activities only.
//   - Xcode → File → New → Target → Widget Extension
//   - Name: AmenLiveActivityExtension
//   - Move AmenLiveActivityView.swift + AmenLiveActivityAttributes.swift
//     to that target's membership
//   - Add both to the new target's WidgetBundle @main struct
//
// WHY: ActivityConfiguration must live in a WidgetBundle (extension process),
// not in the main app process. The main app (AmenLiveActivityManager) starts,
// updates, and ends activities; the extension renders the UI.
//
// ============================================================
// STEP 3: Add AmenLiveActivityWidget to the WidgetBundle
// ============================================================
//
// File:    [AMENWidgetExtension]/[WidgetBundle file].swift
//          (wherever @main struct conforming to WidgetBundle lives)
//
// Action:  Add AmenLiveActivityWidget() to the body:
//
//   @main
//   struct AmenWidgetBundle: WidgetBundle {
//       var body: some Widget {
//           // existing widgets ...
//           if #available(iOS 16.2, *) {
//               AmenLiveActivityWidget()
//           }
//       }
//   }
//
// ============================================================
// STEP 4: Add ActivityKit.framework to AMENAPP target
// ============================================================
//
// Path:  Xcode → AMENAPP target → General →
//        Frameworks, Libraries, and Embedded Content → + button
// Add:   ActivityKit.framework
// Embed: Do Not Embed (it is a system framework)
//
// Without this, the `import ActivityKit` in AmenLiveActivityManager.swift
// and AmenLiveActivityAttributes.swift will fail to compile in the main
// app target (the widget extension gets it automatically).
//
// ============================================================
// STEP 5: Enable Push Notifications capability on AMENAPP target
// ============================================================
//
// Path:  Xcode → AMENAPP target → Signing & Capabilities → + Capability
// Add:   Push Notifications
//
// Remote Live Activity updates arrive via APNs using a special
// `liveactivity` push type. This is separate from standard push
// notifications and requires the Push Notifications entitlement.
// AmenLiveActivityManager already calls `Activity.request(pushType: .token)`
// and logs the push token — you just need the entitlement enabled so
// APNs accepts the requests.
//
// Additionally ensure AMENAPP.entitlements contains:
//   <key>aps-environment</key>
//   <string>production</string>  (or "development" for debug builds)
//
// ============================================================
// WHY THESE STEPS ARE MANUAL
// ============================================================
//
// Xcode project file modifications (.pbxproj) require GUI interaction
// or purpose-built tooling (xcodegen, tuist). Direct .pbxproj text edits
// are fragile and can corrupt the project. The source files are complete
// and correct; only the project wiring is manual.
//
// Once steps 1–5 are complete, build both targets and the Live Activities
// will activate for SPIRITUAL and LOCAL tier IntelligenceCards as described
// in AmenLiveActivityManager.swift.
//
// ============================================================

/// Marker type — exists solely to anchor this documentation file.
/// Do not instantiate or reference.
enum AmenLiveNativeGap { }
