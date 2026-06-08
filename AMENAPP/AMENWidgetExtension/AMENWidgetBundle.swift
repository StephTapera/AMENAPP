//
//  AMENWidgetBundle.swift
//  AMENWidgetExtension
//
//  @main entry point for the AMEN Widget Extension target.
//  All widget types registered here are available for users to add from
//  the Widget Gallery.
//
//  This file compiles only in the AMENWidgetExtensionExtension target;
//  it must NOT import Firebase or any framework that requires a network
//  connection — widgets run in a sandboxed extension process.
//

import WidgetKit
import SwiftUI

@main
struct AMENWidgetBundle: WidgetBundle {
    var body: some Widget {
        SelahVerseWidget()
        PrayerCountWidget()
    }
}
