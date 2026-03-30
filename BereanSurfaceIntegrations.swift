// BereanSurfaceIntegrations.swift
// AMENAPP
//
// Drop-in view modifiers and components that wire BereanCoreService into
// every product surface without modifying existing views.
//
// Usage pattern:
//   TextField(...)
//       .bereanPostAssist(text: $postText, userId: currentUserId)
//
//   MessageBubbleView(...)
//       .bereanDMSafetyGate(onBlock: { ... }, onWarn: { ... })
//
//   ChurchNoteCard(...)
//       .bereanNoteIntelligence(noteText: noteText)
//
// Components:
//   - BereanPostAssistBar       (caption help + tone + verse for post creation)
//   - BereanDMSafetyOverlay     (pre-send DM screening with gentle UX)
//   - BereanNoteIntelligenceBar (church notes summary + action points)
//   - BereanPrayerAssistBar     (prayer request enhancement + crisis detection)
//   - BereanCommentToneHint     (gentle tone guidance before posting comments)
//   - BereanContextualEntryPoint (floating "Ask Berean" on any screen)
//   - BereanRelatedContentBar   (related verses + resources strip)

import SwiftUI
import Combine

// MARK: - BereanPostAssistBar
/// Appears above the keyboard when the user types a post.
/// Shows tone suggestion, verse chip, and safety state.

struct BereanPostAssistBar: View {
    @Binding var text: String
    let userId: String?
    let onVerseChipTapped: (String) -> Void
    let onAskBerean: (String) -> Void

    @State private var assistance: PostCreationAssistance?
    @State private var isAnalyzing = false
    @State private var debounceTask: Task<Void, Never>?
    @State private var visible = false

    private let core = BereanCoreService.shared

    var body: some View {
        Group {
            if visible, let assist = assistance {
                VStack(spacing: 0) {
                    Divider().opacity(0.4)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            // Tone chip
                            if let tone = assist.toneSuggestion, !tone.isEmpty {
                                BereanAssistChip(
                                    icon: toneIcon(tone),
                                    label: toneLabel(tone),
                                    color: toneColor(tone)
                                ) { onAskBerean("My post tone: \(tone). Help me improve this.") }
                            }

                            // Verse suggestion chips
                            ForEach(assist.suggestedVerses.prefix(2), id: \.id) { citation in
                                BereanAssistChip(
                                    icon: "book.closed.fill",
                                    label: citation.reference,
                                    color: Color(red: 0.88, green: 0.38, blue: 0.28)
                                ) { onVerseChipTapped(citation.reference) }
                            }

                            // Safety warning (soft, non-accusatory)
                            if !assist.isClean {
                                BereanAssistChip(
                                    icon: "shield.fill",
                                    label: "Review before posting",
                                    color: Color(red: 0.85, green: 0.45, blue: 0.18)
                                ) { onAskBerean("Help me review this post for tone and content.") }
                            }

                            // Ask Berean shortcut
                            BereanAssistChip(
                                icon: "sparkles",
                                label: "Ask Berean",
                                color: Color(red: 0.58, green: 0.25, blue: 0.88)
                            ) { onAskBerean("Help me improve this post: \(text.prefix(200))") }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                }
                .background(.ultraThinMaterial)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.80), value: visible)
        .onChange(of: text) { _, newText in
            scheduleAnalysis(newText)
        }
    }

    private func scheduleAnalysis(_ text: String) {
        debounceTask?.cancel()
        guard text.count > 20 else {
            withAnimation { visible = false }
            return
        }
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)  // 600ms debounce
            guard !Task.isCancelled else { return }
            await analyze(text)
        }
    }

    private func analyze(_ text: String) async {
        isAnalyzing = true
        assistance = await core.assistPostCreation(text: text, userId: userId)
        withAnimation { visible = true }
        isAnalyzing = false
    }

    private func toneIcon(_ tone: String) -> String {
        if tone.contains("joyful") { return "sun.max.fill" }
        if tone.contains("sorrowful") { return "cloud.fill" }
        if tone.contains("negative") { return "exclamationmark.circle.fill" }
        return "waveform"
    }

    private func toneLabel(_ tone: String) -> String {
        tone.replacingOccurrences(of: "tone:", with: "").capitalized
    }

    private func toneColor(_ tone: String) -> Color {
        if tone.contains("joyful")   { return Color(red: 0.90, green: 0.65, blue: 0.20) }
        if tone.contains("negative") { return Color(red: 0.85, green: 0.35, blue: 0.25) }
        return Color(red: 0.40, green: 0.65, blue: 0.85)
    }
}

