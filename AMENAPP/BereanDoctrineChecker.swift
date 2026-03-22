// BereanDoctrineChecker.swift
// AMENAPP
//
// Theology analysis engine:
//   - Accepts any text (sermon note, Berean AI response, post draft)
//   - Sends to Claude with a systematic theology evaluation prompt
//   - Returns DoctrineCheck: overall verdict + per-claim annotations
//   - Integrated as a collapsible card in ChurchNotesEditor and BereanAIAssistantView
//
// Entry points:
//   BereanDoctrineChecker.shared.analyze(text:) async -> DoctrineCheck
//   DoctrineCheckCard(check:) — SwiftUI result card
//   DoctrineCheckButton(text:) — tap-to-analyze trigger

import SwiftUI
import Combine
import Foundation

// MARK: - Models

enum DoctrineVerdict: String, CaseIterable {
    case orthodox   = "Orthodox"
    case caution    = "Caution"
    case concern    = "Concern"
    case mixed      = "Mixed"
    case unclear    = "Unclear"
}

struct DoctrineAnnotation: Identifiable {
    let id = UUID()
    let claim: String           // the phrase or sentence being evaluated
    let verdict: DoctrineVerdict
    let note: String            // explanation
}

struct DoctrineCheck {
    let overall: DoctrineVerdict
    let summary: String
    let annotations: [DoctrineAnnotation]
    let tradition: String       // e.g. "broadly evangelical", "Reformed", "Charismatic"
}

// MARK: - BereanDoctrineChecker

@MainActor
final class BereanDoctrineChecker: ObservableObject {
    static let shared = BereanDoctrineChecker()

    @Published var isAnalyzing = false
    @Published var lastCheck: DoctrineCheck?

    func analyze(text: String) async -> DoctrineCheck? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        isAnalyzing = true
        defer { isAnalyzing = false }

        let prompt = """
        Evaluate the following text for theological orthodoxy from a broadly Christian, cross-denominational perspective.

        Text to evaluate:
        \(text.prefix(3000))

        Return JSON only (no markdown):
        {
          "overall": "orthodox" | "caution" | "concern" | "mixed" | "unclear",
          "tradition": "short description of theological tradition evident (e.g. broadly evangelical)",
          "summary": "2–3 sentence overall assessment",
          "annotations": [
            {
              "claim": "the specific claim or phrase",
              "verdict": "orthodox" | "caution" | "concern",
              "note": "brief explanation (max 20 words)"
            }
          ]
        }

        Guidelines:
        - "orthodox" = consistent with historic Christian consensus across denominations
        - "caution" = debated within orthodox Christianity; not heretical but note the disagreement
        - "concern" = contradicts core Christian doctrine (Trinity, salvation, Scripture, etc.)
        - Be gracious. Most sermon content is orthodox. Only flag genuine issues.
        - Max 5 annotations. Focus on the most significant claims.
        JSON only.
        """

        guard let raw = try? await ClaudeService.shared.sendMessageSync(prompt, mode: .scholar) else {
            return nil
        }

        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONDecoder().decode(DoctrineCheckJSON.self, from: data) else {
            return nil
        }

        let check = DoctrineCheck(
            overall:     DoctrineVerdict(rawValue: json.overall.capitalized) ?? .unclear,
            summary:     json.summary,
            annotations: (json.annotations ?? []).map {
                DoctrineAnnotation(
                    claim:   $0.claim,
                    verdict: DoctrineVerdict(rawValue: $0.verdict.capitalized) ?? .unclear,
                    note:    $0.note
                )
            },
            tradition: json.tradition
        )
        lastCheck = check
        return check
    }
}

// MARK: - JSON decoding

private struct DoctrineCheckJSON: Codable {
    var overall:     String
    var summary:     String
    var tradition:   String
    var annotations: [AnnotationJSON]?

    struct AnnotationJSON: Codable {
        var claim:   String
        var verdict: String
        var note:    String
    }

    private enum CodingKeys: String, CodingKey {
        case overall, summary, tradition, annotations
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        overall     = (try? c.decode(String.self,          forKey: .overall))     ?? "unclear"
        summary     = (try? c.decode(String.self,          forKey: .summary))     ?? ""
        tradition   = (try? c.decode(String.self,          forKey: .tradition))   ?? ""
        annotations = (try? c.decode([AnnotationJSON].self, forKey: .annotations)) ?? []
    }
}

// MARK: - DoctrineCheckCard

struct DoctrineCheckCard: View {
    let check: DoctrineCheck
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: verdictIcon(check.overall))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(verdictColor(check.overall))

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Doctrine Check")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(.tertiaryLabel))
                            .textCase(.uppercase)
                        Text(check.overall.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(verdictColor(check.overall))
                    }

                    Spacer()

                    Text(check.tradition)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .lineLimit(1)

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if expanded {
                Divider()
                    .padding(.horizontal, 14)

                VStack(alignment: .leading, spacing: 10) {
                    // Summary
                    Text(check.summary)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(.secondaryLabel))
                        .padding(.horizontal, 14)
                        .padding(.top, 8)

                    // Annotations
                    if !check.annotations.isEmpty {
                        ForEach(check.annotations) { ann in
                            HStack(alignment: .top, spacing: 8) {
                                Rectangle()
                                    .fill(verdictColor(ann.verdict))
                                    .frame(width: 3)
                                    .clipShape(Capsule())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(ann.claim)")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Color(.label))
                                        .lineLimit(2)
                                    Text(ann.note)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color(.secondaryLabel))
                                }
                            }
                            .padding(.horizontal, 14)
                        }
                    }
                }
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(verdictColor(check.overall).opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(verdictColor(check.overall).opacity(0.2), lineWidth: 1)
        )
    }

    private func verdictColor(_ v: DoctrineVerdict) -> Color {
        switch v {
        case .orthodox: return .green
        case .caution:  return .orange
        case .concern:  return .red
        case .mixed:    return .orange
        case .unclear:  return Color(.secondaryLabel)
        }
    }

    private func verdictIcon(_ v: DoctrineVerdict) -> String {
        switch v {
        case .orthodox: return "checkmark.seal.fill"
        case .caution:  return "exclamationmark.triangle.fill"
        case .concern:  return "xmark.seal.fill"
        case .mixed:    return "exclamationmark.circle.fill"
        case .unclear:  return "questionmark.circle.fill"
        }
    }
}

// MARK: - DoctrineCheckButton (self-contained trigger + result display)

struct DoctrineCheckButton: View {
    let text: String
    @State private var check: DoctrineCheck?
    @State private var isAnalyzing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let c = check {
                DoctrineCheckCard(check: c)
            }

            Button {
                guard !isAnalyzing else { return }
                isAnalyzing = true
                Task {
                    let result = await BereanDoctrineChecker.shared.analyze(text: text)
                    await MainActor.run {
                        check = result
                        isAnalyzing = false
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if isAnalyzing {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 13))
                    }
                    Text(isAnalyzing ? "Checking doctrine…" : (check == nil ? "Check doctrine" : "Re-check"))
                        .font(.system(size: 13))
                }
                .foregroundStyle(Color(.secondaryLabel))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.systemGray6), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}
