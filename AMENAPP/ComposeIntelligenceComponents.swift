//
//  ComposeIntelligenceComponents.swift
//  AMENAPP
//
//  AI-powered compose intelligence layer for CreatePostView.
//  All components use the existing liquid glass design language.
//  No layout/navigation/submission logic is changed.
//

import SwiftUI
import Combine
import Speech
import AVFoundation

// MARK: - Models

enum ComposePostType: String, CaseIterable {
    case prayer     = "Prayer Request"
    case testimony  = "Testimony"
    case leadership = "Leadership"
    case generic    = "Post"

    var icon: String {
        switch self {
        case .prayer:     return "hands.sparkles.fill"
        case .testimony:  return "star.fill"
        case .leadership: return "briefcase.fill"
        case .generic:    return "text.bubble.fill"
        }
    }

    var color: Color {
        switch self {
        case .prayer:     return .blue
        case .testimony:  return .yellow
        case .leadership: return Color(red: 0.4, green: 0.7, blue: 0.5)
        case .generic:    return .purple
        }
    }

    var description: String {
        switch self {
        case .prayer:     return "This looks like a prayer request"
        case .testimony:  return "This sounds like a testimony"
        case .leadership: return "This reads like a leadership insight"
        case .generic:    return "Switch post format"
        }
    }

    /// Maps to CreatePostView.PostCategory for the category switch action.
    /// Returns nil when no direct mapping exists (generic/leadership have no dedicated category).
    var toPostCategory: CreatePostView.PostCategory? {
        switch self {
        case .prayer:    return .prayer
        case .testimony: return .testimonies
        default:         return nil
        }
    }
}

struct ComposeSuggestion: Identifiable {
    enum Category: String {
        case scripture  = "Scripture"
        case tone       = "Tone"
        case format     = "Format"
    }
    let id = UUID()
    let category: Category
    let text: String
    let applyValue: String?  // Pre-built text to insert (e.g. verse reference)
}

// MARK: - Post Type Classifier (on-device, no API)

enum PostTypeClassifier {
    static func classify(_ text: String) -> ComposePostType? {
        let lower = text.lowercased()
        let wordCount = lower.split(separator: " ").count
        guard wordCount >= 5 else { return nil }

        let prayerKeywords   = ["pray", "prayer", "praying", "lord", "god please", "asking god",
                                "please pray", "need prayer", "lift me", "struggling with",
                                "going through", "hard time", "difficult season"]
        let testimonyKeywords = ["god did", "testimony", "grateful", "thankful", "blessed",
                                 "god was faithful", "he came through", "praise god",
                                 "testimony", "miracle", "god showed up", "he healed"]
        let leadershipKeywords = ["leadership", "decision", "principle", "team", "organization",
                                  "strategy", "vision", "culture", "management", "leading",
                                  "founder", "ceo", "executive", "pastor", "ministry leader"]

        let prayerScore    = prayerKeywords.filter    { lower.contains($0) }.count
        let testimonyScore = testimonyKeywords.filter { lower.contains($0) }.count
        let leaderScore    = leadershipKeywords.filter { lower.contains($0) }.count

        let maxScore = max(prayerScore, testimonyScore, leaderScore)
        guard maxScore >= 1 else { return nil }

        if prayerScore == maxScore    { return .prayer }
        if testimonyScore == maxScore { return .testimony }
        return .leadership
    }
}

// MARK: - Quality Scorer (on-device, no API)