// MARK: - BereanAssistChip
/// Reusable chip for any Berean assist surface.

struct BereanAssistChip: View {
    let icon: String
    let label: String
    let color: Color
    let onTap: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(color.opacity(pressed ? 0.18 : 0.10))
                    .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 0.75))
            )
            .scaleEffect(pressed ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
        ._onButtonGesture { pressing in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.70)) { pressed = pressing }
        } perform: {}
    }
}

// MARK: - BereanDMSafetyOverlay
/// Shows a gentle pre-send review prompt when DM safety flags are detected.
/// Never accusatory — presents as "we noticed something, want to review?"

struct BereanDMSafetyOverlay: View {
    let screening: DMScreeningResult
    let onSendAnyway: () -> Void
    let onRevise: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        if screening.requiresUserReview, let prompt = screening.gentlePrompt {
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.20)
                    .ignoresSafeArea()
                    .onTapGesture { onDismiss() }

                VStack(spacing: 0) {
                    // Handle
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.40))
                        .frame(width: 36, height: 4)
                        .padding(.top, 10)
                        .padding(.bottom, 16)

                    // Icon
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.88, green: 0.58, blue: 0.18).opacity(0.15))
                            .frame(width: 56, height: 56)
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Color(red: 0.88, green: 0.58, blue: 0.18))
                    }
                    .padding(.bottom, 14)

                    Text("Pause a moment")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(white: 0.10))

                    Text(prompt)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color(white: 0.40))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 6)

                    Spacer().frame(height: 24)

                    // Actions
                    VStack(spacing: 8) {
                        Button(action: onRevise) {
                            Text("Review & Edit")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color(red: 0.88, green: 0.38, blue: 0.28))
                                )
                        }
                        .buttonStyle(.plain)

                        if screening.canSend {
                            Button(action: onSendAnyway) {
                                Text("Send Anyway")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color(white: 0.45))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 34)
                }
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.18), radius: 20, y: -4)
                )
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - BereanNoteIntelligenceCard
/// Expandable card that appears at the bottom of a church note.
/// Shows AI summary, action points, extracted verses, and prayer prompts.

struct BereanNoteIntelligenceCard: View {
    let noteText: String
    let userId: String?

    @State private var intelligence: ChurchNoteIntelligence?
    @State private var isLoading = false
    @State private var isExpanded = false
    @State private var hasAnalyzed = false

