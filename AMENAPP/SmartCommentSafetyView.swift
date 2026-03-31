// SmartCommentSafetyView.swift
// AMENAPP
//
// Pre-submit moderation layer for comments.
// Detects tone before posting. Never preachy, always calm.

import SwiftUI
import Combine

// MARK: - Safety Risk Level

enum SafetyRiskLevel {
    case clear       // no intervention
    case mild        // soft suggestion
    case moderate    // suggest reword
    case high        // offer alternatives before submit
}

// MARK: - Safety Assessment

struct SafetyAssessment {
    let riskLevel: SafetyRiskLevel
    let detectedPatterns: [SafetyPattern]
    let rewordSuggestion: String?
    let alternativeActions: [AlternativeAction]

    enum SafetyPattern: String {
        case accusatoryLanguage
        case escalatingTone
        case repeatedNegativePattern
        case harassmentSignal
        case slander
        case selfHarmPattern
        case ragePattern
    }

    struct AlternativeAction {
        let label: String    // e.g. "Post privately instead"
        let icon: String     // SF Symbol
        let action: String   // identifier for caller to handle
    }

    static let clear = SafetyAssessment(
        riskLevel: .clear,
        detectedPatterns: [],
        rewordSuggestion: nil,
        alternativeActions: []
    )
}

// MARK: - Comment Safety Analyzer

final class CommentSafetyAnalyzer {
    static let shared = CommentSafetyAnalyzer()
    private init() {}

    func analyze(text: String, postType: String, priorCommentCount: Int) -> SafetyAssessment {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .clear
        }

        let lowered = text.lowercased()
        var patterns: [SafetyAssessment.SafetyPattern] = []

        // Accusatory language
        let accusatoryPhrases = ["you always", "you never", "you're the reason", "you should be ashamed"]
        if accusatoryPhrases.contains(where: { lowered.contains($0) }) {
            patterns.append(.accusatoryLanguage)
        }

        // Self-harm patterns — highest priority
        let selfHarmPhrases = ["can't go on", "want to disappear", "nobody cares", "no reason to live",
                               "ending it", "give up on life", "don't want to be here anymore"]
        if selfHarmPhrases.contains(where: { lowered.contains($0) }) {
            patterns.append(.selfHarmPattern)
        }

        // Harassment signal
        let harassmentPhrases = ["worthless", "pathetic", "you're disgusting", "you're a failure",
                                 "nobody likes you", "everyone hates you"]
        if harassmentPhrases.contains(where: { lowered.contains($0) }) {
            patterns.append(.harassmentSignal)
        }

        // Slander signal
        let slanderPhrases = ["is a fraud", "is a liar", "is a fake", "is corrupt", "is a predator"]
        if slanderPhrases.contains(where: { lowered.contains($0) }) {
            patterns.append(.slander)
        }

        // Rage pattern: CAPS percentage > 40%, multiple exclamation marks
        let upperCount = text.filter({ $0.isUppercase }).count
        let letterCount = text.filter({ $0.isLetter }).count
        let exclamationCount = text.filter({ $0 == "!" }).count
        if letterCount > 0 {
            let capsRatio = Double(upperCount) / Double(letterCount)
            if capsRatio > 0.40 || exclamationCount >= 3 {
                patterns.append(.ragePattern)
            }
        }

        // Escalation: if priorCommentCount > 3, raise base risk slightly
        if priorCommentCount > 3 {
            patterns.append(.escalatingTone)
        }

        // Repeated negative pattern: multiple negative words
        let negativeWords = ["terrible", "awful", "horrible", "disgusting", "hate", "stupid", "idiot"]
        let negativeCount = negativeWords.filter({ lowered.contains($0) }).count
        if negativeCount >= 2 {
            patterns.append(.repeatedNegativePattern)
        }

        // Determine risk level
        let riskLevel = determineRiskLevel(patterns: patterns)

        // Build reword suggestion
        let rewordSuggestion = buildRewordSuggestion(patterns: patterns, originalText: text)

        // Build alternative actions
        let alternatives = buildAlternativeActions(patterns: patterns, riskLevel: riskLevel)

