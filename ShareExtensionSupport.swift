
//
//  ShareExtensionSupport.swift
//  AMENAPP
//
//  Minimal types shared between the main app target and unit tests.
//  ShareExtensionViewController provides the text-sanitization logic
//  used by the Share Extension (even though the extension is a separate
//  target, the sanitize helper is tested here so it stays in sync).
//  ShareComposeViewModel provides destination-heuristic logic for routing
//  shared content to the right AMEN destination.
//

import Foundation
import SwiftUI
import Combine

// MARK: - ShareExtensionViewController (sanitization helper)

/// Provides sanitization logic used by the Share Extension.
/// The actual UIViewController lives in the AMENShareExtension target;
/// this class exposes the testable static helper in the main target.
public final class ShareExtensionViewController {

    private init() {}

    /// Strip HTML tags, trim whitespace, cap at 500 characters.
    public static func sanitize(_ text: String) -> String {
        // Remove HTML tags
        var result = text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        // Collapse whitespace / trim
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        // Cap length
        if result.count > 500 {
            result = String(result.prefix(500))
        }
        return result
    }
}

// MARK: - ShareComposeViewModel

/// Routes shared content to the correct AMEN destination.
@MainActor
public final class ShareComposeViewModel: ObservableObject {

    public enum Destination: String, Equatable {
        case openTable   = "openTable"
        case testimonies = "testimonies"
        case churchNote  = "churchNote"
    }

    @Published public var selectedDestination: Destination = .openTable
    @Published public var shareText: String = ""

    public init() {}

    /// Suggest a destination based on a URL (e.g. bible.com → church note).
    public func suggestDestination(for url: URL) {
        let host = url.host?.lowercased() ?? ""
        if host.contains("bible.com") || host.contains("biblegateway") || host.contains("youversion") {
            selectedDestination = .churchNote
        } else {
            selectedDestination = .openTable
        }
    }

    /// Suggest a destination based on free-form text content.
    public func suggestDestinationFromText(_ text: String) {
        let lower = text.lowercased()
        let testimonyKeywords = ["testimony", "testify", "god healed", "god saved", "miracle",
                                  "breakthrough", "delivered", "my story", "changed my life"]
        if testimonyKeywords.contains(where: { lower.contains($0) }) {
            selectedDestination = .testimonies
        } else {
            selectedDestination = .openTable
        }
    }
}
