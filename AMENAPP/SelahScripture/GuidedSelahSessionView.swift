//
//  GuidedSelahSessionView.swift
//  AMENAPP
//
//  The Selah Guided Session flow: Read → Listen → Understand → Reflect → Pray → Apply → Complete.
//  Resumable mid-flow, adaptive intro, prosperity-gospel guard on Apply.
//

import SwiftUI

// MARK: - Root View

struct GuidedSelahSessionView: View {
    @StateObject private var viewModel: GuidedSelahSessionViewModel
    @Environment(\.dismiss) private var dismiss

    init(verseId: String, verseText: String, translation: SelahTranslation, verseReference: String) {
        _viewModel = StateObject(wrappedValue: GuidedSelahSessionViewModel(
            verseId: verseId, verseText: verseText,
            translation: translation, verseReference: verseReference
        ))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                if viewModel.isLoading {
                    loadingView
                } else if viewModel.isComplete {
                    SessionCompleteView(
                        verseReference: viewModel.verseReference,
                        onDismiss: { dismiss() }
                    )
                } else {
                    sessionContent
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("guidedSession.closeButton")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.isSaving {
                        ProgressView().scaleEffect(0.75)
                    }
                }
            }
        }
        .task { await viewModel.loadOrCreateSession() }
        .alert("Session Error", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.error = nil }
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    // MARK: - Content

    private var sessionContent: some View {
        VStack(spacing: 0) {
            stepProgressBar
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)

            TabView(selection: .constant(viewModel.currentStep)) {
                ForEach(GuidedSelahSessionViewModel.stepOrder.filter { $0 != .complete }, id: \.self) { step in
                    stepContent(for: step)
                        .tag(step)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .disabled(true) // navigation is only via buttons

            navigationControls
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
        }
    }

    // MARK: - Step Progress Bar

    private var stepProgressBar: some View {
        let steps = GuidedSelahSessionViewModel.stepOrder.filter { $0 != .complete }
        return HStack(spacing: 6) {
            ForEach(steps) { step in
                Capsule()
                    .fill(progressColor(for: step))
                    .frame(height: 4)
                    .animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)
                    .accessibilityLabel("\(step.displayTitle): \(stepAccessibilityStatus(step))")
            }
        }
    }

    private func progressColor(for step: GuidedSelahStep) -> Color {
        if viewModel.completedSteps.contains(step) { return .accentColor }
        if step == viewModel.currentStep { return .accentColor.opacity(0.55) }
        return Color.secondary.opacity(0.2)
    }

    private func stepAccessibilityStatus(_ step: GuidedSelahStep) -> String {
        if viewModel.completedSteps.contains(step) { return "completed" }
        if step == viewModel.currentStep { return "current" }
        return "upcoming"
    }

    // MARK: - Per-Step Content

    @ViewBuilder
    private func stepContent(for step: GuidedSelahStep) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                stepHeader(step)
                stepBody(step)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private func stepHeader(_ step: GuidedSelahStep) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(step.displayTitle.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.secondary)
            Text(step.displayQuestion)
                .font(.system(size: 22, weight: .bold))
            if step == .read {
                Text(viewModel.adaptiveIntroLine)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func stepBody(_ step: GuidedSelahStep) -> some View {
        switch step {
        case .read:
            ReadStepView(verseText: viewModel.verseText, verseReference: viewModel.verseReference)
        case .listen:
            ListenStepView(verseReference: viewModel.verseReference)
        case .understand:
            UnderstandStepView(viewModel: viewModel)
        case .reflect:
            ReflectStepView(viewModel: viewModel)
        case .pray:
            PrayStepView(prayerText: $viewModel.prayerText, prayerSeed: viewModel.studySheetViewModel.studySheet?.layers.application.prayerSeed)
        case .apply:
            ApplyStepView(applyText: $viewModel.applyText, applicationPrompts: viewModel.studySheetViewModel.studySheet?.layers.application.prompts ?? [])
        case .complete:
            EmptyView()
        }
    }

    // MARK: - Navigation Controls

    private var navigationControls: some View {
        HStack(spacing: 12) {
            if viewModel.canGoBack {
                Button {
                    Task { await viewModel.goBack() }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("guidedSession.backButton")
            }

            Spacer()

            if viewModel.canSkip {
                Button {
                    Task { await viewModel.skip() }
                } label: {
                    Text("Skip")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("guidedSession.skipButton")
            }

            nextButton
        }
    }

    @ViewBuilder
    private var nextButton: some View {
        if viewModel.currentStep == .apply {
            Button {
                Task { await viewModel.finishSession() }
            } label: {
                Text("Finish")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor, in: Capsule())
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("guidedSession.finishButton")
        } else {
            Button {
                Task { await viewModel.advance() }
            } label: {
                HStack(spacing: 6) {
                    Text(viewModel.currentStep == .reflect && viewModel.reflectionViewModel.savedSuccessfully ? "Continue" : "Next")
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.accentColor, in: Capsule())
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("guidedSession.nextButton")
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading session…")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Read Step

private struct ReadStepView: View {
    let verseText: String
    let verseReference: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Scripture is MATTE — high contrast serif, zero glass behind it
            VStack(alignment: .leading, spacing: 10) {
                Text(verseReference)
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Text(verseText)
                    .font(.system(size: 20, design: .serif))
                    .foregroundStyle(.primary)
                    .lineSpacing(6)
            }
            .padding(20)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

            Text("Read slowly. What word or phrase catches your attention?")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Listen Step

private struct ListenStepView: View {
    let verseReference: String
    @State private var timerSeconds: Int = 0
    @State private var isRunning: Bool = false
    private let timerDuration = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Be still. Let the words of \(verseReference) settle in your spirit.")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 6)
                        .frame(width: 100, height: 100)
                    Circle()
                        .trim(from: 0, to: CGFloat(timerSeconds) / CGFloat(timerDuration))
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: timerSeconds)
                    Text(timeString)
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                }

                HStack(spacing: 16) {
                    Button {
                        isRunning.toggle()
                    } label: {
                        Label(isRunning ? "Pause" : "Start", systemImage: isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.accentColor, in: Capsule())
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("guidedSession.listen.timerButton")

                    Button {
                        timerSeconds = 0
                        isRunning = false
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("guidedSession.listen.resetButton")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard isRunning && timerSeconds < timerDuration else {
                if timerSeconds >= timerDuration { isRunning = false }
                return
            }
            timerSeconds += 1
        }
    }

    private var timeString: String {
        let remaining = timerDuration - timerSeconds
        let m = remaining / 60
        let s = remaining % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Understand Step

private struct UnderstandStepView: View {
    @ObservedObject var viewModel: GuidedSelahSessionViewModel

    var body: some View {
        BereanStudySheetView(
            verseId: viewModel.verseId,
            verseText: viewModel.verseText,
            translation: viewModel.translation,
            viewModel: viewModel.studySheetViewModel,
            onCrossRefTapped: { _ in /* cross-ref navigation handled by parent reader */ }
        )
        .task { await viewModel.onUnderstandStepAppear() }
    }
}

// MARK: - Reflect Step

private struct ReflectStepView: View {
    @ObservedObject var viewModel: GuidedSelahSessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.reflectionViewModel.savedSuccessfully {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Reflection saved privately.")
                        .font(.system(size: 14, weight: .medium))
                }
                .padding(14)
                .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            } else {
                SelahReflectionComposerView(
                    viewModel: viewModel.reflectionViewModel,
                    verseReference: viewModel.verseReference
                )
                .onChange(of: viewModel.reflectionViewModel.savedSuccessfully) { _, saved in
                    if saved, let id = viewModel.reflectionViewModel.savedReflectionId {
                        Task { await viewModel.onReflectionSaved(reflectionId: id) }
                    }
                }
            }
        }
    }
}

// MARK: - Pray Step

private struct PrayStepView: View {
    @Binding var prayerText: String
    let prayerSeed: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let seed = prayerSeed {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PRAYER SEED")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(.secondary)
                    Text(seed)
                        .font(.system(size: 15, design: .serif))
                        .foregroundStyle(.secondary)
                        .italic()
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }

            Text("Write your own prayer, or simply be present.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                if prayerText.isEmpty {
                    Text("Lord, as I sit with this verse…")
                        .font(.system(size: 15, design: .serif))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 10)
                        .padding(.leading, 6)
                }
                TextEditor(text: $prayerText)
                    .font(.system(size: 15, design: .serif))
                    .frame(minHeight: 160)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("guidedSession.prayerEditor")
        }
    }
}

// MARK: - Apply Step

private struct ApplyStepView: View {
    @Binding var applyText: String
    let applicationPrompts: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Prosperity-gospel guard: shown whenever application prompts are presented
            prosperityGuardNote

            if !applicationPrompts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("REFLECTION PROMPTS")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(.secondary)
                    ForEach(applicationPrompts.prefix(3), id: \.self) { prompt in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .foregroundStyle(.secondary)
                                .padding(.top, 6)
                            Text(prompt)
                                .font(.system(size: 14))
                        }
                    }
                }
            }

            Text("How is God inviting you to respond this week?")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                if applyText.isEmpty {
                    Text("One concrete step I can take…")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 10)
                        .padding(.leading, 6)
                }
                TextEditor(text: $applyText)
                    .font(.system(size: 15))
                    .frame(minHeight: 120)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("guidedSession.applyEditor")
        }
    }

    private var prosperityGuardNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .padding(.top, 1)
            Text("Application is about faithfulness, not guaranteed outcomes. Scripture invites us to obedience, not a formula for prosperity.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Complete View

private struct SessionCompleteView: View {
    let verseReference: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundStyle(.accentColor)

            VStack(spacing: 8) {
                Text("Session Complete")
                    .font(.system(size: 24, weight: .bold))
                Text("You spent time with \(verseReference).")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                onDismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(Color.accentColor, in: Capsule())
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("guidedSession.doneButton")

            Spacer()
        }
        .padding(.horizontal, 32)
        .multilineTextAlignment(.center)
    }
}

// MARK: - GuidedSelahStep display extensions

private extension GuidedSelahStep {
    var displayTitle: String {
        switch self {
        case .read: return "Read"
        case .listen: return "Listen"
        case .understand: return "Understand"
        case .reflect: return "Reflect"
        case .pray: return "Pray"
        case .apply: return "Apply"
        case .complete: return "Complete"
        }
    }

    var displayQuestion: String {
        switch self {
        case .read: return "What does it say?"
        case .listen: return "What do you hear?"
        case .understand: return "What does it mean?"
        case .reflect: return "What is God saying to you?"
        case .pray: return "Respond in prayer."
        case .apply: return "How will you live it?"
        case .complete: return "Well done."
        }
    }
}
