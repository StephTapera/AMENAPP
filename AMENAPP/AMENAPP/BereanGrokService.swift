import Foundation
import FirebaseFunctions
import FirebaseAnalytics

// MARK: - BereanGrokService
//
// Grok is used exclusively as a low-cost utility helper — never as a final
// theological authority. Every output routes through Berean verification.
//
// Feature flags gate every method. Disabling bereanHelperModelEnabled
// causes all methods to return nil silently, preserving existing Berean flow.

@MainActor
final class BereanGrokService {

    static let shared = BereanGrokService()
    private let functions = Functions.functions()
    private init() {}

    private var flags: AMENFeatureFlags { AMENFeatureFlags.shared }

    // MARK: - Classify Request (always runs — no Grok, pure heuristic)

    func classify(text: String) -> BereanRequestClassification {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let wordCount = trimmed.split(separator: " ").count

        let links = extractLinks(from: trimmed)
        let isLong = wordCount > 80

        let isSensitive = sensitiveKeywords.contains(where: lower.contains)
        let isExternalRequest = externalContextPhrases.contains(where: lower.contains)
        let isScriptureQuestion = scriptureKeywords.contains(where: lower.contains)
        let isPastoralRisk = pastoralKeywords.contains(where: lower.contains)

        let risk: BereanRequestRisk
        if isSensitive && isPastoralRisk { risk = .pastoral }
        else if isSensitive { risk = .elevated }
        else { risk = .low }

        let intent: BereanRequestIntent
        if !links.isEmpty { intent = .link }
        else if isExternalRequest { intent = .external }
        else if isScriptureQuestion { intent = .scripture }
        else if isPastoralRisk { intent = .pastoral }
        else if isLong { intent = .longPrompt }
        else { intent = .unknown }

        var pills: [BereanComposerPill] = []

        // Sensitive topics: no playful helper pills
        if risk == .pastoral || risk == .high || risk == .crisis {
            return BereanRequestClassification(
                intent: intent, risk: risk, isLong: isLong,
                containsLink: !links.isEmpty, detectedLinks: links,
                isSensitive: true, suggestedPills: []
            )
        }

        if !links.isEmpty && flags.bereanHelperLinkSummaryEnabled {
            pills.append(.summarizeLink)
        } else if !links.isEmpty && flags.bereanHelperExtractThemesEnabled {
            pills.append(.extractThemes)
        }

        if pills.isEmpty {
            if isLong && flags.bereanHelperPromptSimplifyEnabled {
                pills.append(.simplifyFirst)
            }
            if isExternalRequest && flags.bereanHelperExternalContextEnabled {
                pills.append(.externalContext)
            }
            if isScriptureQuestion && flags.bereanSmartPillsEnabled {
                pills.append(.checkScripture)
            }
        }

        if pills.isEmpty && flags.bereanHelperStudyOutlineEnabled {
            if studyOutlineKeywords.contains(where: lower.contains) {
                pills.append(.createStudyOutline)
            }
        }

        return BereanRequestClassification(
            intent: intent, risk: risk, isLong: isLong,
            containsLink: !links.isEmpty, detectedLinks: links,
            isSensitive: isSensitive, suggestedPills: Array(pills.prefix(2))
        )
    }

    // MARK: - Simplify Long Prompt (Flow 2)

    func simplifyPrompt(_ text: String) async -> BereanSimplifiedPrompt? {
        guard flags.bereanHelperModelEnabled && flags.bereanHelperPromptSimplifyEnabled else { return nil }
        Analytics.logEvent("berean_summary_pill_tapped", parameters: nil)
        do {
            let result = try await functions.httpsCallable("bereanHelperSummarizePrompt")
                .safeCall(["text": text, "operation": "simplify"])
            guard let data = result.data as? [String: Any],
                  let simplified = data["simplified"] as? String else { return nil }
            let themes = data["keyThemes"] as? [String] ?? []
            let angles = data["studyAngles"] as? [String] ?? []
            Analytics.logEvent("berean_summary_pill_shown", parameters: nil)
            return BereanSimplifiedPrompt(
                originalText: text,
                simplifiedText: simplified,
                keyThemes: themes,
                studyAngles: angles
            )
        } catch {
            dlog("[BereanGrokService] simplifyPrompt failed: \(error)")
            return nil
        }
    }

    // MARK: - Analyze Link (Flow 3)

    func analyzeLink(_ url: String) async -> BereanLinkAnalysis? {
        guard flags.bereanHelperModelEnabled && flags.bereanHelperLinkSummaryEnabled else { return nil }
        Analytics.logEvent("berean_link_detected", parameters: ["url_domain": urlDomain(url)])
        do {
            let result = try await functions.httpsCallable("bereanHelperAnalyzeLink")
                .safeCall(["url": url])
            guard let data = result.data as? [String: Any],
                  let summary = data["summary"] as? String else { return nil }
            Analytics.logEvent("berean_link_summary_created", parameters: nil)
            return BereanLinkAnalysis(
                url: url,
                title: data["title"] as? String,
                sourceLabel: data["sourceLabel"] as? String ?? urlDomain(url),
                contentType: data["contentType"] as? String ?? "Link",
                summary: summary,
                keyThemes: data["keyThemes"] as? [String] ?? [],
                claimsToCheck: data["claimsToCheck"] as? [String] ?? [],
                scriptureReferencesFound: data["scriptureReferences"] as? [String] ?? [],
                suggestedQuestion: data["suggestedQuestion"] as? String
            )
        } catch {
            dlog("[BereanGrokService] analyzeLink failed: \(error)")
            return nil
        }
    }

