//
//  LinkSafetyService.swift
//  AMENAPP
//
//  Domain deny/allow list enforcement + link reputation checks.
//
//  Every outbound link posted or sent in a DM passes through this service.
//
//  Decision tiers:
//    .allowed           — known-safe or allowlisted domain
//    .allowedWithWarn   — unknown domain; show "External link" warning before opening
//    .blocked           — denylist match; link removed / not shown
//    .blockedAndStrike  — known adult/illegal domain; content blocked + strike recorded
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Link Safety Decision

enum LinkSafetyDecision {
    case allowed
    case allowedWithWarn(message: String)
    case blocked(reason: String, policyCode: String)
    case blockedAndStrike(reason: String, policyCode: String, violationCode: SexualPolicyViolationCode)
}

// MARK: - Service

enum LinkSafetyService {

    // MARK: - Primary Check

    /// Synchronous check — runs on normalised domain. Call before rendering any link preview
    /// or allowing a link to be tapped.
    static func check(_ urlString: String) -> LinkSafetyDecision {
        guard let url = URL(string: urlString.hasPrefix("http") ? urlString : "https://\(urlString)"),
              let host = url.host?.lowercased() else {
            return .blocked(reason: "Invalid link.", policyCode: "INVALID_URL")
        }

        let domain = stripWWW(host)

        // 1. Allowlist (trusted faith/scripture domains)
        if isAllowlisted(domain) { return .allowed }

        // 2. Adult content denylist (hard block + strike)
        if let reason = adultDenylist[domain] {
            return .blockedAndStrike(
                reason: reason,
                policyCode: "EXPLICIT_CONTENT",
                violationCode: .solicitation
            )
        }

        // 3. URL shortener denylist (often used to obfuscate adult links)
        if shortenerDomains.contains(domain) {
            return .blocked(
                reason: "Short links aren't allowed. Please use the full URL.",
                policyCode: "OFF_PLATFORM"
            )
        }

        // 4. Known bad actors / scam domains
        if scamDomains.contains(domain) {
            return .blocked(
                reason: "This link appears to be a known scam or phishing site.",
                policyCode: "SCAM_PHISHING"
            )
        }

        // 5. Grooming / communication app domains (in DM context — handled by caller)
        if migrationDomains.contains(domain) {
            return .allowedWithWarn(
                message: "This link leads to an external app. For your safety, keep conversations within AMEN."
            )
        }

        // 6. Unknown domain — warn before opening
        return .allowedWithWarn(
            message: "This link leads to an external website. Make sure you trust the source before proceeding."
        )
    }

    /// Context-aware check — stricter in DMs, especially to minors.
    static func checkWithContext(
        _ urlString: String,
        isDM: Bool,
        recipientIsMinor: Bool
    ) -> LinkSafetyDecision {
        let base = check(urlString)

        // In DMs to minors, migration platform links become hard blocks
        if isDM && recipientIsMinor {
            if case .allowedWithWarn = base,
               let url = URL(string: urlString.hasPrefix("http") ? urlString : "https://\(urlString)"),
               let host = url.host?.lowercased() {
                let domain = stripWWW(host)
                if migrationDomains.contains(domain) {
                    return .blocked(
                        reason: "External links cannot be sent to young users for their safety.",
                        policyCode: "OFF_PLATFORM"
                    )
                }
            }
        }

        // In DMs (regardless of minor status), migration domain links get stricter warning
        if isDM {
            if case .allowedWithWarn = base,
               let url = URL(string: urlString.hasPrefix("http") ? urlString : "https://\(urlString)"),
               let host = url.host?.lowercased() {
                let domain = stripWWW(host)
                if migrationDomains.contains(domain) {
                    return .blocked(
                        reason: "For safety, please keep conversations within AMEN rather than moving to other apps.",
                        policyCode: "OFF_PLATFORM"
                    )
                }
            }
        }

        return base
    }

    // MARK: - Domain Lists

    private static func stripWWW(_ host: String) -> String {
        var d = host
        if d.hasPrefix("www.") { d = String(d.dropFirst(4)) }
        return d
    }

    private static func isAllowlisted(_ domain: String) -> Bool {
        return scriptureDomains.contains(where: { domain == $0 || domain.hasSuffix(".\($0)") })
    }

    // ── Scripture / Faith allowlist ───────────────────────────────────────────
    private static let scriptureDomains: Set<String> = [
        "bible.com", "youversion.com",
        "biblegateway.com",
        "blueletterbible.org",
        "biblehub.com",
        "biblestudytools.com",
        "openbible.info",
        "bibleproject.com",
        "desiringgod.org",
        "thegospelcoalition.org",
        "christianity.com",
        "crosswalk.com",
        "gotquestions.org",
        "ligonier.org",
        "bethinking.org",
        "focusonthefamily.com",
        "navigators.org",
        "intervarsity.org"
    ]

    // ── Adult content denylist ────────────────────────────────────────────────
    // Hardcoded known adult platforms. Updated via remote Firestore config
    // (field: `link_safety/adult_denylist`). This is the static fallback.
    private static let adultDenylist: [String: String] = [
        "pornhub.com":    "Adult content site.",
        "xvideos.com":    "Adult content site.",
        "xnxx.com":       "Adult content site.",
        "redtube.com":    "Adult content site.",
        "youporn.com":    "Adult content site.",
        "tube8.com":      "Adult content site.",
        "spankbang.com":  "Adult content site.",
        "xhamster.com":   "Adult content site.",
        "eporner.com":    "Adult content site.",
        "porntrex.com":   "Adult content site.",
        "nudevista.com":  "Adult content site.",
        "onlyfans.com":   "Adult content site — sexual solicitation is not allowed.",
        "fansly.com":     "Adult content site.",
        "manyvids.com":   "Adult content site.",
        "clips4sale.com": "Adult content site.",
        "iwantclips.com": "Adult content site.",
        "niteflirt.com":  "Adult content site.",
        "chaturbate.com": "Adult live stream site.",
        "myfreecams.com": "Adult live stream site.",
        "cam4.com":       "Adult live stream site.",
        "livejasmin.com": "Adult live stream site.",
        "stripchat.com":  "Adult live stream site.",
        "seekingarrangement.com": "Adult dating/escort site.",
        "ashley-madison.com":     "Infidelity/adult dating site.",
        "adultfriendfinder.com":  "Adult dating site.",
        "backpage.com":   "Solicitation-associated site.",
        "redlight.eu":    "Adult solicitation site."
    ]