    private let core = BereanCoreService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Trigger button
            Button {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                    isExpanded.toggle()
                }
                if !hasAnalyzed { analyzeNote() }
            } label: {
                HStack(spacing: 7) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.75)
                            .tint(Color(red: 0.88, green: 0.38, blue: 0.28))
                    } else {
                        Image(systemName: isExpanded ? "chevron.up" : "sparkles")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(red: 0.88, green: 0.38, blue: 0.28))
                    }
                    Text(isLoading ? "Analyzing note..." : "Berean Note Intelligence")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(white: 0.30))
                    Spacer()
                    if let intel = intelligence {
                        Text("\(intel.extractedVerses.count) verses · \(intel.actionPoints.count) actions")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Color(white: 0.55))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 0.88, green: 0.38, blue: 0.28).opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color(red: 0.88, green: 0.38, blue: 0.28).opacity(0.18), lineWidth: 0.75)
                        )
                )
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded, let intel = intelligence {
                VStack(alignment: .leading, spacing: 14) {
                    // Summary
                    if !intel.summary.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Label("Summary", systemImage: "text.alignleft")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(white: 0.45))
                            Text(intel.summary)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(Color(white: 0.18))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    // Action points
                    if !intel.actionPoints.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Label("Action Points", systemImage: "checkmark.circle")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(white: 0.45))
                            ForEach(intel.actionPoints, id: \.self) { point in
                                HStack(alignment: .top, spacing: 7) {
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(Color(red: 0.88, green: 0.38, blue: 0.28))
                                        .padding(.top, 3)
                                    Text(point)
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundStyle(Color(white: 0.20))
                                }
                            }
                        }
                    }

                    // Extracted verses
                    if !intel.extractedVerses.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Scripture", systemImage: "book.closed.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(white: 0.45))
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 7) {
                                    ForEach(intel.extractedVerses, id: \.id) { citation in
                                        BereanAssistChip(
                                            icon: "quote.opening",
                                            label: citation.reference,
                                            color: Color(red: 0.88, green: 0.38, blue: 0.28)
                                        ) {}
                                    }
                                }
                            }
                        }
                    }

                    // Prayer prompts
                    if !intel.prayerPrompts.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Label("Prayer", systemImage: "hands.sparkles.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(white: 0.45))
                            ForEach(intel.prayerPrompts, id: \.self) { prayer in
                                Text(prayer)
                                    .font(.system(size: 12, weight: .regular, design: .serif))
                                    .foregroundStyle(Color(white: 0.28))
                                    .italic()
                            }
                        }
                    }
                }
                .padding(14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.72))
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }

    private func analyzeNote() {
        guard !isLoading else { return }
        isLoading = true
        hasAnalyzed = true
        Task {
            intelligence = await core.processChurchNote(noteText: noteText, userId: userId)
            isLoading = false
        }
    }
}

// MARK: - BereanPrayerAssistBar
/// Appears when user is typing a prayer request.
/// Offers support, verse suggestions, and crisis routing if needed.

struct BereanPrayerAssistBar: View {
    @Binding var text: String
    let userId: String?
    let onAskBerean: (String) -> Void

    @State private var intelligence: PrayerRequestIntelligence?
    @State private var showCrisisCard = false
    @State private var debounceTask: Task<Void, Never>?

    private let core = BereanCoreService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Crisis card (highest priority)
            if showCrisisCard, let intel = intelligence, intel.crisisDetected {
                BereanCrisisSupportCard(resources: intel.crisisResources)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            }

            // Scripture suggestions
            if let intel = intelligence, !intel.scriptureSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(intel.scriptureSuggestions.prefix(3), id: \.id) { verse in
                            BereanAssistChip(
                                icon: "book.closed.fill",
                                label: verse.reference,
                                color: Color(red: 0.88, green: 0.38, blue: 0.28)
                            ) { onAskBerean("Tell me more about \(verse.reference)") }
                        }

                        // "Help me write this" shortcut
                        BereanAssistChip(
                            icon: "pencil.sparkles",
                            label: "Refine prayer",
                            color: Color(red: 0.58, green: 0.25, blue: 0.88)
                        ) { onAskBerean("Help me write a prayer about: \(text.prefix(150))") }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .background(.ultraThinMaterial)
            }
        }
        .onChange(of: text) { _, newText in
            scheduleAnalysis(newText)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.80), value: showCrisisCard)
    }

    private func scheduleAnalysis(_ text: String) {
        debounceTask?.cancel()
        guard text.count > 15 else { return }
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)  // 800ms debounce
            guard !Task.isCancelled else { return }
            let result = await core.processPrayerRequest(text: text, userId: userId)
            await MainActor.run {
                intelligence = result
                withAnimation {
                    showCrisisCard = result.crisisDetected
                }
            }
        }
    }
}

// MARK: - BereanCrisisSupportCard
/// Warm, non-alarming crisis resource card.

struct BereanCrisisSupportCard: View {
    let resources: CrisisResources?

    var body: some View {
        if let res = resources {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.20, green: 0.60, blue: 0.90).opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(red: 0.20, green: 0.60, blue: 0.90))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(res.description)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(white: 0.14))
                    Text("\(res.hotline)  ·  \(res.textLine)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color(white: 0.45))
                }

                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.20, green: 0.60, blue: 0.90).opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color(red: 0.20, green: 0.60, blue: 0.90).opacity(0.20), lineWidth: 0.75)
                    )
            )
        }
    }
}

// MARK: - BereanCommentToneHint
/// Lightweight tone hint shown when typing a comment.
/// Low-friction: just a small chip, not a dialog.

