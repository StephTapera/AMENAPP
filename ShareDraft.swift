
//
//  ShareDraft.swift
//  AMENAPP
//
//  Cross-process model written by AMENShareExtension, read by the main app.
//  Defined here (main target) so AMENAPPApp can decode it from App Group UserDefaults.
//  The AMENShareExtension target should also compile this file (add it in Xcode →
//  Target Membership for AMENShareExtension).
//

import Foundation

/// Written by the Share Extension into App Group UserDefaults, read by the main app on launch.
struct ShareDraft: Codable {
    var text: String
    var linkURLString: String?
    /// Path to a JPEG saved inside the App Group container.
    var imageDataPath: String?
    /// "openTable" | "testimonies" | "churchNote"
    var destination: String
    var source: String = "shareExtension"
}
