//
//  GeneratedDevotionalView.swift
//  AMENAPP
//
//  Displays the AI-generated devotional in a scrollable card stack:
//  • ScriptureCard (opening + additional verses)
//  • ReflectionCard
//  • PrayerCardView
//  • PracticeCard (Live It Out)
//  • CommunityCompanionCard (optional)
//  • GuardrailNoticeCard (optional)
//  • Action bar: Save to Notes, Share
//
//  Design: white background, translucent .regularMaterial cards,
//  staged reveal animations, Liquid Glass–style accents.
//

import SwiftUI

struct GeneratedDevotionalView: View {

    let devotional: DevotionalResponse
    @Bindable var viewModel: DevotionalGeneratorViewModel

    @State private var visibleCards: Set<String> = []
    @State private var isSaving = false
    @State private var showShareSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                // Title block
                devotionalTitle
                    .onAppear { revealCards() }

                // Opening scripture
                DevotionalScriptureCardView(
                    card: devotional.openingVerse,
                    isOpening: true
                )
                .devCardReveal(id: "verse0", visibleCards: visibleCards)

                // Additional scriptures
                ForEach(Array(devotional.additionalScriptures.enumerated()), id: \.element.id) { idx, card in
                    DevotionalScriptureCardView(card: card, isOpening: false)
                        .devCardReveal(id: "verse\(idx + 1)", visibleCards: visibleCards)
                }

                // Reflection
                DevotionalReflectionCardView(card: devotional.reflection, tone: devotional.tone)
                    .devCardReveal(id: "reflection", visibleCards: visibleCards)

                // Prayer
                DevotionalPrayerCardView(card: devotional.prayer)
                    .devCardReveal(id: "prayer", visibleCards: visibleCards)

                // Practice
                DevotionalPracticeCardView(card: devotional.practice)
                    .devCardReveal(id: "practice", visibleCards: visibleCards)

                // Community (optional)
                if let community = devotional.community {
                    DevotionalCommunityCardView(card: community)
                        .devCardReveal(id: "community", visibleCards: visibleCards)
                }

                // Guardrail notice (optional)
                if let notice = devotional.guardrailNotice {
                    GuardrailNoticeCard(notice: notice)
                        .devCardReveal(id: "guardrail", visibleCards: visibleCards)
                }

                // Action bar
                actionBar
                    .devCardReveal(id: "actions", visibleCards: visibleCards)
                    .padding(.bottom, 32)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [shareText])
        }
    }

    // MARK: - Title Block

    private var devotionalTitle: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: devotional.tone.icon)
                    .foregroundStyle(devotional.tone.color)
                Text(devotional.tone.rawValue.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(devotional.tone.color)
                    .tracking(1.2)
            }

            Text(devotional.title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            // Topic tags
            if !devotional.topicTags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(devotional.topicTags.prefix(3), id: \.self) { tag in
                        Text(tag.capitalized)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            // Save to Notes
            Button {
                Task {
                    isSaving = true
                    await viewModel.saveToNotes()
                    isSaving = false
                }
            } label: {
                HStack(spacing: 6) {
                    if isSaving {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: viewModel.generatedDevotional?.isSavedToNotes == true
                              ? "checkmark.circle.fill" : "note.text.badge.plus")
                    }
                    Text(viewModel.generatedDevotional?.isSavedToNotes == true
                         ? "Saved" : "Save to Notes")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.orange.opacity(0.12))
                .foregroundStyle(.orange)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isSaving || viewModel.generatedDevotional?.isSavedToNotes == true)

            // Share
            Button {
                showShareSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.systemScaled(18))
                    .frame(width: 50, height: 50)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // MARK: - Share Text

    private var shareText: String {
        """
        \(devotional.title)

        "\(devotional.openingVerse.text)"
        — \(devotional.openingVerse.reference)

        \(devotional.reflection.body.prefix(300))…

        Shared from the AMEN app
        """
    }

    // MARK: - Card Reveal Animation

    private func revealCards() {
        var ids: [String] = ["verse0"]
        for i in 0..<devotional.additionalScriptures.count {
            ids.append("verse\(i + 1)")
        }
        ids.append(contentsOf: ["reflection", "prayer", "practice"])
        if devotional.community != nil { ids.append("community") }
        if devotional.guardrailNotice != nil { ids.append("guardrail") }
        ids.append("actions")

        for (index, id) in ids.enumerated() {
            let cardId = id
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.12) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    _ = visibleCards.insert(cardId)
                }
            }
        }
    }
}

// MARK: - Scripture Card

private struct DevotionalScriptureCardView: View {
    let card: DevotionalScriptureCard
    let isOpening: Bool

