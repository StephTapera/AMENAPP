import Foundation

// MARK: - Guardian Classification Result
//
// Returned by the guardianClassify Cloud Function.
// Matches the JSON schema in the GUARDIAN system prompt exactly.

struct GuardianResult: Codable {
    let decision: GuardianDecision
    let category: String
    let reason: String
    let route: GuardianRoute
}

// GuardianDecision is defined in ChannelModels.swift (shared between messaging + guardian layers)

enum GuardianRoute: String, Codable {
    case none
    case support   // crisis resources attached; message still delivered
    case review    // human review queue; message held
    case legal     // CSAM / legal path; message held + preserved for reporting
}

// MARK: - Crisis Support Resources
//
// IMPORTANT: Keep these current and region-accurate. Do NOT enumerate self-harm methods anywhere.
// US default: 988 Suicide & Crisis Lifeline.

struct GuardianCrisisResource: Identifiable {
    let id = UUID()
    let name: String
    let shortcode: String       // e.g. "988" or "Text HOME to 741741"
    let url: String?
    let regions: [String]       // ISO 3166-1 alpha-2 codes, or ["*"] for global
}

extension GuardianCrisisResource {
    static let defaults: [GuardianCrisisResource] = [
        .init(name: "988 Suicide & Crisis Lifeline",
              shortcode: "Call or text 988",
              url: "https://988lifeline.org",
              regions: ["US"]),
        .init(name: "Crisis Text Line",
              shortcode: "Text HOME to 741741",
              url: "https://www.crisistextline.org",
              regions: ["US"]),
        .init(name: "International Association for Suicide Prevention — Crisis Centres",
              shortcode: "",
              url: "https://www.iasp.info/resources/Crisis_Centres/",
              regions: ["*"])
    ]

    static func forRegion(_ code: String = Locale.current.region?.identifier ?? "US") -> [GuardianCrisisResource] {
        defaults.filter { $0.regions.contains("*") || $0.regions.contains(code) }
    }
}
