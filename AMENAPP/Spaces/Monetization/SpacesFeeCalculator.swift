// SpacesFeeCalculator.swift
// AMENAPP — Spaces Monetization (Agent E)
//
// Single source of truth for all Spaces fee math.
// Platform fee rate MATCHES GivingInAppSheet.swift exactly (2%).
// Stripe processing fee is backend-only concern (never charged to giver directly);
// exposed here so payout labels stay accurate for creator.
//
// Usage:
//   SpacesFeeCalculator.creatorPayout(amountCents: 999)    // → 940 cents
//   SpacesFeeCalculator.payoutLabel(amountCents: 999)       // → "~$9.40 goes to creator"
//   SpacesFeeCalculator.priceLabel(config: priceConfig)     // → "$9.99/month"

import Foundation

enum SpacesFeeCalculator {

    // MARK: - Rate Constants

    /// Platform fee — MUST match GivingInAppSheet.swift `platformFee = effectiveAmount * 0.02`.
    static let platformFeeRate: Double = 0.02       // 2%

    /// Stripe processing rate — backend concern; used only for payout label accuracy.
    static let stripeFeeRate: Double = 0.029        // 2.9%

    /// Stripe fixed per-charge fee in cents — backend concern.
    static let stripeFixedFee: Int = 30             // $0.30

    // MARK: - Payout Math

    /// Creator net payout in cents after platform fee (2%) and Stripe fees (2.9% + $0.30).
    /// Both fees are deducted from the purchase price; the buyer always pays `amountCents`.
    /// Formula: payout = amount - platformFee - stripeFee - stripeFixed
    static func creatorPayout(amountCents: Int) -> Int {
        let amount = Double(amountCents)
        let platformFee = amount * platformFeeRate
        let stripeFee   = amount * stripeFeeRate + Double(stripeFixedFee)
        let payout = amount - platformFee - stripeFee
        // Never return negative; floor to 0 if price is impossibly low.
        return max(0, Int(payout.rounded(.down)))
    }

    // MARK: - Label Helpers

    /// Human-readable payout string: "~$X.XX goes to creator"
    /// The tilde signals this is an estimate (Stripe fees may vary by card type).
    static func payoutLabel(amountCents: Int) -> String {
        let payoutCents = creatorPayout(amountCents: amountCents)
        let dollars = Double(payoutCents) / 100.0
        return String(format: "~$%.2f goes to creator", dollars)
    }

    /// Human-readable price string for display in the purchase sheet.
    /// - oneTime / no interval → "$X.XX"
    /// - interval "month"     → "$X.XX/month"
    /// - interval "year"      → "$X.XX/year"
    static func priceLabel(config: PriceConfig) -> String {
        let dollars = Double(config.amountCents) / 100.0
        let base = String(format: "$%.2f", dollars)
        switch config.interval?.lowercased() {
        case "month":
            return "\(base)/month"
        case "year":
            return "\(base)/year"
        default:
            return base
        }
    }

    /// Interval descriptor for the purchase sheet (below the large price).
    /// - nil / "":    "One-time access"
    /// - "month":     "Monthly"
    /// - "year":      "Yearly"
    static func intervalDescription(config: PriceConfig) -> String {
        switch config.interval?.lowercased() {
        case "month": return "Monthly"
        case "year":  return "Yearly"
        default:      return "One-time access"
        }
    }
}
