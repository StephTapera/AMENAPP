// SpacesFeeCalculatorWrapper.swift
// AMENAPP — Spaces Monetization (Agent E)
//
// Thin wrapper re-exporting the fee math from the canonical
// SpacesFeeCalculator in AMENAPP/Spaces/Monetization/SpacesFeeCalculator.swift.
//
// IMPORTANT: This file contains NO independent fee math.
// All calculations delegate to the canonical SpacesFeeCalculator enum.
// Fee rates change in exactly one place.
//
// Usage (Agent D creation wizard and all consumers):
//   SpacesFeeCalculatorE.netAmountCents(grossCents: 999)
//   // → 940
//   SpacesFeeCalculatorE.feePreviewString(grossCents: 999, currency: "usd")
//   // → "You'll receive ~$9.40 after fees"
//
// CONTRACT_E.md documents this so Agent D can import SpacesFeeCalculatorE.

import Foundation

// MARK: - SpacesFeeCalculatorE

/// Agent E's public fee-math surface.
/// Delegates entirely to the canonical `SpacesFeeCalculator`
/// in `AMENAPP/Spaces/Monetization/SpacesFeeCalculator.swift`.
enum SpacesFeeCalculatorE {

    // MARK: - Net Amount

    /// Creator net payout in cents after all fees.
    /// Delegates to `SpacesFeeCalculator.creatorPayout(amountCents:)`.
    ///
    /// - Parameter grossCents: Purchase price in cents (e.g. 999 for $9.99).
    /// - Returns: Creator payout in cents after platform fee + Stripe fees.
    static func netAmountCents(grossCents: Int) -> Int {
        SpacesFeeCalculator.creatorPayout(amountCents: grossCents)
    }

    // MARK: - Fee Preview String

    /// Human-readable payout estimate for display in the creation wizard and locked view.
    /// e.g. "You'll receive ~$9.40 after fees" for a $9.99 product.
    static func feePreviewString(grossCents: Int, currency: String) -> String {
        let payoutCents = SpacesFeeCalculator.creatorPayout(amountCents: grossCents)
        let dollars = Double(payoutCents) / 100.0
        let symbol = currencySymbol(for: currency)
        return String(format: "You'll receive ~%@%.2f after fees", symbol, dollars)
    }

    // MARK: - Price Label (convenience re-export)

    /// Human-readable price string. Delegates to `SpacesFeeCalculator.priceLabel(config:)`.
    /// Returns "$X.XX" | "$X.XX/month" | "$X.XX/year".
    static func priceLabel(config: PriceConfig) -> String {
        SpacesFeeCalculator.priceLabel(config: config)
    }

    /// Interval descriptor. Delegates to `SpacesFeeCalculator.intervalDescription(config:)`.
    /// Returns "One-time access" | "Monthly" | "Yearly".
    static func intervalDescription(config: PriceConfig) -> String {
        SpacesFeeCalculator.intervalDescription(config: config)
    }

    // MARK: - Platform Fee Rate (read-only mirror)

    /// Platform fee rate — read-only mirror of the canonical rate.
    /// Do NOT use this for calculation; always call `netAmountCents(grossCents:)`.
    static var platformFeeRate: Double { SpacesFeeCalculator.platformFeeRate }

    // MARK: - Currency Symbol Helper

    private static func currencySymbol(for code: String) -> String {
        switch code.lowercased() {
        case "usd": return "$"
        case "eur": return "€"
        case "gbp": return "£"
        case "cad": return "CA$"
        case "aud": return "A$"
        default:    return "\(code.uppercased()) "
        }
    }
}