struct BereanCommentToneHint: View {
    let text: String
    let onTap: () -> Void

    @State private var toneTag: String?
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let tag = toneTag, tag.contains("negative") || tag.contains("harsh") {
                Button(action: onTap) {
                    HStack(spacing: 4) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 9, weight: .medium))
                        Text("Soften tone?")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color(red: 0.88, green: 0.55, blue: 0.20))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.88, green: 0.55, blue: 0.20).opacity(0.12))
                            .overlay(Capsule().stroke(Color(red: 0.88, green: 0.55, blue: 0.20).opacity(0.25), lineWidth: 0.5))
                    )
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.30, dampingFraction: 0.75), value: toneTag)
        .onChange(of: text) { _, newText in
            scheduleToneCheck(newText)
        }
    }

    private func scheduleToneCheck(_ text: String) {
        debounceTask?.cancel()
        guard text.count > 10 else { toneTag = nil; return }
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            let tag = await SemanticTopicService.shared.extractTagsFast(from: text).first(where: { $0.hasPrefix("tone:") })
            await MainActor.run {
                withAnimation { toneTag = tag }
            }
        }
    }
}

// MARK: - BereanContextualEntryPoint
/// Floating "Ask Berean" entry point that can be added to any screen.
/// Shows the Berean icon + contextual prompt suggestions.

struct BereanContextualEntryPoint: View {
    let surface: AMENSurface
    let context: String
    let userId: String?
    let onPromptSelected: (String) -> Void

    @State private var isExpanded = false
    @State private var prompts: [String] = []

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            // Expanded prompt list
            if isExpanded && !prompts.isEmpty {
                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(prompts.prefix(3), id: \.self) { prompt in
                        Button {
                            onPromptSelected(prompt)
                            withAnimation { isExpanded = false }
                        } label: {
                            Text(prompt)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color(white: 0.18))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .fill(.regularMaterial)
                                        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                                )
                        }
                        .buttonStyle(.plain)
                        .transition(.scale(scale: 0.85, anchor: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.bottom, 4)
            }

            // Trigger button
            Button {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "xmark" : "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                    if !isExpanded {
                        Text("Berean")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, isExpanded ? 14 : 18)
                .padding(.vertical, 11)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.88, green: 0.38, blue: 0.28), Color(red: 0.72, green: 0.28, blue: 0.20)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color(red: 0.88, green: 0.38, blue: 0.28).opacity(0.35), radius: 10, y: 4)
                )
                .scaleEffect(isExpanded ? 0.92 : 1.0)
            }
            .buttonStyle(.plain)
        }
        .task {
            prompts = await RecommendationIntelligenceService.shared.suggestedPrompts(
                surface: surface,
                context: context,
                userId: userId
            )
        }
    }
}

// MARK: - View Modifier: bereanPostAssist

struct BereanPostAssistModifier: ViewModifier {
    @Binding var text: String
    let userId: String?
    let onVerseChipTapped: (String) -> Void
    let onAskBerean: (String) -> Void

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
            BereanPostAssistBar(
                text: $text,
                userId: userId,
                onVerseChipTapped: onVerseChipTapped,
                onAskBerean: onAskBerean
            )
        }
    }
}

extension View {
    func bereanPostAssist(
        text: Binding<String>,
        userId: String?,
        onVerseChipTapped: @escaping (String) -> Void = { _ in },
        onAskBerean: @escaping (String) -> Void = { _ in }
    ) -> some View {
        modifier(BereanPostAssistModifier(
            text: text,
            userId: userId,
            onVerseChipTapped: onVerseChipTapped,
            onAskBerean: onAskBerean
        ))
    }
}

// MARK: - View Modifier: bereanNoteIntelligence

struct BereanNoteIntelligenceModifier: ViewModifier {
    let noteText: String
    let userId: String?

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content
            if noteText.count > 50 {
                BereanNoteIntelligenceCard(noteText: noteText, userId: userId)
            }
        }
    }
}

extension View {
    func bereanNoteIntelligence(noteText: String, userId: String?) -> some View {
        modifier(BereanNoteIntelligenceModifier(noteText: noteText, userId: userId))
    }
}