        return SafetyAssessment(
            riskLevel: riskLevel,
            detectedPatterns: patterns,
            rewordSuggestion: rewordSuggestion,
            alternativeActions: alternatives
        )
    }

    private func determineRiskLevel(patterns: [SafetyAssessment.SafetyPattern]) -> SafetyRiskLevel {
        // High-priority patterns always escalate to high
        let highPatterns: [SafetyAssessment.SafetyPattern] = [.selfHarmPattern, .harassmentSignal, .slander]
        if patterns.contains(where: { highPatterns.contains($0) }) {
            return .high
        }

        // Moderate: 2+ signals or 1 strong signal
        let strongPatterns: [SafetyAssessment.SafetyPattern] = [.ragePattern, .accusatoryLanguage]
        let strongCount = patterns.filter({ strongPatterns.contains($0) }).count
        if strongCount >= 1 || patterns.count >= 2 {
            return .moderate
        }

        // Mild: 1 mild signal
        if patterns.count == 1 {
            return .mild
        }

        return .clear
    }

    private func buildRewordSuggestion(patterns: [SafetyAssessment.SafetyPattern], originalText: String) -> String? {
        guard !patterns.isEmpty else { return nil }
        if patterns.contains(.accusatoryLanguage) {
            return "Consider sharing how you feel rather than directing blame. For example, \"I felt hurt when...\" instead of placing fault."
        }
        if patterns.contains(.ragePattern) {
            return "This reply reads with strong intensity. A calmer tone may land better and start a healthier conversation."
        }
        if patterns.contains(.repeatedNegativePattern) {
            return "There are a few strong words here. Would a gentler phrasing still get your point across?"
        }
        if patterns.contains(.escalatingTone) {
            return "You've been active in this thread. A pause before posting can help keep things constructive."
        }
        return nil
    }

    private func buildAlternativeActions(
        patterns: [SafetyAssessment.SafetyPattern],
        riskLevel: SafetyRiskLevel
    ) -> [SafetyAssessment.AlternativeAction] {
        var actions: [SafetyAssessment.AlternativeAction] = []

        if riskLevel == .high || riskLevel == .moderate {
            actions.append(.init(label: "Post privately instead", icon: "lock", action: "post_private"))
            actions.append(.init(label: "Save as a draft", icon: "square.and.pencil", action: "save_draft"))
        }

        if patterns.contains(.accusatoryLanguage) || patterns.contains(.ragePattern) {
            actions.append(.init(label: "Reflect before replying", icon: "pencil.and.outline", action: "open_reflect"))
        }

        if patterns.contains(.selfHarmPattern) {
            actions.append(.init(label: "Talk to someone", icon: "heart.text.square", action: "support_resource"))
        }

        return actions
    }
}

// MARK: - Smart Comment Safety View

struct SmartCommentSafetyView: View {
    let assessment: SafetyAssessment
    @Binding var commentText: String
    let onProceed: () -> Void
    let onAlternative: (String) -> Void

    @State private var isDismissed = false

    var body: some View {
        if !isDismissed {
            switch assessment.riskLevel {
            case .clear:
                EmptyView()

            case .mild:
                mildView

            case .moderate:
                moderateView

            case .high:
                if assessment.detectedPatterns.contains(.selfHarmPattern) {
                    selfHarmSupportView
                } else {
                    highView
                }
            }
        }
    }

    // MARK: Mild — soft strip with dismiss

    private var mildView: some View {
        HStack(spacing: 10) {
            Image(systemName: "wind")
                .font(.system(size: 13))
                .foregroundStyle(Color.black.opacity(0.4))

            Text("Take a breath before posting?")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.black.opacity(0.55))

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    isDismissed = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.35))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(glassBackground(cornerRadius: 12))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: Moderate — reword suggestion card

    private var moderateView: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let suggestion = assessment.rewordSuggestion {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.black.opacity(0.45))
                        .padding(.top, 1)

                    Text(suggestion)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Button {
                    if let suggestion = assessment.rewordSuggestion {
                        commentText = suggestion
                    }
                } label: {
                    Text("Use suggestion")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isDismissed = true
                    }
                    onProceed()
                } label: {
                    Text("Post anyway")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(glassBackground(cornerRadius: 14))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: High — calm alternatives, no hard block

    private var highView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.black.opacity(0.4))

                Text("Before you post — want to try a different approach?")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.65))
            }

            Text("This reply has some strong language. You can still post, but here are a few other options.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.black.opacity(0.45))

            VStack(spacing: 7) {
                ForEach(assessment.alternativeActions, id: \.action) { alt in
                    Button {
                        onAlternative(alt.action)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: alt.icon)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.black.opacity(0.5))
                            Text(alt.label)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.65))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.black.opacity(0.2))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(glassBackground(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    isDismissed = true
                }
                onProceed()
            } label: {
                Text("Post anyway")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(glassBackground(cornerRadius: 16))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: Self-Harm Support

    private var selfHarmSupportView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "heart")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.black.opacity(0.4))

                Text("We're glad you're here.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.7))
            }

            Text("It sounds like you might be going through something heavy. You don't have to carry that alone.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.black.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                onAlternative("support_resource")
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "heart.text.square")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.black.opacity(0.5))
                    Text("Would you like to talk to someone?")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.65))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.black.opacity(0.2))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(glassBackground(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    isDismissed = true
                }
                onProceed()
            } label: {
                Text("Continue posting")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(glassBackground(cornerRadius: 16))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: Glass Background Helper

    private func glassBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 2)
    }
}

