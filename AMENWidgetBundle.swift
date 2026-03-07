//
//  AMENWidgetBundle.swift
//  AMENWidgetExtension
//
//  ⚠️  This file must be in the AMENWidgetExtension target ONLY (not main app).
//  Move it after creating the Widget Extension target in Xcode.
//
//  Steps:
//    1. Xcode → File → New → Target → Widget Extension
//       Name: AMENWidgetExtension
//       Uncheck "Include Configuration App Intent"
//       Uncheck "Include Live Activity"  (we have our own)
//    2. Move this file + LiveActivityViews.swift to AMENWidgetExtension target
//    3. Keep LiveActivityAttributes.swift in BOTH targets
//    4. Build — Live Activities will be active on device
//

#if canImport(ActivityKit)
import WidgetKit
import SwiftUI
import ActivityKit

@main
struct AMENWidgetBundle: WidgetBundle {
    var body: some Widget {
        ReplyAssistWidget()
    }
}
#endif