    var body: some View {
        DevotionalGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "book.fill")
                        .foregroundStyle(.orange)
                    Text(card.reference)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    Spacer()
                    Text(card.version)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.quaternarySystemFill))
                        .clipShape(Capsule())
                }

                if isOpening {
                    Text("\u{201C}\(card.text)\u{201D}")
                        .font(.body.italic())
                        .foregroundStyle(.primary)
                        .lineSpacing(4)
                } else {
                    Text(card.text)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineSpacing(3)
                }

                if !card.whyThisVerse.isEmpty {
                    Divider()
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                        Text(card.whyThisVerse)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Reflection Card

private struct DevotionalReflectionCardView: View {
    let card: DevotionalReflectionCard
    let tone: DevotionalTone

    var body: some View {
        DevotionalGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(card.heading, systemImage: "brain.head.profile.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tone.color)

                Text(card.body)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineSpacing(5)
            }
        }
    }
}

// MARK: - Prayer Card

private struct DevotionalPrayerCardView: View {
    let card: DevotionalPrayerCard

    var body: some View {
        DevotionalGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(card.heading, systemImage: "hands.sparkles.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.purple)

                Text(card.body)
                    .font(.body.italic())
                    .foregroundStyle(.primary)
                    .lineSpacing(5)

                if card.closingAmen {
                    Text("Amen.")
                        .font(.body.weight(.semibold).italic())
                        .foregroundStyle(.purple)
                }
            }
        }
    }
}

// MARK: - Practice Card

private struct DevotionalPracticeCardView: View {
    let card: DevotionalPracticeCard

    var body: some View {
        DevotionalGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(card.heading, systemImage: "figure.walk")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(card.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Color.green.opacity(0.15))
                                    .frame(width: 24, height: 24)
                                Text("\(index + 1)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.green)
                            }
                            Text(step)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Community Card

private struct DevotionalCommunityCardView: View {
    let card: DevotionalCommunityCard

    var body: some View {
        DevotionalGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(card.heading, systemImage: "person.3.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(card.prompts.enumerated()), id: \.offset) { _, prompt in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "bubble.left.fill")
                                .font(.caption)
                                .foregroundStyle(.blue.opacity(0.6))
                                .padding(.top, 2)
                            Text(prompt)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Guardrail Notice Card

private struct GuardrailNoticeCard: View {
    let notice: DevotionalGuardrailNotice

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: notice.severity == .caution ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(notice.severity == .caution ? .orange : .blue)
                .font(.callout)
                .padding(.top, 1)

            Text(notice.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            (notice.severity == .caution ? Color.orange : Color.blue).opacity(0.08)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Card Reveal Modifier

private struct DevCardRevealModifier: ViewModifier {
    let id: String
    let visibleCards: Set<String>

    func body(content: Content) -> some View {
        content
            .opacity(visibleCards.contains(id) ? 1 : 0)
            .offset(y: visibleCards.contains(id) ? 0 : 20)
    }
}

extension View {
    fileprivate func devCardReveal(id: String, visibleCards: Set<String>) -> some View {
        modifier(DevCardRevealModifier(id: id, visibleCards: visibleCards))
    }
}

#Preview {
    let sampleResponse = DevotionalResponse(
        requestId: "preview",
        userId: "user123",
        title: "Rest in His Faithfulness",
        openingVerse: DevotionalScriptureCard(
            reference: "Philippians 4:6-7",
            text: "Do not be anxious about anything, but in every situation, by prayer and petition, with thanksgiving, present your requests to God.",
            version: "NIV",
            whyThisVerse: "This verse directly addresses anxiety with a practical spiritual discipline."
        ),
        additionalScriptures: [],
        reflection: DevotionalReflectionCard(
            body: "Anxiety often feels like a closed door — a room we enter and cannot find our way out of. Yet Paul writes from prison with an almost stunning calm. His secret is not circumstantial peace, but covenantal peace — the kind that surpasses human understanding."
        ),
        prayer: DevotionalPrayerCard(
            body: "Lord, I bring you every worry I've been carrying. You know each one by name. Teach me to trade my anxiety for trust, one moment at a time."
        ),
        practice: DevotionalPracticeCard(
            steps: [
                "Write down one worry and hand it to God in prayer.",
                "Memorise Philippians 4:7 and repeat it when anxiety rises.",
                "Share one thing you're grateful for with a friend today.",
            ]
        ),
        tone: .contemplative
    )

    NavigationStack {
        GeneratedDevotionalView(
            devotional: sampleResponse,
            viewModel: DevotionalGeneratorViewModel()
        )
        .navigationTitle("Your Devotional")
        .navigationBarTitleDisplayMode(.inline)
    }
}
