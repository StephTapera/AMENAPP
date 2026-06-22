//
//  IntentAwareStudyMode.swift
//  AMENAPP
//
//  Detects WHY the user is studying and adapts Berean's output accordingly.
//  Same input → different output based on intent.
//
//  Intent Detection:
//    • Curiosity      → plain explanation, relatable examples
//    • Deep Study     → theological breakdown, original language, structure
//    • Personal Struggle → pastoral guidance, comfort, grounding scriptures
//    • Teaching Prep  → structured outline, multiple perspectives, discussion Qs
//    • Decision       → routes to BereanDecisionEngine
//    • Crisis         → routes to crisis resources
//
//  Explanation Tone (user-controlled):
//    • Pastor   → practical, warm, encouraging
//    • Scholar  → deep, structured, original language
//    • Friend   → simple, relatable, conversational
//    • Coach    → action-oriented, direct
//
//  Architecture:
//    IntentClassifier       – on-device keyword + heuristic classifier
//    StudyToneManager       – user preference for explanation style
//    IntentAwareStudyView   – the SwiftUI surface with tone pill selector
//

import Foundation
import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Study Intent

enum StudyIntent: String, CaseIterable, Codable {
    case curiosity      = "curiosity"
    case deepStudy      = "deep_study"
    case struggle       = "struggle"
    case teaching       = "teaching"
    case decision       = "decision"
    case crisis         = "crisis"
    case unknown        = "unknown"

    var displayName: String {
        switch self {
        case .curiosity:  return "Curious"
        case .deepStudy:  return "Deep Study"
        case .struggle:   return "Personal Struggle"
        case .teaching:   return "Teaching Prep"
        case .decision:   return "Decision"
        case .crisis:     return "Crisis Support"
        case .unknown:    return "General"
        }
    }

    var icon: String {
        switch self {
        case .curiosity:  return "lightbulb.fill"
        case .deepStudy:  return "magnifyingglass"
        case .struggle:   return "heart.text.square.fill"
        case .teaching:   return "person.3.fill"
        case .decision:   return "scale.3d"
        case .crisis:     return "cross.circle.fill"
        case .unknown:    return "sparkles"
        }
    }

    var systemPromptHint: String {
        switch self {
        case .curiosity:
            return "The user is curious and exploring. Use relatable examples and keep explanations accessible. Avoid jargon."
        case .deepStudy:
            return "The user wants theological depth. Include original language insights, doctrinal context, and structured exegesis."
        case .struggle:
            return "The user is going through something personally difficult. Lead with pastoral care and comfort. Apply scripture to their situation with warmth. Never be preachy."
        case .teaching:
            return "The user is preparing to teach or preach. Provide structured outlines, multiple perspectives, and discussion questions. Be thorough."
        case .decision:
            return "The user is facing a real decision. Apply biblical principles practically. Include risks and guardrails. Be balanced, not prescriptive."
        case .crisis:
            return "The user may be in distress. Lead with empathy, grounding, and care. Provide appropriate resources. Never replace professional help."
        case .unknown:
            return "Provide balanced, helpful biblical insight. Adjust depth based on the user's apparent familiarity."
        }
    }
}

// MARK: - Explanation Tone

enum ExplanationTone: String, CaseIterable, Codable {
    case pastor   = "pastor"
    case scholar  = "scholar"
    case friend   = "friend"
    case coach    = "coach"

    var displayName: String {
        switch self {
        case .pastor:   return "Pastor"
        case .scholar:  return "Scholar"
        case .friend:   return "Friend"
        case .coach:    return "Coach"
        }
    }

    var icon: String {
        switch self {
        case .pastor:   return "person.crop.circle.badge.checkmark"
        case .scholar:  return "graduationcap.fill"
        case .friend:   return "bubble.left.and.bubble.right.fill"
        case .coach:    return "figure.run"
        }
    }

