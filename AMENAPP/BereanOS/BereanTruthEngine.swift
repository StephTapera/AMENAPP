import Foundation
import FirebaseFunctions

// MARK: - BereanTruthEngine

/// Classifies statements' epistemic status via the Berean OS truth-labelling pipeline.
/// Results are cached in-memory (up to 500 entries, keyed on first 100 chars of input).
/// All public methods return `.uncertain` immediately when the feature flag is off.
@MainActor
final class BereanTruthEngine {

    // MARK: Singleton

    static let shared = BereanTruthEngine()

    // MARK: Private State

    private let cache: NSCache<NSString, NSString> = {
        let c = NSCache<NSString, NSString>()
        c.countLimit = 500
        return c
    }()

    private let functions = Functions.functions()

    // MARK: Init

    private init() {}

    // MARK: Public API

    /// Classifies a single statement.
    /// - Returns: A `BereanConfidenceLevel` — `.uncertain` if the feature flag is off.
    func classifyStatement(_ text: String) async throws -> BereanConfidenceLevel {
        guard AMENFeatureFlags.shared.bereanOSTruthLabelsEnabled else { return .uncertain }

        let cacheKey = NSString(string: String(text.prefix(100)))

        if let cached = cache.object(forKey: cacheKey) {
            return BereanConfidenceLevel(rawValue: cached as String) ?? .uncertain
        }

        let result = try await callClassify(statements: [text])
        let level = result.values.first ?? .uncertain

        cache.setObject(NSString(string: level.rawValue), forKey: cacheKey)
        return level
    }

    /// Classifies a batch of statements.
    /// - Returns: A dictionary mapping each statement to its `BereanConfidenceLevel`.
    func classifyBatch(_ statements: [String]) async throws -> [String: BereanConfidenceLevel] {
        guard AMENFeatureFlags.shared.bereanOSTruthLabelsEnabled else {
            return Dictionary(uniqueKeysWithValues: statements.map { ($0, BereanConfidenceLevel.uncertain) })
        }

        var output: [String: BereanConfidenceLevel] = [:]
        var uncached: [String] = []

        for statement in statements {
            let key = NSString(string: String(statement.prefix(100)))
            if let cached = cache.object(forKey: key),
               let level = BereanConfidenceLevel(rawValue: cached as String) {
                output[statement] = level
            } else {
                uncached.append(statement)
            }
        }

        // Process uncached items in batches of 10
        let batches = stride(from: 0, to: uncached.count, by: 10).map {
            Array(uncached[$0 ..< min($0 + 10, uncached.count)])
        }

        for batch in batches {
            let results = try await callClassify(statements: batch)
            for (statement, level) in results {
                output[statement] = level
                let key = NSString(string: String(statement.prefix(100)))
                cache.setObject(NSString(string: level.rawValue), forKey: key)
            }
        }

        return output
    }

    // MARK: Private

    /// Calls the `bereanClassifyStatement` Cloud Function with a list of statements.
    private func callClassify(statements: [String]) async throws -> [String: BereanConfidenceLevel] {
        let callable = functions.httpsCallable("bereanClassifyStatement")
        let data: [String: Any] = ["statements": statements]

        let result = try await callable.call(data)

        guard
            let response = result.data as? [String: Any],
            let classifications = response["classifications"] as? [String: String]
        else {
            return [:]
        }

        var output: [String: BereanConfidenceLevel] = [:]
        for (statement, levelString) in classifications {
            output[statement] = BereanConfidenceLevel(rawValue: levelString) ?? .uncertain
        }
        return output
    }
}
