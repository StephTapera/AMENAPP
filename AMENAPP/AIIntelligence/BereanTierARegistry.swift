// BereanTierARegistry.swift
// AMENAPP — Berean Spiritual Intelligence Layer (Wave 1)
//
// Singleton registry of all Tier A scripture/study source descriptors.
// Values are Swift mirrors of the W0 ScriptureSource contract.
// All sources default `enabled: false` — no flag is flipped in this build.
// `activeSources` returns empty until `bereanTierAConnectorsEnabled` is ON.
//
// ABSENT by policy: ESV, NIV, NASB (licensed, not free). No YouVersion path.

import Foundation

@MainActor
final class BereanTierARegistry {

    static let shared = BereanTierARegistry()

    // MARK: - Source Descriptors

    /// Free-Use Bible API (hello.ao) — BSB, public domain, no key required.
    let freeUseBibleApi = ScriptureSource(
        id: "free-use-bible-api",
        name: "Free Use Bible API (BSB)",
        tier: .a,
        // LIVE: public-domain, no API key, safe to call directly from the client.
        // Gated at runtime by `bereanTierAConnectorsEnabled` via `activeSources`.
        enabled: true,
        defaultTranslation: "BSB",
        availableTranslations: ["BSB", "KJV", "WEB"],
        license: LicenseMetadata(
            name: "Public Domain (BSB)",
            redistribution: .publicDomain,
            attributionRequired: false,
            attributionText: nil,
            cacheable: true,
            noFullBibleDump: false
        ),
        requiresProxiedKey: false,
        capabilities: [.passageLookup, .search]
    )

    /// API.Bible — multi-translation, key must stay server-side only (proxied endpoint).
    let apiBible = ScriptureSource(
        id: "api-bible",
        name: "API.Bible",
        tier: .a,
        enabled: false,
        defaultTranslation: "BSB",
        availableTranslations: ["BSB", "KJV", "WEB", "ASV"],
        license: LicenseMetadata(
            name: "API.Bible License",
            redistribution: .licensed,
            attributionRequired: true,
            // Attribution text must be surfaced wherever API.Bible content appears.
            attributionText: "Scripture taken via API.Bible (api.bible). All rights reserved.",
            cacheable: false,
            noFullBibleDump: true
        ),
        // Key never ships in the client bundle — server-side proxy only.
        requiresProxiedKey: true,
        capabilities: [.passageLookup, .crossReferences, .search]
    )

    /// NET Bible — free with attribution, translator notes available.
    let netBible = ScriptureSource(
        id: "net-bible",
        name: "NET Bible",
        tier: .a,
        enabled: false,
        defaultTranslation: "NET",
        availableTranslations: ["NET"],
        license: LicenseMetadata(
            name: "NET Bible License",
            redistribution: .cc,
            attributionRequired: true,
            attributionText: "Scripture quoted from the NET Bible® full notes edition, copyright ©1996-2006 by Biblical Studies Press, L.L.C. All rights reserved.",
            cacheable: true,
            noFullBibleDump: false
        ),
        requiresProxiedKey: false,
        capabilities: [.passageLookup, .translatorNotes, .crossReferences]
    )

    /// Open Scriptures Hebrew Bible + SBL Greek NT — original languages, lexicon, Strong's numbers.
    let oshbSblgnt = ScriptureSource(
        id: "oshb-sblgnt",
        name: "OSHB / SBLGNT (Original Languages)",
        tier: .a,
        enabled: false,
        defaultTranslation: nil,
        availableTranslations: ["HB", "GNT"],
        license: LicenseMetadata(
            name: "CC BY 4.0",
            redistribution: .cc,
            attributionRequired: true,
            attributionText: "Hebrew text: Open Scriptures Hebrew Bible (CC BY 4.0). Greek text: SBL Greek New Testament, © 2010 Society of Biblical Literature and Logos Bible Software.",
            cacheable: true,
            noFullBibleDump: false
        ),
        requiresProxiedKey: false,
        capabilities: [.passageLookup, .lexicon, .strongNumbers, .morphology]
    )

    // MARK: - All Sources (ordered: public-domain first, original-language last)

    private var allSources: [ScriptureSource] {
        [freeUseBibleApi, apiBible, netBible, oshbSblgnt]
    }

    // MARK: - Lookup

    func source(for id: String) -> ScriptureSource? {
        allSources.first { $0.id == id }
    }

    // MARK: - Active Sources

    /// Returns only sources that are both flag-enabled and individually enabled.
    /// LIVE: when `bereanTierAConnectorsEnabled` is ON this returns the public-domain
    /// Free Use Bible API source. Proxied/key sources (API.Bible) stay `enabled: false`
    /// until their server proxy is deployed. Fail-closed when the flag is OFF.
    var activeSources: [ScriptureSource] {
        guard AMENFeatureFlags.shared.bereanTierAConnectorsEnabled else { return [] }
        return allSources.filter { $0.enabled }
    }

    private init() {}
}