// MARK: - Comment Input Bar View

struct CommentInputBarView: View {
    let postId: String
    let postType: String
    let onSubmit: (String) -> Void

    @State private var text: String = ""
    @State private var assessment: SafetyAssessment? = nil
    @State private var priorCount: Int = 0
    @State private var debounceTask: Task<Void, Never>? = nil

    private var placeholder: String {
        switch postType {
        case "sermonClip", "teaching":  return "What stood out to you?"
        case "testimony":               return "Encourage this person..."
        case "churchEvent":             return "What did you take away?"
        case "question":                return "Share a thoughtful response..."
        case "prayer", "prayerRequest": return "Offer a word of encouragement..."
        default:                        return "Add a reply..."
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            // Safety view (animated in/out)
            if let assessment = assessment, assessment.riskLevel != .clear {
                SmartCommentSafetyView(
                    assessment: assessment,
                    commentText: $text,
                    onProceed: {
                        submitText()
                    },
                    onAlternative: { actionId in
                        handleAlternative(actionId)
                    }
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: assessment.riskLevel)
            }

            // Input row
            HStack(spacing: 10) {
                // Input capsule
                ZStack(alignment: .leading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.black.opacity(0.3))
                            .padding(.horizontal, 16)
                    }
                    TextField("", text: $text, axis: .vertical)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.black.opacity(0.8))
                        .lineLimit(1...5)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .onChange(of: text) { _, newValue in
                            scheduleAnalysis(for: newValue)
                        }
                }
                .background {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.white.opacity(0.55))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                        )
                        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 2)
                }

                // Send button
                Button {
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    let finalAssessment = CommentSafetyAnalyzer.shared.analyze(
                        text: text,
                        postType: postType,
                        priorCommentCount: priorCount
                    )
                    if finalAssessment.riskLevel == .clear || finalAssessment.riskLevel == .mild {
                        submitText()
                    } else {
                        assessment = finalAssessment
                    }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                      ? Color.black.opacity(0.15)
                                      : Color.black.opacity(0.8))
                        )
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .animation(.easeInOut(duration: 0.15), value: text.isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func scheduleAnalysis(for newText: String) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            let result = CommentSafetyAnalyzer.shared.analyze(
                text: newText,
                postType: postType,
                priorCommentCount: priorCount
            )
            await MainActor.run {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if result.riskLevel == .clear {
                        assessment = nil
                    } else {
                        assessment = result
                    }
                }
            }
        }
    }

    private func submitText() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
        text = ""
        assessment = nil
        priorCount += 1
    }

    private func handleAlternative(_ actionId: String) {
        switch actionId {
        case "post_private":
            print("Post privately: \(text)")
            text = ""
            assessment = nil
        case "save_draft":
            print("Saved draft: \(text)")
            text = ""
            assessment = nil
        case "open_reflect":
            print("Open reflect composer with text: \(text)")
        case "support_resource":
            print("Open support resource")
        default:
            break
        }
    }
}

// MARK: - Preview

#Preview("Comment Safety States") {
    ZStack {
        Color(white: 0.96).ignoresSafeArea()

        ScrollView {
            VStack(spacing: 24) {

                // Clear state — just the input bar
                VStack(alignment: .leading, spacing: 6) {
                    Text("Clear state")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                    CommentInputBarView(postId: "post-001", postType: "testimony") { text in
                        print("Submitted: \(text)")
                    }
                }

                // Mild state — inline preview
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mild intervention")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                    let mildAssessment = SafetyAssessment(
                        riskLevel: .mild,
                        detectedPatterns: [.escalatingTone],
                        rewordSuggestion: nil,
                        alternativeActions: []
                    )
                    SmartCommentSafetyView(
                        assessment: mildAssessment,
                        commentText: .constant(""),
                        onProceed: {},
                        onAlternative: { _ in }
                    )
                    .padding(.horizontal, 12)
                }

                // Moderate state
                VStack(alignment: .leading, spacing: 6) {
                    Text("Moderate intervention")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                    let moderateAssessment = SafetyAssessment(
                        riskLevel: .moderate,
                        detectedPatterns: [.accusatoryLanguage],
                        rewordSuggestion: "Consider sharing how you feel rather than directing blame. For example, \"I felt hurt when...\" instead of placing fault.",
                        alternativeActions: [
                            .init(label: "Post privately instead", icon: "lock", action: "post_private"),
                            .init(label: "Save as a draft", icon: "square.and.pencil", action: "save_draft")
                        ]
                    )
                    SmartCommentSafetyView(
                        assessment: moderateAssessment,
                        commentText: .constant(""),
                        onProceed: {},
                        onAlternative: { _ in }
                    )
                    .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 24)
        }
    }
}