enum ComposeQualityScorer {
    static func score(text: String, hasScriptureCard: Bool) -> Double {
        let words = text.split(separator: " ").count
        guard words >= 5 else { return 0 }

        var score: Double = 0

        // Word count contribution (max 0.4)
        let wordScore = min(Double(words) / 150.0, 1.0) * 0.4
        score += wordScore

        // Scripture presence (0.25)
        if hasScriptureCard { score += 0.25 }

        // Specificity signals (mentions a name, number, place → 0.2)
        let hasSpecificity = text.range(of: #"\b\d+\b"#, options: .regularExpression) != nil
            || text.range(of: #"\b[A-Z][a-z]+ [A-Z][a-z]+\b"#, options: .regularExpression) != nil
        if hasSpecificity { score += 0.20 }

        // Question engagement (0.15)
        if text.contains("?") { score += 0.15 }

        return min(score, 1.0)
    }
}

// MARK: - Post Type Detection Banner

struct PostTypeDetectionBanner: View {
    let detectedType: ComposePostType
    let onSwitch: () -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(detectedType.color.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: detectedType.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(detectedType.color)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(detectedType.description)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Switch to \(detectedType.rawValue) format?")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onSwitch()
            } label: {
                Text("Switch")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(detectedType.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(detectedType.color.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(detectedType.color.opacity(0.18), lineWidth: 0.5)
                )
        )
        .accessibilityLabel("\(detectedType.description). Tap Switch to change format.")
        .accessibilityHint("Tap × to dismiss this suggestion")
    }
}

// MARK: - Quality Bar

struct ComposeQualityBar: View {
    let score: Double  // 0.0 – 1.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fillColor: Color {
        if score < 0.35 { return Color(red: 0.95, green: 0.65, blue: 0.2) }
        if score < 0.68 { return Color(red: 0.58, green: 0.35, blue: 0.92) }
        return Color(red: 0.25, green: 0.72, blue: 0.45)
    }

    private var milestoneLabel: String? {
        if score >= 0.68 { return "Great · + scripture" }
        if score >= 0.35 { return "Good · 50 words" }
        return nil
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.07))
                        .frame(height: 3)

                    Capsule()
                        .fill(fillColor)
                        .frame(width: geo.size.width * score, height: 3)
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: 0.5),
                            value: score
                        )
                }
            }
            .frame(height: 3)

            if let label = milestoneLabel {
                Text(label)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(fillColor.opacity(0.7))
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.3), value: milestoneLabel)
            }
        }
        .accessibilityLabel("Post quality: \(Int(score * 100))%")
        .accessibilityHidden(score == 0)
    }
}

// MARK: - Berean Suggestions Panel

struct BereanSuggestionsPanel: View {
    let suggestions: [ComposeSuggestion]
    let isLoading: Bool
    let onApply: (ComposeSuggestion) -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image("amen-logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                    Text("Berean is reading your post")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider().opacity(0.3)

            if isLoading {
                // Three bouncing dots
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { i in
                        LoadingDot(delay: Double(i) * 0.18)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                ForEach(suggestions) { suggestion in
                    BereanSuggestionRow(suggestion: suggestion) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onApply(suggestion)
                    }
                    if suggestion.id != suggestions.last?.id {
                        Divider().opacity(0.2).padding(.horizontal, 14)
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.purple.opacity(0.15), lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct LoadingDot: View {
    let delay: Double
    @State private var bouncing = false

    var body: some View {
        Circle()
            .fill(Color.secondary.opacity(0.5))
            .frame(width: 6, height: 6)
            .offset(y: bouncing ? -5 : 0)
            .animation(
                .easeInOut(duration: 0.4).repeatForever().delay(delay),
                value: bouncing
            )
            .onAppear { bouncing = true }
    }
}

private struct BereanSuggestionRow: View {
    let suggestion: ComposeSuggestion
    let onApply: () -> Void

    private var badgeColor: Color {
        switch suggestion.category {
        case .scripture: return Color(red: 0.9, green: 0.65, blue: 0.2)
        case .tone:      return Color(red: 0.4, green: 0.65, blue: 0.95)
        case .format:    return Color(red: 0.55, green: 0.38, blue: 0.92)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(suggestion.category.rawValue)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(badgeColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(badgeColor.opacity(0.12), in: Capsule())

            Text(suggestion.text)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)

            Spacer(minLength: 0)

            Button(action: onApply) {
                Text("Apply →")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.purple)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityLabel("\(suggestion.category.rawValue) suggestion: \(suggestion.text). Tap Apply to use it.")
    }
}

// MARK: - Scripture Card Attachment

struct ScriptureCardAttachment: View {
    let reference: String
    let verseText: String
    let onRemove: () -> Void

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .top, spacing: 14) {
                // Decorative quote mark
                Text("\u{201C}")
                    .font(.system(size: 52, weight: .bold, design: .serif))
                    .foregroundStyle(Color.purple.opacity(0.15))
                    .offset(y: -8)

                VStack(alignment: .leading, spacing: 6) {
                    Text(verseText)
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .foregroundStyle(.primary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(reference)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(red: 0.85, green: 0.6, blue: 0.2))
                }

                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.purple.opacity(0.2), lineWidth: 0.6)
                    )
            )

            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.secondary)
                    .background(Circle().fill(Color(.systemBackground)))
            }
            .buttonStyle(.plain)
            .offset(x: 8, y: -8)
        }
        .padding(.top, 8)
        .scaleEffect(appeared ? 1.0 : 0.95)
        .opacity(appeared ? 1.0 : 0)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.75)) {
                appeared = true
            }
        }
        .accessibilityLabel("Scripture card: \(reference) — \(verseText)")
        .accessibilityHint("Double tap to remove")
    }
}

