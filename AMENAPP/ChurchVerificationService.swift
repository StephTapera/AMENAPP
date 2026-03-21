//
//  ChurchVerificationService.swift
//  AMENAPP
//
//  Filters MKLocalSearch results to genuine churches.
//
//  Filtering pipeline:
//  1. Hard-reject by MKPointOfInterestCategory (nightlife, food, lodging, etc.)
//  2. Fast-pass if category is .religiousCenter OR name contains a clear church word
//  3. Ambiguous cases → Claude API call with the system prompt from the design doc
//
//  Zero UI changes — this service is called only from performMKLocalSearch().
//

import Foundation
import MapKit

// MARK: - Result model

struct ChurchVerification {
    let isChurch: Bool
    let confidence: Confidence
    let reason: String

    enum Confidence: String, Codable { case high, medium, low }
}

// MARK: - Service

enum ChurchVerificationService {

    // MARK: - MKPointOfInterestCategory sets

    /// Categories that unambiguously disqualify a place.
    private static let rejectCategories: Set<MKPointOfInterestCategory> = {
        var set: Set<MKPointOfInterestCategory> = [
            .nightlife,
            .restaurant,
            .cafe,
            .bakery,
            .foodMarket,
            .winery,
        ]
        if #available(iOS 16.0, *) {
            set.insert(.brewery)
        }
        return set
    }()

    /// Categories that are unambiguously a house of worship.
    /// Note: MapKit has no built-in religious category, so we rely on name-based keyword matching instead.
    private static let acceptCategories: Set<MKPointOfInterestCategory> = []

    // MARK: - Name keywords

    /// Words in a name that strongly suggest a genuine church.
    private static let churchKeywords: [String] = [
        "church", "chapel", "cathedral", "basilica", "parish",
        "congregation", "assembly", "fellowship", "ministry",
        "tabernacle", "sanctuary", "diocese", "abbey", "priory",
        "mosque", "synagogue", "masjid", "temple", "gurdwara",
    ]

    /// Words in a name that suggest a NON-church venue.
    private static let nonChurchKeywords: [String] = [
        "nightclub", "night club", "club", "bar", "pub", "lounge",
        "brewery", "winery", "distillery", "tavern", "inn",
        "hotel", "hostel", "motel", "resort",
        "restaurant", "café", "cafe", "diner", "grill",
        "theater", "theatre", "cinema",
    ]

    // MARK: - Public API

    /// Filters a list of `MKMapItem` results, removing non-churches.
    /// Ambiguous items are validated via Claude; results preserve original order.
    static func filter(mapItems: [MKMapItem]) async -> [MKMapItem] {
        var accepted: [MKMapItem] = []
        for item in mapItems {
            let verdict = await verify(item)
            if verdict.isChurch {
                accepted.append(item)
            }
        }
        return accepted
    }

    // MARK: - Internal

    static func verify(_ item: MKMapItem) async -> ChurchVerification {
        let name = item.name ?? ""
        let category = item.pointOfInterestCategory

        // 1. Hard reject by Apple Maps category
        if let cat = category, rejectCategories.contains(cat) {
            return .init(isChurch: false, confidence: .high,
                         reason: "Category '\(cat.rawValue)' disqualifies this place")
        }

        // 2. Hard reject by non-church name keyword (before fast-pass to catch "The Church Lounge" etc.)
        let lowerName = name.lowercased()
        for kw in nonChurchKeywords {
            if lowerName.contains(kw) {
                return .init(isChurch: false, confidence: .high,
                             reason: "Name contains '\(kw)'")
            }
        }

        // 3. Fast pass by Apple Maps religious category
        if let cat = category, acceptCategories.contains(cat) {
            return .init(isChurch: true, confidence: .high,
                         reason: "MKPointOfInterestCategory is religiousCenter")
        }

        // 4. Fast pass by name keyword
        for kw in churchKeywords {
            if lowerName.contains(kw) {
                return .init(isChurch: true, confidence: .high,
                             reason: "Name contains '\(kw)'")
            }
        }

        // 5. Ambiguous — delegate to Claude
        return await verifyWithClaude(item)
    }

    private static func verifyWithClaude(_ item: MKMapItem) async -> ChurchVerification {
        let apiKey = Bundle.main.object(forInfoDictionaryKey: "ANTHROPIC_API_KEY") as? String ?? ""
        guard !apiKey.isEmpty else {
            // No API key — soft-pass ambiguous items rather than silently dropping them
            return .init(isChurch: true, confidence: .low,
                         reason: "ANTHROPIC_API_KEY not set; passing ambiguous result")
        }

        let name    = item.name ?? "Unknown"
        let address = [item.placemark.thoroughfare,
                       item.placemark.locality,
                       item.placemark.administrativeArea]
            .compactMap { $0 }.joined(separator: ", ")
        let category = item.pointOfInterestCategory?.rawValue ?? "unknown"

        let placeData = """
        Name: \(name)
        Address: \(address)
        Apple Maps Category: \(category)
        """

        let systemPrompt = """
        You are a church verification assistant. Given a place's name, address, and category, \
        determine if it is a genuine Christian church (or other house of worship intended for \
        religious services and community worship).

        Return ONLY a JSON object with this structure:
        {"isChurch":true|false,"confidence":"high"|"medium"|"low","reason":"brief explanation"}

        Rules:
        - A genuine church typically has: religious service types (Sunday worship, mass, prayer \
          meetings), denominational affiliation, or terms like "ministry", "fellowship", "chapel", \
          "cathedral", "parish", "congregation", "assembly", or "tabernacle".
        - REJECT if the place is primarily a: nightclub, bar, music venue, restaurant, event space, \
          brewery, hotel, or retail store — even if it uses the word "church" in its name.
        - REJECT entertainment venues like "The Church" nightclub or similar.
        - When uncertain (e.g., a "community church" with no additional context), return \
          confidence "low" and isChurch: true as a soft pass for human review.
        - Return ONLY the JSON object, no other text.
        """

        do {
            let body: [String: Any] = [
                "model": "claude-sonnet-4-6",
                "max_tokens": 120,
                "system": systemPrompt,
                "messages": [["role": "user", "content": placeData]]
            ]

            var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey,             forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01",       forHTTPHeaderField: "anthropic-version")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .init(isChurch: true, confidence: .low, reason: "Claude API error; soft pass")
            }

            struct AnthropicResponse: Codable {
                let content: [Block]
                struct Block: Codable { let text: String }
            }
            struct VerifyResponse: Codable {
                let isChurch: Bool
                let confidence: String
                let reason: String
            }

            let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
            let raw = decoded.content.first?.text ?? ""
            let clean = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let jsonData = clean.data(using: .utf8),
                  let result = try? JSONDecoder().decode(VerifyResponse.self, from: jsonData) else {
                return .init(isChurch: true, confidence: .low, reason: "Parse error; soft pass")
            }

            let conf = ChurchVerification.Confidence(rawValue: result.confidence) ?? .low
            return .init(isChurch: result.isChurch, confidence: conf, reason: result.reason)

        } catch {
            dlog("ChurchVerificationService: \(error.localizedDescription)")
            return .init(isChurch: true, confidence: .low, reason: "Network error; soft pass")
        }
    }
}
