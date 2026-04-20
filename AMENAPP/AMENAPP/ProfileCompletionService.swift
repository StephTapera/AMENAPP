//
//  ProfileCompletionService.swift
//  AMENAPP
//
//  Computes profile completion score and personalized suggestions.
//  Pure logic — no Firebase, no UI.
//  Driven by UserProfileData (from ProfileView) + UserProfileIdentity.
//

import Foundation

// MARK: - Completion Item

struct ProfileCompletionItem: Identifiable {
    let id: String
    let label: String          // e.g. "Add a profile photo"
    let detail: String?        // optional one-line hint
    let isCompleted: Bool
    let weight: Int            // relative importance — used for score weighting
    let category: Category

    enum Category {
        case foundation   // core presence (photo, bio, name)
        case discovery    // signals that power search + recommendations
        case faith        // AMEN-native spiritual signals
        case social       // links and ministry reach
    }
}

// MARK: - Presence Tier

enum ProfilePresenceTier: String {
    case minimal     // 0–29
    case present     // 30–59
    case established // 60–79
    case witness     // 80–100

    /// Human-readable label — AMEN-native phrasing, not generic "Complete your profile."
    var label: String {
        switch self {
        case .minimal:     return "Build your witness"
        case .present:     return "Complete your presence"
        case .established: return "Strengthen your profile"
        case .witness:     return "Full witness"
        }
    }

    var progressColor: String {
        switch self {
        case .minimal:     return "red"
        case .present:     return "orange"
        case .established: return "yellow"
        case .witness:     return "gold"
        }
    }
}

// MARK: - Profile Completion Service

@MainActor
final class ProfileCompletionService {
    static let shared = ProfileCompletionService()
    private init() {}

    // MARK: - Score (0–100)

    func score(data: UserProfileData, identity: UserProfileIdentity) -> Int {
        let all = items(data: data, identity: identity)
        let totalWeight = all.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return 0 }
        let earned = all.filter(\.isCompleted).reduce(0) { $0 + $1.weight }
        return Int(Double(earned) / Double(totalWeight) * 100)
    }

    // MARK: - Checklist

    func items(data: UserProfileData, identity: UserProfileIdentity) -> [ProfileCompletionItem] {
        [
            // Foundation — highest weight, these block discovery
            .init(id: "photo",
                  label: "Add a profile photo",
                  detail: nil,
                  isCompleted: !(data.profileImageURL?.isEmpty ?? true),
                  weight: 20, category: .foundation),

            .init(id: "bio",
                  label: "Write a bio",
                  detail: "At least 30 characters",
                  isCompleted: data.bio.count >= 30,
                  weight: 15, category: .foundation),

            .init(id: "website",
                  label: "Add a website or link",
                  detail: nil,
                  isCompleted: !(data.bioURL?.isEmpty ?? true),
                  weight: 8, category: .foundation),

            // Discovery
            .init(id: "interests",
                  label: "Add 3 interests",
                  detail: "Powers who finds you and who you discover",
                  isCompleted: data.interests.count >= 3,
                  weight: 10, category: .discovery),

            .init(id: "topics",
                  label: "Add topics you speak on",
                  detail: nil,
                  isCompleted: !data.profileTopics.isEmpty,
                  weight: 8, category: .discovery),

            .init(id: "openTo",
                  label: "Set your open-to signals",
                  detail: "Let the right people find you",
                  isCompleted: !identity.openToSignalIds.isEmpty,
                  weight: 6, category: .discovery),

            .init(id: "location",
                  label: "Add a city or region",
                  detail: "Optional — shows local churches and community",
                  isCompleted: identity.cityRegion != nil,
                  weight: 4, category: .discovery),

            // Faith — AMEN-native
            .init(id: "persona",
                  label: "Choose your role or persona",
                  detail: nil,
                  isCompleted: identity.persona != nil,
                  weight: 10, category: .faith),

            .init(id: "faithStage",
                  label: "Share your faith journey stage",
                  detail: "Optional — shapes your Berean experience",
                  isCompleted: identity.faithJourneyStage != nil,
                  weight: 5, category: .faith),

            .init(id: "pinnedCard",
                  label: "Pin a spiritual card",
                  detail: "Verse, testimony, current prayer, or study",
                  isCompleted: !identity.pinnedCards.isEmpty,
                  weight: 8, category: .faith),

            .init(id: "burden",
                  label: "Add a prayer burden",
                  detail: "What are you carrying right now?",
                  isCompleted: !identity.burdens.isEmpty,
                  weight: 3, category: .faith),

            .init(id: "askMeAbout",
                  label: "Add an \u{201C}Ask me about\u{201D} prompt",
                  detail: "Creates healthier conversation entry points",
                  isCompleted: !identity.askMeAbout.isEmpty,
                  weight: 3, category: .faith),

            // Social
            .init(id: "socialLink",
                  label: "Add a social or ministry link",
                  detail: nil,
                  isCompleted: !data.socialLinks.isEmpty,
                  weight: 5, category: .social),
        ]
    }

    // MARK: - Top Suggestions (incomplete items, descending weight)

    func suggestions(data: UserProfileData, identity: UserProfileIdentity) -> [String] {
        items(data: data, identity: identity)
            .filter { !$0.isCompleted }
            .sorted { $0.weight > $1.weight }
            .prefix(3)
            .map { item in
                switch item.id {
                case "photo":      return "Add a profile photo"
                case "bio":        return "Write a bio so others understand your story"
                case "website":    return "Link your ministry, church, or website"
                case "interests":  return "Add 3 interests to improve who finds you"
                case "topics":     return "Add topics you speak on or care about"
                case "persona":    return "Choose your role — Believer, Pastor, Creator, etc."
                case "pinnedCard": return "Pin a verse or testimony to your profile"
                case "openTo":     return "Set open-to signals so the right people find you"
                case "socialLink": return "Add a social or ministry link"
                case "faithStage": return "Share your faith journey stage"
                case "askMeAbout": return "Add an \u{201C}Ask me about\u{201D} prompt"
                case "burden":     return "Add a prayer burden others can pray with you"
                default:           return item.label
                }
            }
    }

    // MARK: - Presence Tier

    func presenceTier(data: UserProfileData, identity: UserProfileIdentity) -> ProfilePresenceTier {
        switch score(data: data, identity: identity) {
        case 80...100: return .witness
        case 60..<80:  return .established
        case 30..<60:  return .present
        default:       return .minimal
        }
    }

    // MARK: - Category Breakdown

    func categoryScore(category: ProfileCompletionItem.Category,
                       data: UserProfileData,
                       identity: UserProfileIdentity) -> Int {
        let cat = items(data: data, identity: identity).filter { $0.category == category }
        let total = cat.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return 0 }
        let earned = cat.filter(\.isCompleted).reduce(0) { $0 + $1.weight }
        return Int(Double(earned) / Double(total) * 100)
    }
}

// MARK: - ProfileCompletionItem.Category Equatable

extension ProfileCompletionItem.Category: Equatable {}
