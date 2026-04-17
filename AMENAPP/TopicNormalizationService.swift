// TopicNormalizationService.swift
// AMENAPP
//
// Normalizes user-typed topics, profile interests, and SemanticTopicService
// cluster labels into canonical keys for Firestore array-contains queries.
//
// Fully on-device, zero network calls.

import Foundation

@MainActor
final class TopicNormalizationService {

    static let shared = TopicNormalizationService()

    // MARK: - Alias Dictionary

    /// Maps common variations to canonical keys.
    /// Canonical keys are lowercase, hyphenated (e.g. "faith-and-work").
    private let aliases: [String: String] = [
        // Scripture
        "bible": "scripture",
        "bible study": "scripture",
        "word of god": "scripture",
        "devotional": "scripture",
        "daily verse": "scripture",
        "scripture": "scripture",

        // Prayer
        "prayer": "prayer",
        "praying": "prayer",
        "intercession": "prayer",
        "prayer request": "prayer",
        "prayer wall": "prayer",
        "prayer chain": "prayer",

        // Testimony
        "testimony": "testimony",
        "testimonies": "testimony",
        "god story": "testimony",
        "praise report": "testimony",
        "answered prayer": "testimony",

        // Discipleship
        "discipleship": "discipleship",
        "mentoring": "discipleship",
        "mentorship": "discipleship",
        "spiritual growth": "discipleship",
        "accountability": "discipleship",
        "small group": "discipleship",

        // Worship
        "worship": "worship",
        "praise": "worship",
        "worship music": "worship",
        "hymns": "worship",

        // Theology
        "theology": "theology",
        "doctrine": "theology",
        "apologetics": "theology",
        "hermeneutics": "theology",

        // Community
        "community": "community",
        "fellowship": "community",
        "church life": "community",
        "church family": "community",
        "small groups": "community",

        // Faith & Work
        "faith and work": "faith-and-work",
        "faith & work": "faith-and-work",
        "marketplace ministry": "faith-and-work",
        "work": "faith-and-work",
        "vocation": "faith-and-work",
        "career": "faith-and-work",

        // Mental Health
        "mental health": "mental-health",
        "anxiety": "mental-health",
        "depression": "mental-health",
        "wellness": "mental-health",
        "self care": "mental-health",
        "self-care": "mental-health",

        // Family
        "family": "family",
        "parenting": "family",
        "marriage": "family",
        "relationships": "family",
        "children": "family",

        // Evangelism
        "evangelism": "evangelism",
        "missions": "evangelism",
        "outreach": "evangelism",
        "sharing faith": "evangelism",

        // Servanthood
        "servanthood": "servanthood",
        "serving": "servanthood",
        "service": "servanthood",
        "volunteering": "servanthood",
        "ministry": "servanthood",

        // Grief
        "grief": "grief",
        "loss": "grief",
        "bereavement": "grief",
        "mourning": "grief",

        // Healing
        "healing": "healing",
        "restoration": "healing",
        "recovery": "healing",
        "deliverance": "healing",

        // Prophetic
        "prophetic": "prophetic",
        "prophetic word": "prophetic",
        "prophecy": "prophetic",
        "revelation": "prophetic",
    ]

    /// Reverse map: canonical key → SpiritualTopicCluster
    private let clusterMap: [String: SpiritualTopicCluster] = [
        "scripture": .scripture,
        "prayer": .prayer,
        "testimony": .testimony,
        "discipleship": .discipleship,
        "worship": .worship,
        "theology": .theology,
        "community": .community,
        "faith-and-work": .faithAndWork,
        "mental-health": .mentalHealth,
        "family": .family,
        "evangelism": .evangelism,
        "servanthood": .servanthood,
        "grief": .grief,
        "healing": .healing,
        "prophetic": .propheticWord,
        "general": .general,
    ]

    private init() {}

    // MARK: - Public API

    /// Normalize a single user-typed topic string to its canonical key.
    /// Falls through to a sanitized form if no alias match is found.
    func normalize(_ rawTopic: String) -> String {
        let lower = rawTopic.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let mapped = aliases[lower] {
            return mapped
        }
        // Fallback: convert to canonical key format
        return CanonicalTopic.canonicalKey(from: rawTopic)
    }

    /// Normalize an array of raw topics, deduplicating results.
    func normalize(_ rawTopics: [String]) -> [String] {
        let keys = rawTopics.map { normalize($0) }
        return Array(Set(keys)).sorted()
    }

    /// Build a `CanonicalTopic` from a raw label.
    func canonicalTopic(from rawLabel: String) -> CanonicalTopic {
        let key = normalize(rawLabel)
        let cluster = clusterMap[key]
        let displayName = cluster?.rawValue ?? rawLabel.capitalized
        return CanonicalTopic(key: key, displayName: displayName, cluster: cluster)
    }

    /// Convert a SpiritualTopicCluster to its canonical key.
    func canonicalKey(for cluster: SpiritualTopicCluster) -> String {
        switch cluster {
        case .scripture:     return "scripture"
        case .prayer:        return "prayer"
        case .testimony:     return "testimony"
        case .discipleship:  return "discipleship"
        case .worship:       return "worship"
        case .theology:      return "theology"
        case .community:     return "community"
        case .faithAndWork:  return "faith-and-work"
        case .mentalHealth:  return "mental-health"
        case .family:        return "family"
        case .evangelism:    return "evangelism"
        case .servanthood:   return "servanthood"
        case .grief:         return "grief"
        case .healing:       return "healing"
        case .propheticWord: return "prophetic"
        case .general:       return "general"
        }
    }

    /// Resolve a canonical key back to a SpiritualTopicCluster (nil if custom topic).
    func cluster(for canonicalKey: String) -> SpiritualTopicCluster? {
        clusterMap[canonicalKey]
    }

    /// Display name for a canonical key.
    func displayName(for canonicalKey: String) -> String {
        if let cluster = clusterMap[canonicalKey] {
            return cluster.rawValue
        }
        // Best-effort: capitalize and un-hyphenate
        return canonicalKey
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}