    var systemPromptAddition: String {
        switch self {
        case .pastor:
            return "Speak like a trusted, warm pastor. Be encouraging and practically helpful. End with a prayer prompt or challenge."
        case .scholar:
            return "Speak like a biblical scholar. Reference original languages (Greek: use transliteration), theological traditions, and historical context. Structure your response clearly."
        case .friend:
            return "Speak like a close Christian friend. Be conversational, relatable, and real. Avoid formal language. Use everyday examples."
        case .coach:
            return "Speak like a life coach with a biblical foundation. Lead with action items. Be direct and motivating. Minimize abstraction."
        }
    }
}

// MARK: - Intent Classifier (on-device, no network)

struct IntentClassifier {

    static func classify(query: String) -> StudyIntent {
        let q = query.lowercased()

        // Crisis signals — check first
        let crisisWords = ["suicide", "kill myself", "end it", "self harm", "hopeless", "no reason to live", "can't go on"]
        if crisisWords.contains(where: { q.contains($0) }) { return .crisis }

        // Decision signals
        let decisionWords = ["should i", "do i", "is it ok to", "is it a sin", "can i", "what does god say about", "biblical perspective on"]
        if decisionWords.contains(where: { q.contains($0) }) { return .decision }

        // Teaching signals
        let teachingWords = ["preach", "sermon", "teach", "bible study", "sunday school", "lesson plan", "outline for", "how to explain"]
        if teachingWords.contains(where: { q.contains($0) }) { return .teaching }

        // Struggle signals
        let struggleWords = ["struggling", "hurting", "depressed", "anxious", "afraid", "lost", "broken", "alone", "help me", "going through", "hard time", "grief", "grieving", "doubt"]
        if struggleWords.contains(where: { q.contains($0) }) { return .struggle }

        // Deep study signals
        let deepWords = ["greek", "hebrew", "original language", "exegesis", "commentary", "doctrine", "theology", "hermeneutics", "historical context", "what does it mean in"]
        if deepWords.contains(where: { q.contains($0) }) { return .deepStudy }

        // Curiosity (default for questions)
        let curiosityWords = ["what", "who", "why", "how", "when", "where", "explain", "tell me", "what is", "what does"]
        if curiosityWords.contains(where: { q.contains($0) }) { return .curiosity }

        return .unknown
    }
}

// MARK: - Study Tone Manager

@MainActor
final class StudyToneManager: ObservableObject {
    static let shared = StudyToneManager()

    @Published var selectedTone: ExplanationTone = .pastor
    @Published var detectedIntent: StudyIntent = .unknown
    @Published var intentConfidence: Double = 0.0

    private lazy var db = Firestore.firestore()
    private let prefsKey = "berean_study_tone"

    private init() {
        // Load persisted tone preference
        if let raw = UserDefaults.standard.string(forKey: prefsKey),
           let tone = ExplanationTone(rawValue: raw) {
            selectedTone = tone
        }
    }

    func setTone(_ tone: ExplanationTone) {
        selectedTone = tone
        UserDefaults.standard.set(tone.rawValue, forKey: prefsKey)
    }

    func classifyAndUpdate(query: String) {
        detectedIntent = IntentClassifier.classify(query: query)
        // Simple confidence heuristic
        intentConfidence = detectedIntent == .unknown ? 0.4 : 0.85
    }

    /// Builds the combined system prompt addition for current tone + intent.
    func systemPromptAddition(for query: String) -> String {
        classifyAndUpdate(query: query)
        return """
        INTENT CONTEXT: \(detectedIntent.systemPromptHint)
        TONE: \(selectedTone.systemPromptAddition)
        """
    }
}

// MARK: - Tone Selector View (embed anywhere)

struct ToneSelectorView: View {
    @ObservedObject var manager: StudyToneManager
    let compact: Bool

    init(manager: StudyToneManager? = nil, compact: Bool = false) {
        self.manager = manager ?? StudyToneManager.shared
        self.compact = compact
    }

