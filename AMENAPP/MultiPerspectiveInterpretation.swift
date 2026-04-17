//
//  MultiPerspectiveInterpretation.swift
//  AMENAPP
//
//  Shows responsible multi-tradition interpretation of any Bible passage.
//  Builds DISCERNMENT, not confusion — each tradition is clearly labeled,
//  areas of universal agreement are highlighted, and debated points are
//  presented neutrally without promoting any denomination.
//
//  Traditions covered:
//    • Evangelical / Protestant (broadly)
//    • Reformed / Calvinist
//    • Wesleyan / Arminian
//    • Catholic
//    • Eastern Orthodox
//    • Charismatic / Pentecostal
//    • Historical (Early Church Fathers)
//
//  Architecture:
//    MultiPerspectiveService    – builds prompts + parses responses
//    PerspectiveResult          – model for one tradition's view
//    MultiPerspectiveView       – full sheet UI
//    PerspectivePill            – compact embed trigger
//

import Foundation
import SwiftUI
import Combine

// MARK: - Models

enum TheologicalTradition: String, CaseIterable, Codable {
    case evangelical    = "Evangelical"
    case reformed       = "Reformed"
    case wesleyan       = "Wesleyan"
    case catholic       = "Catholic"
    case orthodox       = "Eastern Orthodox"
    case charismatic    = "Charismatic"
    case earlyChurch    = "Early Church"

    var color: Color {
        switch self {
        case .evangelical: return .blue
        case .reformed:    return .indigo
        case .wesleyan:    return .purple
        case .catholic:    return .red
        case .orthodox:    return .orange
        case .charismatic: return .yellow
        case .earlyChurch: return .brown
        }
    }

    var icon: String {
        switch self {
        case .evangelical: return "book.fill"
        case .reformed:    return "shield.fill"
        case .wesleyan:    return "flame.fill"
        case .catholic:    return "cross.fill"
        case .orthodox:    return "star.of.life.fill"
        case .charismatic: return "wind"
        case .earlyChurch: return "scroll.fill"
        }
    }
}

struct PerspectiveResult: Identifiable, Codable {
    let id: String
    let tradition: String
    let summary: String             // 2-3 sentences
    let keyEmphasis: String         // 1 sentence — what this tradition focuses on
    let representativeFigures: [String]  // e.g. ["Calvin", "Jonathan Edwards"]
    let agreesWith: [String]        // traditions that agree on main point
    let isDebated: Bool             // true if this tradition diverges significantly
}

struct MultiPerspectiveAnalysis: Codable {
    let verse: String
    let universallyAgreed: String   // What ALL traditions agree on
    let perspectives: [PerspectiveResult]
    let discernmentNote: String     // Guardrail — nudge toward Scripture + community
    let suggestedReading: [String]  // Helpful commentaries or resources
}

// MARK: - Service

@MainActor
final class MultiPerspectiveService: ObservableObject {
    static let shared = MultiPerspectiveService()

    @Published var analysis: MultiPerspectiveAnalysis?
    @Published var isLoading: Bool = false
    @Published var currentVerse: String = ""
    @Published var errorMessage: String?

    // Which traditions to show (user can toggle)
    @Published var enabledTraditions: Set<TheologicalTradition> = Set(TheologicalTradition.allCases)

    private let claude = ClaudeService.shared

    private init() {}

    func analyze(verse: String) async {
        guard verse != currentVerse || analysis == nil else { return }
        currentVerse = verse
        isLoading = true
        analysis = nil
        errorMessage = nil

        let prompt = buildPrompt(verse: verse)
        let fullResponse = (try? await claude.sendMessageSync(prompt, mode: .scholar)) ?? ""

        if let result = parseAnalysis(from: fullResponse) {
            analysis = result
        } else {
            errorMessage = "Could not parse perspectives. Please try again."
        }

        isLoading = false
    }

    // MARK: - Prompt

    private func buildPrompt(verse: String) -> String {
        let traditions = enabledTraditions.map { $0.rawValue }.joined(separator: ", ")
        return """
        Analyze the Bible verse or passage: "\(verse)"

        Provide interpretations from these traditions: \(traditions)

        Return a JSON object with EXACTLY this structure:
        {
          "verse": "\(verse)",
          "universallyAgreed": "<what all major Christian traditions agree this passage teaches — 2 sentences>",
          "perspectives": [
            {
              "id": "1",
              "tradition": "<tradition name exactly as given>",
              "summary": "<this tradition's interpretation — 2-3 sentences>",
              "keyEmphasis": "<what this tradition uniquely emphasizes — 1 sentence>",
              "representativeFigures": ["<name>", "<name>"],
              "agreesWith": ["<tradition name>"],
              "isDebated": <true if significantly diverges from others, else false>
            }
          ],
          "discernmentNote": "<A single, neutral sentence encouraging the reader to study the Word, pray, and seek their faith community for guidance>",
          "suggestedReading": ["<author - book title>", "<author - book title>"]
        }

        IMPORTANT:
        - Be academically accurate and fair to each tradition
        - Never mock or demean any tradition
        - Clearly mark genuinely debated points with isDebated: true
        - suggestedReading should include classics AND modern works
        Return ONLY valid JSON. No markdown.
        """
    }

