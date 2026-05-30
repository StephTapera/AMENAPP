//
//  FeatureFlagServicing.swift
//  AMENAPP
//

import Foundation

protocol FeatureFlagServicing: AnyObject, Sendable {
    func isEnabled(_ flag: SupportFeatureFlag) -> Bool
}

/// Default implementation backed by SupportIntelligenceFlags.
final class DefaultFeatureFlagService: FeatureFlagServicing, @unchecked Sendable {
    private let flags: SupportIntelligenceFlags

    init(flags: SupportIntelligenceFlags = .allEnabled) {
        self.flags = flags
    }

    func isEnabled(_ flag: SupportFeatureFlag) -> Bool {
        flags.isEnabled(flag)
    }
}
