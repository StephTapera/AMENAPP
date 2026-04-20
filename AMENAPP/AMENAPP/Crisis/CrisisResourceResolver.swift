// CrisisResourceResolver.swift
// AMENAPP
//
// Locale-aware crisis resource resolution.
// Emergency numbers, hotlines, text lines adapted by region.
// Adaptive resource ordering based on crisis state.
// Architecture supports future personalization: veteran status, recent tool usage, etc.
//

import Foundation

// MARK: - Locale Resource Set

struct CrisisLocaleResources {
    let locale: String
    let emergencyNumber: String
    let crisisHotlineNumber: String
    let crisisHotlineLabel: String
    let crisisTextInstruction: String
    let crisisTextLabel: String
    let webResourceURL: String?
}

// MARK: - Resource Resolver

struct CrisisResourceResolver {

    static func resolve(locale: Locale = .current) -> CrisisLocaleResources {
        let region = locale.region?.identifier ?? "US"
        return localeResources(for: region)
    }

    private static func localeResources(for region: String) -> CrisisLocaleResources {
        switch region {
        case "GB", "IE":
            return CrisisLocaleResources(
                locale: region,
                emergencyNumber: "999",
                crisisHotlineNumber: "116123",
                crisisHotlineLabel: "Samaritans",
                crisisTextInstruction: "SHOUT to 85258",
                crisisTextLabel: "Shout Crisis Text Line",
                webResourceURL: "https://www.samaritans.org"
            )
        case "AU":
            return CrisisLocaleResources(
                locale: region,
                emergencyNumber: "000",
                crisisHotlineNumber: "131114",
                crisisHotlineLabel: "Lifeline Australia",
                crisisTextInstruction: "Text 0477 13 11 14",
                crisisTextLabel: "Lifeline Text",
                webResourceURL: "https://www.lifeline.org.au"
            )
        case "CA":
            return CrisisLocaleResources(
                locale: region,
                emergencyNumber: "911",
                crisisHotlineNumber: "988",
                crisisHotlineLabel: "988 Suicide Crisis Helpline",
                crisisTextInstruction: "Text HOME to 686868",
                crisisTextLabel: "Crisis Text Line",
                webResourceURL: "https://www.crisisservicescanada.ca"
            )
        case "NZ":
            return CrisisLocaleResources(
                locale: region,
                emergencyNumber: "111",
                crisisHotlineNumber: "0800543354",
                crisisHotlineLabel: "Lifeline New Zealand",
                crisisTextInstruction: "Text 4357",
                crisisTextLabel: "Crisis Text",
                webResourceURL: "https://www.lifeline.org.nz"
            )
        default:
            // US default
            return CrisisLocaleResources(
                locale: "US",
                emergencyNumber: "911",
                crisisHotlineNumber: "988",
                crisisHotlineLabel: "988 Suicide & Crisis Lifeline",
                crisisTextInstruction: "Text HOME to 741741",
                crisisTextLabel: "Crisis Text Line",
                webResourceURL: "https://988lifeline.org"
            )
        }
    }

    // MARK: - Adaptive Resource List

    /// Returns resources ordered by priority for the given crisis state.
    static func resources(
        for state: CrisisState,
        locale: CrisisLocaleResources,
        hasTrustedContacts: Bool = false
    ) -> [CrisisResource] {

        let emergency = CrisisResource(
            id: "emergency",
            title: "Call \(locale.emergencyNumber)",
            subtitle: "Emergency services",
            channel: .call,
            target: locale.emergencyNumber,
            tint: .red
        )
        let hotline = CrisisResource(
            id: "hotline",
            title: locale.crisisHotlineLabel,
            subtitle: "Available 24 / 7 — free & confidential",
            channel: .call,
            target: locale.crisisHotlineNumber,
            tint: .red
        )
        let textLine = CrisisResource(
            id: "textline",
            title: locale.crisisTextLabel,
            subtitle: locale.crisisTextInstruction,
            channel: .text,
            target: locale.crisisTextInstruction,
            tint: .purple
        )
        let trustedPerson = CrisisResource(
            id: "trusted",
            title: hasTrustedContacts ? "Contact a Trusted Person" : "Add a Trusted Person",
            subtitle: hasTrustedContacts ? "Reach one safe person from your plan" : "Set up your support network",
            channel: .call,
            target: "",
            tint: .orange
        )

        switch state {
        case .inDanger:
            return [emergency, hotline, textLine, trustedPerson]
        case .overwhelmedButSafe:
            return [hotline, textLine, trustedPerson, emergency]
        case .checkingIn:
            return [trustedPerson, textLine, hotline, emergency]
        }
    }
}