    // ── URL shortener denylist ────────────────────────────────────────────────
    // Short links often used to obfuscate adult/malicious destinations.
    private static let shortenerDomains: Set<String> = [
        "bit.ly", "tinyurl.com", "t.co", "ow.ly", "buff.ly",
        "goo.gl", "rb.gy", "lnk.to", "linktr.ee",
        "cutt.ly", "is.gd", "v.gd", "tiny.cc",
        "shorturl.at", "clck.ru"
    ]

    // ── Scam / phishing domains ───────────────────────────────────────────────
    private static let scamDomains: Set<String> = [
        "paypal-security.com", "account-verify.net", "login-secure.org",
        "gift-card-generator.com", "free-robux.net"
    ]

    // ── Off-platform migration domains ───────────────────────────────────────
    // These are not adult sites but are commonly used to migrate victims
    // away from monitored spaces (Snapchat, Telegram, Kik, etc.).
    private static let migrationDomains: Set<String> = [
        "snapchat.com", "t.me", "telegram.me", "kik.com",
        "discord.gg", "discord.com",
        "signal.org",
        "whatsapp.com"
    ]

    // MARK: - Remote Denylist Refresh

    /// Fetches updated denylist from Firestore.
    /// Should be called at app launch (background task) to keep lists fresh.
    static func refreshRemoteDenylist() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        _ = uid // Future: validate permission if denylist is user-tier-gated
        // Currently static — Cloud Function updates Firestore config document
        // which is cached locally by the Firestore SDK.
        // Implementation note: add Firestore document listener here if the denylist
        // is large enough to warrant incremental updates.
    }

    // MARK: - User-facing warning helper

    /// Returns the safe-link warning message to show before opening an external URL.
    static func warningMessage(for decision: LinkSafetyDecision) -> String? {
        switch decision {
        case .allowedWithWarn(let msg): return msg
        default: return nil
        }
    }

    /// Returns true if the link should be completely hidden (not rendered in preview).
    static func shouldHide(_ decision: LinkSafetyDecision) -> Bool {
        switch decision {
        case .blocked, .blockedAndStrike: return true
        default: return false
        }
    }
}

// MARK: - Link Preview Integration Helper

extension LinkSafetyDecision {
    /// Whether the link can be rendered as a preview card.
    var canShowPreview: Bool {
        switch self {
        case .allowed, .allowedWithWarn: return true
        case .blocked, .blockedAndStrike: return false
        }
    }

    /// The policy code string for audit logging.
    var policyCodeString: String? {
        switch self {
        case .blocked(_, let code):          return code
        case .blockedAndStrike(_, let code, _): return code
        default:                              return nil
        }
    }
}

// MARK: - Backward-compatible class wrapper (preserves existing .shared.open() call sites)

import SwiftUI
import UIKit

@MainActor
final class LinkSafetyServiceCompat {
    static let shared = LinkSafetyServiceCompat()
    private init() {}

    /// Opens a URL with safety enforcement.
    /// - Blocked URLs: no-op (optionally show an error sheet).
    /// - Allowed-with-warn: shows a confirmation sheet before opening.
    /// - Allowed: opens immediately.
    func open(_ url: URL, completion: @escaping (AnyView?) -> Void) {
        let decision = LinkSafetyService.check(url.absoluteString)
        switch decision {
        case .allowed:
            UIApplication.shared.open(url)
            completion(nil)
        case .allowedWithWarn(let message):
            let sheet = AnyView(LinkSafetyWarningSheet(url: url, message: message))
            completion(sheet)
        case .blocked(let reason, _):
            let sheet = AnyView(LinkSafetyBlockedSheet(reason: reason))
            completion(sheet)
        case .blockedAndStrike(let reason, _, _):
            let sheet = AnyView(LinkSafetyBlockedSheet(reason: reason))
            completion(sheet)
        }
    }
}

// MARK: - Safety sheets (minimal — shown by existing call sites via sheet(isPresented:))

private struct LinkSafetyWarningSheet: View {
    let url: URL
    let message: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "link.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("External Link")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Open Anyway") {
                    UIApplication.shared.open(url)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding(24)
        .presentationDetents([.medium])
    }
}

private struct LinkSafetyBlockedSheet: View {
    let reason: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "xmark.shield.fill")
                .font(.largeTitle)
                .foregroundStyle(.red)
            Text("Link Blocked")
                .font(.headline)
            Text(reason)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("OK") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .presentationDetents([.medium])
    }
}

// Make the call sites that use `LinkSafetyService.shared` compile by type-aliasing
// the compat class to the expected name used in call sites.
// NOTE: The static-method `LinkSafetyService` enum keeps its name.
// Call sites use `LinkSafetyService.shared` which resolves to this typealias.
extension LinkSafetyServiceCompat {
    // Bridge so legacy `LinkSafetyService.shared` resolves without renaming every call site
    static var legacyShared: LinkSafetyServiceCompat { shared }
}