// MARK: - Compose Template Sheet

struct ComposeTemplateSheet: View {
    @Binding var isPresented: Bool
    var selectedCategory: String = "openTable"
    let onSelect: (String) -> Void

    private struct Template: Identifiable {
        let id = UUID()
        let icon: String
        let color: Color
        let name: String
        let structure: String
        let placeholder: String
        /// Which categories this template appears in ("all" = every category)
        let categories: Set<String>
    }

    private let allTemplates: [Template] = [
        // ── Prayer ──────────────────────────────────────────────────
        Template(
            icon: "hands.sparkles.fill",
            color: .blue,
            name: "Prayer Request",
            structure: "Please pray for / Context / Scripture I'm standing on",
            placeholder: "Please pray for…\n\nHere's the context:\n\nScripture I'm standing on:\n",
            categories: ["prayer", "all"]
        ),
        Template(
            icon: "sun.max.fill",
            color: .cyan,
            name: "Praise Report",
            structure: "What I prayed for / How God answered / What it taught me",
            placeholder: "What I prayed for:\n\nHow God answered:\n\nWhat it taught me:\n",
            categories: ["prayer"]
        ),
        Template(
            icon: "person.2.fill",
            color: .indigo,
            name: "Intercessory Prayer",
            structure: "Who I'm lifting up / The situation / How to pray with me",
            placeholder: "I'm lifting up:\n\nThe situation:\n\nPlease pray with me for:\n",
            categories: ["prayer"]
        ),
        Template(
            icon: "moon.stars.fill",
            color: Color(red: 0.3, green: 0.4, blue: 0.7),
            name: "Evening Reflection Prayer",
            structure: "What I'm thankful for today / Where I need grace / What I'm surrendering",
            placeholder: "Today I'm thankful for:\n\nWhere I need grace:\n\nWhat I'm surrendering tonight:\n",
            categories: ["prayer"]
        ),

        // ── Testimonies ─────────────────────────────────────────────
        Template(
            icon: "star.fill",
            color: .yellow,
            name: "Testimony",
            structure: "The situation / What I asked God for / What happened / What I learned",
            placeholder: "The situation:\n\nWhat I asked God for:\n\nWhat happened:\n\nWhat I learned:\n",
            categories: ["testimonies", "all"]
        ),
        Template(
            icon: "heart.circle.fill",
            color: .pink,
            name: "Breakthrough Story",
            structure: "What I was going through / The turning point / Where I am now",
            placeholder: "What I was going through:\n\nThe turning point:\n\nWhere I am now:\n",
            categories: ["testimonies"]
        ),
        Template(
            icon: "figure.walk",
            color: .orange,
            name: "Faith Journey Milestone",
            structure: "Where I started / What changed / The moment I knew / My encouragement to you",
            placeholder: "Where I started:\n\nWhat changed:\n\nThe moment I knew:\n\nMy encouragement to you:\n",
            categories: ["testimonies"]
        ),

        // ── OpenTable ───────────────────────────────────────────────
        Template(
            icon: "arrow.clockwise.heart.fill",
            color: .orange,
            name: "Weekly Reflection",
            structure: "This week I learned / struggled with / am grateful for / am believing for",
            placeholder: "This week I learned:\n\nI struggled with:\n\nI'm grateful for:\n\nI'm believing for:\n",
            categories: ["openTable", "all"]
        ),
        Template(
            icon: "questionmark.bubble.fill",
            color: Color(red: 0.3, green: 0.6, blue: 0.8),
            name: "Open Question",
            structure: "What I've been thinking about / Why it matters / What's your take?",
            placeholder: "Something I've been thinking about:\n\nWhy it matters:\n\nWhat's your take?\n",
            categories: ["openTable"]
        ),
        Template(
            icon: "quote.opening",
            color: Color(red: 0.78, green: 0.50, blue: 0.18),
            name: "Scripture + Thought",
            structure: "The verse / What stood out / How I'm applying it",
            placeholder: "The verse:\n\nWhat stood out to me:\n\nHow I'm applying it:\n",
            categories: ["openTable", "prayer"]
        ),
        Template(
            icon: "lightbulb.fill",
            color: .orange,
            name: "Hot Take / Discussion",
            structure: "My perspective on / Why I believe this / Open to hearing yours",
            placeholder: "My perspective:\n\nWhy I believe this:\n\nI'm open to hearing yours.\n",
            categories: ["openTable"]
        ),
        Template(
            icon: "briefcase.fill",
            color: Color(red: 0.4, green: 0.7, blue: 0.5),
            name: "Leadership Insight",
            structure: "The challenge / The decision / The principle / The outcome",
            placeholder: "The challenge:\n\nThe decision I made:\n\nThe principle behind it:\n\nThe outcome:\n",
            categories: ["openTable"]
        ),
        Template(
            icon: "book.fill",
            color: .purple,
            name: "Bible Study Note",
            structure: "Passage / Observation / Interpretation / Application (SOAP)",
            placeholder: "Passage:\n\nObservation (what I see):\n\nInterpretation (what it means):\n\nApplication (what I'll do):\n",
            categories: ["openTable", "all"]
        ),
        Template(
            icon: "text.book.closed.fill",
            color: Color(red: 0.5, green: 0.3, blue: 0.6),
            name: "Sermon Notes",
            structure: "Speaker & topic / Key scripture / Main takeaway / One thing I'll apply",
            placeholder: "Speaker & topic:\n\nKey scripture:\n\nMain takeaway:\n\nOne thing I'll apply this week:\n",
            categories: ["openTable"]
        ),
        Template(
            icon: "leaf.fill",
            color: .green,
            name: "Gratitude Post",
            structure: "Three things I'm grateful for today and why",
            placeholder: "Today I'm grateful for:\n\n1. \n\n2. \n\n3. \n\nBecause:\n",
            categories: ["openTable", "all"]
        ),
        Template(
            icon: "megaphone.fill",
            color: .red,
            name: "Encouragement",
            structure: "To anyone who needs to hear this / The truth / My prayer for you",
            placeholder: "To anyone who needs to hear this:\n\nThe truth is:\n\nMy prayer for you:\n",
            categories: ["openTable", "testimonies"]
        ),
    ]

