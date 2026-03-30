//
//  AppConstants.swift
//  AMENAPP
//
//  App-wide constants: legal URLs, support contacts, age requirements.
//

import Foundation

enum AppConstants {
    enum Legal {
        static let privacyPolicy = URL(string: "https://theamenapp.lovable.app/privacy")!
        static let termsOfService = URL(string: "https://theamenapp.lovable.app/terms")!
        static let supportEmail = "support@theamenapp.com"
        static let minimumAge = 13
    }

    enum Stripe {
        // Keys are loaded from Info.plist — NEVER hardcode live keys in source.
        static var publishableKey: String {
            Bundle.main.object(forInfoDictionaryKey: "STRIPE_PUBLISHABLE_KEY") as? String ?? ""
        }
    }

    enum ApplePay {
        static let merchantID = "merchant.com.amenapp.payments"
        static let merchantDisplayName = "AMEN"
        static let countryCode = "US"
    }
}
