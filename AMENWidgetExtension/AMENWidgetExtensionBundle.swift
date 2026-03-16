//
//  AMENWidgetExtensionBundle.swift
//  AMENWidgetExtension
//
//  Entry point for the AMEN Widget Extension.
//  Registers all Live Activity widgets (Dynamic Island + Lock Screen).
//

import WidgetKit
import SwiftUI
import ActivityKit

@main
struct AMENWidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        // Dynamic Island / Live Activity widget for Reply Assist
        ReplyAssistWidget()
        // Home screen widgets
        DailyVerseWidget()
        PrayerCountWidget()
        QuickActionsWidget()
    }
}