    /// Templates filtered to the selected category, with "all" templates always included.
    /// Category-specific templates appear first, then universal ones.
    private var filteredTemplates: [Template] {
        let categorySpecific = allTemplates.filter {
            $0.categories.contains(selectedCategory) && !$0.categories.contains("all")
        }
        let universal = allTemplates.filter {
            $0.categories.contains("all")
        }
        // Deduplicate: if a template is both category-specific and "all", it's already in categorySpecific
        let universalOnly = universal.filter { u in
            !categorySpecific.contains(where: { $0.name == u.name })
        }
        return categorySpecific + universalOnly
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Category-specific header
                        categoryHeader

                        // Template rows
                        VStack(spacing: 1) {
                            ForEach(filteredTemplates) { template in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    onSelect(template.placeholder)
                                    isPresented = false
                                } label: {
                                    HStack(spacing: 14) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(template.color.opacity(0.15))
                                                .frame(width: 36, height: 36)
                                            Image(systemName: template.icon)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(template.color)
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(template.name)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(.primary)
                                            Text(template.structure)
                                                .font(.system(size: 12, weight: .regular))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color(.systemBackground))
                                    .accessibilityLabel("\(template.name) template: \(template.structure)")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Choose a Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }

    private var categoryHeader: some View {
        let categoryName: String = {
            switch selectedCategory {
            case "prayer": return "Prayer"
            case "testimonies": return "Testimonies"
            case "openTable": return "OpenTable"
            default: return "Post"
            }
        }()
        return Text("Templates for \(categoryName)")
            .font(.custom("OpenSans-Regular", size: 13))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 4)
    }
}