    // MARK: - External Context (Flow 4)

    func fetchExternalContext(query: String) async -> BereanExternalContextResult? {
        guard flags.bereanHelperModelEnabled && flags.bereanHelperExternalContextEnabled else { return nil }
        Analytics.logEvent("berean_external_context_started", parameters: nil)
        do {
            let result = try await functions.httpsCallable("bereanHelperExternalContext")
                .safeCall(["query": query])
            guard let data = result.data as? [String: Any],
                  let publicSummary = data["publicSummary"] as? String else { return nil }
            let rawClusters = data["viewpointClusters"] as? [[String: Any]] ?? []
            let clusters = rawClusters.compactMap { c -> BereanViewpointCluster? in
                guard let label = c["label"] as? String,
                      let summary = c["summary"] as? String else { return nil }
                return BereanViewpointCluster(
                    label: label, summary: summary,
                    isControversial: c["isControversial"] as? Bool ?? false
                )
            }
            Analytics.logEvent("berean_external_context_completed", parameters: nil)
            return BereanExternalContextResult(
                query: query,
                publicSummary: publicSummary,
                viewpointClusters: clusters,
                cautionNotes: data["cautionNotes"] as? [String] ?? [],
                suggestedScriptureAngles: data["scriptureAngles"] as? [String] ?? []
            )
        } catch {
            dlog("[BereanGrokService] fetchExternalContext failed: \(error)")
            return nil
        }
    }

    // MARK: - Study Outline (Flow 1 + 2)

    func createStudyOutline(topic: String) async -> BereanStudyOutline? {
        guard flags.bereanHelperModelEnabled && flags.bereanHelperStudyOutlineEnabled else { return nil }
        Analytics.logEvent("berean_study_outline_created", parameters: nil)
        do {
            let result = try await functions.httpsCallable("bereanHelperStudyOutline")
                .safeCall(["topic": topic])
            guard let data = result.data as? [String: Any],
                  let title = data["title"] as? String,
                  let mainQuestion = data["mainQuestion"] as? String else { return nil }
            return BereanStudyOutline(
                title: title,
                mainQuestion: mainQuestion,
                keyPassages: data["keyPassages"] as? [String] ?? [],
                historicalContextNote: data["historicalContext"] as? String,
                reflectionQuestions: data["reflectionQuestions"] as? [String] ?? [],
                nextSteps: data["nextSteps"] as? [String] ?? []
            )
        } catch {
            dlog("[BereanGrokService] createStudyOutline failed: \(error)")
            return nil
        }
    }

    // MARK: - Thinking Steps

    func thinkingStep(for index: Int) -> BereanThinkingStep {
        let steps = BereanThinkingStep.allCases
        return steps[min(index, steps.count - 1)]
    }

    // MARK: - Provenance

    func buildProvenance(
        helperUsed: Bool,
        externalContext: Bool,
        sensitiveDetected: Bool,
        scripturePassed: Bool
    ) -> BereanProvenanceRecord {
        BereanProvenanceRecord(
            helperModelUsed: helperUsed,
            externalContextUsed: externalContext,
            scriptureChecked: true,
            safetyReviewed: true,
            bereanVerified: sensitiveDetected ? .needsCaution : (scripturePassed ? .passed : .limited),
            requiresPastoralCare: sensitiveDetected,
            sensitiveTopicDetected: sensitiveDetected
        )
    }

    // MARK: - Private Helpers

    private func extractLinks(from text: String) -> [String] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.matches(in: text, range: range)
            .compactMap { $0.url?.absoluteString } ?? []
    }

    private func urlDomain(_ url: String) -> String {
        URL(string: url)?.host ?? "link"
    }

    // MARK: - Signal Lists

    private let sensitiveKeywords = [
        "abuse", "suicide", "self-harm", "hurt myself", "kill", "end my life",
        "trauma", "divorce", "affair", "addiction", "depression", "anxiety",
        "exploitation", "assault", "rape", "molest", "grooming"
    ]

    private let pastoralKeywords = [
        "my pastor", "my marriage", "my spouse", "confess", "sinned",
        "struggling", "i want to die", "nobody cares", "no hope", "i'm lost"
    ]

    private let externalContextPhrases = [
        "what are people saying", "why is this debated", "compare christian views",
        "summarize the public", "what do people think", "common argument",
        "different denominations", "controversy", "what does culture say"
    ]

    private let scriptureKeywords = [
        "bible says", "scripture", "verse", "passage", "book of", "matthew", "john",
        "psalm", "proverbs", "genesis", "revelation", "corinthians", "romans",
        "ephesians", "philippians", "hebrews", "isaiah", "jeremiah", "jesus said",
        "old testament", "new testament", "gospel"
    ]

    private let studyOutlineKeywords = [
        "study outline", "bible study", "study guide", "teach me", "deep dive",
        "learn more about", "comprehensive look", "outline for"
    ]
}
