// ScriptureAttributionView.swift
// AMENAPP — Berean Spiritual Intelligence Layer (Wave 1)
//
// Compact per-source attribution view rendered beneath a verse card.
//
// Liquid Glass rules applied here:
//   - .ultraThinMaterial only on the outer pill container (floating chrome).
//   - No glass material behind text — opaque/high-contrast text surfaces only.
//   - Original-language sources (lexicon/Strong's) receive amenGold accent;
//     all others use .secondary (neutral, meets contrast requirements).

import SwiftUI

struct ScriptureAttributionView: View {

    let source: ScriptureSource

    // Original-language sources receive a gold accent to signal scholarly depth.
    private var isOriginalLanguage: Bool {
        source.capabilities.contains(.lexicon) || source.capabilities.contains(.strongNumbers)
    }

    private var accentColor: Color {
        isOriginalLanguage ? .amenGold : .secondary
    }

    var body: some View {
        HStack(spacing: 6) {
            // License name — always shown, small and neutral.
            Text(source.license.name)
                .font(.caption2)
                .foregroundColor(accentColor)

            // Attribution text — shown only when the license requires it.
            if source.license.attributionRequired, let attributionText = source.license.attributionText {
                Text("·")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text(attributionText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        // Outer pill: ultraThinMaterial for the floating-chrome container only.
        // Text inside is on an opaque background (no glass-on-glass).
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Public Domain") {
    ScriptureAttributionView(
        source: ScriptureSource(
            id: "preview-pd",
            name: "Free Use Bible API (BSB)",
            tier: .a,
            enabled: false,
            defaultTranslation: "BSB",
            availableTranslations: ["BSB"],
            license: LicenseMetadata(
                name: "Public Domain (BSB)",
                redistribution: .publicDomain,
                attributionRequired: false,
                attributionText: nil,
                cacheable: true,
                noFullBibleDump: false
            ),
            requiresProxiedKey: false,
            capabilities: [.passageLookup]
        )
    )
    .padding()
}

#Preview("Attribution Required") {
    ScriptureAttributionView(
        source: ScriptureSource(
            id: "preview-net",
            name: "NET Bible",
            tier: .a,
            enabled: false,
            defaultTranslation: "NET",
            availableTranslations: ["NET"],
            license: LicenseMetadata(
                name: "NET Bible License",
                redistribution: .cc,
                attributionRequired: true,
                attributionText: "Scripture quoted from the NET Bible® full notes edition, copyright ©1996-2006 by Biblical Studies Press, L.L.C.",
                cacheable: true,
                noFullBibleDump: false
            ),
            requiresProxiedKey: false,
            capabilities: [.passageLookup, .translatorNotes]
        )
    )
    .padding()
}

#Preview("Original Language") {
    ScriptureAttributionView(
        source: ScriptureSource(
            id: "preview-oshb",
            name: "OSHB / SBLGNT (Original Languages)",
            tier: .a,
            enabled: false,
            defaultTranslation: nil,
            availableTranslations: ["HB", "GNT"],
            license: LicenseMetadata(
                name: "CC BY 4.0",
                redistribution: .cc,
                attributionRequired: true,
                attributionText: "Hebrew text: Open Scriptures Hebrew Bible (CC BY 4.0). Greek text: SBL Greek New Testament.",
                cacheable: true,
                noFullBibleDump: false
            ),
            requiresProxiedKey: false,
            capabilities: [.passageLookup, .lexicon, .strongNumbers, .morphology]
        )
    )
    .padding()
}
#endif
