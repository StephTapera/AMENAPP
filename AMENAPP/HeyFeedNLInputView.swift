//
//  HeyFeedNLInputView.swift
//  AMENAPP
//
//  The private natural-language feed control sheet.
//  Users type commands like "show me more testimonies this week"
//  and the system parses, interprets, and applies them.
//  No public posting required. No UI redesign.
//

import SwiftUI

struct HeyFeedNLInputView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var nlService   = HeyFeedNLPreferencesService.shared
    @StateObject private var sessionSvc  = HeyFeedSessionModeService.shared

    @State private var inputText     = ""
    @State private var parsedIntent: HeyFeedParsedIntent?
    @State private var isSubmitting  = false
    @State private var showSuccess   = false
    @State private var parseTask: Task<Void, Never>?
    @State private var selectedDuration: HeyFeedDuration = .threeDays
    @FocusState private var inputFocused: Bool

    private let quickChips: [(String, String)] = [
        ("More testimonies",     "show me more testimonies"),
        ("More prayer",          "more prayer requests"),
        ("Less debate",          "less controversial debate"),
        ("More Bible teaching",  "more bible teaching this week"),
        ("More local churches",  "more local churches near me"),
        ("Less repetitive",      "less repetitive content"),
        ("More encouragement",   "more encouraging content"),
        ("People I follow",      "more from people I follow"),
    ]

    private let sessionModes: [HeyFeedSessionMode] = HeyFeedSessionMode.allCases.filter { $0 != .none }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {

                        // ── Input ──────────────────────────────────────────
                        inputSection

                        // ── Interpretation preview ─────────────────────────
                        if let intent = parsedIntent, !inputText.isEmpty {
                            intentPreviewCard(intent)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        // ── Quick chips ────────────────────────────────────
                        if inputText.isEmpty {
                            quickChipsSection
                        }

                        // ── Session mode row ───────────────────────────────
                        sessionModeSection

                        // ── Active preferences ─────────────────────────────
                        if !nlService.activePreferences.isEmpty {
                            activePreferencesSection
                        }

                        // ── Reset row ──────────────────────────────────────
                        if !nlService.activePreferences.isEmpty || sessionSvc.isActive {
                            resetRow
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Hey Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.primary)
                }
            }
            .animation(Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.78)), value: parsedIntent != nil)
            .animation(Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.78)), value: nlService.activePreferences.count)
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(22)
        .presentationBackground(.regularMaterial)
        .onAppear { nlService.startListening() }
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tell your feed what you want")
                .font(AMENFont.semiBold(15))
                .foregroundStyle(.primary)

            HStack(spacing: 10) {
                TextField("e.g. more testimonies, less debate…", text: $inputText, axis: .vertical)
                    .font(AMENFont.regular(16))
                    .foregroundStyle(.primary)
                    .lineLimit(1...3)
                    .focused($inputFocused)
                    .onChange(of: inputText) { _, newValue in
                        scheduleParse(newValue)
                    }
                    .submitLabel(.done)
                    .onSubmit { submitIfReady() }

                if !inputText.isEmpty {
                    Button {
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                            inputText = ""
                            parsedIntent = nil
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.systemGray6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(inputFocused ? Color.primary.opacity(0.2) : Color.clear, lineWidth: 1)
                    )
            )

            // Duration picker
            if !inputText.isEmpty {
                HStack(spacing: 8) {
                    Text("For:")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)

                    ForEach(HeyFeedDuration.allCases, id: \.self) { dur in
                        Button {
                            withAnimation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.7))) {
                                selectedDuration = dur
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Text(dur.label.capitalized)
                                .font(AMENFont.semiBold(12))
                                .foregroundStyle(selectedDuration == dur ? .primary : .secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(selectedDuration == dur
                                              ? Color(.systemGray5)
                                              : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.opacity)

                // Submit button
                Button {
                    submitIfReady()
                } label: {
                    HStack(spacing: 6) {
                        if isSubmitting {
                            ProgressView().scaleEffect(0.8)
                        } else if showSuccess {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Text(showSuccess ? "Applied" : "Apply to feed")
                            .font(AMENFont.semiBold(14))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(showSuccess ? Color.green : Color.primary)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .transition(.opacity)
            }
        }
    }

    // MARK: - Intent Preview

    private func intentPreviewCard(_ intent: HeyFeedParsedIntent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Interpreted as")
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(.secondary)
                Spacer()
                if intent.requiresConfirmation {
                    Text("Low confidence — confirm")
                        .font(AMENFont.regular(11))
                        .foregroundStyle(.orange)
                }
            }

            if intent.targets.isEmpty {
                Text("Could not understand the request. Try being more specific.")
                    .font(AMENFont.regular(13))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(intent.targets) { target in
                        HStack(spacing: 8) {
                            Image(systemName: intent.action == .increase ? "arrow.up" :
                                  intent.action == .decrease ? "arrow.down" :
                                  intent.action == .mute ? "eye.slash" : "arrow.2.circlepath")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(intent.action == .increase ? .green :
                                                 intent.action == .decrease ? .orange :
                                                 intent.action == .mute ? .red : .secondary)

                            Text("\(intent.action.verbLabel) \(target.label)")
                                .font(AMENFont.regular(14))
                                .foregroundStyle(.primary)

                            Spacer()

                            Text(intent.duration.label)
                                .font(AMENFont.regular(12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    // MARK: - Quick Chips

    private var quickChipsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick adjustments")
                .font(AMENFont.semiBold(13))
                .foregroundStyle(.secondary)

            AMENFlowLayout(spacing: 8) {
                ForEach(quickChips, id: \.0) { chip in
                    Button {
                        inputText = chip.1
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        inputFocused = false
                        scheduleParse(chip.1)
                    } label: {
                        Text(chip.0)
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(.thinMaterial)
                                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Session Mode

    private var sessionModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Session mode")
                    .font(AMENFont.semiBold(13))
                    .foregroundStyle(.secondary)
                if sessionSvc.isActive {
                    Text(sessionSvc.timeRemainingLabel)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if sessionSvc.isActive {
                    Button {
                        sessionSvc.clearMode()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text("Clear")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HeyFeedSessionModeChips(
                    sessionModes: sessionModes,
                    activeMode: sessionSvc.activeMode
                ) { mode in
                    if sessionSvc.activeMode == mode {
                        sessionSvc.clearMode()
                    } else {
                        sessionSvc.setMode(mode)
                    }
                }
            }
        }
    }

    // MARK: - Active Preferences

    private var activePreferencesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active adjustments")
                .font(AMENFont.semiBold(13))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(nlService.activePreferences.filter { !$0.isExpired }) { pref in
                    HeyFeedNLCapsuleRow(preference: pref) {
                        Task { try? await nlService.removePreference(id: pref.id) }
                    }
                }
            }
        }
    }

    // MARK: - Reset

    private var resetRow: some View {
        Button {
            Task {
                try? await nlService.removeAll()
                sessionSvc.clearMode()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .semibold))
                Text("Reset feed tuning")
                    .font(AMENFont.regular(14))
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func scheduleParse(_ text: String) {
        parseTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 3 else { parsedIntent = nil; return }
        parseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000) // 400ms debounce
            guard !Task.isCancelled else { return }
            parsedIntent = HeyFeedNLParser.shared.parse(trimmed)
            // Use the detected duration as default selection
            if let detected = parsedIntent?.duration {
                selectedDuration = detected
            }
        }
    }

    private func submitIfReady() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSubmitting else { return }
        let intent = parsedIntent ?? HeyFeedNLParser.shared.parse(trimmed)
        guard !intent.targets.isEmpty else { return }

        // Override duration with user-selected
        let finalIntent = HeyFeedParsedIntent(
            action: intent.action,
            targets: intent.targets,
            duration: selectedDuration,
            strength: intent.strength,
            confidence: intent.confidence,
            originalText: intent.originalText,
            requiresConfirmation: false,
            parserVersion: intent.parserVersion
        )

        isSubmitting = true
        Task { @MainActor in
            try? await nlService.applyIntent(finalIntent)
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                isSubmitting = false
                showSuccess = true
                inputText = ""
                parsedIntent = nil
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation { showSuccess = false }
        }
    }
}

// MARK: - Capsule Row

private struct HeyFeedNLCapsuleRow: View {
    let preference: HeyFeedNLPreference
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconForAction(preference.action))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(colorForAction(preference.action))
                .frame(width: 20)

            Text(preference.targetLabel)
                .font(AMENFont.regular(14))
                .foregroundStyle(.primary)

            Spacer()

            Text(preference.timeRemainingLabel)
                .font(AMENFont.regular(12))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(5)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemGray6))
        )
    }

    private func iconForAction(_ action: HeyFeedNLAction) -> String {
        switch action {
        case .increase: return "arrow.up"
        case .decrease: return "arrow.down"
        case .mute:     return "eye.slash"
        case .explore:  return "sparkles"
        case .balance:  return "arrow.2.circlepath"
        }
    }

    private func colorForAction(_ action: HeyFeedNLAction) -> Color {
        switch action {
        case .increase: return .green
        case .decrease: return .orange
        case .mute:     return .red
        case .explore:  return .blue
        case .balance:  return .secondary
        }
    }
}

// MARK: - HeyFeedNLAction verb label

extension HeyFeedNLAction {
    var verbLabel: String {
        switch self {
        case .increase: return "More"
        case .decrease: return "Less"
        case .mute:     return "Hide"
        case .explore:  return "Explore"
        case .balance:  return "Balance"
        }
    }
}