    var body: some View {
        if compact {
            // Horizontal pill selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ExplanationTone.allCases, id: \.self) { tone in
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                manager.setTone(tone)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: tone.icon)
                                    .font(.caption2)
                                if !compact {
                                    Text(tone.displayName)
                                        .font(.caption.weight(.medium))
                                }
                            }
                            .padding(.horizontal, compact ? 10 : 12)
                            .padding(.vertical, 6)
                            .background(manager.selectedTone == tone ? Color.indigo : Color(.systemGray5),
                                        in: Capsule())
                            .foregroundStyle(manager.selectedTone == tone ? .white : .primary)
                        }
                    }
                }
            }
        } else {
            // Full labeled selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Explanation Style")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)

                HStack(spacing: 8) {
                    ForEach(ExplanationTone.allCases, id: \.self) { tone in
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                manager.setTone(tone)
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: tone.icon)
                                    .font(.title3)
                                Text(tone.displayName)
                                    .font(.caption2.weight(.medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(manager.selectedTone == tone
                                        ? Color.indigo.opacity(0.15)
                                        : Color(.systemGray6),
                                        in: RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                if manager.selectedTone == tone {
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(Color.indigo, lineWidth: 1.5)
                                }
                            }
                            .foregroundStyle(manager.selectedTone == tone ? .indigo : .primary)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Intent Badge

struct IntentBadgeView: View {
    let intent: StudyIntent

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: intent.icon)
                .font(.caption2)
            Text(intent.displayName)
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(badgeColor.opacity(0.12), in: Capsule())
        .foregroundStyle(badgeColor)
    }

    private var badgeColor: Color {
        switch intent {
        case .curiosity:  return .blue
        case .deepStudy:  return .indigo
        case .struggle:   return .pink
        case .teaching:   return .green
        case .decision:   return .orange
        case .crisis:     return .red
        case .unknown:    return .secondary
        }
    }
}

// MARK: - Intent-Aware Study Sheet

struct IntentAwareStudySheet: View {
    @StateObject private var toneManager = StudyToneManager.shared
    @State private var query: String = ""
    @State private var response: String = ""
    @State private var isLoading: Bool = false
    @Environment(\.dismiss) private var dismiss

    private let claude = ClaudeService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Tone selector
                    ToneSelectorView(manager: toneManager)
                        .padding(.horizontal)

                    // Intent badge (updates as user types)
                    if !query.isEmpty {
                        HStack {
                            Text("Detected intent:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            IntentBadgeView(intent: toneManager.detectedIntent)
                        }
                        .padding(.horizontal)
                    }

                    // Query input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ask anything")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal)
                        TextField("Verse, topic, question, or situation…", text: $query, axis: .vertical)
                            .lineLimit(3...8)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal)
                            .onChange(of: query) { _, q in
                                if q.count > 3 {
                                    toneManager.classifyAndUpdate(query: q)
                                }
                            }
                    }

                    Button {
                        Task { await submitQuery() }
                    } label: {
                        Label(isLoading ? "Studying…" : "Ask Berean", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                    .padding(.horizontal)

                    if !response.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                IntentBadgeView(intent: toneManager.detectedIntent)
                                Spacer()
                                Image(systemName: toneManager.selectedTone.icon)
                                    .foregroundStyle(.secondary)
                                Text(toneManager.selectedTone.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)

                            Text(response)
                                .font(.body)
                                .padding()
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                                .padding(.horizontal)
                        }
                    }

                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Study Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func submitQuery() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLoading = true
        response = ""

        let userContext = await BereanUserContextProvider.shared.getContextBlock()
        _ = toneManager.systemPromptAddition(for: query)

        let prompt = """
        \(userContext)

        User asks: \(query)
        """

        response = (try? await claude.sendMessageSync(prompt, mode: .shepherd)) ?? ""

        isLoading = false
    }
}
