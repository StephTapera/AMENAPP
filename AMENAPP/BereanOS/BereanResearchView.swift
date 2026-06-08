// BereanResearchView.swift
// AMENAPP - BereanOS
// Full research entry + results surface for the Berean Research Engine.

import SwiftUI
import FirebaseAuth

// MARK: - BereanResearchView

struct BereanResearchView: View {
    let projectId: String?

    // MARK: Environment / observed objects
    @StateObject private var service = BereanResearchService.shared

    // MARK: Local state
    @State private var query: String = ""
    @State private var selectedMode: BereanResearchMode = .quick
    @State private var saveError: String?
    @State private var saveSuccess: Bool = false
    @State private var isSaving: Bool = false
    @State private var showingError: Bool = false
    @State private var errorMessage: String = ""

    // MARK: Body

    var body: some View {
        Group {
            if AMENFeatureFlags.shared.bereanOSResearchEngineEnabled {
                mainContent
            } else {
                featureDisabledPlaceholder
            }
        }
        .navigationTitle("Research Engine")
        .navigationBarTitleDisplayMode(.large)
        .alert("Research Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: Main content

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                querySection
                modeSelector
                researchButton

                if service.isResearching {
                    loadingSection
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if let report = service.activeReport, !service.isResearching {
                    resultsSection(report: report)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(16)
            .animation(.easeInOut(duration: 0.3), value: service.isResearching)
            .animation(.easeInOut(duration: 0.3), value: service.activeReport?.id)
        }
    }

    // MARK: Query input

    private var querySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What do you want to research?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: $query)
                .frame(minHeight: 80)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(UIColor.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if query.isEmpty {
                        Text("Research anything...")
                            .foregroundStyle(Color.secondary.opacity(0.5))
                            .font(.body)
                            .padding(14)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel("Research query input")
                .accessibilityHint("Describe what you want to research")
        }
    }

    // MARK: Mode selector

    private var modeSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Research Mode")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(BereanResearchMode.allCases) { mode in
                        modeChip(mode)
                    }
                }
                .padding(.horizontal, 1)
                .padding(.vertical, 2)
            }
        }
    }

    private func modeChip(_ mode: BereanResearchMode) -> some View {
        let isSelected = selectedMode == mode
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                selectedMode = mode
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: mode.systemIcon)
                    .font(.systemScaled(13, weight: .semibold))
                Text(mode.displayName)
                    .font(.systemScaled(14, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color(UIColor.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.displayName) research mode")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Research button

    private var researchButton: some View {
        Button {
            Task { await runResearch() }
        } label: {
            HStack(spacing: 8) {
                if service.isResearching {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.85)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.systemScaled(16, weight: .semibold))
                }
                Text(service.isResearching ? "Researching..." : "Research")
                    .font(.systemScaled(16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isResearchButtonDisabled ? Color.secondary.opacity(0.4) : Color.accentColor)
            )
        }
        .disabled(isResearchButtonDisabled)
        .buttonStyle(.plain)
        .accessibilityLabel("Start research")
        .accessibilityHint(isResearchButtonDisabled ? "Enter a query first" : "Runs research on your query")
    }

    private var isResearchButtonDisabled: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || service.isResearching
    }

    // MARK: Loading state

    private var loadingSection: some View {
        VStack(spacing: 14) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.accentColor)
            Text(service.researchStage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .animation(.easeInOut(duration: 0.3), value: service.researchStage)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }

    // MARK: Results

    private func resultsSection(report: BereanResearchReport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Compact summary card
            BereanResearchReportCard(report: report)

            // Confidence ring
            confidenceRing(report.confidenceScore)

            // Executive Summary (always expanded)
            disclosureSection(title: "Executive Summary", icon: "doc.text.fill", initiallyExpanded: true) {
                Text(report.executiveSummary)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            // Key Findings (collapsed by default)
            if !report.keyFindings.isEmpty {
                disclosureSection(title: "Key Findings", icon: "list.bullet.clipboard.fill", initiallyExpanded: false) {
                    ForEach(Array(report.keyFindings.enumerated()), id: \.element.id) { index, finding in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1).")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, alignment: .leading)
                            Text(finding.content)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            BereanConfidenceBadge(level: finding.confidence, compact: true)
                        }
                    }
                }
            }

            if !report.supportingEvidence.isEmpty {
                disclosureSection(title: "Supporting Evidence", icon: "checkmark.seal.fill", initiallyExpanded: false) {
                    bulletList(report.supportingEvidence)
                }
            }

            if !report.counterarguments.isEmpty {
                disclosureSection(title: "Counterarguments", icon: "exclamationmark.bubble.fill", initiallyExpanded: false) {
                    bulletList(report.counterarguments)
                }
            }

            if !report.openQuestions.isEmpty {
                disclosureSection(title: "Open Questions", icon: "questionmark.bubble.fill", initiallyExpanded: false) {
                    bulletList(report.openQuestions)
                }
            }

            if !report.actionableRecommendations.isEmpty {
                disclosureSection(title: "Recommendations", icon: "bolt.fill", initiallyExpanded: false) {
                    bulletList(report.actionableRecommendations)
                }
            }

            // Save to Project button (only when projectId is set)
            if let pid = projectId {
                saveToProjectButton(projectId: pid)
            }
        }
    }

    // MARK: Confidence ring

    private func confidenceRing(_ score: Double) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 6)
                    .frame(width: 60, height: 60)
                Circle()
                    .trim(from: 0, to: CGFloat(score))
                    .stroke(confidenceRingColor(score), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 60, height: 60)
                    .animation(.easeOut(duration: 0.8), value: score)
                Text("\(Int(score * 100))%")
                    .font(.systemScaled(13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Overall Confidence")
                    .font(.subheadline.weight(.semibold))
                Text(confidenceLabel(score))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .accessibilityLabel("Overall confidence: \(Int(score * 100)) percent. \(confidenceLabel(score))")
    }

    private func confidenceRingColor(_ score: Double) -> Color {
        switch score {
        case 0.75...: return Color.green
        case 0.5..<0.75: return Color.orange
        default: return Color.red
        }
    }

    private func confidenceLabel(_ score: Double) -> String {
        switch score {
        case 0.85...: return "High confidence - well-supported findings"
        case 0.65..<0.85: return "Moderate confidence - verify key points"
        case 0.45..<0.65: return "Mixed confidence - treat with caution"
        default: return "Low confidence - independent verification needed"
        }
    }

    // MARK: Disclosure group helper

    private func disclosureSection<Content: View>(
        title: String,
        icon: String,
        initiallyExpanded: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        BereanDisclosureGroupCard(
            title: title,
            icon: icon,
            initiallyExpanded: initiallyExpanded,
            content: content
        )
    }

    // MARK: Bullet list

    private func bulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 6) {
                    Text("*")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(item)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Save to project button

    private func saveToProjectButton(projectId: String) -> some View {
        Group {
            if saveSuccess {
                Label("Saved to Project", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.green)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 6) {
                    Button {
                        Task { await saveReport(to: projectId) }
                    } label: {
                        HStack(spacing: 6) {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "tray.and.arrow.down.fill")
                                    .font(.systemScaled(15, weight: .semibold))
                            }
                            Text(isSaving ? "Saving..." : "Save to Project")
                                .font(.systemScaled(15, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isSaving ? Color.secondary.opacity(0.4) : Color.accentColor)
                        )
                    }
                    .disabled(isSaving)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Save report to project")

                    if let err = saveError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(Color.red)
                    }
                }
            }
        }
    }

    // MARK: Feature disabled placeholder

    private var featureDisabledPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass.circle")
                .font(.systemScaled(60))
                .foregroundStyle(Color.secondary.opacity(0.4))
            Text("Research Engine")
                .font(.title2.weight(.semibold))
            Text("This feature is not yet available.\nCheck back soon.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    private func runResearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        saveSuccess = false
        saveError = nil
        do {
            _ = try await service.startResearch(query: trimmed, mode: selectedMode, projectId: projectId)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func saveReport(to projectId: String) async {
        isSaving = true
        saveError = nil
        do {
            try await service.saveActiveReport(projectId: projectId)
            saveSuccess = true
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - BereanDisclosureGroupCard

struct BereanDisclosureGroupCard<Content: View>: View {
    let title: String
    let icon: String
    let initiallyExpanded: Bool
    @ViewBuilder let content: () -> Content

    @State private var isExpanded: Bool

    init(
        title: String,
        icon: String,
        initiallyExpanded: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.initiallyExpanded = initiallyExpanded
        self._isExpanded = State(initialValue: initiallyExpanded)
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(.spring(response: 0.3), value: isExpanded)
                }
                .padding(14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityHint(isExpanded ? "Tap to collapse" : "Tap to expand")

            if isExpanded {
                Divider()
                    .padding(.horizontal, 14)
                content()
                    .padding(14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        BereanResearchView(projectId: nil)
    }
}