// MARK: - Voice Language Picker

struct VoiceLanguagePickerSheet: View {
    @Binding var isPresented: Bool
    @Binding var selectedLocale: Locale

    private let supportedLocales: [(Locale, String)] = [
        (Locale(identifier: "en-US"), "English (US)"),
        (Locale(identifier: "es-US"), "Español (US)"),
        (Locale(identifier: "es-ES"), "Español (España)"),
        (Locale(identifier: "fr-FR"), "Français"),
        (Locale(identifier: "pt-BR"), "Português (Brasil)"),
        (Locale(identifier: "de-DE"), "Deutsch"),
        (Locale(identifier: "zh-CN"), "中文 (简体)")
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(supportedLocales, id: \.0.identifier) { locale, label in
                    Button {
                        selectedLocale = locale
                        isPresented = false
                    } label: {
                        HStack {
                            Text(label)
                                .foregroundStyle(.primary)
                            Spacer()
                            if locale.identifier == selectedLocale.identifier {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.purple)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Transcription Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Voice Transcription Button

struct VoiceTranscribeButton: View {
    @Binding var isRecording: Bool
    let onTranscription: (String) -> Void

    @StateObject private var whisperVM = WhisperVoiceViewModel()
    @State private var selectedLocale: Locale = Locale(identifier: "en-US")
    @State private var showLanguagePicker = false
    @State private var pulse = false
    @State private var permissionDenied = false
    @State private var errorMessage: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            Button {
                Task {
                    if isRecording {
                        await stopAndTranscribe()
                    } else {
                        await startRecording()
                    }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(isRecording ? Color.red.opacity(0.15) : Color(.systemGray6))
                        .frame(width: 32, height: 32)

                    if isRecording && !reduceMotion {
                        Circle()
                            .stroke(Color.red.opacity(0.3), lineWidth: 2)
                            .frame(width: 32, height: 32)
                            .scaleEffect(pulse ? 1.5 : 1.0)
                            .opacity(pulse ? 0 : 0.6)
                            .animation(.easeOut(duration: 0.9).repeatForever(autoreverses: false), value: pulse)
                            .onAppear { pulse = true }
                            .onDisappear { pulse = false }
                    }

                    if whisperVM.isTranscribing {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: isRecording ? "mic.fill" : "mic")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(isRecording ? .red : .secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(whisperVM.isTranscribing)
            .accessibilityLabel(isRecording ? "Stop recording" : "Start voice transcription")

            // Language indicator button — only show when not recording
            if !isRecording && !whisperVM.isTranscribing {
                Button { showLanguagePicker = true } label: {
                    Text(selectedLocale.identifier.prefix(2).uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change transcription language: \(selectedLocale.identifier)")
            }
        }
        .sheet(isPresented: $showLanguagePicker) {
            VoiceLanguagePickerSheet(isPresented: $showLanguagePicker, selectedLocale: $selectedLocale)
        }
        // Consent banner — shown on first use
        .alert("Voice Recording", isPresented: $whisperVM.showConsentBanner) {
            Button("Allow") {
                Task { await whisperVM.acceptConsent() }
            }
            Button("Not Now", role: .cancel) {
                whisperVM.declineConsent()
            }
        } message: {
            Text("AMEN uses voice-to-text to transcribe your words. Audio is processed securely and deleted immediately after transcription.")
        }
        .alert("Microphone access is required for voice transcription.", isPresented: $permissionDenied) {
            Button("OK", role: .cancel) {}
        }
        .alert(errorMessage ?? "Transcription failed.", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        }
        // Sync whisperVM.isRecording → parent binding
        .onChange(of: whisperVM.isRecording) { _, newValue in
            isRecording = newValue
        }
        // Deliver transcript when ready
        .onChange(of: whisperVM.transcript) { _, newTranscript in
            guard !newTranscript.isEmpty else { return }
            onTranscription(newTranscript)
            whisperVM.transcript = ""
        }
    }

    private func startRecording() async {
        // Sync language to WhisperVoiceService
        let langCode = String(selectedLocale.identifier.prefix(2))
        WhisperVoiceService.shared.languageCode = langCode

        await whisperVM.startRecording()

        if let err = whisperVM.error {
            if case .micPermissionDenied = err {
                permissionDenied = true
            } else {
                errorMessage = err.localizedDescription
            }
        }
    }

    private func stopAndTranscribe() async {
        await whisperVM.stopAndTranscribe()

        if let err = whisperVM.error {
            // Low confidence: still delivered via onChange(of: transcript)
            if case .lowConfidence = err { return }
            errorMessage = err.localizedDescription
        }
    }
}

// MARK: - Compose Analysis Service

/// Calls Claude Haiku with the post text and returns up to 3 contextual suggestions.
/// Response JSON format: [{"category": "scripture"|"tone"|"format", "text": "...", "applyValue": "..."|null}]
@MainActor
final class ComposeAnalysisService {
    static let shared = ComposeAnalysisService()
    private init() {}

    func analyze(postText: String) async throws -> [ComposeSuggestion] {
        let prompt = """
        Analyze this draft post for a Christian community app and return 1-3 helpful suggestions in JSON.

        Post:
        \(postText)

        Return ONLY a JSON array, no markdown, no explanation:
        [{"category":"scripture","text":"This connects to Romans 8:28 — want to anchor it?","applyValue":"Romans 8:28"},
         {"category":"tone","text":"This reads as venting — consider framing it as a prayer request instead.","applyValue":null}]

        Categories: scripture (relevant verse), tone (framing suggestion), format (structure suggestion).
        Maximum 3 items. Keep text under 80 characters. If the post is already excellent, return [].
        """

        let raw = try await ClaudeService.shared.sendMessageSync(
            prompt,
            conversationHistory: [],
            mode: .shepherd
        )

        // Parse JSON
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonStart = cleaned.firstIndex(of: "["),
              let jsonEnd = cleaned.lastIndex(of: "]") else {
            return []
        }
        let jsonSlice = String(cleaned[jsonStart...jsonEnd])
        guard let data = jsonSlice.data(using: .utf8) else { return [] }

        struct RawSuggestion: Decodable {
            let category: String
            let text: String
            let applyValue: String?
        }
        let rawSuggestions = try JSONDecoder().decode([RawSuggestion].self, from: data)
        return rawSuggestions.compactMap { raw -> ComposeSuggestion? in
            let cat: ComposeSuggestion.Category
            switch raw.category.lowercased() {
            case "scripture": cat = .scripture
            case "tone":      cat = .tone
            case "format":    cat = .format
            default:          return nil
            }
            return ComposeSuggestion(category: cat, text: raw.text, applyValue: raw.applyValue)
        }
    }
}

// MARK: - Sensitivity / Privacy Detector (on-device)

enum SensitivityClassifier {
    struct Result {
        let isSensitive: Bool
        let reason: String
        let suggestedVisibility: String  // "followers" | "private" | nil-implies-no-change
    }

    private static let healthKeywords     = ["cancer", "diagnosis", "hospital", "surgery", "illness",
                                              "chronic", "disability", "mental health", "depression",
                                              "anxiety disorder", "medication", "therapist"]
    private static let addictionKeywords  = ["addiction", "addicted", "sobriety", "recovery", "relapse",
                                              "alcohol", "drugs", "porn", "gambling", "rehab"]
    private static let marriageKeywords   = ["divorce", "separated", "infidelity", "cheating", "affair",
                                              "marital", "marriage issues", "spouse", "abusive"]
    private static let griefKeywords      = ["died", "death", "passed away", "funeral", "grieving",
                                              "lost my", "suicide", "miscarriage", "stillborn"]

    static func classify(_ text: String) -> Result {
        let lower = text.lowercased()
        let wordCount = lower.split(separator: " ").count
        guard wordCount >= 8 else { return Result(isSensitive: false, reason: "", suggestedVisibility: "") }

        if addictionKeywords.contains(where: { lower.contains($0) }) {
            return Result(isSensitive: true, reason: "This post mentions addiction or recovery", suggestedVisibility: "followers")
        }
        if griefKeywords.contains(where: { lower.contains($0) }) {
            return Result(isSensitive: true, reason: "This post mentions grief or loss", suggestedVisibility: "followers")
        }
        if healthKeywords.contains(where: { lower.contains($0) }) {
            return Result(isSensitive: true, reason: "This post mentions personal health", suggestedVisibility: "followers")
        }
        if marriageKeywords.contains(where: { lower.contains($0) }) {
            return Result(isSensitive: true, reason: "This post mentions relationship struggles", suggestedVisibility: "private")
        }
        return Result(isSensitive: false, reason: "", suggestedVisibility: "")
    }
}

// MARK: - Sensitivity Nudge Banner

struct SensitivityPrivacyNudge: View {
    let reason: String
    let suggestedVisibility: String
    let onApply: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color(red: 0.55, green: 0.35, blue: 0.92))

            VStack(alignment: .leading, spacing: 2) {
                Text(reason)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Consider sharing with followers only")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onApply()
            } label: {
                Text("Apply")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.55, green: 0.35, blue: 0.92))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(red: 0.55, green: 0.35, blue: 0.92).opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color(red: 0.55, green: 0.35, blue: 0.92).opacity(0.18), lineWidth: 0.5)
                )
        )
        .accessibilityLabel("\(reason). Tap Apply to change visibility.")
    }
}

// MARK: - Smart Tag Suggestions

struct SmartTagSuggestions: View {
    let detectedType: ComposePostType
    let onSelectTag: (String) -> Void

    private var suggestedTags: [String] {
        switch detectedType {
        case .prayer:     return ["#prayer", "#intercession", "#healing", "#faith"]
        case .testimony:  return ["#testimony", "#grateful", "#godfaithful", "#blessed"]
        case .leadership: return ["#leadership", "#faith", "#ministry", "#wisdom"]
        case .generic:    return ["#reflection", "#faith", "#community"]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Suggested tags")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(suggestedTags, id: \.self) { tag in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onSelectTag(tag)
                        } label: {
                            Text(tag)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(detectedType.color)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(detectedType.color.opacity(0.10), in: Capsule())
                                .overlay(Capsule().stroke(detectedType.color.opacity(0.2), lineWidth: 0.6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add tag \(tag)")
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - First-Time Coaching Tooltip

struct ComposeIntelligenceCoachTooltip: View {
    @Binding var isVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.75)) {
                        isVisible = false
                    }
                    UserDefaults.standard.set(true, forKey: "composeIntelligenceCoachShown")
                }

            VStack(spacing: 16) {
                Spacer()

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: "sparkles")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color(red: 1.0, green: 0.75, blue: 0.2))
                        Text("AI Compose Assistant")
                            .font(.system(size: 16, weight: .semibold))
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        CoachRow(icon: "chart.bar.fill",
                                 color: Color(red: 0.58, green: 0.35, blue: 0.92),
                                 title: "Quality bar",
                                 message: "Shows how complete your post is — grows as you add words, scripture, and detail.")
                        CoachRow(icon: "lightbulb.fill",
                                 color: Color(red: 1.0, green: 0.75, blue: 0.2),
                                 title: "Berean suggestions",
                                 message: "After 20+ words, Berean reads your draft and offers a relevant verse, tone tip, or format idea.")
                        CoachRow(icon: "hands.sparkles.fill",
                                 color: .blue,
                                 title: "Post type detection",
                                 message: "Writing a prayer? A testimony? The app detects it and offers to format it for you.")
                    }

                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.75)) {
                            isVisible = false
                        }
                        UserDefaults.standard.set(true, forKey: "composeIntelligenceCoachShown")
                    } label: {
                        Text("Got it")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color.purple, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
                        )
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea()
    }
}

