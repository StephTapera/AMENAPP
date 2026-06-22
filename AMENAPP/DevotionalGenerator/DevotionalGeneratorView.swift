//
//  DevotionalGeneratorView.swift
//  AMENAPP
//
//  Full-screen devotional generator: topic input, tone chips, preferences,
//  a Selah-pause interstitial, and the generation loading state.
//  Uses Liquid Glass–style translucent cards on a white background.
//

import SwiftUI

struct DevotionalGeneratorView: View {

    @State private var viewModel = DevotionalGeneratorViewModel()
    @State private var showHistory = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                // White background
                Color(.systemBackground).ignoresSafeArea()

                if viewModel.isGenerating {
                    generatingView
                } else if viewModel.showGenerated, let devotional = viewModel.generatedDevotional {
                    GeneratedDevotionalView(devotional: devotional, viewModel: viewModel)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                } else {
                    inputScrollView
                        .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: viewModel.phase)
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: viewModel.showGenerated)
            .navigationTitle("Devotional Generator")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                            .foregroundStyle(.secondary)
                    }
                }
                if viewModel.showGenerated {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("New") {
                            viewModel.reset()
                        }
                    }
                }
            }
            .sheet(isPresented: $showHistory) {
                DevotionalHistorySheet(viewModel: viewModel)
            }
        }
    }

    // MARK: - Input Scroll View

    private var inputScrollView: some View {
        ScrollView {
            VStack(spacing: 20) {

                // Hero header
                DevotionalHeroHeader()

                // Spiritual Rhythm Card
                SpiritualRhythmCard(snapshot: SpiritualRhythmService.shared.snapshot)

                // Topic input
                DevotionalInputCard(viewModel: viewModel)

                // Tone selector
                DevotionalToneSelector(selectedTone: $viewModel.selectedTone)

                // Community mode
                DevotionalCommunitySelector(selectedMode: $viewModel.communityMode)

                // Context toggles
                DevotionalPreferenceSection(viewModel: viewModel)

                // Recommended verses for topic
                if !viewModel.recommendedVerses.isEmpty {
                    DevotionalVersePickerSection(viewModel: viewModel)
                }

                // Specific question
                DevotionalSpecificQuestionField(text: $viewModel.specificQuestion)

                // Error
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                // Generate button
                GenerateButton(viewModel: viewModel)
                    .padding(.bottom, 32)
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Generating View

    private var generatingView: some View {
        VStack(spacing: 28) {
            Spacer()

            // Pulsing icon
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 96, height: 96)
                Image(systemName: "sun.max.fill")
                    .font(.systemScaled(44))
                    .foregroundStyle(Color.orange)
                    .symbolEffect(.pulse)
            }

            VStack(spacing: 8) {
                Text(viewModel.phase.displayLabel)
                    .font(.title3.weight(.semibold))
                Text("Preparing your devotional…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Phase progress dots
            HStack(spacing: 8) {
                ForEach(generationPhases, id: \.self) { p in
                    Circle()
                        .fill(viewModel.phase == p ? Color.orange : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .animation(.spring(response: 0.3), value: viewModel.phase)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private let generationPhases: [DevotionalGenerationPhase] = [
        .gatheringContext, .fetchingScripture, .composing, .validatingSafety
    ]
}

// MARK: - Hero Header

private struct DevotionalHeroHeader: View {
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(.orange)
                Text("Create a Devotional")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            Text("Grounded in your notes, prayers, and scripture")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }
}

// MARK: - Topic Input Card

private struct DevotionalInputCard: View {
    @Bindable var viewModel: DevotionalGeneratorViewModel
    @FocusState private var focused: Bool

    var body: some View {
        DevotionalGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("What's on your heart?", systemImage: "heart.fill")
                    .font(.subheadline.weight(.semibold))

                TextField("e.g. anxiety, purpose, grief, hope…", text: $viewModel.topic)
                    .focused($focused)
                    .submitLabel(.done)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                // Topic chips
                DevotionalTopicChips(viewModel: viewModel)
            }
        }
    }
}

// MARK: - Topic Chips

private struct DevotionalTopicChips: View {
    @Bindable var viewModel: DevotionalGeneratorViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.suggestedTopicChips, id: \.self) { chip in
                    Button {
                        viewModel.applyTopic(chip)
                    } label: {
                        Text(chip.capitalized)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                viewModel.topic.lowercased() == chip.lowercased()
                                    ? Color.orange.opacity(0.2)
                                    : Color(.tertiarySystemBackground)
                            )
                            .foregroundStyle(
                                viewModel.topic.lowercased() == chip.lowercased()
                                    ? Color.orange
                                    : Color.primary
                            )
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Tone Selector

private struct DevotionalToneSelector: View {
    @Binding var selectedTone: DevotionalTone

    var body: some View {
        DevotionalGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Tone", systemImage: "waveform")
                    .font(.subheadline.weight(.semibold))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(DevotionalTone.allCases) { tone in
                        Button {
                            selectedTone = tone
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: tone.icon)
                                    .font(.systemScaled(18))
                                    .foregroundStyle(selectedTone == tone ? tone.color : .secondary)
                                Text(tone.rawValue)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(selectedTone == tone ? tone.color : .secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                selectedTone == tone
                                    ? tone.color.opacity(0.12)
                                    : Color(.tertiarySystemBackground)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(selectedTone == tone ? tone.color.opacity(0.4) : .clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Community Selector

private struct DevotionalCommunitySelector: View {
    @Binding var selectedMode: CommunityMode

    var body: some View {
        DevotionalGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Who is this for?", systemImage: "person.2.fill")
                    .font(.subheadline.weight(.semibold))

                HStack(spacing: 8) {
                    ForEach(CommunityMode.allCases) { mode in
                        Button {
                            selectedMode = mode
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: mode.icon)
                                    .font(.systemScaled(16))
                                Text(mode.rawValue)
                                    .font(.caption2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(selectedMode == mode ? .white : .secondary)
                            .background(selectedMode == mode ? Color.blue : Color(.tertiarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Preference Section

private struct DevotionalPreferenceSection: View {
    @Bindable var viewModel: DevotionalGeneratorViewModel

    var body: some View {
        DevotionalGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Personalise with my…", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))

                Toggle(isOn: $viewModel.useChurchNotesContext) {
                    Label("Church Notes", systemImage: "note.text")
                        .font(.subheadline)
                }
                .tint(.orange)

                Divider()

                Toggle(isOn: $viewModel.usePrayerContext) {
                    Label("Recent Prayers", systemImage: "hands.sparkles")
                        .font(.subheadline)
                }
                .tint(.orange)
            }
        }
    }
}

// MARK: - Verse Picker Section

private struct DevotionalVersePickerSection: View {
    @Bindable var viewModel: DevotionalGeneratorViewModel

    var body: some View {
        DevotionalGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Suggested Scripture", systemImage: "book.fill")
                    .font(.subheadline.weight(.semibold))

                ForEach(viewModel.recommendedVerses, id: \.self) { ref in
                    Button {
                        viewModel.toggleVerse(ref)
                    } label: {
                        HStack {
                            Image(systemName: viewModel.selectedVerses.contains(ref)
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(viewModel.selectedVerses.contains(ref) ? .orange : .secondary)
                            Text(ref)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Specific Question Field

private struct DevotionalSpecificQuestionField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        DevotionalGlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Specific Question (optional)", systemImage: "questionmark.bubble.fill")
                    .font(.subheadline.weight(.semibold))

                TextField("What I really need today…", text: $text, axis: .vertical)
                    .focused($focused)
                    .lineLimit(2...4)
                    .font(.subheadline)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

// MARK: - Generate Button

private struct GenerateButton: View {
    @Bindable var viewModel: DevotionalGeneratorViewModel

    var body: some View {
        Button {
            Task { await viewModel.generate() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                Text("Generate Devotional")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(viewModel.topicIsValid ? Color.orange : Color.gray.opacity(0.3))
            .foregroundStyle(viewModel.topicIsValid ? .white : .secondary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(!viewModel.topicIsValid || viewModel.isGenerating)
        .buttonStyle(.plain)
    }
}

// MARK: - Spiritual Rhythm Card

struct SpiritualRhythmCard: View {
    let snapshot: SpiritualRhythmSnapshot

    var body: some View {
        if snapshot.totalDevotionalsCompleted > 0 {
            DevotionalGlassCard {
                // streak count hidden per constitution — vanityMetricsAlwaysHidden
                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Text("Consistent this week")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider().frame(height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your rhythm of faithfulness")
                            .font(.subheadline.weight(.semibold))
                        if let tone = snapshot.mostUsedTone {
                            Text("Most used: \(tone.rawValue)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Image(systemName: "heart.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

// MARK: - History Sheet

private struct DevotionalHistorySheet: View {
    @Bindable var viewModel: DevotionalGeneratorViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoadingHistory {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.history.isEmpty {
                    ContentUnavailableView(
                        "No Devotionals Yet",
                        systemImage: "sun.max",
                        description: Text("Your generated devotionals will appear here.")
                    )
                } else {
                    List(viewModel.history) { devotional in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(devotional.title)
                                .font(.subheadline.weight(.semibold))
                            Text(devotional.openingVerse.reference)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(devotional.generatedAt, style: .date)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await viewModel.loadHistory() }
        }
    }
}

// MARK: - Glass Card Helper

struct DevotionalGlassCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
            )
    }
}

#Preview {
    DevotionalGeneratorView()
}
