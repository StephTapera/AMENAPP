// ONELivingThreadsEngine.swift
// ONE — On-Device Living Threads AI Distillation
// P1-F
//
// PRIVACY INVARIANT: Message content NEVER leaves this device.
// ONELivingThreadSummary is non-Codable by design. The user explicitly
// chooses to share any individual item before it is sent anywhere.
//
// Strategy:
//   Primary   → FoundationModels SystemLanguageModel (requires Apple Intelligence)
//   Fallback  → Rule-based extraction (regex + keyword scan)

import Foundation
import FoundationModels

// MARK: - Generable extraction type

@Generable
struct ONEThreadExtractionResult {
    @Guide(description: "Key decisions explicitly made in the conversation, as short statements")
    var decisions: [String]

    @Guide(description: "Explicit promises or commitments someone made, as short statements")
    var promises: [String]

    @Guide(description: "Specific dates or times mentioned (include context), as short strings")
    var importantDates: [String]

    @Guide(description: "Action items or tasks assigned to someone, as short statements")
    var tasks: [String]

    @Guide(description: "Prayer requests or spiritual needs mentioned")
    var prayerRequests: [String]
}

// MARK: - ONELivingThreadsEngine

actor ONELivingThreadsEngine {

    private let model = SystemLanguageModel.default

    // MARK: - Main Distillation

    /// Distils a batch of decrypted message strings into structured memory.
    /// Input is processed on-device. No network calls made.
    /// Returns nil if the message batch is too small to be useful (< 5 messages).
    func distil(messages: [(senderName: String, text: String)]) async -> ONELivingThreadSummary? {
        guard messages.count >= 5 else { return nil }

        switch model.availability {
        case .available:
            return await distilWithFoundationModels(messages: messages)
        case .unavailable:
            return distilWithRules(messages: messages)
        }
    }

    // MARK: - FoundationModels Path

    private func distilWithFoundationModels(
        messages: [(senderName: String, text: String)]
    ) async -> ONELivingThreadSummary {
        let transcript = messages
            .suffix(80)  // stay within context window
            .map { "\($0.senderName): \($0.text)" }
            .joined(separator: "\n")

        let session = LanguageModelSession(
            instructions: Instructions {
                "You are a private note-taking assistant that extracts structured information from private conversations."
                "RULES: Only extract information that is EXPLICITLY stated. Do not infer or guess."
                "Keep each extracted item to one short sentence. Leave arrays empty if nothing applies."
                "This is private, end-to-end encrypted content. Your output is shown only to the conversation participants."
            }
        )

        do {
            let prompt = Prompt("Extract key items from this private conversation:\n\n\(transcript)")
            let response = try await session.respond(
                to: prompt,
                generating: ONEThreadExtractionResult.self
            )
            return buildSummary(from: response.content)
        } catch {
            return distilWithRules(messages: messages)
        }
    }

    // MARK: - Rule-Based Fallback

    private func distilWithRules(messages: [(senderName: String, text: String)]) -> ONELivingThreadSummary {
        var decisions: [String] = []
        var promises: [String] = []
        var importantDates: [String] = []
        var tasks: [String] = []
        var prayerRequests: [String] = []
        var links: [String] = []

        let decisionKeywords = ["decided", "we'll", "going with", "confirmed", "agreed"]
        let promiseKeywords  = ["i'll", "i will", "promise", "i can", "i'll handle"]
        let taskKeywords     = ["todo:", "action:", "can you", "please", "need to", "should"]
        let prayerKeywords   = ["pray", "prayer", "praying", "lord", "god", "healing", "hospital"]
        let datePattern      = try? NSRegularExpression(
            pattern: #"(monday|tuesday|wednesday|thursday|friday|saturday|sunday|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec|\d{1,2}[\/\-]\d{1,2}|\d{1,2}(st|nd|rd|th))"#,
            options: .caseInsensitive
        )
        let urlPattern = try? NSRegularExpression(
            pattern: #"https?://[^\s]+"#,
            options: .caseInsensitive
        )

        for msg in messages.suffix(100) {
            let text = msg.text
            let lower = text.lowercased()
            let range = NSRange(text.startIndex..., in: text)

            if decisionKeywords.contains(where: { lower.contains($0) }) {
                decisions.append("\(msg.senderName): \(text.prefix(120))")
            }
            if promiseKeywords.contains(where: { lower.contains($0) }) {
                promises.append("\(msg.senderName): \(text.prefix(120))")
            }
            if taskKeywords.contains(where: { lower.contains($0) }) {
                tasks.append(text.prefix(120).description)
            }
            if prayerKeywords.contains(where: { lower.contains($0) }) {
                prayerRequests.append(text.prefix(120).description)
            }
            if let dp = datePattern, dp.firstMatch(in: text, range: range) != nil {
                importantDates.append(text.prefix(120).description)
            }
            if let up = urlPattern {
                let matches = up.matches(in: text, range: range)
                for m in matches {
                    if let r = Range(m.range, in: text) { links.append(String(text[r])) }
                }
            }
        }

        let dedupedDecisions = Array(Set(decisions).prefix(5))
        let dedupedPromises  = Array(Set(promises).prefix(5))
        let dedupedDates     = Array(Set(importantDates).prefix(5))
        let dedupedLinks     = Array(Set(links).prefix(10))
        let dedupedTasks     = Array(Set(tasks).prefix(5))
        let dedupedPrayers   = Array(Set(prayerRequests).prefix(5))
        return ONELivingThreadSummary(
            decisions:       dedupedDecisions,
            promises:        dedupedPromises,
            importantDates:  buildDates(from: dedupedDates),
            sharedLinks:     dedupedLinks,
            tasks:           buildTasks(from: dedupedTasks),
            prayerRequests:  dedupedPrayers,
            lastDistilledAt: Date()
        )
    }

    // MARK: - Helpers

    private func buildSummary(from result: ONEThreadExtractionResult) -> ONELivingThreadSummary {
        ONELivingThreadSummary(
            decisions: result.decisions,
            promises: result.promises,
            importantDates: result.importantDates.map { ONELivingDate(label: $0, date: Date()) },
            sharedLinks: [],
            tasks: result.tasks.map { ONELivingTask(id: UUID().uuidString, description: $0) },
            prayerRequests: result.prayerRequests,
            lastDistilledAt: Date()
        )
    }

    private func buildDates(from strings: [String]) -> [ONELivingDate] {
        strings.map { ONELivingDate(label: $0, date: Date()) }
    }

    private func buildTasks(from strings: [String]) -> [ONELivingTask] {
        strings.map { ONELivingTask(id: UUID().uuidString, description: $0) }
    }
}
