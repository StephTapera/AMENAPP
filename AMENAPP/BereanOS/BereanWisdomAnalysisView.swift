import SwiftUI

// MARK: - Berean Wisdom Analysis View

struct BereanWisdomAnalysisView: View {
    let projectId: String?

    @StateObject private var service = BereanWisdomService.shared

    @State private var question = ""
    @State private var selectedMode: BereanWisdomMode = .secular
    @State private var contextNotes = ""
    @State private var showContextEditor = false
    @State private var errorMessage: String?
    @State private var showActionPlanPlaceholder = false

    private var isAnalyzeDisabled: Bool {
        question.count < 10 || service.isAnalyzing
    }

    var body: some View {
        Group {
            if AMENFeatureFlags.shared.bereanOSWisdomEngineEnabled {
                mainContent
            } else {
                featureDisabledView
            }
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                inputSection
                if let analysis = service.currentAnalysis {
                    resultsSection(analysis)
                }
            }
            .padding()
        }
        .navigationTitle("Wisdom Engine")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showActionPlanPlaceholder) {
            actionPlanPlaceholder
        }
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Question TextEditor with placeholder overlay
            VStack(alignment: .leading, spacing: 6) {
                Text("What decision are you facing?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ZStack(alignment: .topLeading) {
                    if question.isEmpty {
                        Text("Describe the decision, situation, or question you need wisdom for...")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $question)
                        .font(.body)
                        .frame(minHeight: 80)
                        .scrollContentBackground(.hidden)
                }
                .padding(10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Decision question")
            }

            // Mode picker: horizontal segmented pills
            modePicker

            // Optional context
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showContextEditor.toggle()
                    }
                } label: {
                    Label(
                        showContextEditor ? "Hide context" : "Add context (optional)",
                        systemImage: showContextEditor ? "chevron.up" : "plus.circle"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.accentColor)
                }
                .accessibilityLabel(showContextEditor ? "Hide context input" : "Add optional context")

                if showContextEditor {
                    TextEditor(text: $contextNotes)
                        .font(.callout)
                        .frame(minHeight: 60)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .accessibilityLabel("Additional context")
                }
            }

            // Error banner
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 4)
                    .accessibilityLabel("Error: \(error)")
            }

            // Analyze button
            Button {
                Task { await runAnalysis() }
            } label: {
                HStack(spacing: 8) {
                    if service.isAnalyzing {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.85)
                    }
                    Text(service.isAnalyzing ? "Analyzing..." : "Analyze")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isAnalyzeDisabled ? Color.accentColor.opacity(0.4) : Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isAnalyzeDisabled)
            .accessibilityLabel("Analyze decision")
            .accessibilityHint("Runs an AI wisdom analysis of your decision")
        }
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(BereanWisdomMode.allCases) { mode in
                    Button {
                        selectedMode = mode
                    } label: {
                        Text(mode.displayName)
                            .font(.subheadline)
                            .fontWeight(selectedMode == mode ? .semibold : .regular)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                selectedMode == mode
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.15),
                                in: Capsule()
                            )
                            .foregroundStyle(selectedMode == mode ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mode: \(mode.displayName)")
                    .accessibilityAddTraits(selectedMode == mode ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Results Section

    @ViewBuilder
    private func resultsSection(_ analysis: BereanWisdomAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Divider()

            // Radar score card at top
            HStack {
                Spacer()
                BereanWisdomScoreCard(analysis: analysis)
                Spacer()
            }

            LazyVStack(spacing: 12) {

                // Truth — 0-10 gauge bar
                dimensionRow(title: "Truth", icon: "checkmark.seal.fill", score: analysis.truthScore) {
                    gaugeBar(value: analysis.truthScore, color: .blue)
                    bodyText("Premise accuracy: \(gaugeLabel(analysis.truthScore))")
                }

                // Wisdom — 0-10 gauge bar
                dimensionRow(title: "Wisdom", icon: "lightbulb.fill", score: analysis.wisdomScore) {
                    gaugeBar(value: analysis.wisdomScore, color: .yellow)
                    bodyText("Overall wisdom: \(gaugeLabel(analysis.wisdomScore))")
                }

                if !analysis.impactSummary.isEmpty {
                    dimensionRow(title: "Impact", icon: "person.3.fill", score: nil) {
                        bodyText(analysis.impactSummary)
                    }
                }

                if !analysis.riskSummary.isEmpty {
                    dimensionRow(title: "Risk", icon: "exclamationmark.triangle.fill", score: nil) {
                        bodyText(analysis.riskSummary)
                    }
                }

                if !analysis.stewardshipNotes.isEmpty {
                    dimensionRow(title: "Stewardship", icon: "leaf.fill", score: nil) {
                        bodyText(analysis.stewardshipNotes)
                    }
                }

                if !analysis.characterImplications.isEmpty {
                    dimensionRow(title: "Character", icon: "heart.fill", score: nil) {
                        bodyText(analysis.characterImplications)
                    }
                }

                if !analysis.longTermConsequences.isEmpty {
                    dimensionRow(title: "Long-Term", icon: "calendar", score: nil) {
                        bodyText(analysis.longTermConsequences)
                    }
                }

                // Faith Perspective — christian / churchLeadership modes only
                if let faithText = analysis.faithPerspective,
                   !faithText.isEmpty,
                   (analysis.mode == .christian || analysis.mode == .churchLeadership) {
                    dimensionRow(title: "Faith Perspective", icon: "book.closed.fill", score: nil) {
                        bodyText(faithText)
                    }
                }

                // Multi-perspective cards
                ForEach(analysis.perspectives) { perspective in
                    perspectiveCard(perspective)
                }
            }

            // Generate Action Plan placeholder
            Button {
                showActionPlanPlaceholder = true
            } label: {
                Label("Generate Action Plan", systemImage: "list.bullet.clipboard.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.quaternary.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .accessibilityLabel("Generate an action plan based on this analysis")
        }
    }

    // MARK: - Dimension Row

    private func dimensionRow<Content: View>(
        title: String,
        icon: String,
        score: Double?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(.accentColor)
                    .frame(width: 20)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let score = score {
                    Text(gaugeLabel(score))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Gauge Bar (0-10 scale)

    private func gaugeBar(value: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.15))
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(value.wisdomClamped))
            }
        }
        .frame(height: 8)
    }

    // MARK: - Body Text

    private func bodyText(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Perspective Card

    private func perspectiveCard(_ perspective: BereanPerspective) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                if !perspective.summary.isEmpty {
                    bodyText(perspective.summary)
                }
                bulletList("Agreements", items: perspective.agreements, icon: "checkmark.circle.fill", color: .green)
                bulletList("Disagreements", items: perspective.disagreements, icon: "xmark.circle.fill", color: .red)
                bulletList("Tradeoffs", items: perspective.tradeoffs, icon: "arrow.left.arrow.right.circle.fill", color: .orange)
                bulletList("Unknowns", items: perspective.unknowns, icon: "questionmark.circle.fill", color: .secondary)
            }
            .padding(.top, 6)
        } label: {
            HStack {
                Image(systemName: "person.fill")
                    .foregroundStyle(.accentColor)
                Text(perspective.perspectiveType.isEmpty ? "Perspective" : perspective.perspectiveType)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func bulletList(
        _ heading: String,
        items: [String],
        icon: String,
        color: Color
    ) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(heading)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(items, id: \.self) { item in
                    Label(item, systemImage: icon)
                        .font(.callout)
                        .foregroundStyle(color.opacity(0.85))
                }
            }
        }
    }

    // MARK: - Feature Disabled

    private var featureDisabledView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Wisdom Engine")
                .font(.title2.bold())
            Text("This feature is not yet available.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Action Plan Placeholder

    private var actionPlanPlaceholder: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "list.bullet.clipboard")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Action Plan")
                    .font(.title2.bold())
                Text("Action plan generation coming soon.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                // TODO: Navigate to BereanActionPlanView when built
            }
            .padding()
            .navigationTitle("Action Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showActionPlanPlaceholder = false }
                }
            }
        }
    }

    // MARK: - Helpers

    private func gaugeLabel(_ value: Double) -> String {
        "\(Int((value.wisdomClamped * 10).rounded()))/10"
    }

    private func runAnalysis() async {
        errorMessage = nil
        service.clearAnalysis()
        do {
            _ = try await service.analyzeDecision(
                question,
                context: contextNotes.isEmpty ? nil : contextNotes,
                projectId: projectId,
                mode: selectedMode
            )
        } catch let error as BereanOSError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Double helper (local)

private extension Double {
    var wisdomClamped: Double { Swift.max(0, Swift.min(1, self)) }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        BereanWisdomAnalysisView(projectId: nil)
    }
}
#endif