private struct CoachRow: View {
    let icon: String
    let color: Color
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(color.opacity(0.12)).frame(width: 28, height: 28)
                Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                Text(message).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Post-Quickly Nudge (AI insights pending)

struct PostQuicklyBereanNudge: View {
    let onDismiss: () -> Void

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.75, blue: 0.2))
                .scaleEffect(pulse ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
                .onAppear { pulse = true }

            Text("AI insights are ready for your post")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 1.0, green: 0.75, blue: 0.2).opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color(red: 1.0, green: 0.75, blue: 0.2).opacity(0.18), lineWidth: 0.5)
                )
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Compose Draft Manager

/// Saves and restores compose drafts using UserDefaults.
/// Auto-save fires 3s after the user stops typing (debounced in CreatePostView).
enum ComposeDraftManager {
    private static let textKey     = "composeDraft_text"
    private static let categoryKey = "composeDraft_category"
    private static let savedAtKey  = "composeDraft_savedAt"

    static func save(text: String, category: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        UserDefaults.standard.set(text, forKey: textKey)
        UserDefaults.standard.set(category, forKey: categoryKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: savedAtKey)
    }

    static func load() -> (text: String, category: String)? {
        guard let text = UserDefaults.standard.string(forKey: textKey),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let category = UserDefaults.standard.string(forKey: categoryKey) ?? "openTable"
        return (text, category)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: textKey)
        UserDefaults.standard.removeObject(forKey: categoryKey)
        UserDefaults.standard.removeObject(forKey: savedAtKey)
    }

    /// Time since last save, or nil if no draft exists.
    static var savedAt: Date? {
        let ts = UserDefaults.standard.double(forKey: savedAtKey)
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }
}

// MARK: - Draft Recovery Banner

struct ComposeDraftRecoveryBanner: View {
    let savedAt: Date
    let onRecover: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.purple)

            VStack(alignment: .leading, spacing: 1) {
                Text("Continue where you left off?")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Draft from \(savedAt, style: .relative) ago")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onRecover()
            } label: {
                Text("Recover")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.purple, in: Capsule())
            }
            .buttonStyle(.plain)

            Button(action: onDiscard) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.purple.opacity(0.15), lineWidth: 0.5)
                )
        )
        .accessibilityLabel("Draft recovery. Tap Recover to continue your previous post.")
    }
}