    private func parseAnalysis(from json: String) -> MultiPerspectiveAnalysis? {
        var clean = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("```") {
            let lines = clean.components(separatedBy: "\n")
            clean = lines.dropFirst().dropLast().joined(separator: "\n")
        }
        guard let data = clean.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MultiPerspectiveAnalysis.self, from: data)
    }
}

// MARK: - SwiftUI View

struct MultiPerspectiveView: View {
    let verse: String
    @StateObject private var service = MultiPerspectiveService.shared
    @State private var selectedTradition: TheologicalTradition?
    @State private var showingTraditionFilter = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    if service.isLoading {
                        loadingView
                    } else if let analysis = service.analysis {
                        // Universal agreement card
                        UniversalAgreementCard(text: analysis.universallyAgreed)

                        // Tradition filter
                        HStack {
                            Text("Traditions")
                                .font(.headline)
                            Spacer()
                            Button {
                                showingTraditionFilter = true
                            } label: {
                                Label("Filter", systemImage: "slider.horizontal.3")
                                    .font(.caption)
                            }
                        }
                        .padding(.horizontal)

                        // Perspective cards
                        ForEach(analysis.perspectives, id: \.id) { perspective in
                            if let tradition = TheologicalTradition(rawValue: perspective.tradition),
                               service.enabledTraditions.contains(tradition) {
                                PerspectiveCard(perspective: perspective, tradition: tradition)
                            }
                        }

                        // Discernment note
                        DiscernmentNoteView(note: analysis.discernmentNote)

                        // Suggested reading
                        if !analysis.suggestedReading.isEmpty {
                            SuggestedReadingView(books: analysis.suggestedReading)
                        }
                    } else if let err = service.errorMessage {
                        Text(err)
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
                .padding()
            }
            .navigationTitle("Perspectives: \(verse)")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingTraditionFilter) {
                TraditionFilterSheet(service: service)
            }
        }
        .task {
            await service.analyze(verse: verse)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Gathering perspectives from multiple traditions…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

// MARK: - Sub-views

private struct UniversalAgreementCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("What All Traditions Agree On", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
            Text(text)
                .font(.subheadline)
        }
        .padding()
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14).strokeBorder(Color.green.opacity(0.25), lineWidth: 1)
        }
    }
}

private struct PerspectiveCard: View {
    let perspective: PerspectiveResult
    let tradition: TheologicalTradition
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.spring(response: 0.35)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: tradition.icon)
                        .foregroundStyle(tradition.color)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(perspective.tradition)
                                .font(.subheadline.weight(.semibold))
                            if perspective.isDebated {
                                Text("Debated")
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.orange)
                            }
                        }
                        Text(perspective.keyEmphasis)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(isExpanded ? nil : 1)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text(perspective.summary)
                        .font(.subheadline)

                    if !perspective.representativeFigures.isEmpty {
                        HStack(spacing: 4) {
                            Text("Key figures:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(perspective.representativeFigures.joined(separator: ", "))
                                .font(.caption.weight(.medium))
                        }
                    }

                    if !perspective.agreesWith.isEmpty {
                        HStack(spacing: 4) {
                            Text("Agrees with:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(perspective.agreesWith.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
                .padding()
                .transition(.opacity.combined(with: .push(from: .top)))
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct DiscernmentNoteView: View {
    let note: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.indigo)
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .italic()
        }
        .padding()
        .background(Color.indigo.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SuggestedReadingView: View {
    let books: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Suggested Reading", systemImage: "books.vertical")
                .font(.subheadline.weight(.semibold))
            ForEach(books, id: \.self) { book in
                HStack(spacing: 6) {
                    Image(systemName: "book.closed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(book)
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct TraditionFilterSheet: View {
    @ObservedObject var service: MultiPerspectiveService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(TheologicalTradition.allCases, id: \.self) { tradition in
                    Toggle(isOn: Binding(
                        get: { service.enabledTraditions.contains(tradition) },
                        set: { on in
                            if on { service.enabledTraditions.insert(tradition) }
                            else  { service.enabledTraditions.remove(tradition) }
                        }
                    )) {
                        Label(tradition.rawValue, systemImage: tradition.icon)
                    }
                }
            }
            .navigationTitle("Show Traditions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Compact Trigger Pill

struct MultiPerspectivePill: View {
    let verse: String
    @State private var showingSheet = false

    var body: some View {
        Button {
            showingSheet = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "person.3.fill")
                    .font(.caption2)
                Text("Multiple Perspectives")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.purple.opacity(0.12), in: Capsule())
            .foregroundStyle(.purple)
        }
        .sheet(isPresented: $showingSheet) {
            MultiPerspectiveView(verse: verse)
        }
    }
}
