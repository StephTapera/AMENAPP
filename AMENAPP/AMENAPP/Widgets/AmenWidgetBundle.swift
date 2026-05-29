//
//  AmenWidgetBundle.swift
//  AmenWidgetExtension
//
// NOTE: This file belongs in a Widget Extension target, NOT the main app target.
// In Xcode: File → New → Target → Widget Extension, then move widget files there.
//
// @main is intentionally removed here because there is no separate Widget Extension
// target in this project yet. Re-add @main when the target is created.
//

import WidgetKit
import SwiftUI

struct AmenWidgetBundle: WidgetBundle {
    var body: some Widget {
        DailyVerseWidget()
        PrayerWidget()
    }
}
